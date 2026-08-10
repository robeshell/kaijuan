import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../ai/ai_chat.dart';
import '../../ai/ai_graph.dart';
import '../../ai/ai_graph_store.dart';
import '../persistence/app_database.dart';
import '../storage/library_paths.dart';
import 'backup_format.dart';

class BackupExport {
  const BackupExport({required this.records, required this.objects});

  final BackupRecords records;
  final List<BackupObjectExport> objects;
}

class BackupObjectExport {
  const BackupObjectExport({required this.descriptor, required this.file});

  final BackupObjectDescriptor descriptor;
  final File file;
}

/// Reads a logical, portable snapshot from the database and validates every
/// referenced content-addressed file before a remote manifest is published.
class BackupExporter {
  BackupExporter({required this.database, required this.supportDirectory});

  final AppDatabase database;
  final Directory supportDirectory;

  Future<BackupExport> export() async {
    final snapshot = await database.transaction(() async {
      final items = await database.select(database.readingItems).get();
      final progress = await database.select(database.readingProgress).get();
      final bookmarks = await database.select(database.bookmarks).get();
      final annotations = await database.select(database.bookAnnotations).get();
      final readingLists = await database.select(database.readingLists).get();
      final readingListMembers = await database
          .select(database.readingListMembers)
          .get();
      final collections = await database.select(database.collections).get();
      final collectionMembers = await database
          .select(database.collectionMembers)
          .get();
      final dayStats = await database.select(database.readingDayStats).get();
      final itemTime = await database.select(database.readingItemTime).get();
      return _DatabaseSnapshot(
        items: items,
        progress: progress,
        bookmarks: bookmarks,
        annotations: annotations,
        readingLists: readingLists,
        readingListMembers: readingListMembers,
        collections: collections,
        collectionMembers: collectionMembers,
        dayStats: dayStats,
        itemTime: itemTime,
      );
    });

    final hashById = <String, String>{
      for (final item in snapshot.items) item.id: item.contentHash,
    };
    final records = BackupRecords(
      items: [
        for (final item in snapshot.items)
          {
            'contentHash': item.contentHash,
            'kind': item.kind,
            'format': item.format,
            'title': item.title,
            'seriesName': item.seriesName,
            'pageCount': item.pageCount,
            'pageOrderVersion': item.pageOrderVersion,
            'onShelf': item.onShelf,
            'addedAt': _date(item.addedAt),
            'updatedAt': _date(item.updatedAt),
            'lastOpenedAt': _date(item.lastOpenedAt),
          },
      ],
      progress: [
        for (final row in snapshot.progress)
          if (hashById[row.itemId] case final hash?)
            {
              'contentHash': hash,
              'locatorJson': row.locatorJson,
              'progressFraction': row.progressFraction,
              'updatedAt': _date(row.updatedAt),
            },
      ],
      bookmarks: [
        for (final row in snapshot.bookmarks)
          if (hashById[row.itemId] case final hash?)
            {
              'contentHash': hash,
              'locatorJson': row.locatorJson,
              'label': row.label,
              'createdAt': _date(row.createdAt),
            },
      ],
      annotations: [
        for (final row in snapshot.annotations)
          if (hashById[row.itemId] case final hash?)
            {
              'contentHash': hash,
              'cfi': row.cfi,
              'type': row.type,
              'color': row.color,
              'selectedText': row.selectedText,
              'note': row.note,
              'createdAt': _date(row.createdAt),
            },
      ],
      readingLists: [
        for (final row in snapshot.readingLists)
          {
            'id': row.id,
            'name': row.name,
            'sortOrder': row.sortOrder,
            'createdAt': _date(row.createdAt),
            'updatedAt': _date(row.updatedAt),
          },
      ],
      readingListMembers: [
        for (final row in snapshot.readingListMembers)
          if (hashById[row.itemId] case final hash?)
            {
              'listId': row.listId,
              'contentHash': hash,
              'addedAt': _date(row.addedAt),
            },
      ],
      collections: [
        for (final row in snapshot.collections)
          {
            'id': row.id,
            'name': row.name,
            'onShelf': row.onShelf,
            'sortOrder': row.sortOrder,
            'createdAt': _date(row.createdAt),
            'updatedAt': _date(row.updatedAt),
          },
      ],
      collectionMembers: [
        for (final row in snapshot.collectionMembers)
          if (hashById[row.itemId] case final hash?)
            {
              'collectionId': row.collectionId,
              'contentHash': hash,
              'sortOrder': row.sortOrder,
              'addedAt': _date(row.addedAt),
            },
      ],
      dayStats: [
        for (final row in snapshot.dayStats)
          {
            'day': row.day,
            'activeSeconds': row.activeSeconds,
            'comicSeconds': row.comicSeconds,
            'bookSeconds': row.bookSeconds,
            'sessionsCount': row.sessionsCount,
          },
      ],
      itemTime: [
        for (final row in snapshot.itemTime)
          if (hashById[row.itemId] case final hash?)
            {
              'contentHash': hash,
              'activeSeconds': row.activeSeconds,
              'updatedAt': _date(row.updatedAt),
            },
      ],
      aiChats: await _readAiChats(),
      aiGraphs: await _readAiGraphs(),
    );

    final paths = LibraryPaths(supportDirectory);
    final objects = <BackupObjectExport>[];
    for (final item in snapshot.items) {
      final file = await paths.resolveExisting(
        item.filePath,
        contentHash: item.contentHash,
      );
      if (file == null) {
        throw BackupIntegrityException('找不到书籍文件：${item.title}');
      }
      final descriptor = await _describe(item.contentHash, file);
      objects.add(BackupObjectExport(descriptor: descriptor, file: file));
    }
    return BackupExport(records: records, objects: objects);
  }

  Future<List<Map<String, Object?>>> _readAiGraphs() async {
    final directory = Directory(p.join(supportDirectory.path, 'ai_graph'));
    if (!await directory.exists()) return const [];
    final result = <Map<String, Object?>>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is! Map) continue;
        final graph = AiBookGraph.fromJson(Map<String, dynamic>.from(raw));
        if (graph == null || !KaijuanBackupFormat.isSha256(graph.contentHash)) {
          continue;
        }
        result.add({
          'contentHash': graph.contentHash,
          if (AiGraphStore.workKeyOfFile(
                entity.uri.pathSegments.last,
                graph.contentHash,
              ) !=
              null)
            'workKey': AiGraphStore.workKeyOfFile(
              entity.uri.pathSegments.last,
              graph.contentHash,
            ),
          'graph': graph.toJson(),
        });
      } catch (_) {
        // A damaged graph file must not make the entire library backup fail.
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _readAiChats() async {
    final directory = Directory(p.join(supportDirectory.path, 'ai_chat'));
    if (!await directory.exists()) return const [];
    final result = <Map<String, Object?>>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = jsonDecode(await entity.readAsString());
        if (raw is! Map) continue;
        final session = AiChatSession.fromJson(Map<String, dynamic>.from(raw));
        if (!KaijuanBackupFormat.isSha256(session.contentHash)) continue;
        result.add({
          'contentHash': session.contentHash,
          'messages': [
            for (final message in session.messages) message.toJson(),
          ],
          if (session.outline != null) 'outline': session.outline!.toJson(),
          if (session.workOutlines.isNotEmpty)
            'workOutlines': session.workOutlines.map(
              (key, value) => MapEntry(key, value.toJson()),
            ),
          if (session.workMessages.isNotEmpty)
            'workMessages': session.workMessages.map(
              (key, value) => MapEntry(
                key,
                value
                    .map((message) => message.toJson())
                    .toList(growable: false),
              ),
            ),
        });
      } catch (_) {
        // A damaged chat file must not make the entire library backup fail.
      }
    }
    return result;
  }

  Future<BackupObjectDescriptor> _describe(
    String expectedHash,
    File file,
  ) async {
    final chunks = <BackupChunkDescriptor>[];
    final full = _DigestSink();
    final conversion = sha256.startChunkedConversion(full);
    final input = await file.open();
    var total = 0;
    var index = 0;
    try {
      while (true) {
        final bytes = await input.read(KaijuanBackupFormat.chunkSize);
        if (bytes.isEmpty) break;
        conversion.add(bytes);
        final chunkHash = sha256.convert(bytes).toString();
        chunks.add(
          BackupChunkDescriptor(
            index: index++,
            hash: chunkHash,
            size: bytes.length,
          ),
        );
        total += bytes.length;
      }
    } finally {
      await input.close();
    }
    conversion.close();
    final actualHash = full.value.toString();
    if (actualHash != expectedHash) {
      throw BackupIntegrityException('书籍文件校验失败：${p.basename(file.path)}');
    }
    return BackupObjectDescriptor(
      hash: expectedHash,
      extension: _extension(file.path),
      size: total,
      chunks: chunks,
    );
  }

  static String _extension(String path) {
    final extension = p.extension(path).toLowerCase();
    if (extension.isNotEmpty &&
        RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)) {
      return extension;
    }
    return '.bin';
  }

  static String? _date(DateTime? value) => value?.toUtc().toIso8601String();
}

class BackupIntegrityException implements Exception {
  const BackupIntegrityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest ?? (throw StateError('digest not available'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

class _DatabaseSnapshot {
  const _DatabaseSnapshot({
    required this.items,
    required this.progress,
    required this.bookmarks,
    required this.annotations,
    required this.readingLists,
    required this.readingListMembers,
    required this.collections,
    required this.collectionMembers,
    required this.dayStats,
    required this.itemTime,
  });

  final List<ReadingItem> items;
  final List<ReadingProgressData> progress;
  final List<Bookmark> bookmarks;
  final List<BookAnnotationRow> annotations;
  final List<ReadingList> readingLists;
  final List<ReadingListMember> readingListMembers;
  final List<Collection> collections;
  final List<CollectionMember> collectionMembers;
  final List<ReadingDayStat> dayStats;
  final List<ReadingItemTimeData> itemTime;
}

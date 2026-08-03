import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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
      return _DatabaseSnapshot(
        items: items,
        progress: progress,
        bookmarks: bookmarks,
        annotations: annotations,
        readingLists: readingLists,
        readingListMembers: readingListMembers,
        collections: collections,
        collectionMembers: collectionMembers,
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
  });

  final List<ReadingItem> items;
  final List<ReadingProgressData> progress;
  final List<Bookmark> bookmarks;
  final List<BookAnnotationRow> annotations;
  final List<ReadingList> readingLists;
  final List<ReadingListMember> readingListMembers;
  final List<Collection> collections;
  final List<CollectionMember> collectionMembers;
}

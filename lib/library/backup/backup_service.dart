import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_store.dart';
import '../../ai/ai_graph.dart';
import '../../ai/ai_graph_store.dart';
import '../../domain/reader_models.dart';
import '../import/import_pipeline.dart';
import '../import/import_sources.dart';
import '../persistence/app_database.dart';
import '../remote/remote_models.dart';
import '../remote/remote_store.dart';
import '../remote/webdav_client.dart';
import '../storage/library_paths.dart';
import '../stats/reading_day_counters.dart';
import 'backup_exporter.dart';
import 'backup_format.dart';
import 'backup_store.dart';

enum BackupPhase { preparing, uploading, publishing, downloading, restoring }

class BackupProgress {
  const BackupProgress({
    required this.phase,
    required this.completed,
    required this.total,
    required this.message,
  });

  final BackupPhase phase;
  final int completed;
  final int total;
  final String message;

  double? get fraction =>
      total <= 0 ? null : (completed / total).clamp(0.0, 1.0);
}

class BackupRunResult {
  const BackupRunResult({
    required this.manifest,
    required this.uploadedObjects,
    required this.reusedObjects,
  });

  final BackupSnapshotManifest manifest;
  final int uploadedObjects;
  final int reusedObjects;
}

class BackupRestorePreview {
  const BackupRestorePreview({
    required this.manifest,
    required this.newBooks,
    required this.existingBooks,
    required this.progressRows,
    required this.bookmarkRows,
    required this.annotationRows,
    required this.aiChatRows,
    required this.aiGraphRows,
  });

  final BackupSnapshotManifest manifest;
  final int newBooks;
  final int existingBooks;
  final int progressRows;
  final int bookmarkRows;
  final int annotationRows;
  final int aiChatRows;
  final int aiGraphRows;
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.addedBooks,
    required this.updatedBooks,
    required this.restoredProgress,
    required this.restoredBookmarks,
    required this.restoredAnnotations,
    required this.restoredLists,
    required this.restoredCollections,
    required this.restoredAiChats,
    required this.restoredAiGraphs,
  });

  final int addedBooks;
  final int updatedBooks;
  final int restoredProgress;
  final int restoredBookmarks;
  final int restoredAnnotations;
  final int restoredLists;
  final int restoredCollections;
  final int restoredAiChats;
  final int restoredAiGraphs;
}

/// Orchestrates logical snapshots. It knows the database and import pipeline,
/// but the presentation layer only sees this controller-facing API.
class BackupService {
  BackupService({
    required this.database,
    required this.supportDirectory,
    required this.connectionStore,
    required this.credentialStore,
    required this.importPipeline,
    required this.settingsStore,
    WebDavClient? webDav,
  }) : _webDav = webDav ?? WebDavClient();

  final AppDatabase database;
  final Directory supportDirectory;
  final RemoteConnectionStore connectionStore;
  final RemoteCredentialStore credentialStore;
  final ImportPipeline importPipeline;
  final JsonBackupTargetSettingsStore settingsStore;
  final WebDavClient _webDav;

  BackupTargetSettings _settings = const BackupTargetSettings();
  bool _loaded = false;
  bool _running = false;

  BackupTargetSettings get settings => _settings;
  bool get isRunning => _running;

  Future<void> load() async {
    if (_loaded) return;
    _settings = await settingsStore.read();
    var changed = false;
    String remotePath;
    try {
      remotePath = WebDavBackupStore.sanitizeRelativePath(_settings.remotePath);
    } on FormatException {
      remotePath = const BackupTargetSettings().remotePath;
      changed = true;
    }
    if (remotePath != _settings.remotePath) {
      _settings = _settings.copyWith(remotePath: remotePath);
      changed = true;
    }
    if (!KaijuanBackupFormat.isPathSegment(_settings.deviceId)) {
      _settings = _settings.copyWith(
        deviceId: _newId('device'),
        deviceName: _defaultDeviceName(),
      );
      changed = true;
    } else {
      final deviceName = KaijuanBackupFormat.truncateDeviceName(
        _settings.deviceName,
      );
      final normalizedName = deviceName.isEmpty
          ? _defaultDeviceName()
          : deviceName;
      if (normalizedName != _settings.deviceName) {
        _settings = _settings.copyWith(deviceName: normalizedName);
        changed = true;
      }
    }
    if (changed) await settingsStore.write(_settings);
    _loaded = true;
  }

  Future<void> updateSettings(BackupTargetSettings settings) async {
    await load();
    final normalizedPath = WebDavBackupStore.sanitizeRelativePath(
      settings.remotePath,
    );
    final deviceName = KaijuanBackupFormat.truncateDeviceName(
      settings.deviceName,
    );
    _settings = settings.copyWith(
      remotePath: normalizedPath,
      deviceName: deviceName.isEmpty ? _defaultDeviceName() : deviceName,
    );
    await settingsStore.write(_settings);
  }

  Future<BackupRunResult> backup({
    void Function(BackupProgress progress)? onProgress,
  }) async {
    await load();
    if (_running) throw const BackupServiceException('备份正在进行');
    _running = true;
    try {
      final connection = await _webDavConnection();
      final credentials =
          await credentialStore.read(connection.id) ??
          const RemoteCredentials();
      onProgress?.call(
        const BackupProgress(
          phase: BackupPhase.preparing,
          completed: 0,
          total: 0,
          message: '正在整理书库数据…',
        ),
      );
      final exported = await BackupExporter(
        database: database,
        supportDirectory: supportDirectory,
      ).export();
      final snapshotId = _newId('snapshot');
      final encodedRecords = utf8.encode(exported.records.encode());
      if (encodedRecords.length >
          KaijuanBackupFormat.maxUncompressedRecordsBytes) {
        throw const BackupServiceException('备份数据过大，暂时无法创建快照');
      }
      final compressed = gzip.encode(encodedRecords);
      if (compressed.length > KaijuanBackupFormat.maxCompressedRecordsBytes) {
        throw const BackupServiceException('备份记录压缩后超过大小限制');
      }
      final manifest = BackupSnapshotManifest(
        snapshotId: snapshotId,
        deviceId: _settings.deviceId,
        deviceName: _settings.deviceName,
        createdAt: DateTime.now().toUtc(),
        recordsSha256: sha256.convert(compressed).toString(),
        recordsBytes: compressed.length,
        objects: [for (final object in exported.objects) object.descriptor],
        counts: {
          'items': exported.records.items.length,
          'progress': exported.records.progress.length,
          'bookmarks': exported.records.bookmarks.length,
          'annotations': exported.records.annotations.length,
          'readingLists': exported.records.readingLists.length,
          'collections': exported.records.collections.length,
          'dayStats': exported.records.dayStats.length,
          'itemTime': exported.records.itemTime.length,
          'aiChats': exported.records.aiChats.length,
          'aiGraphs': exported.records.aiGraphs.length,
        },
        databaseSchemaVersion: database.schemaVersion,
      );

      final store = WebDavBackupStore(
        connection: connection,
        credentials: credentials,
        client: _webDav,
      );
      var uploaded = 0;
      var reused = 0;
      await store.withSession(_settings.remotePath, (session, root) async {
        onProgress?.call(
          BackupProgress(
            phase: BackupPhase.uploading,
            completed: 0,
            total: exported.objects.length,
            message: '正在检查书籍文件…',
          ),
        );
        for (var i = 0; i < exported.objects.length; i++) {
          final object = exported.objects[i];
          final objectFile = WebDavBackupStore.objectManifestUri(
            root,
            object.descriptor.hash,
          );
          final before = await session.stat(objectFile);
          await store.uploadObject(session, root, object);
          if (before == null) {
            uploaded++;
          } else {
            reused++;
          }
          onProgress?.call(
            BackupProgress(
              phase: BackupPhase.uploading,
              completed: i + 1,
              total: exported.objects.length,
              message: '已处理 ${i + 1}/${exported.objects.length} 本书',
            ),
          );
        }
        onProgress?.call(
          const BackupProgress(
            phase: BackupPhase.publishing,
            completed: 0,
            total: 1,
            message: '正在发布备份快照…',
          ),
        );
        await store.uploadRecords(session, root, manifest, exported.records);
        await store.publishManifest(session, root, manifest);
      });

      _settings = _settings.copyWith(
        lastSnapshotId: manifest.snapshotId,
        lastSuccessfulAt: DateTime.now().toUtc(),
        clearLastError: true,
      );
      await settingsStore.write(_settings);
      return BackupRunResult(
        manifest: manifest,
        uploadedObjects: uploaded,
        reusedObjects: reused,
      );
    } catch (error) {
      _settings = _settings.copyWith(lastError: _friendlyError(error));
      await settingsStore.write(_settings);
      rethrow;
    } finally {
      _running = false;
    }
  }

  Future<List<BackupSnapshotManifest>> listSnapshots() async {
    await load();
    final connection = await _webDavConnection();
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    return WebDavBackupStore(
      connection: connection,
      credentials: credentials,
      client: _webDav,
    ).listSnapshots(_settings.remotePath);
  }

  Future<BackupRestorePreview> preview(BackupSnapshotManifest manifest) async {
    await load();
    final (store, _, _) = await _storeParts();
    return store.withSession(_settings.remotePath, (session, root) async {
      final records = await store.readRecords(session, root, manifest);
      var newBooks = 0;
      var existingBooks = 0;
      for (final object in manifest.objects) {
        final local = await database.readingItemByHash(object.hash);
        final localFile = local == null ? null : await _existingItemFile(local);
        if (localFile != null && await _fileMatchesObject(localFile, object)) {
          existingBooks++;
        } else {
          newBooks++;
        }
      }
      return BackupRestorePreview(
        manifest: manifest,
        newBooks: newBooks,
        existingBooks: existingBooks,
        progressRows: records.progress.length,
        bookmarkRows: records.bookmarks.length,
        annotationRows: records.annotations.length,
        aiChatRows: records.aiChats.length,
        aiGraphRows: records.aiGraphs.length,
      );
    });
  }

  Future<BackupRestoreResult> restore(
    BackupSnapshotManifest manifest, {
    void Function(BackupProgress progress)? onProgress,
  }) async {
    await load();
    if (_running) throw const BackupServiceException('备份任务正在进行');
    _running = true;
    final staging = Directory(
      p.join(supportDirectory.path, '.backup-staging', manifest.snapshotId),
    );
    try {
      final localHashesBeforeRestore = {
        for (final item in await database.select(database.readingItems).get())
          item.contentHash,
      };
      final (store, _, _) = await _storeParts();
      await staging.create(recursive: true);
      return await store.withSession(_settings.remotePath, (
        session,
        root,
      ) async {
        final records = await store.readRecords(session, root, manifest);
        final objectsToRestore = <BackupObjectDescriptor>[];
        final corruptLocalFiles = <String, File>{};
        final downloadedFiles = <String, File>{};
        final newlyImportedHashes = <String>{};
        for (final object in manifest.objects) {
          final local = await database.readingItemByHash(object.hash);
          final localFile = local == null
              ? null
              : await _existingItemFile(local);
          if (localFile != null &&
              await _fileMatchesObject(localFile, object)) {
            continue;
          }
          if (localFile != null) corruptLocalFiles[object.hash] = localFile;
          objectsToRestore.add(object);
        }
        onProgress?.call(
          BackupProgress(
            phase: BackupPhase.downloading,
            completed: 0,
            total: objectsToRestore.length,
            message: '正在下载并校验待恢复书籍…',
          ),
        );
        // Finish every network transfer and integrity check before mutating
        // the library. A failed download therefore leaves local data intact.
        for (var i = 0; i < objectsToRestore.length; i++) {
          final object = objectsToRestore[i];
          final destination = File(
            p.join(staging.path, '${object.hash}${object.extension}'),
          );
          await store.downloadObject(session, root, object, destination);
          downloadedFiles[object.hash] = destination;
          onProgress?.call(
            BackupProgress(
              phase: BackupPhase.downloading,
              completed: i + 1,
              total: objectsToRestore.length,
              message: '已校验 ${i + 1}/${objectsToRestore.length} 本书',
            ),
          );
        }
        for (var i = 0; i < objectsToRestore.length; i++) {
          final object = objectsToRestore[i];
          final destination = downloadedFiles[object.hash]!;
          final corruptLocal = corruptLocalFiles[object.hash];
          if (corruptLocal != null) {
            await _replaceCorruptFile(corruptLocal, destination, object);
          } else {
            final candidate = ImportCandidate(
              source: LocalFileImportSource(
                destination,
                method: ImportMethod.localFile,
                displayName: '${object.hash}${object.extension}',
              ),
              declaredFormat: ReaderFormat.fromExtension(object.extension),
            );
            final result = await importPipeline.importCandidates([candidate]);
            if (result.hasFailures || result.added + result.updated == 0) {
              throw BackupServiceException(
                '恢复书籍失败：${result.failures.firstOrNull?.reason ?? object.hash}',
              );
            }
            newlyImportedHashes.add(object.hash);
          }
          onProgress?.call(
            BackupProgress(
              phase: BackupPhase.restoring,
              completed: i + 1,
              total: objectsToRestore.length,
              message: '已恢复 ${i + 1}/${objectsToRestore.length} 本书',
            ),
          );
        }
        return _mergeRecords(
          records,
          newlyImportedHashes,
          localHashesBeforeRestore,
          onProgress,
        );
      });
    } finally {
      _running = false;
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<BackupRestoreResult> _mergeRecords(
    BackupRecords records,
    Set<String> newlyImportedHashes,
    Set<String> localHashesBeforeRestore,
    void Function(BackupProgress progress)? onProgress,
  ) async {
    var addedBooks = 0;
    var updatedBooks = 0;
    var restoredProgress = 0;
    var restoredBookmarks = 0;
    var restoredAnnotations = 0;
    var restoredLists = 0;
    var restoredCollections = 0;
    var restoredAiChats = 0;
    var restoredAiGraphs = 0;

    final itemIds = <String, String>{};
    await database.transaction(() async {
      final now = DateTime.now();
      for (final raw in records.items) {
        final hash = _string(raw['contentHash']);
        if (hash == null) continue;
        final existing = await database.readingItemByHash(hash);
        if (existing == null) continue;
        itemIds[hash] = existing.id;
        final remoteUpdated = _date(raw['updatedAt']) ?? now;
        final remoteAdded = _date(raw['addedAt']) ?? remoteUpdated;
        final remoteLastOpened = _date(raw['lastOpenedAt']);
        final latestOpened = _later(existing.lastOpenedAt, remoteLastOpened);
        await database.upsertReadingItem(
          ReadingItemsCompanion(
            id: Value(existing.id),
            kind: Value(_string(raw['kind']) ?? existing.kind),
            format: Value(_string(raw['format']) ?? existing.format),
            // A non-empty local title may be a deliberate rename; restore
            // never silently overwrites it in merge mode.
            title: Value(
              localHashesBeforeRestore.contains(hash)
                  ? existing.title
                  : (_string(raw['title']) ?? existing.title),
            ),
            filePath: Value(existing.filePath),
            contentHash: Value(existing.contentHash),
            coverPath: Value(existing.coverPath),
            seriesName: Value(
              _nullableString(raw['seriesName']) ?? existing.seriesName,
            ),
            pageCount: Value(_int(raw['pageCount']) ?? existing.pageCount),
            pageOrderVersion: Value(
              _int(raw['pageOrderVersion']) ?? existing.pageOrderVersion,
            ),
            onShelf: Value(existing.onShelf || raw['onShelf'] == true),
            addedAt: Value(
              existing.addedAt.isBefore(remoteAdded)
                  ? existing.addedAt
                  : remoteAdded,
            ),
            updatedAt: Value(
              existing.updatedAt.isAfter(remoteUpdated)
                  ? existing.updatedAt
                  : remoteUpdated,
            ),
            lastOpenedAt: Value(latestOpened),
          ),
        );
        if (newlyImportedHashes.contains(hash) &&
            !localHashesBeforeRestore.contains(hash)) {
          addedBooks++;
        } else {
          updatedBooks++;
        }
      }

      for (final raw in records.progress) {
        final itemId = itemIds[_string(raw['contentHash'])];
        final locator = _string(raw['locatorJson']);
        if (itemId == null || locator == null) continue;
        final updatedAt = _date(raw['updatedAt']) ?? now;
        final local = await database.progressFor(itemId);
        if (local != null && !updatedAt.isAfter(local.updatedAt)) continue;
        await database.upsertProgress(
          itemId: itemId,
          locatorJson: locator,
          progressFraction: (_num(raw['progressFraction']) ?? 0).clamp(
            0.0,
            1.0,
          ),
          updatedAt: updatedAt,
        );
        restoredProgress++;
      }

      for (final raw in records.bookmarks) {
        final itemId = itemIds[_string(raw['contentHash'])];
        final locator = _string(raw['locatorJson']);
        if (itemId == null || locator == null) continue;
        final existing =
            await (database.select(database.bookmarks)..where(
                  (table) =>
                      table.itemId.equals(itemId) &
                      table.locatorJson.equals(locator),
                ))
                .getSingleOrNull();
        if (existing != null) continue;
        await database
            .into(database.bookmarks)
            .insert(
              BookmarksCompanion.insert(
                itemId: itemId,
                locatorJson: locator,
                label: Value(_nullableString(raw['label'])),
                createdAt: _date(raw['createdAt']) ?? now,
              ),
            );
        restoredBookmarks++;
      }

      for (final raw in records.annotations) {
        final itemId = itemIds[_string(raw['contentHash'])];
        final cfi = _string(raw['cfi']);
        final type = _string(raw['type']);
        final color = _string(raw['color']);
        if (itemId == null || cfi == null || type == null || color == null) {
          continue;
        }
        final existing =
            await (database.select(database.bookAnnotations)..where(
                  (table) =>
                      table.itemId.equals(itemId) & table.cfi.equals(cfi),
                ))
                .getSingleOrNull();
        if (existing != null) continue;
        await database
            .into(database.bookAnnotations)
            .insert(
              BookAnnotationsCompanion.insert(
                itemId: itemId,
                cfi: cfi,
                type: type,
                color: color,
                selectedText: Value(_nullableString(raw['selectedText'])),
                note: Value(_nullableString(raw['note'])),
                createdAt: _date(raw['createdAt']) ?? now,
              ),
            );
        restoredAnnotations++;
      }

      for (final raw in records.readingLists) {
        final id = _string(raw['id']);
        final name = _string(raw['name']);
        if (id == null || name == null) continue;
        final existing = await database.readingListById(id);
        if (existing != null) continue;
        await database
            .into(database.readingLists)
            .insert(
              ReadingListsCompanion.insert(
                id: id,
                name: name,
                sortOrder: Value(_int(raw['sortOrder']) ?? 0),
                createdAt: _date(raw['createdAt']) ?? now,
                updatedAt: _date(raw['updatedAt']) ?? now,
              ),
            );
        restoredLists++;
      }
      for (final raw in records.readingListMembers) {
        final listId = _string(raw['listId']);
        final itemId = itemIds[_string(raw['contentHash'])];
        if (listId == null ||
            itemId == null ||
            await database.readingListById(listId) == null) {
          continue;
        }
        await database
            .into(database.readingListMembers)
            .insertOnConflictUpdate(
              ReadingListMembersCompanion.insert(
                listId: listId,
                itemId: itemId,
                addedAt: _date(raw['addedAt']) ?? now,
              ),
            );
      }

      for (final raw in records.collections) {
        final id = _string(raw['id']);
        final name = _string(raw['name']);
        if (id == null || name == null) continue;
        final existing = await database.collectionById(id);
        if (existing != null) continue;
        await database
            .into(database.collections)
            .insert(
              CollectionsCompanion.insert(
                id: id,
                name: name,
                onShelf: Value(raw['onShelf'] == true),
                sortOrder: Value(_int(raw['sortOrder']) ?? 0),
                createdAt: _date(raw['createdAt']) ?? now,
                updatedAt: _date(raw['updatedAt']) ?? now,
              ),
            );
        restoredCollections++;
      }
      for (final raw in records.collectionMembers) {
        final collectionId = _string(raw['collectionId']);
        final itemId = itemIds[_string(raw['contentHash'])];
        if (collectionId == null ||
            itemId == null ||
            await database.collectionById(collectionId) == null) {
          continue;
        }
        final localMembership = await (database.select(
          database.collectionMembers,
        )..where((table) => table.itemId.equals(itemId))).getSingleOrNull();
        if (localMembership != null) {
          continue;
        }
        await database
            .into(database.collectionMembers)
            .insertOnConflictUpdate(
              CollectionMembersCompanion.insert(
                collectionId: collectionId,
                itemId: itemId,
                sortOrder: Value(_int(raw['sortOrder']) ?? 0),
                addedAt: _date(raw['addedAt']) ?? now,
              ),
            );
      }

      // Duration tables are snapshot counters, not additive sync. Pick one
      // coherent normalized day row so active == comic + book stays true.
      for (final raw in records.dayStats) {
        final day = _string(raw['day']);
        if (day == null || !isValidReadingDayKey(day)) continue;
        final remote = ReadingDayCounters.normalized(
          activeSeconds: _int(raw['activeSeconds']) ?? 0,
          comicSeconds: _int(raw['comicSeconds']) ?? 0,
          bookSeconds: _int(raw['bookSeconds']) ?? 0,
          sessionsCount: _int(raw['sessionsCount']) ?? 0,
        );
        final local = await (database.select(
          database.readingDayStats,
        )..where((t) => t.day.equals(day))).getSingleOrNull();
        if (local == null) {
          await database
              .into(database.readingDayStats)
              .insert(
                ReadingDayStatsCompanion.insert(
                  day: day,
                  activeSeconds: Value(remote.activeSeconds),
                  comicSeconds: Value(remote.comicSeconds),
                  bookSeconds: Value(remote.bookSeconds),
                  sessionsCount: Value(remote.sessionsCount),
                ),
              );
        } else {
          final chosen = ReadingDayCounters.chooseLarger(
            ReadingDayCounters.normalized(
              activeSeconds: local.activeSeconds,
              comicSeconds: local.comicSeconds,
              bookSeconds: local.bookSeconds,
              sessionsCount: local.sessionsCount,
            ),
            remote,
          );
          await (database.update(
            database.readingDayStats,
          )..where((t) => t.day.equals(day))).write(
            ReadingDayStatsCompanion(
              activeSeconds: Value(chosen.activeSeconds),
              comicSeconds: Value(chosen.comicSeconds),
              bookSeconds: Value(chosen.bookSeconds),
              sessionsCount: Value(chosen.sessionsCount),
            ),
          );
        }
      }

      for (final raw in records.itemTime) {
        final itemId = itemIds[_string(raw['contentHash'])];
        final remoteSeconds = _int(raw['activeSeconds']) ?? 0;
        if (itemId == null || !isValidReadingCounter(remoteSeconds)) continue;
        final local = await (database.select(
          database.readingItemTime,
        )..where((t) => t.itemId.equals(itemId))).getSingleOrNull();
        final remoteUpdated = _date(raw['updatedAt']) ?? now;
        if (local == null) {
          await database
              .into(database.readingItemTime)
              .insert(
                ReadingItemTimeCompanion.insert(
                  itemId: itemId,
                  activeSeconds: Value(remoteSeconds),
                  updatedAt: remoteUpdated,
                ),
              );
        } else if (remoteSeconds > local.activeSeconds) {
          await (database.update(
            database.readingItemTime,
          )..where((t) => t.itemId.equals(itemId))).write(
            ReadingItemTimeCompanion(
              activeSeconds: Value(remoteSeconds),
              updatedAt: Value(
                remoteUpdated.isAfter(local.updatedAt)
                    ? remoteUpdated
                    : local.updatedAt,
              ),
            ),
          );
        }
      }
    });
    restoredAiChats = await _mergeAiChats(records.aiChats, itemIds);
    restoredAiGraphs = await _mergeAiGraphs(records.aiGraphs, itemIds);
    onProgress?.call(
      const BackupProgress(
        phase: BackupPhase.restoring,
        completed: 1,
        total: 1,
        message: '备份记录已恢复',
      ),
    );
    return BackupRestoreResult(
      addedBooks: addedBooks,
      updatedBooks: updatedBooks,
      restoredProgress: restoredProgress,
      restoredBookmarks: restoredBookmarks,
      restoredAnnotations: restoredAnnotations,
      restoredLists: restoredLists,
      restoredCollections: restoredCollections,
      restoredAiChats: restoredAiChats,
      restoredAiGraphs: restoredAiGraphs,
    );
  }

  Future<int> _mergeAiGraphs(
    List<Map<String, Object?>> rows,
    Map<String, String> itemIds,
  ) async {
    var restored = 0;
    final directory = Directory(p.join(supportDirectory.path, 'ai_graph'));
    for (final raw in rows) {
      final hash = _string(raw['contentHash']);
      final graphRaw = raw['graph'];
      if (hash == null ||
          !KaijuanBackupFormat.isSha256(hash) ||
          !itemIds.containsKey(hash) ||
          graphRaw is! Map) {
        continue;
      }
      final remote = AiBookGraph.fromJson(Map<String, dynamic>.from(graphRaw));
      if (remote == null || remote.contentHash != hash) continue;
      final workKey = _string(raw['workKey']);
      final graphStore = AiGraphStore(directory);
      if (await graphStore.read(hash, workKey: workKey) != null) {
        // A valid local graph wins; an unreadable local file is repairable.
        continue;
      }
      await graphStore.write(remote, workKey: workKey);
      restored++;
    }
    return restored;
  }

  Future<int> _mergeAiChats(
    List<Map<String, Object?>> rows,
    Map<String, String> itemIds,
  ) async {
    var restored = 0;
    final directory = Directory(p.join(supportDirectory.path, 'ai_chat'));
    final store = JsonAiChatHistoryStore(directory);
    for (final raw in rows) {
      final hash = _string(raw['contentHash']);
      final messagesRaw = raw['messages'];
      final outlineRaw = raw['outline'];
      final workOutlinesRaw = raw['workOutlines'];
      final workMessagesRaw = raw['workMessages'];
      if (hash == null ||
          !KaijuanBackupFormat.isSha256(hash) ||
          !itemIds.containsKey(hash) ||
          (messagesRaw is! List &&
              outlineRaw is! Map &&
              workOutlinesRaw is! Map &&
              workMessagesRaw is! Map)) {
        continue;
      }
      final remote = AiChatSession.fromJson({
        'contentHash': hash,
        'messages': messagesRaw is List ? messagesRaw : const [],
        if (outlineRaw is Map) 'outline': outlineRaw,
        if (workOutlinesRaw is Map) 'workOutlines': workOutlinesRaw,
        if (workMessagesRaw is Map) 'workMessages': workMessagesRaw,
      });
      if (remote.messages.isEmpty &&
          remote.outline == null &&
          remote.workOutlines.isEmpty &&
          remote.workMessages.isEmpty) {
        continue;
      }
      final itemId = itemIds[hash]!;
      AiChatSession local;
      try {
        local =
            await store.read(contentHash: hash, itemId: itemId) ??
            AiChatSession(contentHash: hash, itemId: itemId);
      } on FormatException {
        // A syntactically corrupt local generation contains no recoverable
        // messages. JsonAiChatHistoryStore keeps a backup during replacement.
        local = AiChatSession(contentHash: hash, itemId: itemId);
      }
      List<AiChatMessage> mergeMessages(
        List<AiChatMessage> localMessages,
        List<AiChatMessage> remoteMessages,
      ) {
        final seen = <String>{
          for (final message in localMessages) jsonEncode(message.toJson()),
        };
        final merged = <AiChatMessage>[...localMessages];
        for (final message in remoteMessages) {
          final key = jsonEncode(message.toJson());
          if (seen.add(key)) merged.add(message);
        }
        return merged;
      }

      final workMessages = <String, List<AiChatMessage>>{};
      for (final key in {
        ...local.workMessages.keys,
        ...remote.workMessages.keys,
      }) {
        final merged = mergeMessages(
          local.workMessages[key] ?? const [],
          remote.workMessages[key] ?? const [],
        );
        if (merged.isNotEmpty) workMessages[key] = merged;
      }
      final desired = AiChatSession(
        contentHash: hash,
        itemId: itemId,
        messages: mergeMessages(local.messages, remote.messages),
        // Restore fills gaps but never replaces local analysis.
        outline: local.outline ?? remote.outline,
        workOutlines: {...remote.workOutlines, ...local.workOutlines},
        workMessages: workMessages,
      );
      final normalizedLocal = AiChatSession(
        contentHash: hash,
        itemId: itemId,
        messages: local.messages,
        outline: local.outline,
        workOutlines: local.workOutlines,
        workMessages: local.workMessages,
      );
      if (jsonEncode(desired.toJson()) ==
          jsonEncode(normalizedLocal.toJson())) {
        continue;
      }
      await store.write(desired);
      restored++;
    }
    return restored;
  }

  Future<(WebDavBackupStore, RemoteConnection, RemoteCredentials)>
  _storeParts() async {
    final connection = await _webDavConnection();
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    return (
      WebDavBackupStore(
        connection: connection,
        credentials: credentials,
        client: _webDav,
      ),
      connection,
      credentials,
    );
  }

  Future<RemoteConnection> _webDavConnection() async {
    final id = _settings.connectionId;
    if (id == null || id.isEmpty) {
      throw const BackupServiceException('请先选择 WebDAV 备份位置');
    }
    final connections = await connectionStore.read();
    final connection = connections.where((item) => item.id == id).firstOrNull;
    if (connection == null || connection.type != RemoteSourceType.webDav) {
      throw const BackupServiceException('备份使用的 WebDAV 连接不存在');
    }
    if (Uri.tryParse(connection.url)?.scheme.toLowerCase() != 'https') {
      throw const BackupServiceException('备份位置需要使用 HTTPS。请编辑 WebDAV 连接地址后重试');
    }
    return connection;
  }

  Future<File?> _existingItemFile(ReadingItem item) async {
    final paths = LibraryPaths(supportDirectory);
    return paths.resolveExisting(item.filePath, contentHash: item.contentHash);
  }

  Future<bool> _fileMatchesObject(
    File file,
    BackupObjectDescriptor descriptor,
  ) async {
    try {
      if (!await file.exists() || await file.length() != descriptor.size) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == descriptor.hash;
    } catch (_) {
      return false;
    }
  }

  Future<void> _replaceCorruptFile(
    File existing,
    File downloaded,
    BackupObjectDescriptor descriptor,
  ) async {
    final suffix = '$pid.${DateTime.now().microsecondsSinceEpoch}';
    final replacement = File('${existing.path}.backup-repair.$suffix.partial');
    final previous = File('${existing.path}.backup-repair.$suffix.previous');
    try {
      await downloaded.copy(replacement.path);
      if (!await _fileMatchesObject(replacement, descriptor)) {
        throw const BackupServiceException('恢复后的书籍文件校验失败');
      }
      await existing.rename(previous.path);
      try {
        await replacement.rename(existing.path);
      } catch (_) {
        if (!await existing.exists() && await previous.exists()) {
          await previous.rename(existing.path);
        }
        rethrow;
      }
      if (await previous.exists()) {
        try {
          await previous.delete();
        } catch (_) {
          // The repaired generation is already active. A stale recovery copy
          // is preferable to reporting a false restore failure.
        }
      }
      if (await downloaded.exists()) await downloaded.delete();
    } finally {
      if (await replacement.exists()) await replacement.delete();
      if (!await existing.exists() && await previous.exists()) {
        await previous.rename(existing.path);
      }
    }
  }

  static String _newId(String prefix) {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$random';
  }

  static String _defaultDeviceName() {
    try {
      final name = Platform.localHostname.trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return '我的设备';
  }

  String userMessageFor(Object error, {required String fallback}) {
    if (error is BackupServiceException) return error.message;
    if (error is BackupStoreException) return error.message;
    if (error is RemoteProtocolException) return error.message;
    return fallback;
  }

  String _friendlyError(Object error) =>
      userMessageFor(error, fallback: '备份失败。请检查网络、权限和 WebDAV 设置后重试');

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static String? _nullableString(Object? value) =>
      value is String ? value : null;
  static int? _int(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : null);
  static double? _num(Object? value) => value is num ? value.toDouble() : null;
  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
  static DateTime? _later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

class BackupServiceException implements Exception {
  const BackupServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

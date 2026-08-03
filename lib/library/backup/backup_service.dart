import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../import/import_pipeline.dart';
import '../import/import_sources.dart';
import '../persistence/app_database.dart';
import '../remote/remote_models.dart';
import '../remote/remote_store.dart';
import '../remote/webdav_client.dart';
import '../storage/library_paths.dart';
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
  });

  final BackupSnapshotManifest manifest;
  final int newBooks;
  final int existingBooks;
  final int progressRows;
  final int bookmarkRows;
  final int annotationRows;
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
  });

  final int addedBooks;
  final int updatedBooks;
  final int restoredProgress;
  final int restoredBookmarks;
  final int restoredAnnotations;
  final int restoredLists;
  final int restoredCollections;
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
    } else if (_settings.deviceName.trim().isEmpty) {
      _settings = _settings.copyWith(deviceName: _defaultDeviceName());
      changed = true;
    }
    if (changed) await settingsStore.write(_settings);
    _loaded = true;
  }

  Future<void> updateSettings(BackupTargetSettings settings) async {
    await load();
    final normalizedPath = WebDavBackupStore.sanitizeRelativePath(
      settings.remotePath,
    );
    _settings = settings.copyWith(remotePath: normalizedPath);
    await settingsStore.write(_settings);
  }

  Future<BackupRunResult> backup({
    void Function(BackupProgress progress)? onProgress,
  }) async {
    await load();
    if (_running) throw const BackupServiceException('备份正在进行');
    final connection = await _webDavConnection();
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    _running = true;
    try {
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
      final compressed = gzip.encode(utf8.encode(exported.records.encode()));
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
      final localItems = await database.select(database.readingItems).get();
      final hashes = {for (final item in localItems) item.contentHash};
      return BackupRestorePreview(
        manifest: manifest,
        newBooks: manifest.objects
            .where((object) => !hashes.contains(object.hash))
            .length,
        existingBooks: manifest.objects
            .where((object) => hashes.contains(object.hash))
            .length,
        progressRows: records.progress.length,
        bookmarkRows: records.bookmarks.length,
        annotationRows: records.annotations.length,
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
    final localHashesBeforeRestore = {
      for (final item in await database.select(database.readingItems).get())
        item.contentHash,
    };
    try {
      final (store, _, _) = await _storeParts();
      await staging.create(recursive: true);
      return await store.withSession(_settings.remotePath, (
        session,
        root,
      ) async {
        final records = await store.readRecords(session, root, manifest);
        final objectsToRestore = <BackupObjectDescriptor>[];
        final newlyImportedHashes = <String>{};
        for (final object in manifest.objects) {
          final local = await database.readingItemByHash(object.hash);
          final localFile = local == null
              ? null
              : await _existingItemFile(local);
          if (local == null || localFile == null) objectsToRestore.add(object);
        }
        onProgress?.call(
          BackupProgress(
            phase: BackupPhase.downloading,
            completed: 0,
            total: objectsToRestore.length,
            message: '正在下载缺失书籍…',
          ),
        );
        for (var i = 0; i < objectsToRestore.length; i++) {
          final object = objectsToRestore[i];
          final destination = File(
            p.join(staging.path, '${object.hash}${object.extension}'),
          );
          await store.downloadObject(session, root, object, destination);
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
          onProgress?.call(
            BackupProgress(
              phase: BackupPhase.downloading,
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
    });
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
    );
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
    return connection;
  }

  Future<File?> _existingItemFile(ReadingItem item) async {
    final paths = LibraryPaths(supportDirectory);
    return paths.resolveExisting(item.filePath, contentHash: item.contentHash);
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

  static String _friendlyError(Object error) {
    if (error is BackupServiceException || error is BackupStoreException) {
      return error.toString();
    }
    return '备份失败，请检查网络、权限或 WebDAV 设置';
  }

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

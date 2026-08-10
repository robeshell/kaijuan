import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:kaijuan/library/backup/backup_service.dart';
import 'package:kaijuan/library/backup/backup_store.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_store.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_outline.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/import/import_pipeline.dart';
import 'package:kaijuan/library/import/import_sources.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/library/remote/remote_models.dart';
import 'package:kaijuan/library/remote/remote_store.dart';
import 'package:kaijuan/library/remote/webdav_client.dart';

const _png = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xde,
  0x00,
  0x00,
  0x00,
  0x0c,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0x00,
  0x00,
  0x00,
  0x03,
  0x00,
  0x01,
  0x00,
  0x05,
  0xfe,
  0xd4,
  0xef,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];

void main() {
  late _FakeDavServer server;
  late Directory sourceDir;
  late AppDatabase sourceDb;
  late BackupService sourceBackup;
  late RemoteConnectionStore sourceConnections;
  late RemoteCredentialStore sourceCredentials;

  setUp(() async {
    server = _FakeDavServer();
    sourceDir = await Directory.systemTemp.createTemp('kaijuan_backup_source_');
    sourceDb = AppDatabase(NativeDatabase.memory());
    final comic = ComicImportService(
      database: sourceDb,
      supportDirectory: sourceDir,
    );
    final book = BookImportService(
      database: sourceDb,
      supportDirectory: sourceDir,
    );
    final pipeline = ImportPipeline(comicImport: comic, bookImport: book);
    final sourceFile = await _createCbz(sourceDir, 'backup.cbz');
    final result = await pipeline.importCandidates([
      ImportCandidate(source: LocalFileImportSource.picked(sourceFile.path)),
    ]);
    expect(result.hasFailures, isFalse, reason: '${result.failures}');

    final item = (await sourceDb.select(sourceDb.readingItems).get()).single;
    await sourceDb.renameReadingItem(item.id, '已重命名的漫画');
    await sourceDb.upsertProgress(
      itemId: item.id,
      locatorJson: '{"page":1}',
      progressFraction: 0.5,
      updatedAt: DateTime.utc(2026, 8, 3, 10),
    );
    await sourceDb.addBookmark(
      itemId: item.id,
      locatorJson: '{"page":1}',
      label: '重要',
    );
    await sourceDb.upsertAnnotation(
      itemId: item.id,
      cfi: 'page-1',
      type: 'highlight',
      color: '#FACC15',
      selectedText: '摘录内容',
      note: '我的笔记',
    );
    final listId = await sourceDb.createReadingList('待读');
    await sourceDb.addItemToList(listId: listId, itemId: item.id);
    final collectionId = await sourceDb.createCollection('系列', onShelf: true);
    await sourceDb.addItemToCollection(
      collectionId: collectionId,
      itemId: item.id,
    );
    final aiDirectory = Directory(p.join(sourceDir.path, 'ai_chat'));
    await aiDirectory.create(recursive: true);
    await File(
      p.join(aiDirectory.path, '${item.contentHash}.json'),
    ).writeAsString(
      jsonEncode(
        AiChatSession(
          contentHash: item.contentHash,
          itemId: item.id,
          messages: [
            AiChatMessage(
              role: AiMessageRole.user,
              content: '这本书的主线是什么？',
              createdAt: DateTime.utc(2026, 8, 3, 11),
            ),
            AiChatMessage(
              role: AiMessageRole.assistant,
              content: '先看主要人物和关键转折。',
              createdAt: DateTime.utc(2026, 8, 3, 11, 1),
            ),
          ],
          outline: AiBookOutline(
            createdAt: DateTime.utc(2026, 8, 3, 12),
            model: 'backup-test',
            overview: '远端大纲。',
            units: const [AiOutlineUnit(title: '主题', blurb: '远端主题说明。')],
          ),
          workOutlines: {
            's3': AiBookOutline(
              createdAt: DateTime.utc(2026, 8, 3, 12, 5),
              model: 'backup-test',
              overview: '合集篇目大纲。',
              units: const [AiOutlineUnit(title: '篇目主题', blurb: '篇目主题说明。')],
            ),
          },
          workMessages: {
            's3': [
              AiChatMessage(
                role: AiMessageRole.user,
                content: '这篇作品讲什么？',
                createdAt: DateTime.utc(2026, 8, 3, 12, 6),
              ),
              AiChatMessage(
                role: AiMessageRole.assistant,
                content: '这是篇目范围内的回答。',
                createdAt: DateTime.utc(2026, 8, 3, 12, 7),
              ),
            ],
          },
        ).toJson(),
      ),
    );

    final aiGraphDirectory = Directory(p.join(sourceDir.path, 'ai_graph'));
    await aiGraphDirectory.create(recursive: true);
    await File(
      p.join(aiGraphDirectory.path, '${item.contentHash}.json'),
    ).writeAsString(
      jsonEncode(
        AiBookGraph(
          contentHash: item.contentHash,
          generatedAt: DateTime.utc(2026, 8, 3, 12, 30),
          model: 'backup-test',
          includesUnread: false,
          coveredSections: const [1],
          entities: const [
            AiGraphEntity(
              name: '张三',
              type: AiGraphEntityType.person,
              description: '远端实体描述。',
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: '张三出场')],
              firstSection: 1,
              lastSection: 1,
            ),
          ],
          relations: const [
            AiGraphRelation(
              source: '张三',
              target: '李四',
              type: 'meet',
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: '张三与李四相遇')],
            ),
          ],
        ).toJson(),
      ),
    );

    final aiMindMapDirectory = Directory(p.join(sourceDir.path, 'ai_mind_map'));
    await aiMindMapDirectory.create(recursive: true);
    await File(
      p.join(aiMindMapDirectory.path, '${item.contentHash}.json'),
    ).writeAsString(
      jsonEncode(
        AiBookMindMap(
          contentHash: item.contentHash,
          workKey: null,
          createdAt: DateTime.utc(2026, 8, 3, 12, 40),
          model: 'backup-test',
          scopeSectionIndices: const [1],
          scopeFingerprint: 'backup-scope',
          contentKind: AiMindMapContentKind.narrative,
          layout: AiMindMapLayout.rightFacing,
          nodes: const [
            AiBookMindMapNode(
              nodeId: 'mm001',
              parentId: null,
              order: 0,
              level: 0,
              title: '全书主题',
              summary: '远端思维导图总览。',
            ),
            AiBookMindMapNode(
              nodeId: 'mm002',
              parentId: 'mm001',
              order: 0,
              level: 1,
              title: '第一主题',
              summary: '远端思维导图分支。',
              evidence: [
                AiMindMapEvidence(
                  sectionIndex: 1,
                  quote: '第一章证据',
                  progressInSection: 0.25,
                  spanResolved: true,
                ),
              ],
            ),
          ],
        ).toJson(),
      ),
    );
    await File(
      p.join(aiMindMapDirectory.path, '${item.contentHash}.checkpoint.json'),
    ).writeAsString(
      jsonEncode(
        AiMindMapCheckpoint(
          contentHash: item.contentHash,
          workKey: null,
          scopeFingerprint: 'in-progress-scope',
          completedBatches: const [],
        ).toJson(),
      ),
    );

    sourceConnections = MemoryRemoteConnectionStore();
    sourceCredentials = MemoryRemoteCredentialStore();
    final connection = _connection();
    await sourceConnections.write([connection]);
    await sourceCredentials.write(
      connection.id,
      const RemoteCredentials(username: 'u', password: 'p'),
    );
    sourceBackup = BackupService(
      database: sourceDb,
      supportDirectory: sourceDir,
      connectionStore: sourceConnections,
      credentialStore: sourceCredentials,
      importPipeline: pipeline,
      settingsStore: JsonBackupTargetSettingsStore(
        File(p.join(sourceDir.path, 'backup-settings.json')),
      ),
      webDav: WebDavClient(clientFactory: server.createClient),
    );
    await sourceBackup.load();
    await sourceBackup.updateSettings(
      sourceBackup.settings.copyWith(
        connectionId: connection.id,
        remotePath: 'KaijuanBackup/v1',
        deviceId: 'device-a',
        deviceName: '测试设备',
      ),
    );
  });

  tearDown(() async {
    await sourceDb.close();
    if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
  });

  test(
    'backup publishes a valid snapshot and second run reuses objects',
    () async {
      final first = await sourceBackup.backup();
      expect(first.manifest.objects, hasLength(1));
      expect(first.manifest.counts['aiChats'], 1);
      expect(first.manifest.counts['aiGraphs'], 1);
      expect(first.manifest.counts['aiMindMaps'], 1);
      expect(first.uploadedObjects, 1);
      expect(
        server.files.keys.any((key) => key.endsWith('/manifest.json')),
        isTrue,
      );
      expect(server.requests.last, endsWith('.manifest.json.partial'));

      final chunkKey = server.files.keys.singleWhere(
        (key) => key.endsWith('.bin'),
      );
      final validChunk = List<int>.from(server.files[chunkKey]!);
      server.files[chunkKey] = [for (final byte in validChunk) byte ^ 0xff];

      final second = await sourceBackup.backup();
      expect(second.uploadedObjects, 0);
      expect(second.reusedObjects, 1);
      expect(server.files[chunkKey], validChunk);
      expect(second.manifest.snapshotId, isNot(first.manifest.snapshotId));
      final snapshots = await sourceBackup.listSnapshots();
      expect(snapshots, hasLength(2));
      expect(snapshots.first.snapshotId, second.manifest.snapshotId);
    },
  );

  test('restore merges books and records into an empty database', () async {
    final backup = await sourceBackup.backup();
    final targetDir = await Directory.systemTemp.createTemp(
      'kaijuan_backup_target_',
    );
    final targetDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await targetDb.close();
      if (await targetDir.exists()) await targetDir.delete(recursive: true);
    });
    final comic = ComicImportService(
      database: targetDb,
      supportDirectory: targetDir,
    );
    final book = BookImportService(
      database: targetDb,
      supportDirectory: targetDir,
    );
    final connection = _connection();
    final connections = MemoryRemoteConnectionStore();
    await connections.write([connection]);
    final credentials = MemoryRemoteCredentialStore();
    await credentials.write(
      connection.id,
      const RemoteCredentials(username: 'u', password: 'p'),
    );
    final targetBackup = BackupService(
      database: targetDb,
      supportDirectory: targetDir,
      connectionStore: connections,
      credentialStore: credentials,
      importPipeline: ImportPipeline(comicImport: comic, bookImport: book),
      settingsStore: JsonBackupTargetSettingsStore(
        File(p.join(targetDir.path, 'backup-settings.json')),
      ),
      webDav: WebDavClient(clientFactory: server.createClient),
    );
    await targetBackup.load();
    await targetBackup.updateSettings(
      targetBackup.settings.copyWith(
        connectionId: connection.id,
        remotePath: 'KaijuanBackup/v1',
        deviceId: 'device-b',
        deviceName: '恢复设备',
      ),
    );

    final restored = await targetBackup.restore(backup.manifest);
    expect(restored.addedBooks, 1);
    expect(restored.restoredProgress, 1);
    expect(restored.restoredBookmarks, 1);
    expect(restored.restoredAnnotations, 1);
    expect(restored.restoredAiChats, 1);
    expect(restored.restoredAiGraphs, 1);
    expect(restored.restoredAiMindMaps, 1);
    expect(restored.restoredLists, 1);
    expect(restored.restoredCollections, 1);
    expect(
      (await targetDb.select(targetDb.readingItems).get()).single.title,
      '已重命名的漫画',
    );
    expect((await targetDb.select(targetDb.bookmarks).get()), hasLength(1));
    expect(
      (await targetDb.select(targetDb.bookAnnotations).get()),
      hasLength(1),
    );
    final targetHash =
        (await targetDb.select(targetDb.readingItems).get()).single.contentHash;
    final restoredChat = AiChatSession.fromJson(
      jsonDecode(
            await File(
              p.join(targetDir.path, 'ai_chat', '$targetHash.json'),
            ).readAsString(),
          )
          as Map<String, dynamic>,
    );
    expect(restoredChat.messages, hasLength(2));
    expect(restoredChat.outline?.overview, '远端大纲。');
    expect(restoredChat.outline?.units.single.title, '主题');
    expect(restoredChat.workOutlines['s3']?.overview, '合集篇目大纲。');
    expect(restoredChat.workOutlines['s3']?.units.single.title, '篇目主题');
    expect(restoredChat.workMessages['s3'], hasLength(2));
    expect(restoredChat.workMessages['s3']?.first.content, '这篇作品讲什么？');

    final restoredGraph = AiBookGraph.fromJson(
      jsonDecode(
            await File(
              p.join(targetDir.path, 'ai_graph', '$targetHash.json'),
            ).readAsString(),
          )
          as Map<String, dynamic>,
    );
    expect(restoredGraph, isNotNull);
    expect(restoredGraph!.entities.single.name, '张三');
    expect(restoredGraph.relations.single.type, 'meet');
    expect(restoredGraph.coveredSections, [1]);

    final restoredMindMap = AiBookMindMap.fromJson(
      jsonDecode(
        await File(
          p.join(targetDir.path, 'ai_mind_map', '$targetHash.json'),
        ).readAsString(),
      ),
    );
    expect(restoredMindMap, isNotNull);
    expect(restoredMindMap!.root.title, '全书主题');
    expect(restoredMindMap.layout, AiMindMapLayout.rightFacing);
    expect(restoredMindMap.nodes[1].evidence.single.sectionIndex, 1);

    final targetItem =
        (await targetDb.select(targetDb.readingItems).get()).single;
    final localMessages = [
      for (var index = 0; index < 105; index++)
        AiChatMessage(
          role: AiMessageRole.user,
          content: '本地消息 $index',
          createdAt: DateTime.utc(2026, 8, 4).add(Duration(minutes: index)),
        ),
    ];
    final chatStore = JsonAiChatHistoryStore(
      Directory(p.join(targetDir.path, 'ai_chat')),
    );
    await chatStore.write(
      AiChatSession(
        contentHash: targetHash,
        itemId: targetItem.id,
        messages: localMessages,
      ),
    );
    final damagedFile = File(targetItem.filePath);
    await damagedFile.writeAsBytes(
      List<int>.filled(await damagedFile.length(), 0x5a),
      flush: true,
    );

    final repaired = await targetBackup.restore(backup.manifest);
    expect(repaired.updatedBooks, 1);
    expect(
      (await sha256.bind(damagedFile.openRead()).first).toString(),
      targetHash,
    );
    final mergedChat = await chatStore.read(
      contentHash: targetHash,
      itemId: targetItem.id,
    );
    expect(mergedChat?.messages, hasLength(107));
    expect(mergedChat?.messages.first.content, '本地消息 0');
  });

  test('backup store rejects insecure HTTP connections', () async {
    final store = WebDavBackupStore(
      connection: _connection().copyWith(url: 'http://dav.example/root/'),
      credentials: const RemoteCredentials(username: 'u', password: 'p'),
      client: WebDavClient(clientFactory: server.createClient),
    );

    await expectLater(
      store.withSession<void>('KaijuanBackup/v1', (_, _) async {}),
      throwsA(
        isA<BackupStoreException>().having(
          (error) => error.message,
          'message',
          contains('需要使用 HTTPS'),
        ),
      ),
    );
  });
}

RemoteConnection _connection() => const RemoteConnection(
  id: 'webdav:test',
  type: RemoteSourceType.webDav,
  displayName: '测试 WebDAV',
  url: 'https://dav.example/root/',
  status: RemoteConnectionStatus.connected,
);

Future<File> _createCbz(Directory dir, String name) async {
  final archive = Archive()
    ..addFile(ArchiveFile('page.png', _png.length, _png));
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

class _FakeDavServer {
  final Map<String, List<int>> files = {};
  final Set<String> directories = {'/root'};
  final List<String> requests = [];

  http.Client createClient() => _FakeDavClient(this);

  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    final path = _key(request.url.path);
    requests.add('${request.method} $path');
    switch (request.method) {
      case 'MKCOL':
        if (directories.contains(path)) return _response(405, request: request);
        final parent = _key(p.dirname(path));
        if (!directories.contains(parent)) {
          return _response(409, request: request);
        }
        directories.add(path);
        return _response(201, request: request);
      case 'HEAD':
        final body = files[path];
        return body == null
            ? _response(404, request: request)
            : _response(
                200,
                headers: {'content-length': '${body.length}'},
                request: request,
              );
      case 'PUT':
        return _put(request, path);
      case 'MOVE':
        final destination = Uri.parse(request.headers['destination']!).path;
        final bytes = files.remove(path);
        if (bytes == null) return _response(404, request: request);
        files[_key(destination)] = bytes;
        return _response(201, request: request);
      case 'GET':
        final body = files[path];
        return body == null
            ? _response(404, request: request)
            : _response(200, body: body, request: request);
      case 'DELETE':
        files.remove(path);
        return _response(204, request: request);
      case 'PROPFIND':
        return _propfind(request, path);
      default:
        return _response(200, request: request);
    }
  }

  Future<http.StreamedResponse> _put(
    http.BaseRequest request,
    String path,
  ) async {
    final done = Completer<void>();
    unawaited(() async {
      try {
        final bytes = await request.finalize().fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        files[path] = bytes;
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }());
    return http.StreamedResponse(
      Stream<List<int>>.fromFuture(done.future.then((_) => <int>[])),
      201,
      request: request,
    );
  }

  Future<http.StreamedResponse> _propfind(
    http.BaseRequest request,
    String path,
  ) async {
    final children = <String>[];
    for (final directory in directories) {
      if (_key(p.dirname(directory)) == path && directory != path) {
        children.add(directory);
      }
    }
    for (final file in files.keys) {
      if (_key(p.dirname(file)) == path) children.add(file);
    }
    final response = StringBuffer(
      '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">',
    );
    response.write(
      '<d:response><d:href>$path/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
    );
    for (final child in children) {
      final isDir = directories.contains(child);
      final size = files[child]?.length ?? 0;
      response.write(
        '<d:response><d:href>$child${isDir ? '/' : ''}</d:href><d:propstat><d:prop>${isDir ? '<d:resourcetype><d:collection/></d:resourcetype>' : '<d:getcontentlength>$size</d:getcontentlength>'}</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
      );
    }
    response.write('</d:multistatus>');
    return _response(
      207,
      body: utf8.encode(response.toString()),
      request: request,
    );
  }

  static String _key(String path) => path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;

  static http.StreamedResponse _response(
    int status, {
    List<int> body = const [],
    Map<String, String> headers = const {},
    http.BaseRequest? request,
  }) => http.StreamedResponse(
    Stream<List<int>>.value(body),
    status,
    headers: headers,
    request: request,
  );
}

class _FakeDavClient extends http.BaseClient {
  _FakeDavClient(this.server);

  final _FakeDavServer server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      server.handle(request);
}

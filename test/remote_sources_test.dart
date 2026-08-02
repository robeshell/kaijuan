import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:kaijuan/library/import/import_models.dart';
import 'package:kaijuan/library/remote/opds_client.dart';
import 'package:kaijuan/library/remote/remote_import_queue.dart';
import 'package:kaijuan/library/remote/remote_models.dart';
import 'package:kaijuan/library/remote/remote_source_controller.dart';
import 'package:kaijuan/library/remote/remote_store.dart';
import 'package:kaijuan/library/remote/webdav_client.dart';

void main() {
  test('WebDAV probes and parses directories and files', () async {
    final requests = <String>[];
    final webDav = WebDavClient(
      clientFactory: () => _FakeClient((request) {
        requests.add(request.method);
        if (request.method == 'OPTIONS') {
          return _response('', headers: {'dav': '1'});
        }
        expect(request.method, 'PROPFIND');
        expect(request.headers['depth'], '1');
        return _response(_webDavResponse);
      }),
    );

    final result = await webDav.probe(
      'https://dav.example/books',
      credentials: const RemoteCredentials(
        username: 'reader',
        password: 'secret',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.error);
    expect(requests, ['OPTIONS', 'PROPFIND']);
    expect(result.entries, hasLength(2));
    expect(
      result.entries.firstWhere((entry) => entry.isDirectory).displayName,
      '第一集',
    );
    expect(
      result.entries.firstWhere((entry) => !entry.isDirectory).displayName,
      'sample.epub',
    );
  });

  test('OPDS parses acquisition and navigation links', () async {
    String? authorization;
    final opds = OpdsClient(
      clientFactory: () => _FakeClient((request) {
        authorization = request.headers['authorization'];
        return _response(_opdsFeed);
      }),
    );

    final result = await opds.browse(
      'https://catalog.example/root',
      credentials: const RemoteCredentials(username: 'u', password: 'p'),
    );

    expect(authorization, 'Basic dTpw');
    expect(result.entries, hasLength(2));
    expect(result.entries.first.displayName, 'book.epub');
    expect(
      result.entries.first.downloadUri,
      'https://catalog.example/files/book.epub',
    );
    expect(
      result.entries.first.coverUri,
      'https://catalog.example/covers/book.jpg',
    );
    expect(result.entries.last.isDirectory, isTrue);
    expect(
      result.entries.last.navigationUri,
      'https://catalog.example/fiction',
    );
    expect(result.nextUri, 'https://catalog.example/root?page=2');
    expect(result.searchUri, 'https://catalog.example/search?q={searchTerms}');
  });

  test(
    'remote folder selection recursively collects paged OPDS files',
    () async {
      final opds = OpdsClient(
        clientFactory: () => _FakeClient((request) {
          final path = request.url.path;
          final query = request.url.query;
          if (path == '/fiction' && query == '') {
            return _response(_opdsFolderFeed);
          }
          if (path == '/fiction' && query == 'page=2') {
            return _response(_opdsFolderPageTwoFeed);
          }
          if (path == '/fiction/nested') {
            return _response(_opdsNestedFolderFeed);
          }
          fail('unexpected OPDS URL: ${request.url}');
        }),
      );
      final remote = RemoteSourceController(
        connectionStore: MemoryRemoteConnectionStore(),
        credentialStore: MemoryRemoteCredentialStore(),
        opds: opds,
      );
      final connection = RemoteConnection(
        id: 'remote:opds',
        type: RemoteSourceType.opds,
        displayName: '书库',
        url: 'https://catalog.example/root',
        status: RemoteConnectionStatus.connected,
      );
      const folder = RemoteEntry(
        uri: 'fiction',
        displayName: '小说',
        isDirectory: true,
        navigationUri: 'https://catalog.example/fiction',
      );

      final files = await remote.collectFilesRecursively(connection, folder);

      expect(files.map((entry) => entry.displayName), [
        'one.epub',
        'two.epub',
        'three.epub',
      ]);
    },
  );

  test(
    'remote connections persist metadata and secure credentials separately',
    () async {
      final webDav = WebDavClient(
        clientFactory: () => _FakeClient((request) {
          if (request.method == 'OPTIONS') {
            return _response('', headers: {'dav': '1'});
          }
          return _response(_webDavResponse);
        }),
      );
      final connectionStore = MemoryRemoteConnectionStore();
      final credentialStore = MemoryRemoteCredentialStore();
      final remote = RemoteSourceController(
        connectionStore: connectionStore,
        credentialStore: credentialStore,
        webDav: webDav,
      );
      await remote.load();

      final result = await remote.saveConnection(
        type: RemoteSourceType.webDav,
        displayName: '我的 NAS',
        url: 'https://dav.example/books',
        credentials: const RemoteCredentials(
          username: 'reader',
          password: 'secret',
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.error);
      final connection = remote.connectionsFor(RemoteSourceType.webDav).single;
      expect(connection.status, RemoteConnectionStatus.connected);
      expect((await credentialStore.read(connection.id))?.password, 'secret');
      expect(
        (await connectionStore.read()).single.toJson()['url'],
        'https://dav.example/books/',
      );
    },
  );

  test(
    'remote queue waits for start and processes selected files in order',
    () async {
      final remote = RemoteSourceController(
        connectionStore: MemoryRemoteConnectionStore(),
        credentialStore: MemoryRemoteCredentialStore(),
        webDav: WebDavClient(
          clientFactory: () => _FakeClient((request) {
            return _response('book bytes');
          }),
        ),
      );
      final connection = RemoteConnection(
        id: 'remote:1',
        type: RemoteSourceType.webDav,
        displayName: 'NAS',
        url: 'https://dav.example/',
        status: RemoteConnectionStatus.connected,
      );
      final names = <String>[];
      final queue = RemoteImportQueueController(
        remote: remote,
        importOne: (candidate) async {
          final bytes = await candidate.source.openRead().fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          expect(bytes, utf8.encode('book bytes'));
          names.add(candidate.displayName);
          return const ImportResult(added: 1);
        },
        items: [
          RemoteImportQueueItem(
            connection: connection,
            entry: const RemoteEntry(
              uri: 'https://dav.example/a.epub',
              displayName: 'a.epub',
              isDirectory: false,
            ),
          ),
          RemoteImportQueueItem(
            connection: connection,
            entry: const RemoteEntry(
              uri: 'https://dav.example/b.epub',
              displayName: 'b.epub',
              isDirectory: false,
            ),
          ),
        ],
      );

      expect(
        queue.items.every((item) => item.status == RemoteQueueStatus.waiting),
        isTrue,
      );
      await queue.start();
      expect(names, ['a.epub', 'b.epub']);
      expect(queue.allCompleted, isTrue);
    },
  );
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final http.Response Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([response.bodyBytes]),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

http.Response _response(
  String body, {
  Map<String, String> headers = const {},
}) => http.Response.bytes(
  utf8.encode(body),
  body.isEmpty ? 200 : 207,
  headers: headers,
);

const _webDavResponse = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/books/</d:href>
    <d:propstat><d:prop><d:displayname>书库根目录</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/books/%E7%AC%AC%E4%B8%80%E9%9B%86/</d:href>
    <d:propstat><d:prop><d:displayname>%E7%AC%AC%E4%B8%80%E9%9B%86</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/books/sample.epub</d:href>
    <d:propstat><d:prop><d:displayname>sample.epub</d:displayname><d:getcontentlength>12</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

const _opdsFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <link rel="next" href="/root?page=2"/>
  <link rel="search" href="/search?q={searchTerms}"/>
  <entry>
    <title>测试书</title>
    <id>book-1</id>
    <author><name>作者</name></author>
    <link rel="http://opds-spec.org/image" href="/covers/book.jpg" type="image/jpeg"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/files/book.epub" type="application/epub+zip"/>
  </entry>
  <entry>
    <title>小说分类</title>
    <id>fiction</id>
    <link rel="subsection" href="/fiction" type="application/atom+xml;profile=opds-catalog"/>
  </entry>
</feed>''';

const _opdsFolderFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <link rel="next" href="/fiction?page=2"/>
  <entry>
    <title>第一本</title>
    <id>book-1</id>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/files/one.epub" type="application/epub+zip"/>
  </entry>
</feed>''';

const _opdsFolderPageTwoFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>第二本</title>
    <id>book-2</id>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/files/two.epub" type="application/epub+zip"/>
  </entry>
  <entry>
    <title>嵌套分类</title>
    <id>nested</id>
    <link rel="subsection" href="/fiction/nested" type="application/atom+xml"/>
  </entry>
</feed>''';

const _opdsNestedFolderFeed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>第三本</title>
    <id>book-3</id>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/files/three.epub" type="application/epub+zip"/>
  </entry>
</feed>''';

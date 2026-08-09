import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:kaijuan/library/remote/remote_models.dart';
import 'package:kaijuan/library/remote/webdav_client.dart';

void main() {
  group('WebDavClient.list', () {
    test('keeps hrefs inside the authenticated collection origin', () async {
      final client = _ScriptedClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], isNotEmpty);
        final body = utf8.encode(
          '<?xml version="1.0"?>'
          '<d:multistatus xmlns:d="DAV:">'
          '${_entry('/root/backups/', collection: true)}'
          '${_entry('/root/backups/valid/', collection: true)}'
          '${_entry('/root/outside/', collection: true)}'
          '${_entry('https://evil.example/steal/', collection: true)}'
          '</d:multistatus>',
        );
        return http.StreamedResponse(
          Stream<List<int>>.value(body),
          207,
          request: request,
        );
      });
      final webDav = WebDavClient(clientFactory: () => client);

      final entries = await webDav.list(
        'https://dav.example/root/backups/',
        credentials: const RemoteCredentials(username: 'u', password: 'p'),
      );

      expect(entries.map((entry) => entry.displayName), ['valid']);
      expect(entries.single.uri, 'https://dav.example/root/backups/valid/');
    });
  });

  group('WebDavSession.makeCollection', () {
    test('accepts provider 409 when PROPFIND confirms a collection', () async {
      final client = _ScriptedClient((request) async {
        if (request.method == 'MKCOL') return _response(409, request);
        expect(request.method, 'PROPFIND');
        expect(request.headers['Depth'], '0');
        return _propfindResponse(request, collection: true);
      });
      final session = WebDavSession(
        client: client,
        credentials: const RemoteCredentials(),
      );
      addTearDown(session.close);

      await session.makeCollection(Uri.parse('https://dav.example/backup/v1/'));

      expect(client.methods, ['MKCOL', 'PROPFIND']);
    });

    test('rejects an ordinary file with the same name', () async {
      final client = _ScriptedClient((request) async {
        if (request.method == 'MKCOL') return _response(405, request);
        return _propfindResponse(request, collection: false);
      });
      final session = WebDavSession(
        client: client,
        credentials: const RemoteCredentials(),
      );
      addTearDown(session.close);

      await expectLater(
        session.makeCollection(Uri.parse('https://dav.example/backup/v1/')),
        throwsA(
          isA<RemoteProtocolException>()
              .having((error) => error.method, 'method', 'MKCOL')
              .having((error) => error.statusCode, 'statusCode', 405)
              .having((error) => error.uri?.path, 'path', '/backup/v1/')
              .having(
                (error) => error.message,
                'message',
                '远程路径与同名文件冲突，请选择其他备份目录',
              )
              .having(
                (error) => error.toString(),
                'diagnostic',
                contains('MKCOL /backup/v1/ HTTP 405'),
              ),
        ),
      );
    });

    test('explains a 409 when the target is still absent', () async {
      final client = _ScriptedClient((request) async {
        if (request.method == 'MKCOL') return _response(409, request);
        return _response(404, request);
      });
      final session = WebDavSession(
        client: client,
        credentials: const RemoteCredentials(),
      );
      addTearDown(session.close);

      await expectLater(
        session.makeCollection(Uri.parse('https://dav.example/backup/v1/')),
        throwsA(
          isA<RemoteProtocolException>().having(
            (error) => error.message,
            'message',
            '无法创建远程文件夹，请确认上级目录仍然存在后重试',
          ),
        ),
      );
    });
  });
}

String _entry(String href, {required bool collection}) {
  final segments = Uri.parse(
    href,
  ).pathSegments.where((value) => value.isNotEmpty).toList();
  final name = segments.isEmpty ? 'root' : segments.last;
  return '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
      '<d:displayname>$name</d:displayname>'
      '<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status>'
      '</d:propstat></d:response>';
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;
  final List<String> methods = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    methods.add(request.method);
    return handler(request);
  }
}

http.StreamedResponse _propfindResponse(
  http.BaseRequest request, {
  required bool collection,
}) {
  final resource = collection
      ? '<d:resourcetype><d:collection/></d:resourcetype>'
      : '<d:resourcetype/>';
  final body = utf8.encode(
    '<?xml version="1.0"?>'
    '<d:multistatus xmlns:d="DAV:">'
    '<d:response><d:propstat><d:prop>$resource</d:prop>'
    '<d:status>HTTP/1.1 200 OK</d:status>'
    '</d:propstat></d:response></d:multistatus>',
  );
  return http.StreamedResponse(
    Stream<List<int>>.value(body),
    207,
    request: request,
  );
}

http.StreamedResponse _response(int status, http.BaseRequest request) =>
    http.StreamedResponse(
      const Stream<List<int>>.empty(),
      status,
      request: request,
    );

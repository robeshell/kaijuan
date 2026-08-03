import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'remote_http.dart';
import 'remote_models.dart';

class WebDavClient {
  WebDavClient({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? createDefaultRemoteClient;

  static const _timeout = Duration(seconds: 12);

  /// Long-lived transfers need a larger connection establishment/response
  /// window than a directory probe. The response stream itself remains
  /// back-pressure driven, so a slow NAS can still stream for hours.
  static const transferTimeout = Duration(seconds: 60);
  static const _maxXmlBytes = 4 * 1024 * 1024;
  final http.Client Function() _clientFactory;

  /// Opens a reusable WebDAV session for write-heavy workflows such as
  /// backup. The browsing/import APIs below intentionally keep their own
  /// short-lived clients; a backup may issue hundreds of requests and should
  /// not create a new TLS connection for every chunk.
  WebDavSession openSession({
    required RemoteCredentials credentials,
    bool allowBadCertificate = false,
  }) {
    final client = allowBadCertificate
        ? createLenientRemoteClient()
        : _clientFactory();
    return WebDavSession(client: client, credentials: credentials);
  }

  Future<RemoteProbeResult> probe(
    String url, {
    required RemoteCredentials credentials,
    bool allowBadCertificate = false,
  }) async {
    final client = allowBadCertificate
        ? createLenientRemoteClient()
        : _clientFactory();
    try {
      final uri = Uri.parse(url);
      final options = http.Request('OPTIONS', uri);
      _applyCredentials(options, credentials);
      final optionsResponse = await client.send(options).timeout(_timeout);
      if (optionsResponse.statusCode == 401 ||
          optionsResponse.statusCode == 403) {
        await optionsResponse.stream.drain<void>();
        return const RemoteProbeResult(
          entries: [],
          error: '认证失败，请检查用户名和密码',
          authenticationFailed: true,
        );
      }
      final dav = _header(optionsResponse.headers, 'dav');
      await optionsResponse.stream.drain<void>();
      if (optionsResponse.statusCode < 200 ||
          optionsResponse.statusCode >= 300 ||
          dav == null ||
          dav.trim().isEmpty) {
        return const RemoteProbeResult(entries: [], error: '该地址没有提供 WebDAV 服务');
      }
      return RemoteProbeResult(
        entries: await _listWithClient(client, uri, credentials),
      );
    } on TimeoutException {
      return const RemoteProbeResult(entries: [], error: '连接超时，请检查网络或服务器状态');
    } on FormatException {
      return const RemoteProbeResult(entries: [], error: '地址或服务器响应格式无效');
    } catch (error) {
      return RemoteProbeResult(
        entries: [],
        error: remoteTlsError(error) ?? _friendlyError(error),
      );
    } finally {
      client.close();
    }
  }

  Future<List<RemoteEntry>> list(
    String url, {
    required RemoteCredentials credentials,
    bool allowBadCertificate = false,
  }) async {
    final client = allowBadCertificate
        ? createLenientRemoteClient()
        : _clientFactory();
    try {
      return await _listWithClient(
        client,
        Uri.parse(normalizeWebDavUrl(url)),
        credentials,
      );
    } finally {
      client.close();
    }
  }

  Stream<List<int>> download(
    String url, {
    required RemoteCredentials credentials,
    bool allowBadCertificate = false,
  }) async* {
    final client = allowBadCertificate
        ? createLenientRemoteClient()
        : _clientFactory();
    try {
      final request = http.Request('GET', Uri.parse(url));
      _applyCredentials(request, credentials);
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw RemoteProtocolException(_statusMessage(response.statusCode));
      }
      yield* response.stream;
    } finally {
      client.close();
    }
  }

  Future<List<RemoteEntry>> _listWithClient(
    http.Client client,
    Uri uri,
    RemoteCredentials credentials,
  ) async {
    final request = http.Request('PROPFIND', uri)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = _propfindBody;
    _applyCredentials(request, credentials);
    final response = await client.send(request).timeout(_timeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      await response.stream.drain<void>();
      throw const RemoteProtocolException('认证失败，请检查用户名和密码');
    }
    if (response.statusCode != 207) {
      await response.stream.drain<void>();
      throw RemoteProtocolException(_statusMessage(response.statusCode));
    }
    final body = await _readBody(response).timeout(_timeout);
    return _parse(body, baseUri: uri);
  }

  Future<String> _readBody(http.StreamedResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxXmlBytes) {
        throw const FormatException('WebDAV 响应超过 4 MiB 限制');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  List<RemoteEntry> _parse(String source, {required Uri baseUri}) {
    final document = XmlDocument.parse(source);
    final entries = <RemoteEntry>[];
    for (final response in _elementsNamed(document, 'response')) {
      final href = _firstText(response, 'href');
      if (href == null || href.isEmpty) continue;
      final uri = _resolve(baseUri, href);
      if (uri == null) continue;
      // PROPFIND with Depth: 1 includes the requested collection itself.
      // It is not a child folder and must not appear in the browser.
      if (_sameResource(uri, baseUri)) continue;
      final propstats = _elementsNamed(response, 'propstat')
          .where(
            (element) =>
                _firstText(element, 'status')?.contains(' 200 ') == true,
          )
          .toList(growable: false);
      final scopes = propstats.isEmpty ? <XmlNode>[response] : propstats;
      final name =
          _decodeDisplayName(_firstTextFrom(scopes, 'displayname')) ??
          _decodeDisplayName(
            uri.pathSegments.where((segment) => segment.isNotEmpty).lastOrNull,
          ) ??
          uri.toString();
      final isDirectory = scopes.any(
        (scope) => _elementsNamed(scope, 'collection').isNotEmpty,
      );
      final size =
          int.tryParse(_firstTextFrom(scopes, 'getcontentlength') ?? '') ?? -1;
      final modified = parseRemoteHttpDate(
        _firstTextFrom(scopes, 'getlastmodified'),
      );
      entries.add(
        RemoteEntry(
          uri: uri.toString(),
          displayName: name,
          isDirectory: isDirectory,
          size: size,
          modifiedAt: modified,
        ),
      );
    }
    return entries;
  }

  void _applyCredentials(
    http.BaseRequest request,
    RemoteCredentials credentials,
  ) {
    if (credentials.isEmpty) return;
    request.headers['Authorization'] =
        'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';
  }

  String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  Iterable<XmlElement> _elementsNamed(XmlNode node, String name) => node
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == name);

  String? _firstText(XmlNode node, String name) =>
      _elementsNamed(node, name).firstOrNull?.innerText.trim();

  String? _firstTextFrom(Iterable<XmlNode> nodes, String name) {
    for (final node in nodes) {
      final value = _firstText(node, name);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _decodeDisplayName(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  Uri? _resolve(Uri base, String value) {
    final decoded = Uri.decodeFull(value.trim());
    final parsed = Uri.tryParse(decoded);
    if (parsed == null) return null;
    return parsed.hasScheme ? parsed : base.resolveUri(parsed);
  }

  bool _sameResource(Uri left, Uri right) {
    String normalizedPath(Uri value) {
      final path = value.path.isEmpty ? '/' : value.path;
      return path.endsWith('/') ? path : '$path/';
    }

    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port &&
        normalizedPath(left) == normalizedPath(right);
  }

  static String normalizeWebDavUrl(String value) {
    final uri = Uri.parse(value.trim());
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const FormatException('WebDAV 地址必须是有效的 HTTP(S) URL');
    }
    if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const FormatException('请把凭据填在账号密码字段中，地址不能包含片段');
    }
    final path = uri.path.isEmpty || uri.path.endsWith('/')
        ? uri.path
        : '${uri.path}/';
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: path,
        )
        .toString();
  }

  /// Returns the path of [targetUrl] relative to the configured WebDAV root.
  ///
  /// Folder pickers use this instead of slicing URL strings so encoded names,
  /// host casing, and a trailing slash on the root remain well-defined.
  static String? relativePathFromRoot(String rootUrl, String targetUrl) {
    try {
      final root = Uri.parse(normalizeWebDavUrl(rootUrl));
      final target = Uri.parse(targetUrl.trim());
      if (target.query.isNotEmpty || target.fragment.isNotEmpty) return null;
      if (root.scheme.toLowerCase() != target.scheme.toLowerCase() ||
          root.host.toLowerCase() != target.host.toLowerCase() ||
          root.port != target.port ||
          target.userInfo.isNotEmpty) {
        return null;
      }
      final baseSegments = root.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      final targetSegments = target.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (targetSegments.any((segment) => segment == '.' || segment == '..')) {
        return null;
      }
      if (targetSegments.length < baseSegments.length) return null;
      for (var index = 0; index < baseSegments.length; index++) {
        if (targetSegments[index] != baseSegments[index]) return null;
      }
      return targetSegments.skip(baseSegments.length).join('/');
    } catch (_) {
      return null;
    }
  }

  static String _statusMessage(int status) => '服务器返回 HTTP $status';

  static String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('connection refused')) return '无法连接到服务器，请检查地址和端口';
    if (text.contains('host') && text.contains('not found')) {
      return '找不到服务器地址，请检查 URL';
    }
    return '连接失败，请检查网络或服务器状态';
  }
}

class RemoteProtocolException implements Exception {
  const RemoteProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>''';

/// A reusable, authenticated WebDAV request session.
///
/// WebDAV servers in the wild differ in how much of RFC 4918 they implement,
/// so the backup layer only depends on the small common subset: MKCOL, HEAD,
/// streamed PUT, MOVE, GET and DELETE.
class WebDavSession {
  WebDavSession({required this._client, required this.credentials});

  final http.Client _client;
  final RemoteCredentials credentials;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  Future<void> makeCollection(Uri uri) async {
    final response = await _send(http.Request('MKCOL', uri));
    // 405 means the collection already exists, which is the desired result
    // for an idempotent directory ensure operation.
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        response.statusCode != 405) {
      await response.stream.drain<void>();
      throw RemoteProtocolException(_statusMessage(response.statusCode));
    }
    await response.stream.drain<void>();
  }

  Future<WebDavStat?> stat(Uri uri) async {
    final response = await _send(http.Request('HEAD', uri));
    final status = response.statusCode;
    await response.stream.drain<void>();
    if (status == 404 || status == 410) return null;
    if (status < 200 || status >= 300) {
      throw RemoteProtocolException(_statusMessage(status));
    }
    return WebDavStat(
      uri: uri,
      statusCode: status,
      contentLength: int.tryParse(
        _header(response.headers, 'content-length') ?? '',
      ),
      etag: _header(response.headers, 'etag'),
    );
  }

  Future<void> putBytes(Uri uri, List<int> bytes) {
    return putStream(uri, Stream<List<int>>.value(bytes), length: bytes.length);
  }

  Future<void> putStream(
    Uri uri,
    Stream<List<int>> bytes, {
    int? length,
  }) async {
    final request = http.StreamedRequest('PUT', uri);
    _applyCredentials(request);
    request.headers['Content-Type'] = 'application/octet-stream';
    if (length != null) request.contentLength = length;

    final responseFuture = _client
        .send(request)
        .timeout(WebDavClient.transferTimeout);
    try {
      await for (final chunk in bytes) {
        request.sink.add(chunk);
      }
      await request.sink.close();
    } catch (_) {
      await request.sink.close();
      rethrow;
    }
    final response = await responseFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw RemoteProtocolException(_statusMessage(response.statusCode));
    }
    await response.stream.drain<void>();
  }

  Stream<List<int>> download(Uri uri) async* {
    final response = await _send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw RemoteProtocolException(_statusMessage(response.statusCode));
    }
    yield* response.stream;
  }

  Future<void> move(
    Uri source,
    Uri destination, {
    bool overwrite = false,
  }) async {
    final request = http.Request('MOVE', source)
      ..headers['Destination'] = destination.toString()
      ..headers['Overwrite'] = overwrite ? 'T' : 'F';
    final response = await _send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw RemoteProtocolException(_statusMessage(response.statusCode));
    }
    await response.stream.drain<void>();
  }

  Future<void> delete(Uri uri) async {
    final response = await _send(http.Request('DELETE', uri));
    if (response.statusCode != 404 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      await response.stream.drain<void>();
      throw RemoteProtocolException(_statusMessage(response.statusCode));
    }
    await response.stream.drain<void>();
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) {
    if (_closed) throw StateError('WebDAV session is closed');
    _applyCredentials(request);
    return _client.send(request).timeout(WebDavClient.transferTimeout);
  }

  void _applyCredentials(http.BaseRequest request) {
    if (credentials.isEmpty) return;
    request.headers['Authorization'] =
        'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';
  }

  String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  static String _statusMessage(int status) => '服务器返回 HTTP $status';
}

class WebDavStat {
  const WebDavStat({
    required this.uri,
    required this.statusCode,
    this.contentLength,
    this.etag,
  });

  final Uri uri;
  final int statusCode;
  final int? contentLength;
  final String? etag;
}

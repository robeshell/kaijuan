import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'remote_http.dart';
import 'remote_models.dart';

class OpdsClient {
  OpdsClient({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? createDefaultRemoteClient;

  static const _timeout = Duration(seconds: 12);
  static const _maxFeedBytes = 8 * 1024 * 1024;
  final http.Client Function() _clientFactory;

  Future<RemoteProbeResult> probe(
    String url, {
    required RemoteCredentials credentials,
  }) async {
    try {
      return await browse(url, credentials: credentials);
    } on TimeoutException {
      return const RemoteProbeResult(entries: [], error: '连接超时，请检查网络或服务器状态');
    } on RemoteProtocolException catch (error) {
      return RemoteProbeResult(
        entries: [],
        error: error.message,
        authenticationFailed: error.authenticationFailed,
      );
    } on FormatException {
      return const RemoteProbeResult(entries: [], error: 'OPDS 地址或目录格式无效');
    } catch (error) {
      return RemoteProbeResult(
        entries: [],
        error: remoteTlsError(error) ?? '无法连接到 OPDS 目录，请检查地址和网络',
      );
    }
  }

  Future<RemoteProbeResult> browse(
    String url, {
    required RemoteCredentials credentials,
  }) async {
    final client = _clientFactory();
    try {
      final request = http.Request('GET', Uri.parse(url));
      _applyCredentials(request, credentials);
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.stream.drain<void>();
        throw const RemoteProtocolException(
          '认证失败，请检查用户名和密码',
          authenticationFailed: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw RemoteProtocolException('服务器返回 HTTP ${response.statusCode}');
      }
      final body = await _readBody(response).timeout(_timeout);
      return _parse(body, Uri.parse(url));
    } finally {
      client.close();
    }
  }

  Stream<List<int>> download(
    String url, {
    required RemoteCredentials credentials,
  }) async* {
    final client = _clientFactory();
    try {
      final request = http.Request('GET', Uri.parse(url));
      _applyCredentials(request, credentials);
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw RemoteProtocolException('下载失败：HTTP ${response.statusCode}');
      }
      yield* response.stream;
    } finally {
      client.close();
    }
  }

  Future<String> _readBody(http.StreamedResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (builder.length + chunk.length > _maxFeedBytes) {
        throw const FormatException('OPDS 目录响应超过 8 MiB 限制');
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  RemoteProbeResult _parse(String source, Uri baseUri) {
    final document = XmlDocument.parse(source);
    final entries = <RemoteEntry>[];
    for (final entry in _elementsNamed(document, 'entry')) {
      final title = _firstText(entry, 'title') ?? '未命名书目';
      final id = _firstText(entry, 'id') ?? title;
      final author = _firstText(
        entry,
        'name',
        within: _firstElement(entry, 'author'),
      );
      final summary =
          _firstText(entry, 'summary') ?? _firstText(entry, 'content');
      String? coverUri;
      String? downloadUri;
      String? navigationUri;
      for (final link in _elementsNamed(entry, 'link')) {
        final href = link.getAttribute('href');
        if (href == null || href.isEmpty) continue;
        final resolved = _resolve(baseUri, href);
        if (resolved == null) continue;
        final rel = (link.getAttribute('rel') ?? '').toLowerCase();
        final type = (link.getAttribute('type') ?? '').toLowerCase();
        if (rel.contains('thumbnail') || rel.contains('image')) {
          coverUri ??= resolved.toString();
        }
        if (rel.contains('acquisition') ||
            _isSupportedMime(type) ||
            RemoteEntry(
              uri: resolved.toString(),
              displayName: title,
              isDirectory: false,
            ).isSupportedFile) {
          downloadUri ??= resolved.toString();
          continue;
        }
        if (rel == 'subsection' ||
            (rel == 'alternate' && type.contains('atom'))) {
          navigationUri ??= resolved.toString();
        }
      }
      if (downloadUri != null) {
        final fileName = _fileNameFromDownload(downloadUri, title);
        entries.add(
          RemoteEntry(
            uri: id,
            displayName: fileName,
            isDirectory: false,
            title: title,
            mimeType: _mimeFor(entry),
            description: summary,
            author: author,
            coverUri: coverUri,
            downloadUri: downloadUri,
          ),
        );
      } else if (navigationUri != null) {
        entries.add(
          RemoteEntry(
            uri: id,
            displayName: title,
            isDirectory: true,
            title: title,
            description: summary,
            author: author,
            coverUri: coverUri,
            navigationUri: navigationUri,
          ),
        );
      }
    }
    return RemoteProbeResult(
      entries: entries,
      nextUri: _linkByRel(document, baseUri, 'next'),
      searchUri: _searchTemplate(document, baseUri),
    );
  }

  String? _mimeFor(XmlElement entry) {
    for (final link in _elementsNamed(entry, 'link')) {
      final type = link.getAttribute('type');
      if (type != null && _isSupportedMime(type.toLowerCase())) return type;
    }
    return null;
  }

  bool _isSupportedMime(String type) =>
      type.contains('epub') ||
      type.contains('zip') ||
      type.contains('pdf') ||
      type.contains('fb2') ||
      type.contains('mobipocket') ||
      type.contains('azw');

  String _fileNameFromDownload(String url, String title) {
    final uri = Uri.tryParse(url);
    final pathName = uri?.pathSegments
        .where((value) => value.isNotEmpty)
        .lastOrNull;
    if (pathName != null && pathName.contains('.')) {
      return Uri.decodeComponent(pathName);
    }
    final mime = uri == null ? null : _extensionFromPath(uri.path);
    return '${title.trim().isEmpty ? '未命名书目' : title.trim()}${mime ?? '.epub'}';
  }

  String? _extensionFromPath(String path) {
    final lower = path.toLowerCase();
    for (final extension in [
      '.epub',
      '.cbz',
      '.zip',
      '.pdf',
      '.fb2',
      '.mobi',
      '.azw3',
    ]) {
      if (lower.endsWith(extension)) return extension;
    }
    return null;
  }

  String? _linkByRel(XmlDocument document, Uri base, String wanted) {
    for (final link in _elementsNamed(document, 'link')) {
      if ((link.getAttribute('rel') ?? '').toLowerCase() != wanted) continue;
      final href = link.getAttribute('href');
      final resolved = href == null ? null : _resolve(base, href);
      if (resolved != null) {
        return resolved
            .toString()
            .replaceAll('%7BsearchTerms%7D', '{searchTerms}')
            .replaceAll('%7BsearchTerms%3F%7D', '{searchTerms?}');
      }
    }
    return null;
  }

  String? _searchTemplate(XmlDocument document, Uri base) {
    for (final link in _elementsNamed(document, 'link')) {
      final rel = (link.getAttribute('rel') ?? '').toLowerCase();
      if (rel != 'search') continue;
      final href = link.getAttribute('href');
      if (href == null) continue;
      final resolved = _resolve(base, href);
      if (resolved != null) {
        return resolved
            .toString()
            .replaceAll('%7BsearchTerms%7D', '{searchTerms}')
            .replaceAll('%7BsearchTerms%3F%7D', '{searchTerms?}');
      }
    }
    return null;
  }

  void _applyCredentials(
    http.BaseRequest request,
    RemoteCredentials credentials,
  ) {
    if (credentials.isEmpty) return;
    request.headers['Authorization'] =
        'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';
  }

  Iterable<XmlElement> _elementsNamed(XmlNode node, String name) => node
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == name);

  XmlElement? _firstElement(XmlNode node, String name) =>
      _elementsNamed(node, name).firstOrNull;

  String? _firstText(XmlNode node, String name, {XmlNode? within}) =>
      _elementsNamed(within ?? node, name).firstOrNull?.innerText.trim();

  Uri? _resolve(Uri base, String href) {
    final parsed = Uri.tryParse(href.trim());
    if (parsed == null) return null;
    return parsed.hasScheme ? parsed : base.resolveUri(parsed);
  }
}

class RemoteProtocolException implements Exception {
  const RemoteProtocolException(
    this.message, {
    this.authenticationFailed = false,
  });

  final String message;
  final bool authenticationFailed;
}

// The service keeps its implementation dependencies private while exposing
// a small public lifecycle/state API.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'import_models.dart';
import 'import_sources.dart';

typedef WifiImportCallback =
    Future<ImportResult> Function(ImportCandidate candidate);
typedef WifiIpProvider = Future<String?> Function();

enum WifiTransferPhase {
  stopped,
  starting,
  waiting,
  receiving,
  importing,
  completed,
  failed,
}

/// Short-lived HTTP upload server used by the WiFi transfer entry point.
///
/// The server only exposes a single token-protected upload endpoint. Uploaded
/// bytes first land in a private temporary directory and are then handed to
/// the regular [ImportPipeline] through [WifiImportCallback].
class WifiTransferService extends ChangeNotifier {
  WifiTransferService({
    required Directory supportDirectory,
    required WifiImportCallback onImport,
    NetworkInfo? networkInfo,
    WifiIpProvider? ipProvider,
    this.sessionDuration = const Duration(minutes: 20),
    this.maxFileBytes = 2 * 1024 * 1024 * 1024,
  }) : _supportDirectory = supportDirectory,
       _onImport = onImport,
       _networkInfo = networkInfo ?? NetworkInfo(),
       _ipProvider = ipProvider;

  static const _transferDirectoryName = '.wifi-transfer';
  static const _tokenQuery = 'token';
  static const _fileNameHeader = 'x-kaijuan-file-name';
  static const _jsonHeaders = {
    HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
    HttpHeaders.cacheControlHeader: 'no-store',
  };

  final Directory _supportDirectory;
  final WifiImportCallback _onImport;
  final NetworkInfo _networkInfo;
  final WifiIpProvider? _ipProvider;

  final Duration sessionDuration;
  final int maxFileBytes;

  HttpServer? _server;
  Timer? _expiryTimer;
  String? _token;
  DateTime? _expiresAt;
  bool _starting = false;
  bool _uploading = false;
  bool _disposed = false;

  WifiTransferPhase _phase = WifiTransferPhase.stopped;
  String? _url;
  String? _currentFileName;
  int _receivedBytes = 0;
  int? _totalBytes;
  ImportResult? _lastResult;
  String? _error;

  WifiTransferPhase get phase => _phase;
  bool get isRunning => _server != null;
  bool get isUploading => _uploading;
  String? get url => _url;
  DateTime? get expiresAt => _expiresAt;
  String? get currentFileName => _currentFileName;
  int get receivedBytes => _receivedBytes;
  int? get totalBytes => _totalBytes;
  ImportResult? get lastResult => _lastResult;
  String? get error => _error;

  double? get progress {
    final total = _totalBytes;
    if (total == null || total <= 0) return null;
    return (_receivedBytes / total).clamp(0.0, 1.0);
  }

  Future<void> start() async {
    if (isRunning || _starting) return;
    _starting = true;
    _phase = WifiTransferPhase.starting;
    _error = null;
    _lastResult = null;
    _notify();

    try {
      await _purgeTransferPartials();
      final token = _newToken();
      final router = Router()
        ..get('/', _serveUploadPage)
        ..get('/health', _health)
        ..post('/upload', _upload);
      final handler = const Pipeline().addHandler(router.call);
      final server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        0,
        poweredByHeader: null,
      );
      _server = server;
      _token = token;

      final ip = await _resolveLocalIp();
      if (ip == null || ip.isEmpty) {
        await server.close(force: true);
        _server = null;
        throw const SocketException('无法获取当前设备的局域网地址');
      }

      _expiresAt = DateTime.now().add(sessionDuration);
      _url = Uri(
        scheme: 'http',
        host: ip,
        port: server.port,
        path: '/',
        queryParameters: {_tokenQuery: token},
      ).toString();
      _expiryTimer = Timer(sessionDuration, () {
        unawaited(stop());
      });
      _phase = WifiTransferPhase.waiting;
      _notify();
    } catch (error) {
      _error = error.toString();
      _phase = WifiTransferPhase.failed;
      _notify();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final server = _server;
    _server = null;
    _token = null;
    _url = null;
    _expiresAt = null;
    _currentFileName = null;
    _receivedBytes = 0;
    _totalBytes = null;
    _uploading = false;
    if (server != null) await server.close(force: true);
    _phase = WifiTransferPhase.stopped;
    _notify();
  }

  Future<Response> _serveUploadPage(Request request) async {
    if (!_isAuthorized(request)) return _unauthorized();
    return Response.ok(
      _uploadPage,
      headers: const {
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store',
      },
    );
  }

  Response _health(Request request) {
    if (!_isAuthorized(request)) return _unauthorized();
    return Response.ok(
      jsonEncode({'ok': true, 'expiresAt': _expiresAt?.toIso8601String()}),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _upload(Request request) async {
    if (!_isAuthorized(request)) return _unauthorized();
    if (_uploading) {
      return Response(
        HttpStatus.conflict,
        body: jsonEncode({'ok': false, 'message': '已有文件正在传输'}),
        headers: _jsonHeaders,
      );
    }

    final fileName = _safeFileName(request.headers[_fileNameHeader]);
    if (fileName == null) {
      return Response(
        HttpStatus.badRequest,
        body: jsonEncode({'ok': false, 'message': '缺少有效文件名'}),
        headers: _jsonHeaders,
      );
    }
    final announcedLength = request.contentLength;
    if (announcedLength != null && announcedLength > maxFileBytes) {
      return Response(
        HttpStatus.requestEntityTooLarge,
        body: jsonEncode({'ok': false, 'message': '文件超过大小限制'}),
        headers: _jsonHeaders,
      );
    }

    _uploading = true;
    _phase = WifiTransferPhase.receiving;
    _currentFileName = fileName;
    _receivedBytes = 0;
    _totalBytes = announcedLength;
    _error = null;
    _notify();

    File? partial;
    try {
      final directory = Directory(
        p.join(_supportDirectory.path, _transferDirectoryName),
      );
      await directory.create(recursive: true);
      partial = File(
        p.join(
          directory.path,
          '${DateTime.now().microsecondsSinceEpoch}-${_newToken()}.partial',
        ),
      );
      final sink = partial.openWrite();
      try {
        await for (final chunk in request.read()) {
          _receivedBytes += chunk.length;
          if (_receivedBytes > maxFileBytes) {
            throw const _WifiTransferException('文件超过大小限制');
          }
          sink.add(chunk);
          _notify();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      _phase = WifiTransferPhase.importing;
      _notify();
      final result = await _onImport(
        ImportCandidate(
          source: LocalFileImportSource(
            partial,
            method: ImportMethod.wifi,
            displayName: fileName,
            mimeType: request.headers[HttpHeaders.contentTypeHeader],
          ),
        ),
      );
      _lastResult = result;
      _phase = result.hasFailures
          ? WifiTransferPhase.failed
          : WifiTransferPhase.completed;
      if (result.hasFailures) {
        _error = result.failures.first.reason;
      }
      _notify();
      return Response(
        result.hasFailures ? HttpStatus.unprocessableEntity : HttpStatus.ok,
        body: jsonEncode(_resultJson(result)),
        headers: _jsonHeaders,
      );
    } catch (error) {
      _phase = WifiTransferPhase.failed;
      _error = error.toString();
      _notify();
      final statusCode =
          error is _WifiTransferException && error.message == '文件超过大小限制'
          ? HttpStatus.requestEntityTooLarge
          : HttpStatus.internalServerError;
      return Response(
        statusCode,
        body: jsonEncode({'ok': false, 'message': error.toString()}),
        headers: _jsonHeaders,
      );
    } finally {
      if (partial != null) await _deleteIfExists(partial);
      _uploading = false;
      _notify();
    }
  }

  bool _isAuthorized(Request request) {
    final token = _token;
    final expiresAt = _expiresAt;
    return token != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt) &&
        request.url.queryParameters[_tokenQuery] == token;
  }

  Response _unauthorized() => Response(
    HttpStatus.unauthorized,
    body: '传输链接已失效，请回到开卷重新打开 WiFi 传书。',
    headers: const {HttpHeaders.contentTypeHeader: 'text/plain; charset=utf-8'},
  );

  Future<String?> _resolveLocalIp() async {
    try {
      final provided = await (_ipProvider?.call() ?? _networkInfo.getWifiIP());
      if (_isUsableIp(provided)) return provided;
    } catch (_) {
      // Fall through to the dart:io interface list, which also covers desktop
      // machines where the platform WiFi API may not be available.
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (_isUsableIp(address.address)) return address.address;
        }
      }
    } catch (_) {
      // Report a friendly error from start() rather than exposing the socket
      // binding exception to the user.
    }
    return null;
  }

  bool _isUsableIp(String? value) {
    if (value == null || value.isEmpty) return false;
    return value != InternetAddress.loopbackIPv4.address &&
        !value.startsWith('169.254.');
  }

  Future<void> _purgeTransferPartials() async {
    final directory = Directory(
      p.join(_supportDirectory.path, _transferDirectoryName),
    );
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.partial')) {
        await _deleteIfExists(entity);
      }
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A failed cleanup must not change an already completed import result.
    }
  }

  String _newToken() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String? _safeFileName(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(encoded);
    } catch (_) {
      decoded = encoded;
    }
    final normalized = decoded.replaceAll('\\', '/');
    final base = normalized.split('/').last.trim();
    if (base.isEmpty || base == '.' || base == '..') return null;
    final cleaned = base.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '_');
    return cleaned.isEmpty ? null : cleaned;
  }

  Map<String, Object?> _resultJson(ImportResult result) => {
    'ok': !result.hasFailures,
    'added': result.added,
    'updated': result.updated,
    'failures': [
      for (final failure in result.failures)
        {'fileName': failure.fileName, 'reason': failure.reason},
    ],
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    unawaited(_server?.close(force: true));
    _server = null;
    super.dispose();
  }

  static const _uploadPage = r'''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>开卷 · WiFi 传书</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    body { margin:0; min-height:100vh; display:grid; place-items:center; background:#f7f9fc; color:#172033; }
    main { width:min(92vw,480px); box-sizing:border-box; padding:28px; border:1px solid #dce3ee; border-radius:22px; background:#fff; box-shadow:0 16px 50px #27364a18; }
    h1 { margin:0 0 8px; font-size:24px; } p { color:#5c687b; line-height:1.6; }
    label { display:flex; justify-content:center; align-items:center; min-height:54px; margin-top:20px; border-radius:14px; background:#e76b38; color:#fff; font-weight:600; cursor:pointer; }
    input { display:none; } #status { margin-top:18px; min-height:24px; font-size:14px; color:#5c687b; white-space:pre-wrap; }
  </style>
</head>
<body>
  <main>
    <h1>WiFi 传书</h1>
    <p>请从当前设备选择图书或漫画文件。文件会直接导入开卷，不会上传到互联网。</p>
    <label for="files">选择文件</label>
    <input id="files" type="file" multiple>
    <div id="status">等待选择文件</div>
  </main>
  <script>
    const token = new URLSearchParams(location.search).get('token');
    const input = document.getElementById('files');
    const status = document.getElementById('status');
    input.addEventListener('change', async () => {
      const files = Array.from(input.files || []);
      for (const file of files) {
        status.textContent = `正在传输：${file.name}`;
        try {
          const response = await fetch(`/upload?token=${encodeURIComponent(token || '')}`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/octet-stream',
              'X-Kaijuan-File-Name': encodeURIComponent(file.name),
            },
            body: file,
          });
          const result = await response.json();
          if (!response.ok || !result.ok) throw new Error(result.message || (result.failures && result.failures[0] && result.failures[0].reason) || '导入失败');
          status.textContent = `已导入：${file.name}`;
        } catch (error) {
          status.textContent = `失败：${file.name}\n${error.message || error}`;
        }
      }
      input.value = '';
    });
  </script>
</body>
</html>''';
}

class _WifiTransferException implements Exception {
  const _WifiTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

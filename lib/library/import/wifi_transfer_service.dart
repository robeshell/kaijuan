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

enum WifiTransferItemPhase { queued, receiving, importing, completed, failed }

class WifiTransferQueueItem {
  const WifiTransferQueueItem({
    required this.id,
    required this.fileName,
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes,
    this.result,
    this.error,
  });

  final String id;
  final String fileName;
  final WifiTransferItemPhase phase;
  final int receivedBytes;
  final int? totalBytes;
  final ImportResult? result;
  final String? error;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  WifiTransferQueueItem copyWith({
    WifiTransferItemPhase? phase,
    int? receivedBytes,
    int? totalBytes,
    ImportResult? result,
    String? error,
  }) {
    return WifiTransferQueueItem(
      id: id,
      fileName: fileName,
      phase: phase ?? this.phase,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      result: result ?? this.result,
      error: error ?? this.error,
    );
  }
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
  static const _queueIdQuery = 'queueId';
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
  int _sessionGeneration = 0;

  WifiTransferPhase _phase = WifiTransferPhase.stopped;
  String? _url;
  String? _currentFileName;
  int _receivedBytes = 0;
  int? _totalBytes;
  ImportResult? _lastResult;
  String? _error;
  int _queueSequence = 0;
  final List<WifiTransferQueueItem> _queue = [];

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
  List<WifiTransferQueueItem> get queue => List.unmodifiable(_queue);

  ImportResult get queueResult {
    var result = const ImportResult();
    for (final item in _queue) {
      final itemResult = item.result;
      if (itemResult != null) {
        result += itemResult;
      } else if (item.phase == WifiTransferItemPhase.failed &&
          item.error != null) {
        result += ImportResult(
          failures: [ImportFailure(path: item.fileName, reason: item.error!)],
        );
      }
    }
    return result;
  }

  double? get progress {
    final total = _totalBytes;
    if (total == null || total <= 0) return null;
    return (_receivedBytes / total).clamp(0.0, 1.0);
  }

  Future<void> start() async {
    if (isRunning || _starting) return;
    _starting = true;
    final generation = ++_sessionGeneration;
    _phase = WifiTransferPhase.starting;
    _error = null;
    _lastResult = null;
    _queue.clear();
    _notify();

    try {
      await _purgeTransferPartials();
      if (!_isCurrentGeneration(generation)) return;
      final token = _newToken();
      final router = Router()
        ..get('/', _serveUploadPage)
        ..get('/health', _health)
        ..post('/queue', _createQueue)
        ..post('/upload', _upload);
      final handler = const Pipeline().addHandler(router.call);
      final server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        0,
        poweredByHeader: null,
      );
      if (!_isCurrentGeneration(generation)) {
        await server.close(force: true);
        return;
      }
      _server = server;
      _token = token;

      final ip = await _resolveLocalIp();
      if (!_isCurrentGeneration(generation)) {
        await server.close(force: true);
        _server = null;
        return;
      }
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
      if (!_isCurrentGeneration(generation)) return;
      debugPrint('[WiFiTransfer] start failed: $error');
      _error = _wifiUserError(error, fallback: '无法启动传书，请检查网络后重试');
      _phase = WifiTransferPhase.failed;
      _notify();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    ++_sessionGeneration;
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
    _queue.clear();
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

  Future<Response> _createQueue(Request request) async {
    if (!_isAuthorized(request)) return _unauthorized();
    final generation = _sessionGeneration;
    if (_uploading ||
        _queue.any(
          (item) =>
              item.phase == WifiTransferItemPhase.queued ||
              item.phase == WifiTransferItemPhase.receiving ||
              item.phase == WifiTransferItemPhase.importing,
        )) {
      return Response(
        HttpStatus.conflict,
        body: jsonEncode({'ok': false, 'message': '已有传输队列在进行'}),
        headers: _jsonHeaders,
      );
    }

    try {
      final payload = jsonDecode(await request.readAsString());
      if (!_isCurrentGeneration(generation)) return _sessionEnded();
      final rawFiles = payload is Map<String, dynamic>
          ? payload['files']
          : null;
      if (rawFiles is! List || rawFiles.isEmpty || rawFiles.length > 100) {
        throw const _WifiTransferException('请选择 1 到 100 个文件');
      }

      final items = <WifiTransferQueueItem>[];
      for (final rawFile in rawFiles) {
        if (rawFile is! Map<String, dynamic>) {
          throw const _WifiTransferException('队列文件信息无效');
        }
        final rawName = rawFile['name'];
        final fileName = rawName is String
            ? _safeFileName(Uri.encodeComponent(rawName))
            : null;
        final rawSize = rawFile['size'];
        final size = rawSize is num ? rawSize.toInt() : null;
        if (fileName == null || size == null || size < 0) {
          throw const _WifiTransferException('队列文件信息无效');
        }
        if (size > maxFileBytes) {
          throw const _WifiTransferException('文件超过大小限制');
        }
        items.add(
          WifiTransferQueueItem(
            id: _newQueueId(),
            fileName: fileName,
            totalBytes: size,
            phase: WifiTransferItemPhase.queued,
          ),
        );
      }

      _queue
        ..clear()
        ..addAll(items);
      _error = null;
      _lastResult = null;
      _phase = WifiTransferPhase.waiting;
      _notify();
      return Response.ok(
        jsonEncode({
          'ok': true,
          'files': [
            for (final item in items)
              {
                'id': item.id,
                'fileName': item.fileName,
                'size': item.totalBytes,
              },
          ],
        }),
        headers: _jsonHeaders,
      );
    } catch (error) {
      debugPrint('[WiFiTransfer] queue request failed: $error');
      final message = _wifiUserError(error, fallback: '无法处理文件列表，请重试');
      return Response(
        error is _WifiTransferException
            ? HttpStatus.badRequest
            : HttpStatus.internalServerError,
        body: jsonEncode({'ok': false, 'message': message}),
        headers: _jsonHeaders,
      );
    }
  }

  Future<Response> _upload(Request request) async {
    if (!_isAuthorized(request)) return _unauthorized();
    final generation = _sessionGeneration;
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

    final queueId = request.url.queryParameters[_queueIdQuery];
    WifiTransferQueueItem? queueItem;
    if (queueId != null && queueId.isNotEmpty) {
      for (final item in _queue) {
        if (item.id == queueId) {
          queueItem = item;
          break;
        }
      }
      if (queueItem == null ||
          queueItem.phase != WifiTransferItemPhase.queued) {
        return Response(
          HttpStatus.badRequest,
          body: jsonEncode({'ok': false, 'message': '传输队列项无效'}),
          headers: _jsonHeaders,
        );
      }
      if (queueItem.fileName != fileName) {
        return Response(
          HttpStatus.badRequest,
          body: jsonEncode({'ok': false, 'message': '文件名与队列不一致'}),
          headers: _jsonHeaders,
        );
      }
    } else {
      queueItem = WifiTransferQueueItem(
        id: _newQueueId(),
        fileName: fileName,
        phase: WifiTransferItemPhase.queued,
        totalBytes: announcedLength,
      );
      _queue.add(queueItem);
    }

    final itemId = queueItem.id;
    _updateQueueItem(
      itemId,
      phase: WifiTransferItemPhase.receiving,
      receivedBytes: 0,
      totalBytes: announcedLength ?? queueItem.totalBytes,
    );

    _uploading = true;
    _phase = WifiTransferPhase.receiving;
    _currentFileName = fileName;
    _receivedBytes = 0;
    _totalBytes = announcedLength ?? queueItem.totalBytes;
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
          if (!_isCurrentGeneration(generation)) return _sessionEnded();
          _receivedBytes += chunk.length;
          if (_receivedBytes > maxFileBytes) {
            throw const _WifiTransferException('文件超过大小限制');
          }
          sink.add(chunk);
          _updateQueueItem(
            itemId,
            receivedBytes: _receivedBytes,
            totalBytes: _totalBytes,
          );
          _notify();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (!_isCurrentGeneration(generation)) return _sessionEnded();
      _phase = WifiTransferPhase.importing;
      _updateQueueItem(
        itemId,
        phase: WifiTransferItemPhase.importing,
        receivedBytes: _receivedBytes,
        totalBytes: _totalBytes,
      );
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
      if (!_isCurrentGeneration(generation)) return _sessionEnded();
      _lastResult = result;
      _phase = result.hasFailures
          ? WifiTransferPhase.failed
          : WifiTransferPhase.completed;
      if (result.hasFailures) {
        _error = result.failures.first.reason;
      }
      _updateQueueItem(
        itemId,
        phase: result.hasFailures
            ? WifiTransferItemPhase.failed
            : WifiTransferItemPhase.completed,
        receivedBytes: _receivedBytes,
        totalBytes: _totalBytes,
        result: result,
        error: result.hasFailures ? result.failures.first.reason : null,
      );
      _notify();
      return Response(
        result.hasFailures ? HttpStatus.unprocessableEntity : HttpStatus.ok,
        body: jsonEncode(_resultJson(result)),
        headers: _jsonHeaders,
      );
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return _sessionEnded();
      debugPrint('[WiFiTransfer] upload failed: $error');
      final message = _wifiUserError(error, fallback: '上传失败，请重新选择文件后重试');
      _phase = WifiTransferPhase.failed;
      _error = message;
      _updateQueueItem(
        itemId,
        phase: WifiTransferItemPhase.failed,
        receivedBytes: _receivedBytes,
        totalBytes: _totalBytes,
        error: message,
      );
      _notify();
      final statusCode =
          error is _WifiTransferException && error.message == '文件超过大小限制'
          ? HttpStatus.requestEntityTooLarge
          : HttpStatus.internalServerError;
      return Response(
        statusCode,
        body: jsonEncode({'ok': false, 'message': message}),
        headers: _jsonHeaders,
      );
    } finally {
      if (partial != null) await _deleteIfExists(partial);
      if (_isCurrentGeneration(generation)) {
        _uploading = false;
        final hasPending = _queue.any(
          (item) =>
              item.phase == WifiTransferItemPhase.queued ||
              item.phase == WifiTransferItemPhase.receiving ||
              item.phase == WifiTransferItemPhase.importing,
        );
        if (hasPending) {
          _phase = WifiTransferPhase.waiting;
        } else if (_queue.any(
          (item) => item.phase == WifiTransferItemPhase.failed,
        )) {
          _phase = WifiTransferPhase.failed;
        } else {
          _phase = WifiTransferPhase.completed;
        }
        _notify();
      }
    }
  }

  void _updateQueueItem(
    String id, {
    WifiTransferItemPhase? phase,
    int? receivedBytes,
    int? totalBytes,
    ImportResult? result,
    String? error,
  }) {
    final index = _queue.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _queue[index] = _queue[index].copyWith(
      phase: phase,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      result: result,
      error: error,
    );
  }

  String _newQueueId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${++_queueSequence}';

  bool _isCurrentGeneration(int generation) =>
      !_disposed && generation == _sessionGeneration;

  Response _sessionEnded() => Response(
    HttpStatus.gone,
    body: jsonEncode({'ok': false, 'message': '传输会话已结束'}),
    headers: _jsonHeaders,
  );

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
    ++_sessionGeneration;
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
    body { margin:0; min-height:100vh; box-sizing:border-box; padding:24px 0; display:grid; place-items:center; background:#f7f9fc; color:#172033; }
    main { width:min(92vw,480px); min-width:0; box-sizing:border-box; padding:28px; border:1px solid #dce3ee; border-radius:22px; background:#fff; box-shadow:0 16px 50px #27364a18; }
    h1 { margin:0 0 8px; font-size:24px; } p { color:#5c687b; line-height:1.6; margin-bottom:0; }
    label, button { display:flex; justify-content:center; align-items:center; width:100%; box-sizing:border-box; min-height:52px; border-radius:14px; font:inherit; font-weight:600; cursor:pointer; }
    label { margin-top:20px; border:1px solid #e76b38; background:#fff; color:#d75e2e; }
    button { margin-top:10px; border:0; background:#e76b38; color:#fff; }
    label:has(+ input:disabled), button:disabled { opacity:.55; cursor:wait; }
    input { display:none; } #status { margin-top:18px; min-height:24px; font-size:14px; color:#5c687b; white-space:pre-wrap; overflow-wrap:anywhere; }
    #queue { display:grid; gap:8px; width:100%; min-width:0; max-width:100%; margin-top:14px; overflow:hidden; }
    .queue-item { display:flex; align-items:center; gap:10px; width:100%; min-width:0; box-sizing:border-box; overflow:hidden; padding:10px 12px; border-radius:12px; background:#f4f6fa; font-size:13px; }
    .queue-item .name { flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    .queue-item .state { color:#68758a; white-space:nowrap; }
    .queue-item.completed .state { color:#24865d; } .queue-item.failed .state { color:#c34b4b; }
    [hidden] { display:none !important; }
  </style>
</head>
<body>
  <main>
    <h1>WiFi 传书</h1>
    <p>请从当前设备选择图书或漫画文件，确认后再开始传输。文件会直接导入开卷，不会上传到互联网。</p>
    <label for="files">选择文件</label>
    <input id="files" type="file" multiple>
    <button id="start" type="button" hidden>开始传输</button>
    <div id="status">等待选择文件</div>
    <div id="queue" aria-live="polite"></div>
  </main>
  <script>
    const token = new URLSearchParams(location.search).get('token');
    const input = document.getElementById('files');
    const startButton = document.getElementById('start');
    const status = document.getElementById('status');
    const queue = document.getElementById('queue');
    let selectedFiles = [];
    let isTransferring = false;

    function renderQueue(files) {
      queue.replaceChildren(...files.map((file, index) => {
        const row = document.createElement('div');
        row.className = 'queue-item queued';
        row.dataset.index = index;
        row.innerHTML = `<span class="name"></span><span class="state">等待传输</span>`;
        row.querySelector('.name').textContent = file.name;
        return row;
      }));
    }

    function updateQueueItem(index, state, label) {
      const row = queue.querySelector(`[data-index="${index}"]`);
      if (!row) return;
      row.className = `queue-item ${state}`;
      row.querySelector('.state').textContent = label;
    }

    async function readJson(response) {
      try { return await response.json(); } catch (_) { return {}; }
    }

    input.addEventListener('change', () => {
      const files = Array.from(input.files || []);
      if (!files.length) return;
      selectedFiles = files;
      renderQueue(files);
      startButton.hidden = false;
      startButton.disabled = false;
      status.textContent = `已选择 ${files.length} 个文件，请确认后开始传输`;
      input.value = '';
    });

    startButton.addEventListener('click', async () => {
      if (!selectedFiles.length || isTransferring) return;
      const files = selectedFiles.slice();
      isTransferring = true;
      input.disabled = true;
      startButton.disabled = true;
      status.textContent = `正在准备队列：${files.length} 个文件`;
      try {
        const queueResponse = await fetch(`/queue?token=${encodeURIComponent(token || '')}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ files: files.map(file => ({ name: file.name, size: file.size })) }),
        });
        const manifest = await readJson(queueResponse);
        if (!queueResponse.ok || !manifest.ok) throw new Error(manifest.message || '无法创建传输队列');

        for (let index = 0; index < files.length; index += 1) {
          const file = files[index];
          const queueFile = manifest.files[index];
          updateQueueItem(index, 'receiving', '正在传输');
          status.textContent = `正在传输 ${index + 1}/${files.length}：${file.name}`;
          try {
            const response = await fetch(`/upload?token=${encodeURIComponent(token || '')}&queueId=${encodeURIComponent(queueFile.id)}`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/octet-stream',
                'X-Kaijuan-File-Name': encodeURIComponent(file.name),
              },
              body: file,
            });
            const result = await readJson(response);
            if (!response.ok || !result.ok) throw new Error(result.message || (result.failures && result.failures[0] && result.failures[0].reason) || '导入失败');
            updateQueueItem(index, 'completed', '已完成');
          } catch (error) {
            updateQueueItem(index, 'failed', '失败');
            status.textContent = `第 ${index + 1} 个文件上传失败，请重试：${file.name}`;
          }
        }
        const failed = Array.from(queue.querySelectorAll('.failed')).length;
        status.textContent = failed ? `队列完成：${files.length - failed} 个成功，${failed} 个失败` : `队列完成：已导入 ${files.length} 个文件`;
      } catch (error) {
        status.textContent = '无法创建传输队列，请重新选择文件后重试';
        files.forEach((_, index) => updateQueueItem(index, 'failed', '未传输'));
      } finally {
        selectedFiles = [];
        isTransferring = false;
        input.disabled = false;
        startButton.hidden = true;
      }
    });
  </script>
</body>
</html>''';
}

String _wifiUserError(Object error, {required String fallback}) {
  if (error is _WifiTransferException) return error.message;
  if (error is SocketException && error.message.contains('局域网地址')) {
    return '无法获取局域网地址，请确认设备已连接 Wi-Fi';
  }
  return fallback;
}

class _WifiTransferException implements Exception {
  const _WifiTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

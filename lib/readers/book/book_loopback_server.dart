import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// App-lifetime loopback host for Foliate assets and mounted book files.
///
/// Sessions mount/unmount books; they do not own the HTTP server. Keeping a
/// stable `127.0.0.1:<port>` origin lets WebView reuse cached foliate-js across
/// opens without accepting absolute filesystem paths from the client.
class BookLoopbackServer {
  BookLoopbackServer._(this._server);

  static const _assetRoot = 'assets/book/foliate-js/';
  static const _portFileName = 'foliate_loopback_port.txt';

  /// First-paint Foliate modules (modern + legacy entry). Loaded once into
  /// memory so open-book HTTP serves skip repeated `rootBundle.load`.
  static const _hotAssets = <String>[
    'index.html',
    'src/book.js',
    'src/view.js',
    'src/epub.js',
    'src/epubcfi.js',
    'src/footnotes.js',
    'src/overlayer.js',
    'src/paginator.js',
    'src/progress.js',
    'src/text-walker.js',
    'src/translator.js',
    'src/tts.js',
    'src/vendor/zip.js',
    'src/vendor/pdfjs/pdf.js',
    'src/vendor/pdfjs/pdf.worker.js',
    'dist/bundle.js',
    'dist/pdf-legacy.js',
  ];

  static BookLoopbackServer? _shared;
  static Future<BookLoopbackServer>? _starting;
  static int? _preferredPort;
  static File? _portFile;

  final HttpServer _server;
  final Map<String, File> _mounts = {};
  final Map<String, File> _fontMounts = {};
  final Map<String, Uint8List> _assetCache = {};
  int _nextMountId = 0;

  int get port => _server.port;

  /// Currently running shared server, if any.
  static BookLoopbackServer? get sharedOrNull => _shared;

  Uri get indexUri =>
      Uri.parse('http://127.0.0.1:$port/foliate-js/index.html');

  Uri get probeUri =>
      Uri.parse('http://127.0.0.1:$port/foliate-js/metadata-probe.html');

  Uri bookUriFor(String mountId) =>
      Uri.parse('http://127.0.0.1:$port/books/$mountId.epub');

  Uri fontUriFor(String fontId, String fileName) {
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1)
        : 'ttf';
    return Uri.parse('http://127.0.0.1:$port/fonts/$fontId.$ext');
  }

  /// Seeds the preferred bind port from the app support directory.
  ///
  /// Call once during bootstrap so restarts can keep the same origin and hit
  /// WebView disk cache for foliate-js.
  static Future<void> configureSupportDirectory(Directory supportDirectory) async {
    final file = File(p.join(supportDirectory.path, _portFileName));
    _portFile = file;
    try {
      if (await file.exists()) {
        final parsed = int.tryParse((await file.readAsString()).trim());
        if (parsed != null && parsed > 0 && parsed < 65536) {
          _preferredPort = parsed;
        }
      }
    } catch (_) {
      // Corrupted port file — bind a fresh port.
    }
  }

  static Future<BookLoopbackServer> ensureStarted() async {
    final existing = _shared;
    if (existing != null) return existing;
    final inFlight = _starting;
    if (inFlight != null) return inFlight;
    final future = _start();
    _starting = future;
    try {
      return await future;
    } finally {
      if (identical(_starting, future)) _starting = null;
    }
  }

  /// Bind loopback and prime the Foliate asset cache (bootstrap / warm path).
  static Future<BookLoopbackServer> warmHotAssets() async {
    final server = await ensureStarted();
    await server.warmAssets();
    return server;
  }

  static Future<BookLoopbackServer> _start() async {
    final preferred = _preferredPort;
    late final HttpServer server;
    if (preferred != null) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, preferred);
      } catch (_) {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
    } else {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    _preferredPort = server.port;
    final shared = BookLoopbackServer._(server);
    _shared = shared;
    unawaited(shared._serve());
    unawaited(shared._persistPort());
    return shared;
  }

  /// Drop and rebind the shared listener (iOS may kill loopback sockets).
  ///
  /// Active mounts are cleared; callers must open a fresh session afterwards.
  static Future<BookLoopbackServer> recover() async {
    final preferred = _shared?.port ?? _preferredPort;
    await debugStop();
    _preferredPort = preferred;
    return ensureStarted();
  }

  String mount(File bookFile) {
    final id = '${++_nextMountId}';
    _mounts[id] = bookFile;
    return id;
  }

  void unmount(String mountId) {
    _mounts.remove(mountId);
  }

  void mountFont(String fontId, File fontFile) {
    _fontMounts[fontId] = fontFile;
  }

  void unmountFont(String fontId) {
    _fontMounts.remove(fontId);
  }

  /// Prefetch hot Foliate assets into [_assetCache] (idempotent).
  Future<void> warmAssets() async {
    await Future.wait(
      _hotAssets.map((relative) async {
        try {
          await _loadAssetBytes(relative);
        } catch (error) {
          debugPrint('[BookLoopback] warm skip $relative: $error');
        }
      }),
    );
  }

  Future<Uint8List> _loadAssetBytes(String relative) async {
    // Never memoize HTML/JS: hot reload keeps this server alive and would keep
    // serving a pre-fix overlayer.js (missing/broken squiggly, stale dismiss).
    final skipMemo = relative.endsWith('.js') ||
        relative.endsWith('.mjs') ||
        relative.endsWith('.html');
    if (!skipMemo) {
      final cached = _assetCache[relative];
      if (cached != null) return cached;
    }
    final data = await rootBundle.load('$_assetRoot$relative');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (!skipMemo) {
      _assetCache[relative] = bytes;
    }
    return bytes;
  }

  Future<void> _persistPort() async {
    final file = _portFile;
    if (file == null) return;
    try {
      await file.writeAsString('$port');
    } catch (error) {
      debugPrint('[BookLoopback] failed to persist port: $error');
    }
  }

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        unawaited(_handle(request));
      }
    } on HttpException catch (_) {
      // Expected when close(force: true) interrupts the accept loop.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else if (_isBookPath(request.uri.path)) {
        final mountId = _mountIdFromPath(request.uri.path);
        final bookFile = mountId == null ? null : _mounts[mountId];
        if (bookFile == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          response.headers.contentType = ContentType('application', 'epub+zip');
          response.contentLength = await bookFile.length();
          if (request.method == 'GET') {
            await response.addStream(bookFile.openRead());
          }
        }
      } else if (_isFontPath(request.uri.path)) {
        final fontId = _fontIdFromPath(request.uri.path);
        final fontFile = fontId == null ? null : _fontMounts[fontId];
        if (fontFile == null || !await fontFile.exists()) {
          response.statusCode = HttpStatus.notFound;
        } else {
          response.headers.contentType = ContentType.parse(
            _contentTypeFor(fontFile.path),
          );
          response.headers.set('Cache-Control', 'public, max-age=31536000');
          response.contentLength = await fontFile.length();
          if (request.method == 'GET') {
            await response.addStream(fontFile.openRead());
          }
        }
      } else if (request.uri.path.startsWith('/foliate-js/')) {
        final relative = request.uri.path.substring('/foliate-js/'.length);
        if (!_isSafeAssetPath(relative)) {
          response.statusCode = HttpStatus.notFound;
        } else {
          final bytes = await _loadAssetBytes(relative);
          response.headers.contentType = ContentType.parse(
            _contentTypeFor(relative),
          );
          // Loopback serves the same URL across hot restarts; avoid sticky
          // WebView caches of old foliate sources (e.g. missing squiggly).
          response.headers.set('Cache-Control', 'no-cache');
          response.contentLength = bytes.length;
          if (request.method == 'GET') response.add(bytes);
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (error) {
      debugPrint('[BookLoopback] request failed: $error');
      try {
        response.statusCode = HttpStatus.notFound;
      } on StateError {
        // Headers may already be committed by a failed streaming response.
      }
    } finally {
      await response.close();
    }
  }

  static bool _isBookPath(String path) {
    return RegExp(r'^/books/\d+\.epub$').hasMatch(path);
  }

  static String? _mountIdFromPath(String path) {
    final match = RegExp(r'^/books/(\d+)\.epub$').firstMatch(path);
    return match?.group(1);
  }

  static bool _isFontPath(String path) {
    return RegExp(r'^/fonts/[^/]+\.(ttf|otf|woff2?)$', caseSensitive: false)
        .hasMatch(path);
  }

  static String? _fontIdFromPath(String path) {
    final match = RegExp(
      r'^/fonts/([^/]+)\.(ttf|otf|woff2?)$',
      caseSensitive: false,
    ).firstMatch(path);
    return match?.group(1);
  }

  static bool _isSafeAssetPath(String relative) {
    if (relative.isEmpty || relative.startsWith('/')) return false;
    final segments = relative.replaceAll('\\', '/').split('/');
    return !segments.contains('..') && !segments.contains('.');
  }

  static String _contentTypeFor(String path) {
    final extension = path.contains('.')
        ? path.substring(path.lastIndexOf('.') + 1).toLowerCase()
        : '';
    return switch (extension) {
      'html' => 'text/html; charset=utf-8',
      'css' => 'text/css; charset=utf-8',
      'js' => 'application/javascript; charset=utf-8',
      'json' || 'map' => 'application/json; charset=utf-8',
      'svg' => 'image/svg+xml',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      _ => 'application/octet-stream',
    };
  }

  /// Test-only: stop the shared listener and clear mounts.
  @visibleForTesting
  static Future<void> debugStop() async {
    final shared = _shared;
    _shared = null;
    _starting = null;
    if (shared == null) return;
    shared._mounts.clear();
    shared._fontMounts.clear();
    shared._assetCache.clear();
    await shared._server.close(force: true);
  }
}

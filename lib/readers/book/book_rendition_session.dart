import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef BookJavascriptEvaluator = Future<dynamic> Function(String source);
typedef BookRenditionTimingListener = void Function(BookRenditionTiming timing);

class BookRenditionTiming {
  const BookRenditionTiming({
    required this.step,
    required this.elapsed,
    required this.sincePrevious,
  });

  final String step;
  final Duration elapsed;
  final Duration sincePrevious;

  @override
  String toString() =>
      'step=$step elapsed=${elapsed.inMilliseconds}ms '
      'delta=${sincePrevious.inMilliseconds}ms';
}

/// Owns one opened book's loopback input, active WebView lease and timings.
///
/// Every WebView attachment receives a monotonically increasing lease. Async
/// callbacks must carry that lease; callbacks from a replaced renderer become
/// harmless instead of mutating the next rendition.
class BookRenditionSession {
  BookRenditionSession._(
    this._server,
    this._bookFile,
    this._timingListener,
    this._clock,
  );

  static const _assetRoot = 'assets/anx_reader/foliate-js/';

  final HttpServer _server;
  final File _bookFile;
  final BookRenditionTimingListener? _timingListener;
  final Stopwatch _clock;
  final List<BookRenditionTiming> _timings = [];

  int _webGeneration = 0;
  BookJavascriptEvaluator? _evaluator;
  bool _closed = false;

  Uri get indexUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/foliate-js/index.html');
  Uri get probeUri => Uri.parse(
    'http://127.0.0.1:${_server.port}/foliate-js/metadata-probe.html',
  );
  Uri get bookUri => Uri.parse('http://127.0.0.1:${_server.port}/book.epub');
  bool get isClosed => _closed;
  List<BookRenditionTiming> get timings => List.unmodifiable(_timings);

  static Future<BookRenditionSession> open(
    File bookFile, {
    BookRenditionTimingListener? onTiming,
  }) async {
    if (!await bookFile.exists()) {
      throw Exception('文件不存在：${bookFile.path}');
    }
    final clock = Stopwatch()..start();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final session = BookRenditionSession._(server, bookFile, onTiming, clock);
    session.mark('server-ready');
    unawaited(session._serve());
    return session;
  }

  Uri readerUri(Map<String, String> queryParameters) {
    return indexUri.replace(queryParameters: queryParameters);
  }

  BookRenditionWebLease attachWebView(BookJavascriptEvaluator evaluator) {
    if (_closed) throw StateError('Book rendition session is closed');
    _evaluator = evaluator;
    final lease = BookRenditionWebLease._(this, ++_webGeneration);
    mark('webview-created');
    return lease;
  }

  bool isCurrent(BookRenditionWebLease lease) {
    return !_closed &&
        identical(lease._session, this) &&
        lease.generation == _webGeneration &&
        _evaluator != null;
  }

  Future<dynamic> evaluate(BookRenditionWebLease lease, String source) async {
    if (!isCurrent(lease)) return null;
    final evaluator = _evaluator;
    if (evaluator == null) return null;
    try {
      return await evaluator(source);
    } catch (error) {
      debugPrint('[BookRendition] JavaScript failed: $error');
      return null;
    }
  }

  void invalidateWebView(BookRenditionWebLease? lease) {
    if (lease == null || !isCurrent(lease)) return;
    _evaluator = null;
    _webGeneration++;
    mark('webview-invalidated');
  }

  void mark(String step) {
    if (_closed) return;
    final elapsed = _clock.elapsed;
    final previous = _timings.isEmpty ? Duration.zero : _timings.last.elapsed;
    final timing = BookRenditionTiming(
      step: step,
      elapsed: elapsed,
      sincePrevious: elapsed - previous,
    );
    _timings.add(timing);
    _timingListener?.call(timing);
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
      } else if (request.uri.path == '/book.epub') {
        response.headers.contentType = ContentType('application', 'epub+zip');
        response.contentLength = await _bookFile.length();
        if (request.method == 'GET') {
          await response.addStream(_bookFile.openRead());
        }
      } else if (request.uri.path.startsWith('/foliate-js/')) {
        final relative = request.uri.path.substring('/foliate-js/'.length);
        if (!_isSafeAssetPath(relative)) {
          response.statusCode = HttpStatus.notFound;
        } else {
          final data = await rootBundle.load('$_assetRoot$relative');
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          response.headers.contentType = ContentType.parse(
            _contentTypeFor(relative),
          );
          response.headers.set('Cache-Control', 'public, max-age=3600');
          response.contentLength = bytes.length;
          if (request.method == 'GET') response.add(bytes);
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (error) {
      debugPrint('[BookRendition] loopback request failed: $error');
      try {
        response.statusCode = HttpStatus.notFound;
      } on StateError {
        // Headers may already be committed by a failed streaming response.
      }
    } finally {
      await response.close();
    }
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
      _ => 'application/octet-stream',
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _evaluator = null;
    _webGeneration++;
    _closed = true;
    _clock.stop();
    await _server.close(force: true);
  }
}

class BookRenditionWebLease {
  const BookRenditionWebLease._(this._session, this.generation);

  final BookRenditionSession _session;
  final int generation;

  bool get isCurrent => _session.isCurrent(this);
}

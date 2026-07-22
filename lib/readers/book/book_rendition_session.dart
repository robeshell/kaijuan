import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/pipeline_diagnostics.dart';
import 'book_loopback_server.dart';

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

/// Owns one opened book's mount, active WebView lease and timings.
///
/// The HTTP listener is the shared [BookLoopbackServer]. Every WebView
/// attachment receives a monotonically increasing lease. Async callbacks must
/// carry that lease; callbacks from a replaced renderer become harmless
/// instead of mutating the next rendition.
class BookRenditionSession {
  BookRenditionSession._(
    this._server,
    this._mountId,
    this._timingListener,
    this._clock,
  );

  final BookLoopbackServer _server;
  final String _mountId;
  final BookRenditionTimingListener? _timingListener;
  final Stopwatch _clock;
  final List<BookRenditionTiming> _timings = [];

  int _webGeneration = 0;
  BookJavascriptEvaluator? _evaluator;
  bool _closed = false;

  Uri get indexUri => _server.indexUri;
  Uri get probeUri => _server.probeUri;
  Uri get bookUri => _server.bookUriFor(_mountId);
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
    final server = await BookLoopbackServer.ensureStarted();
    final mountId = server.mount(bookFile);
    final session = BookRenditionSession._(server, mountId, onTiming, clock);
    session.mark('server-ready');
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
    PipelineDiagnostics.instance.record(
      '[BookRendition][$_mountId] $timing',
    );
    _timingListener?.call(timing);
  }

  Future<void> close() async {
    if (_closed) return;
    _evaluator = null;
    _webGeneration++;
    _closed = true;
    _clock.stop();
    _server.unmount(_mountId);
  }
}

class BookRenditionWebLease {
  const BookRenditionWebLease._(this._session, this.generation);

  final BookRenditionSession _session;
  final int generation;

  bool get isCurrent => _session.isCurrent(this);
}

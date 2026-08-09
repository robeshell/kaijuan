import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/reader_models.dart';
import '../persistence/app_database.dart';

/// Accumulates foreground reading seconds for one open reader session.
///
/// Rules (PRODUCT §4.8 / reading-stats.md):
/// - Only counts while the app lifecycle is [AppLifecycleState.resumed]
///   and [countingEnabled] is true.
/// - TTS playback should set [countingEnabled] to false.
/// - Flushes about every 30s and on pause / detach; splits across local midnights.
class ReadingTimeTracker with WidgetsBindingObserver {
  ReadingTimeTracker({
    required this.database,
    required this.itemId,
    required this.kind,
    this.flushInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    Duration Function()? monotonicClock,
    this.onWriteError,
  }) : _clock = clock ?? DateTime.now,
       _monotonicClock =
           monotonicClock ?? (clock == null ? _readMonotonicClock : null);

  final AppDatabase database;
  final String itemId;
  final ReaderKind kind;
  final Duration flushInterval;
  final DateTime Function() _clock;
  final Duration Function()? _monotonicClock;
  final void Function(Object error, StackTrace stackTrace)? onWriteError;

  bool _attached = false;
  bool _countingEnabled = true;
  bool _contentReady = false;
  bool _routeVisible = true;
  bool _lifecycleResumed = true;
  DateTime? _segmentStartedAt;
  Duration? _segmentStartedTick;
  bool _sessionCounted = false;
  Timer? _flushTimer;
  Future<void> _writeChain = Future<void>.value();

  static final Stopwatch _processStopwatch = Stopwatch()..start();
  static Duration _readMonotonicClock() => _processStopwatch.elapsed;

  bool get isActivelyCounting =>
      _attached &&
      _countingEnabled &&
      _contentReady &&
      _routeVisible &&
      _lifecycleResumed &&
      _segmentStartedAt != null;

  bool get _eligible =>
      _attached &&
      _countingEnabled &&
      _contentReady &&
      _routeVisible &&
      _lifecycleResumed;

  /// Register lifecycle observer and start counting if eligible.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _lifecycleResumed = state == null || state == AppLifecycleState.resumed;
    _syncRunningState();
  }

  /// Pause, final flush, unregister.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    _flushTimer = null;
    await _pauseAndFlush();
    await _writeChain;
  }

  /// Reading time starts only after the actual page/reflow surface is ready.
  void setContentReady(bool ready) {
    if (_contentReady == ready) return;
    _contentReady = ready;
    if (ready) {
      _syncRunningState();
    } else {
      unawaited(_pauseAndFlush());
    }
  }

  /// Pause while a modal route covers the reader; resume when it becomes top.
  void setRouteVisible(bool visible) {
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    if (visible) {
      _syncRunningState();
    } else {
      unawaited(_pauseAndFlush());
    }
  }

  /// When false (e.g. TTS playing), time is not accumulated.
  void setCountingEnabled(bool enabled) {
    if (_countingEnabled == enabled) return;
    _countingEnabled = enabled;
    if (!enabled) {
      unawaited(_pauseAndFlush());
    } else {
      _syncRunningState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _lifecycleResumed) return;
    _lifecycleResumed = resumed;
    if (resumed) {
      _syncRunningState();
    } else {
      unawaited(_pauseAndFlush());
    }
  }

  void _syncRunningState() {
    if (!_eligible) return;
    if (_segmentStartedAt != null) return;
    _segmentStartedAt = _clock();
    _segmentStartedTick = _monotonicClock?.call();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) {
      unawaited(_flushOpenSegment(restart: true));
    });
  }

  Future<void> _pauseAndFlush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushOpenSegment(restart: false);
  }

  Future<void> _flushOpenSegment({required bool restart}) {
    final started = _segmentStartedAt;
    if (started == null) {
      return _writeChain;
    }
    final wallEnd = _clock();
    final monotonicNow = _monotonicClock?.call();
    final monotonicStarted = _segmentStartedTick;
    final elapsed = monotonicNow != null && monotonicStarted != null
        ? monotonicNow - monotonicStarted
        : wallEnd.difference(started);
    final end = elapsed > Duration.zero ? started.add(elapsed) : started;
    _segmentStartedAt = restart && _eligible ? wallEnd : null;
    _segmentStartedTick = restart && _eligible ? monotonicNow : null;
    _writeChain = _writeChain
        .then((_) => _persistRange(start: started, end: end))
        .catchError((Object error, StackTrace stackTrace) {
          final handler = onWriteError;
          if (handler != null) {
            handler(error, stackTrace);
          } else {
            debugPrint('[ReadingTime] failed to persist segment: $error');
          }
        });
    return _writeChain;
  }

  Future<void> _persistRange({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start)) return;

    var cursor = start.toLocal();
    final endLocal = end.toLocal();
    while (cursor.isBefore(endLocal)) {
      final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final chunkEnd = endLocal.isBefore(nextMidnight)
          ? endLocal
          : nextMidnight;
      final seconds = chunkEnd.difference(cursor).inSeconds;
      if (seconds > 0) {
        final countSession = !_sessionCounted;
        await _addChunkWithRetry(
          dayKey: AppDatabase.localDayKey(cursor),
          seconds: seconds,
          countSession: countSession,
        );
        if (countSession) _sessionCounted = true;
      }
      cursor = chunkEnd;
    }
  }

  Future<void> _addChunkWithRetry({
    required String dayKey,
    required int seconds,
    required bool countSession,
  }) async {
    try {
      await database.addReadingSeconds(
        dayKey: dayKey,
        itemId: itemId,
        kind: kind,
        seconds: seconds,
        countSession: countSession,
      );
    } catch (_) {
      // A short retry covers transient executor contention without risking a
      // duplicate: addReadingSeconds is one atomic transaction per chunk.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await database.addReadingSeconds(
        dayKey: dayKey,
        itemId: itemId,
        kind: kind,
        seconds: seconds,
        countSession: countSession,
      );
    }
  }
}

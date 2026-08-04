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
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final String itemId;
  final ReaderKind kind;
  final Duration flushInterval;
  final DateTime Function() _clock;

  bool _attached = false;
  bool _countingEnabled = true;
  bool _lifecycleResumed = true;
  DateTime? _segmentStartedAt;
  bool _sessionCounted = false;
  Timer? _flushTimer;
  Future<void> _writeChain = Future<void>.value();

  bool get isActivelyCounting =>
      _attached &&
      _countingEnabled &&
      _lifecycleResumed &&
      _segmentStartedAt != null;

  /// Register lifecycle observer and start counting if eligible.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _lifecycleResumed =
        state == null || state == AppLifecycleState.resumed;
    _syncRunningState();
  }

  /// Pause, final flush, unregister.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    _flushTimer = null;
    await _pauseAndFlush(countSession: true);
    await _writeChain;
  }

  /// When false (e.g. TTS playing), time is not accumulated.
  void setCountingEnabled(bool enabled) {
    if (_countingEnabled == enabled) return;
    if (!enabled) {
      unawaited(_pauseAndFlush());
      _countingEnabled = false;
    } else {
      _countingEnabled = true;
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
    if (!_attached || !_countingEnabled || !_lifecycleResumed) {
      return;
    }
    if (_segmentStartedAt != null) return;
    _segmentStartedAt = _clock();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) {
      unawaited(_flushOpenSegment(restart: true));
    });
  }

  Future<void> _pauseAndFlush({bool countSession = false}) async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushOpenSegment(
      restart: false,
      countSession: countSession && !_sessionCounted,
    );
    if (countSession) {
      _sessionCounted = true;
    }
  }

  Future<void> _flushOpenSegment({
    required bool restart,
    bool countSession = false,
  }) {
    final started = _segmentStartedAt;
    if (started == null) {
      return _writeChain;
    }
    final end = _clock();
    _segmentStartedAt = restart && _countingEnabled && _lifecycleResumed
        ? end
        : null;
    final task = _writeChain.then(
      (_) => _persistRange(
        start: started,
        end: end,
        countSession: countSession,
      ),
    );
    _writeChain = task.catchError((_) {});
    return task;
  }

  Future<void> _persistRange({
    required DateTime start,
    required DateTime end,
    required bool countSession,
  }) async {
    if (!end.isAfter(start)) return;

    var cursor = start.toLocal();
    final endLocal = end.toLocal();
    var sessionFlag = countSession;

    while (cursor.isBefore(endLocal)) {
      final nextMidnight = DateTime(
        cursor.year,
        cursor.month,
        cursor.day + 1,
      );
      final chunkEnd = endLocal.isBefore(nextMidnight)
          ? endLocal
          : nextMidnight;
      final seconds = chunkEnd.difference(cursor).inSeconds;
      if (seconds > 0) {
        await database.addReadingSeconds(
          dayKey: AppDatabase.localDayKey(cursor),
          itemId: itemId,
          kind: kind,
          seconds: seconds,
          countSession: sessionFlag,
        );
        sessionFlag = false;
      }
      cursor = chunkEnd;
    }
  }
}

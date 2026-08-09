import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_stats.dart';

/// Aggregates library insights + duration for the reading-stats screen.
///
/// Screens subscribe here; they do not touch drift or import services.
class ReadingStatsController extends ChangeNotifier {
  ReadingStatsController({required this.database, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _startWatching();
    _scheduleMidnightRefresh();
  }

  final AppDatabase database;
  final DateTime Function() _clock;

  StreamSubscription<List<LibraryEntry>>? _entriesSub;
  StreamSubscription<(int, int)>? _totalsSub;
  StreamSubscription<List<ReadingDayStat>>? _daySub;
  StreamSubscription<List<ReadingItemTimeData>>? _itemTimeSub;
  Timer? _midnightTimer;

  List<LibraryEntry> _entries = const [];
  List<ReadingDayStat> _dayStats = const [];
  Map<String, int> _itemSecondsById = const {};
  int _bookmarkCount = 0;
  int _annotationCount = 0;
  StatsPeriod _period = StatsPeriod.week;
  ReadingStatsSnapshot _snapshot = ReadingStatsSnapshot.empty;
  Object? _error;
  bool _entriesLoaded = false;
  bool _totalsLoaded = false;
  bool _dayLoaded = false;
  bool _itemTimeLoaded = false;
  bool _rebuildScheduled = false;
  bool _ready = false;
  bool _clearing = false;
  bool _disposed = false;

  StatsPeriod get period => _period;
  ReadingStatsSnapshot get snapshot => _snapshot;
  Object? get error => _error;
  bool get isReady => _ready;
  bool get isClearing => _clearing;

  bool get _allInitialSourcesLoaded =>
      _entriesLoaded && _totalsLoaded && _dayLoaded && _itemTimeLoaded;

  void _startWatching() {
    _entriesSub = database.watchLibraryEntries().listen((entries) {
      if (_disposed) return;
      _entries = entries;
      _entriesLoaded = true;
      _sourceUpdated();
    }, onError: _sourceFailed);
    unawaited(_refreshAnnotationTotals());
    _totalsSub = database.watchAnnotationTotals().listen((pair) {
      if (_disposed) return;
      _bookmarkCount = pair.$1;
      _annotationCount = pair.$2;
      _totalsLoaded = true;
      _sourceUpdated();
    }, onError: _sourceFailed);
    _daySub = database.watchAllDayStats().listen((rows) {
      if (_disposed) return;
      _dayStats = rows;
      _dayLoaded = true;
      _sourceUpdated();
    }, onError: _sourceFailed);
    _itemTimeSub = database.watchAllItemTimes().listen((rows) {
      if (_disposed) return;
      _itemSecondsById = {
        for (final row in rows)
          row.itemId: row.activeSeconds < 0 ? 0 : row.activeSeconds,
      };
      _itemTimeLoaded = true;
      _sourceUpdated();
    }, onError: _sourceFailed);
  }

  void setPeriod(StatsPeriod period) {
    if (_period == period) return;
    _period = period;
    _scheduleRebuild();
  }

  Future<void> retry() async {
    if (_disposed) return;
    await _cancelSubscriptions();
    _entriesLoaded = false;
    _totalsLoaded = false;
    _dayLoaded = false;
    _itemTimeLoaded = false;
    _ready = false;
    _error = null;
    notifyListeners();
    _startWatching();
  }

  Future<void> clearReadingTime() async {
    if (_clearing) return;
    _clearing = true;
    _error = null;
    notifyListeners();
    try {
      await database.clearReadingTimeData();
      if (_disposed) return;
      _dayStats = const [];
      _itemSecondsById = const {};
      // Reflect an explicit destructive action immediately. Drift streams will
      // emit the same empty state afterwards, but the UI must not briefly show
      // stale reading time after the operation has completed.
      if (_ready) {
        _rebuild();
      } else {
        _scheduleRebuild();
      }
    } catch (error) {
      if (!_disposed) {
        _error = error;
        notifyListeners();
      }
      rethrow;
    } finally {
      if (!_disposed) {
        _clearing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshAnnotationTotals() async {
    try {
      final b = await database.countAllBookmarks();
      final a = await database.countAllAnnotations();
      if (_disposed) return;
      _bookmarkCount = b;
      _annotationCount = a;
      _totalsLoaded = true;
      _sourceUpdated();
    } catch (error) {
      _sourceFailed(error);
    }
  }

  void _sourceUpdated() {
    _error = null;
    _scheduleRebuild();
  }

  void _sourceFailed(Object error, [StackTrace? stackTrace]) {
    if (_disposed) return;
    _error = error;
    notifyListeners();
  }

  void _scheduleRebuild() {
    if (_disposed || (!_allInitialSourcesLoaded && !_ready)) return;
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    scheduleMicrotask(() {
      _rebuildScheduled = false;
      if (_disposed || (!_allInitialSourcesLoaded && !_ready)) return;
      _rebuild();
    });
  }

  void _rebuild() {
    _snapshot = buildReadingStats(
      entries: _entries,
      bookmarkCount: _bookmarkCount,
      annotationCount: _annotationCount,
      period: _period,
      now: _clock(),
      dayStats: _dayStats,
      itemSecondsById: _itemSecondsById,
    );
    _ready = true;
    notifyListeners();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = _clock().toLocal();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    var delay = nextMidnight.difference(now) + const Duration(seconds: 1);
    if (delay <= Duration.zero) delay = const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () {
      if (_disposed) return;
      _scheduleRebuild();
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _cancelSubscriptions() async {
    final subscriptions = [_entriesSub, _totalsSub, _daySub, _itemTimeSub];
    _entriesSub = null;
    _totalsSub = null;
    _daySub = null;
    _itemTimeSub = null;
    await Future.wait([
      for (final subscription in subscriptions)
        if (subscription != null) subscription.cancel(),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _midnightTimer?.cancel();
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}

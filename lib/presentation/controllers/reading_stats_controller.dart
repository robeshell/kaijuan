import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_stats.dart';

/// Aggregates library insights + duration for the reading-stats screen.
///
/// Screens subscribe here; they do not touch drift or import services.
class ReadingStatsController extends ChangeNotifier {
  ReadingStatsController({required this.database}) {
    _entriesSub = database.watchLibraryEntries().listen((entries) {
      _entries = entries;
      _rebuild();
    });
    unawaited(_refreshAnnotationTotals());
    _totalsSub = database.watchAnnotationTotals().listen((pair) {
      _bookmarkCount = pair.$1;
      _annotationCount = pair.$2;
      _rebuild();
    });
    _daySub = database.watchAllDayStats().listen((rows) {
      _dayStats = rows;
      _rebuild();
    });
    _itemTimeSub = database.watchAllItemTimes().listen((rows) {
      _itemSecondsById = {
        for (final row in rows) row.itemId: row.activeSeconds,
      };
      _rebuild();
    });
  }

  final AppDatabase database;

  StreamSubscription<List<LibraryEntry>>? _entriesSub;
  StreamSubscription<(int, int)>? _totalsSub;
  StreamSubscription<List<ReadingDayStat>>? _daySub;
  StreamSubscription<List<ReadingItemTimeData>>? _itemTimeSub;

  List<LibraryEntry> _entries = const [];
  List<ReadingDayStat> _dayStats = const [];
  Map<String, int> _itemSecondsById = const {};
  int _bookmarkCount = 0;
  int _annotationCount = 0;
  StatsPeriod _period = StatsPeriod.week;
  ReadingStatsSnapshot _snapshot = ReadingStatsSnapshot.empty;
  bool _ready = false;
  bool _clearing = false;

  StatsPeriod get period => _period;
  ReadingStatsSnapshot get snapshot => _snapshot;
  bool get isReady => _ready;
  bool get isClearing => _clearing;

  void setPeriod(StatsPeriod period) {
    if (_period == period) return;
    _period = period;
    _rebuild();
  }

  Future<void> clearReadingTime() async {
    if (_clearing) return;
    _clearing = true;
    notifyListeners();
    try {
      await database.clearReadingTimeData();
      _dayStats = const [];
      _itemSecondsById = const {};
      _rebuild();
    } finally {
      _clearing = false;
      notifyListeners();
    }
  }

  Future<void> _refreshAnnotationTotals() async {
    try {
      final b = await database.countAllBookmarks();
      final a = await database.countAllAnnotations();
      if (_bookmarkCount == b && _annotationCount == a && _ready) return;
      _bookmarkCount = b;
      _annotationCount = a;
      _rebuild();
    } catch (_) {
      // Leave zeros; next table update will retry via the stream.
    }
  }

  void _rebuild() {
    _snapshot = buildReadingStats(
      entries: _entries,
      bookmarkCount: _bookmarkCount,
      annotationCount: _annotationCount,
      period: _period,
      now: DateTime.now(),
      dayStats: _dayStats,
      itemSecondsById: _itemSecondsById,
    );
    _ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_entriesSub?.cancel() ?? Future<void>.value());
    unawaited(_totalsSub?.cancel() ?? Future<void>.value());
    unawaited(_daySub?.cancel() ?? Future<void>.value());
    unawaited(_itemTimeSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}

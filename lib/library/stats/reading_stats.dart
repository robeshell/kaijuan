import '../../domain/reader_models.dart';
import '../persistence/app_database.dart';

/// Period filter for opened-in-range and duration metrics.
///
/// Library-wide KPIs (在读 / 已读完 / 馆藏) always ignore period.
enum StatsPeriod {
  week,
  month,
  all;

  String get segmentLabel => switch (this) {
    StatsPeriod.week => '本周',
    StatsPeriod.month => '本月',
    StatsPeriod.all => '全部',
  };

  /// Label for the period-scoped open count.
  String openedLabel(int count) {
    final n = count;
    return switch (this) {
      StatsPeriod.week => '近 7 天打开 $n 本',
      StatsPeriod.month => '近 30 天打开 $n 本',
      StatsPeriod.all => '打开过 $n 本',
    };
  }

  /// First local calendar day key included in this period (inclusive).
  ///
  /// Week = today−6 … today (7 days, matches [buildLast7DayBars]).
  /// Month = today−29 … today (30 days). All = no lower bound (`null`).
  String? inclusiveStartDayKey(DateTime now) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    return switch (this) {
      StatsPeriod.week =>
        AppDatabase.localDayKey(today.subtract(const Duration(days: 6))),
      StatsPeriod.month =>
        AppDatabase.localDayKey(today.subtract(const Duration(days: 29))),
      StatsPeriod.all => null,
    };
  }
}

/// One cover row on the stats surface (recent or finished).
class StatsItemRow {
  const StatsItemRow({
    required this.item,
    this.progressFraction,
    this.activeSeconds = 0,
  });

  final ReadingItem item;
  final double? progressFraction;
  final int activeSeconds;
}

/// One day in the rolling 7-day chart (local calendar).
class StatsDayBar {
  const StatsDayBar({
    required this.dayKey,
    required this.weekdayLabel,
    required this.seconds,
    required this.isToday,
  });

  final String dayKey;
  final String weekdayLabel;
  final int seconds;
  final bool isToday;
}

/// One cell in the contribution heatmap (local calendar day).
class StatsHeatmapCell {
  const StatsHeatmapCell({
    required this.dayKey,
    required this.seconds,
    required this.isToday,
    required this.inFuture,
  });

  final String dayKey;
  final int seconds;
  final bool isToday;

  /// Padding cell after today in the last week column.
  final bool inFuture;
}

/// Aggregated library insights + duration for the stats screen.
class ReadingStatsSnapshot {
  const ReadingStatsSnapshot({
    required this.period,
    required this.totalCount,
    required this.comicCount,
    required this.bookCount,
    required this.readingCount,
    required this.finishedCount,
    required this.unreadCount,
    required this.openedInPeriod,
    required this.bookmarkCount,
    required this.annotationCount,
    required this.recent,
    required this.finished,
    required this.periodActiveSeconds,
    required this.periodComicSeconds,
    required this.periodBookSeconds,
    required this.last7Days,
    required this.hasStoredDuration,
    required this.currentStreakDays,
    required this.heatmapCells,
    required this.heatmapWeeks,
    required this.topByTime,
    this.averageProgress,
  });

  final StatsPeriod period;
  final int totalCount;
  final int comicCount;
  final int bookCount;
  final int readingCount;
  final int finishedCount;
  final int unreadCount;
  final int openedInPeriod;
  final int bookmarkCount;
  final int annotationCount;
  final List<StatsItemRow> recent;
  final List<StatsItemRow> finished;

  /// Foreground reading seconds in the selected period.
  final int periodActiveSeconds;
  final int periodComicSeconds;
  final int periodBookSeconds;

  /// Always the rolling 7 local days ending today (for the week chart).
  final List<StatsDayBar> last7Days;

  /// True when any day-stat row has active seconds (survives empty library).
  final bool hasStoredDuration;

  /// Consecutive local days with any reading, ending today (or yesterday if
  /// today is still empty — day not closed yet).
  final int currentStreakDays;

  /// Column-major weeks for the heatmap: length == [heatmapWeeks] * 7.
  final List<StatsHeatmapCell> heatmapCells;
  final int heatmapWeeks;

  /// Books with the most cumulative reading seconds (detail surface on stats).
  final List<StatsItemRow> topByTime;

  /// Mean progress among items that have a progress row; null if none.
  final double? averageProgress;

  bool get isEmptyLibrary => totalCount == 0;

  double get comicShare => totalCount == 0 ? 0 : comicCount / totalCount;
  double get bookShare => totalCount == 0 ? 0 : bookCount / totalCount;

  static const empty = ReadingStatsSnapshot(
    period: StatsPeriod.week,
    totalCount: 0,
    comicCount: 0,
    bookCount: 0,
    readingCount: 0,
    finishedCount: 0,
    unreadCount: 0,
    openedInPeriod: 0,
    bookmarkCount: 0,
    annotationCount: 0,
    recent: [],
    finished: [],
    periodActiveSeconds: 0,
    periodComicSeconds: 0,
    periodBookSeconds: 0,
    last7Days: [],
    hasStoredDuration: false,
    currentStreakDays: 0,
    heatmapCells: [],
    heatmapWeeks: 0,
    topByTime: [],
  );
}

/// Formats cumulative reading seconds for UI (Chinese, calm).
String formatReadingDuration(int seconds) {
  if (seconds <= 0) return '暂无阅读时长';
  if (seconds < 60) return '不足 1 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (rem == 0) return '$hours 小时';
  return '$hours 小时 $rem 分';
}

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// Builds last-7-day bars from day rows (local calendar ending [now]).
List<StatsDayBar> buildLast7DayBars({
  required Map<String, ReadingDayStat> byDay,
  required DateTime now,
}) {
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final day = today.subtract(Duration(days: i));
        final key = AppDatabase.localDayKey(day);
        final row = byDay[key];
        // DateTime.weekday: Mon=1 … Sun=7
        final label = _weekdayLabels[day.weekday - 1];
        return StatsDayBar(
          dayKey: key,
          weekdayLabel: label,
          seconds: row?.activeSeconds ?? 0,
          isToday: i == 0,
        );
      }(),
  ];
}

/// Consecutive reading days ending today, or yesterday if today is still empty.
int buildCurrentStreakDays({
  required Map<String, ReadingDayStat> byDay,
  required DateTime now,
}) {
  final local = now.toLocal();
  var cursor = DateTime(local.year, local.month, local.day);
  final todayKey = AppDatabase.localDayKey(cursor);
  if ((byDay[todayKey]?.activeSeconds ?? 0) <= 0) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (true) {
    final key = AppDatabase.localDayKey(cursor);
    if ((byDay[key]?.activeSeconds ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

/// GitHub contribution graph: [weeks] columns × 7 rows (Mon…Sun), ending this week.
///
/// Default **53** weeks ≈ one year (matches github.com contribution calendar).
List<StatsHeatmapCell> buildHeatmapCells({
  required Map<String, ReadingDayStat> byDay,
  required DateTime now,
  int weeks = 53,
}) {
  assert(weeks > 0);
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  // Align to Monday of the current week.
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final startMonday = thisMonday.subtract(Duration(days: 7 * (weeks - 1)));
  final cells = <StatsHeatmapCell>[];
  for (var w = 0; w < weeks; w++) {
    for (var d = 0; d < 7; d++) {
      final day = startMonday.add(Duration(days: w * 7 + d));
      final key = AppDatabase.localDayKey(day);
      final inFuture = day.isAfter(today);
      final seconds = inFuture ? 0 : (byDay[key]?.activeSeconds ?? 0);
      cells.add(
        StatsHeatmapCell(
          dayKey: key,
          seconds: seconds,
          isToday: day.year == today.year &&
              day.month == today.month &&
              day.day == today.day,
          inFuture: inFuture,
        ),
      );
    }
  }
  return cells;
}

/// GitHub-style intensity 0…4 from seconds relative to [peak] (max day in range).
int contributionLevel(int seconds, int peak) {
  if (seconds <= 0 || peak <= 0) return 0;
  final t = seconds / peak;
  if (t <= 0.25) return 1;
  if (t <= 0.5) return 2;
  if (t <= 0.75) return 3;
  return 4;
}

/// Builds a [ReadingStatsSnapshot] from library entries + day stats.
///
/// Pure function — unit-testable without Flutter.
ReadingStatsSnapshot buildReadingStats({
  required List<LibraryEntry> entries,
  required int bookmarkCount,
  required int annotationCount,
  required StatsPeriod period,
  required DateTime now,
  List<ReadingDayStat> dayStats = const [],
  /// itemId → cumulative seconds from [ReadingItemTime].
  Map<String, int> itemSecondsById = const {},
  int recentLimit = 12,
  int finishedLimit = 12,
  int topByTimeLimit = 8,
}) {
  final windowStartDay = period.inclusiveStartDayKey(now);

  var comicCount = 0;
  var bookCount = 0;
  var readingCount = 0;
  var finishedCount = 0;
  var unreadCount = 0;
  var openedInPeriod = 0;
  var progressSum = 0.0;
  var progressN = 0;

  final opened = <StatsItemRow>[];
  final finishedRows = <StatsItemRow>[];

  for (final entry in entries) {
    final kind = ReaderKind.fromStorage(entry.item.kind);
    if (kind == ReaderKind.comic) {
      comicCount++;
    } else if (kind == ReaderKind.book) {
      bookCount++;
    }

    if (entry.isUnread) {
      unreadCount++;
    } else if (entry.isFinished) {
      finishedCount++;
      finishedRows.add(
        StatsItemRow(
          item: entry.item,
          progressFraction: entry.progressFraction,
        ),
      );
    } else {
      readingCount++;
    }

    final progress = entry.progressFraction;
    if (progress != null) {
      progressSum += progress.clamp(0.0, 1.0);
      progressN++;
    }

    final lastOpened = entry.item.lastOpenedAt;
    if (lastOpened != null) {
      final openDay = AppDatabase.localDayKey(lastOpened);
      final inWindow =
          windowStartDay == null || openDay.compareTo(windowStartDay) >= 0;
      if (inWindow) {
        openedInPeriod++;
        opened.add(
          StatsItemRow(
            item: entry.item,
            progressFraction: entry.progressFraction,
          ),
        );
      }
    }
  }

  opened.sort((a, b) {
    final aAt = a.item.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bAt = b.item.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bAt.compareTo(aAt);
  });

  finishedRows.sort((a, b) {
    final aAt = a.item.lastOpenedAt ?? a.item.updatedAt;
    final bAt = b.item.lastOpenedAt ?? b.item.updatedAt;
    return bAt.compareTo(aAt);
  });

  final byDay = <String, ReadingDayStat>{
    for (final row in dayStats) row.day: row,
  };

  var periodActive = 0;
  var periodComic = 0;
  var periodBook = 0;
  var hasStoredDuration = false;
  for (final row in dayStats) {
    if (row.activeSeconds > 0) {
      hasStoredDuration = true;
    }
    if (windowStartDay != null && row.day.compareTo(windowStartDay) < 0) {
      continue;
    }
    periodActive += row.activeSeconds;
    periodComic += row.comicSeconds;
    periodBook += row.bookSeconds;
  }

  const heatmapWeeks = 53;

  final topByTime = <StatsItemRow>[
    for (final entry in entries)
      if ((itemSecondsById[entry.item.id] ?? 0) > 0)
        StatsItemRow(
          item: entry.item,
          progressFraction: entry.progressFraction,
          activeSeconds: itemSecondsById[entry.item.id] ?? 0,
        ),
  ]..sort((a, b) => b.activeSeconds.compareTo(a.activeSeconds));

  // Also flag item-level duration as stored (for empty-day edge cases).
  final hasItemDuration = itemSecondsById.values.any((s) => s > 0);

  return ReadingStatsSnapshot(
    period: period,
    totalCount: entries.length,
    comicCount: comicCount,
    bookCount: bookCount,
    readingCount: readingCount,
    finishedCount: finishedCount,
    unreadCount: unreadCount,
    openedInPeriod: openedInPeriod,
    bookmarkCount: bookmarkCount,
    annotationCount: annotationCount,
    recent: opened.take(recentLimit).toList(growable: false),
    finished: finishedRows.take(finishedLimit).toList(growable: false),
    periodActiveSeconds: periodActive,
    periodComicSeconds: periodComic,
    periodBookSeconds: periodBook,
    last7Days: buildLast7DayBars(byDay: byDay, now: now),
    hasStoredDuration: hasStoredDuration || hasItemDuration,
    currentStreakDays: buildCurrentStreakDays(byDay: byDay, now: now),
    heatmapCells: buildHeatmapCells(
      byDay: byDay,
      now: now,
      weeks: heatmapWeeks,
    ),
    heatmapWeeks: heatmapWeeks,
    topByTime: topByTime.take(topByTimeLimit).toList(growable: false),
    averageProgress: progressN == 0 ? null : progressSum / progressN,
  );
}

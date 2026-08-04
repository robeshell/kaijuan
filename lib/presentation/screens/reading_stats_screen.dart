import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_stats.dart';
import '../controllers/library_controller.dart';
import '../controllers/reading_stats_controller.dart';
import '../navigation/app_page_route.dart';
import '../navigation/open_reading_item.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/cover_card_ink.dart';
import '../widgets/settings_components.dart';

/// Library insights + foreground reading duration. See docs/specs/reading-stats.md.
class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({
    super.key,
    required this.libraryController,
    this.comicReadingPreferences,
    this.bookReadingPreferences,
  });

  final LibraryController libraryController;
  final ComicReadingPreferences? comicReadingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  static Future<void> open(
    BuildContext context, {
    required LibraryController libraryController,
    ComicReadingPreferences? comicReadingPreferences,
    BookReadingPreferences? bookReadingPreferences,
  }) {
    return Navigator.of(context).push<void>(
      appPageRoute<void>(
        (_) => ReadingStatsScreen(
          libraryController: libraryController,
          comicReadingPreferences: comicReadingPreferences,
          bookReadingPreferences: bookReadingPreferences,
        ),
      ),
    );
  }

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> {
  late final ReadingStatsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReadingStatsController(
      database: widget.libraryController.database,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openItem(ReadingItem item) {
    openReadingItem(
      context,
      database: widget.libraryController.database,
      item: item,
      comicReadingPreferences: widget.comicReadingPreferences,
      bookReadingPreferences: widget.bookReadingPreferences,
    );
  }

  Future<void> _confirmClearTime() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '清除阅读时长？',
      message: '将删除全部阅读时长记录。书籍、进度、书签和笔记不受影响。',
      confirmLabel: '清除时长',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    await _controller.clearReadingTime();
    if (!mounted) return;
    showAppSnackBar(context, '已清除阅读时长');
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;
    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: AppSettingsSafeArea(
        bottom: true,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final snap = _controller.snapshot;
            // Side-rail hosts stats like a root destination — no back chrome.
            // Compact (bottom bar) still needs pop to leave the subpage.
            final onBack = context.appUsesSideRail
                ? null
                : () => Navigator.of(context).maybePop();

            // Match shelf / library: full content width, only page gutters.
            // (Previously formMaxWidth 720 while settings used 920 — looked uneven.)
            const contentMaxWidth = double.infinity;

            if (!_controller.isReady) {
              return AppSettingsScrollView(
                maxWidth: contentMaxWidth,
                padding: EdgeInsets.fromLTRB(
                  hPad,
                  AppSettingsMetrics.pageTop(context),
                  hPad,
                  context.appContentBottomPadding,
                ),
                children: [
                  AppSettingsPageHeader(
                    title: '阅读统计',
                    onBack: onBack,
                  ),
                  const SizedBox(height: AppSettingsMetrics.headerGap),
                  const AppEmptyState(
                    icon: KaijuanIcons.stats,
                    title: '正在汇总…',
                    message: '正在读取书库进度',
                    loading: true,
                  ),
                ],
              );
            }

            return AppSettingsScrollView(
              maxWidth: contentMaxWidth,
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSettingsMetrics.pageTop(context),
                hPad,
                context.appContentBottomPadding,
              ),
              children: [
                AppSettingsPageHeader(
                  title: '阅读统计',
                  onBack: onBack,
                ),
                const SizedBox(height: AppSettingsMetrics.headerGap),
                if (snap.isEmptyLibrary) ...[
                  const AppEmptyState(
                    icon: KaijuanIcons.stats,
                    title: '还没有书籍',
                    message: '导入后，这里会汇总在读与读完情况。',
                  ),
                  // Orphan day stats after deleting all books still need
                  // duration view + clear (spec: empty is upper-half only).
                  if (snap.hasStoredDuration) ...[
                    const SizedBox(height: AppSettingsMetrics.sectionGap),
                    _PeriodSegment(
                      period: _controller.period,
                      onChanged: _controller.setPeriod,
                    ),
                    const SizedBox(height: 16),
                    _DurationSummary(snapshot: snap),
                    if (snap.period == StatsPeriod.week) ...[
                      const SizedBox(height: 14),
                      _WeekBars(bars: snap.last7Days),
                    ],
                    const SizedBox(height: 14),
                    _HeatmapCard(snapshot: snap),
                    const SizedBox(height: AppSettingsMetrics.sectionGap),
                    const _SectionLabel('数据'),
                    const SizedBox(height: 10),
                    AppSettingsGroup(
                      children: [
                        _SettingsLinkRow(
                          label: '清除阅读时长…',
                          destructive: true,
                          enabled: !_controller.isClearing,
                          onTap: _confirmClearTime,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '听书播放时间不计入阅读时长。清除只影响时长记录。',
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: context.settingsMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  _PeriodSegment(
                    period: _controller.period,
                    onChanged: _controller.setPeriod,
                  ),
                  const SizedBox(height: 16),
                  _KpiRow(snapshot: snap),
                  const SizedBox(height: 12),
                  _DurationSummary(snapshot: snap),
                  if (snap.period == StatsPeriod.week) ...[
                    const SizedBox(height: 14),
                    _WeekBars(bars: snap.last7Days),
                  ],
                  const SizedBox(height: AppSettingsMetrics.sectionGap),
                  _HeatmapCard(snapshot: snap),
                  if (snap.topByTime.isNotEmpty) ...[
                    const SizedBox(height: AppSettingsMetrics.sectionGap),
                    const _SectionLabel('单本阅读时长'),
                    const SizedBox(height: 10),
                    _TopByTimeList(
                      rows: snap.topByTime,
                      onOpen: _openItem,
                    ),
                  ],
                  if (snap.recent.isNotEmpty) ...[
                    const SizedBox(height: AppSettingsMetrics.sectionGap),
                    const _SectionLabel('最近在读'),
                    const SizedBox(height: 12),
                    _RecentCovers(
                      rows: snap.recent,
                      onOpen: _openItem,
                    ),
                  ] else if (snap.period != StatsPeriod.all) ...[
                    const SizedBox(height: AppSettingsMetrics.sectionGap),
                    const _SectionLabel('最近在读'),
                    const SizedBox(height: 10),
                    Text(
                      '这段时间还没有打开过书',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        color: context.settingsMuted,
                      ),
                    ),
                  ],
                  if (snap.finished.isNotEmpty) ...[
                    const SizedBox(height: AppSettingsMetrics.sectionGap),
                    const _SectionLabel('已读完'),
                    const SizedBox(height: 10),
                    _FinishedList(
                      rows: snap.finished,
                      onOpen: _openItem,
                    ),
                  ],
                  const SizedBox(height: AppSettingsMetrics.sectionGap),
                  const _SectionLabel('笔记与书签'),
                  const SizedBox(height: 10),
                  AppSettingsGroup(
                    children: [
                      _MetaRow(
                        label: '书签',
                        value: '${snap.bookmarkCount}',
                      ),
                      _MetaRow(
                        label: '划线与笔记',
                        value: '${snap.annotationCount}',
                      ),
                      if (snap.averageProgress != null)
                        _MetaRow(
                          label: '平均进度',
                          value:
                              '${(snap.averageProgress! * 100).round()}%',
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSettingsMetrics.sectionGap),
                  const _SectionLabel('数据'),
                  const SizedBox(height: 10),
                  AppSettingsGroup(
                    children: [
                      _SettingsLinkRow(
                        label: '清除阅读时长…',
                        destructive: true,
                        enabled: !_controller.isClearing,
                        onTap: _confirmClearTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '听书播放时间不计入阅读时长。清除只影响时长记录。',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        color: context.settingsMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: context.appCaptionSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: context.settingsSecondary,
        ),
      ),
    );
  }
}

class _PeriodSegment extends StatelessWidget {
  const _PeriodSegment({
    required this.period,
    required this.onChanged,
  });

  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '统计周期',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.settingsGroupSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final p in StatsPeriod.values)
                Expanded(
                  child: _PeriodChip(
                    label: p.segmentLabel,
                    selected: period == p,
                    accent: accent,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(p);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.card - 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card - 2),
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: context.appLabelSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? accent : context.settingsSecondary,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.snapshot});

  final ReadingStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            value: '${snapshot.readingCount}',
            label: '在读',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            value: '${snapshot.finishedCount}',
            label: '已读完',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            value: '${snapshot.totalCount}',
            label: '馆藏',
          ),
        ),
      ],
    );
  }
}

class _DurationSummary extends StatelessWidget {
  const _DurationSummary({required this.snapshot});

  final ReadingStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final duration = formatReadingDuration(snapshot.periodActiveSeconds);
    final comic = formatReadingDuration(snapshot.periodComicSeconds);
    final book = formatReadingDuration(snapshot.periodBookSeconds);
    final hasTime = snapshot.periodActiveSeconds > 0;

    return Semantics(
      label:
          '阅读时长 $duration。${snapshot.period.openedLabel(snapshot.openedInPeriod)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.settingsGroupSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '阅读时长',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  fontWeight: FontWeight.w600,
                  color: context.settingsSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                duration,
                style: TextStyle(
                  fontSize: context.appSectionTitleSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.15,
                  color: hasTime ? accent : context.settingsPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.period.openedLabel(snapshot.openedInPeriod),
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.settingsSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (hasTime) ...[
                const SizedBox(height: 6),
                Text(
                  '漫画 $comic · 图书 $book',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: context.settingsMuted,
                  ),
                ),
              ],
              if (snapshot.currentStreakDays > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '连续阅读 ${snapshot.currentStreakDays} 天',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    fontWeight: FontWeight.w600,
                    color: context.settingsPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// GitHub contribution-graph palette (levels 0–4).
abstract final class _GithubHeatColors {
  // Light — classic github.com greens
  static const light = <Color>[
    Color(0xFFEBEDF0),
    Color(0xFF9BE9A8),
    Color(0xFF40C463),
    Color(0xFF30A14E),
    Color(0xFF216E39),
  ];

  // Dark — github dark dimmed contribution greens
  static const dark = <Color>[
    Color(0xFF161B22),
    Color(0xFF0E4429),
    Color(0xFF006D32),
    Color(0xFF26A641),
    Color(0xFF39D353),
  ];

  static List<Color> of(Brightness b) =>
      b == Brightness.dark ? dark : light;
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.snapshot});

  final ReadingStatsSnapshot snapshot;

  static const _monthNames = [
    '1月', '2月', '3月', '4月', '5月', '6月',
    '7月', '8月', '9月', '10月', '11月', '12月',
  ];

  /// Weekday labels for Mon…Sun rows (only Mon/Wed/Fri shown, like GitHub).
  static const _dayLabels = ['一', '', '三', '', '五', '', ''];

  @override
  Widget build(BuildContext context) {
    final cells = snapshot.heatmapCells;
    final weeks = snapshot.heatmapWeeks;
    if (cells.isEmpty || weeks <= 0) return const SizedBox.shrink();

    final peak = cells.fold<int>(
      0,
      (m, c) => c.seconds > m ? c.seconds : m,
    );
    final colors = _GithubHeatColors.of(Theme.of(context).brightness);
    final muted = context.settingsMuted;

    // Month label per week column (first week of each month).
    final monthByWeek = List<String?>.filled(weeks, null);
    int? lastMonth;
    for (var w = 0; w < weeks; w++) {
      final key = cells[w * 7].dayKey; // Monday of that week
      final parts = key.split('-');
      if (parts.length < 2) continue;
      final month = int.tryParse(parts[1]);
      if (month == null) continue;
      if (month != lastMonth) {
        monthByWeek[w] = _monthNames[month - 1];
        lastMonth = month;
      }
    }

    return Semantics(
      label: '近一年阅读热力图，GitHub 风格',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.settingsGroupSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '近一年',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        fontWeight: FontWeight.w600,
                        color: context.settingsSecondary,
                      ),
                    ),
                  ),
                  if (snapshot.currentStreakDays > 0)
                    Text(
                      '连续 ${snapshot.currentStreakDays} 天',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        fontWeight: FontWeight.w600,
                        color: context.settingsPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  const dayLabelW = 20.0;
                  const gap = 3.5;
                  final gridW = constraints.maxWidth - dayLabelW;
                  // Fill width; height is boosted so the year grid reads larger.
                  final cellW =
                      ((gridW - gap * (weeks - 1)) / weeks).clamp(4.0, 22.0);
                  final cellH = (cellW * 1.55).clamp(12.0, 26.0);
                  final gridH = cellH * 7 + gap * 6;
                  const monthH = 18.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Month labels row
                      SizedBox(
                        height: monthH,
                        child: Row(
                          children: [
                            const SizedBox(width: dayLabelW),
                            Expanded(
                              child: Stack(
                                children: [
                                  for (var w = 0; w < weeks; w++)
                                    if (monthByWeek[w] != null)
                                      Positioned(
                                        left: w * (cellW + gap),
                                        top: 0,
                                        child: Text(
                                          monthByWeek[w]!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.2,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Day labels + grid — every day is a visible cell (incl. empty/future).
                      SizedBox(
                        height: gridH,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: dayLabelW,
                              height: gridH,
                              child: Column(
                                children: [
                                  for (var row = 0; row < 7; row++) ...[
                                    if (row > 0) const SizedBox(height: gap),
                                    SizedBox(
                                      height: cellH,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _dayLabels[row],
                                          style: TextStyle(
                                            fontSize: 10,
                                            height: 1,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  for (var row = 0; row < 7; row++) ...[
                                    if (row > 0) const SizedBox(height: gap),
                                    SizedBox(
                                      height: cellH,
                                      child: Row(
                                        children: [
                                          for (var col = 0;
                                              col < weeks;
                                              col++) ...[
                                            if (col > 0)
                                              SizedBox(width: gap),
                                            Expanded(
                                              child: _GithubHeatCell(
                                                cell: cells[col * 7 + row],
                                                level: contributionLevel(
                                                  cells[col * 7 + row].seconds,
                                                  peak,
                                                ),
                                                colors: colors,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Less ▢▢▢▢▢ More
                      Row(
                        children: [
                          const Spacer(),
                          Text(
                            '少',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          for (var level = 0; level <= 4; level++) ...[
                            if (level > 0) const SizedBox(width: 3),
                            Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: colors[level],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Text(
                            '多',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GithubHeatCell extends StatelessWidget {
  const _GithubHeatCell({
    required this.cell,
    required this.level,
    required this.colors,
  });

  final StatsHeatmapCell cell;
  final int level;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    // Always paint a cell (including empty + future), like GitHub's grid.
    final fill = colors[cell.inFuture ? 0 : level.clamp(0, 4)];
    final label = cell.inFuture
        ? cell.dayKey
        : cell.seconds <= 0
        ? '${cell.dayKey}，无阅读'
        : '${cell.dayKey}，${formatReadingDuration(cell.seconds)}';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopByTimeList extends StatelessWidget {
  const _TopByTimeList({
    required this.rows,
    required this.onOpen,
  });

  final List<StatsItemRow> rows;
  final void Function(ReadingItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return AppSettingsGroup(
      children: [
        for (final row in rows)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onOpen(row.item),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: context.appListTitleSize,
                          fontWeight: FontWeight.w600,
                          color: context.settingsPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatReadingDuration(row.activeSeconds),
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        fontWeight: FontWeight.w600,
                        color: context.settingsSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.bars});

  final List<StatsDayBar> bars;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final track = context.appDivider.withValues(alpha: 0.45);
    final maxSeconds = bars.fold<int>(
      0,
      (m, b) => b.seconds > m ? b.seconds : m,
    );
    final peak = maxSeconds <= 0 ? 1 : maxSeconds;

    return Semantics(
      label: '近 7 日阅读时长',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.settingsGroupSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '近 7 日',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  fontWeight: FontWeight.w600,
                  color: context.settingsSecondary,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 112,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final bar in bars)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _DayBarColumn(
                            bar: bar,
                            peak: peak,
                            accent: accent,
                            track: track,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayBarColumn extends StatelessWidget {
  const _DayBarColumn({
    required this.bar,
    required this.peak,
    required this.accent,
    required this.track,
  });

  final StatsDayBar bar;
  final int peak;
  final Color accent;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final ratio = (bar.seconds / peak).clamp(0.0, 1.0);
    final minutes = bar.seconds ~/ 60;
    final label = bar.seconds <= 0
        ? '${bar.weekdayLabel}，无阅读'
        : '${bar.weekdayLabel}，${formatReadingDuration(bar.seconds)}';

    return Semantics(
      label: label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: bar.seconds <= 0 ? 0.04 : (0.12 + 0.88 * ratio),
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bar.seconds <= 0
                        ? track
                        : accent.withValues(alpha: bar.isToday ? 1 : 0.72),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bar.weekdayLabel,
            style: TextStyle(
              fontSize: context.appCaptionSmallSize,
              fontWeight: bar.isToday ? FontWeight.w700 : FontWeight.w500,
              color: bar.isToday
                  ? context.settingsPrimary
                  : context.settingsMuted,
            ),
          ),
          if (minutes > 0)
            Text(
              '$minutes',
              style: TextStyle(
                fontSize: context.appCaptionSmallSize,
                color: context.settingsMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            Text(
              '·',
              style: TextStyle(
                fontSize: context.appCaptionSmallSize,
                color: context.settingsMuted.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsLinkRow extends StatelessWidget {
  const _SettingsLinkRow({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? context.settingsMuted
        : destructive
        ? Theme.of(context).colorScheme.error
        : context.settingsPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(
            label,
            style: TextStyle(
              fontSize: context.appListTitleSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.settingsGroupSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: context.appSectionTitleSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.1,
                  color: context.settingsPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  fontWeight: FontWeight.w500,
                  color: context.settingsSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentCovers extends StatelessWidget {
  const _RecentCovers({
    required this.rows,
    required this.onOpen,
  });

  final List<StatsItemRow> rows;
  final void Function(ReadingItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hairline = context.appDivider;
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(end: 8),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final row = rows[i];
          return _CoverTile(
            title: row.item.title,
            progress: row.progressFraction,
            accent: accent,
            hairline: hairline,
            cover: _FileCover(
              path: row.item.coverPath,
            ),
            onTap: () => onOpen(row.item),
          );
        },
      ),
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.title,
    required this.cover,
    required this.accent,
    required this.hairline,
    required this.onTap,
    this.progress,
  });

  final String title;
  final Widget cover;
  final double? progress;
  final Color accent;
  final Color hairline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: CoverCardInk(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppProductRadii.cover),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              height: 140,
              child: SoftCoverFrame(child: cover),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 18,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appGridTitleStyle.copyWith(
                  color: context.appPrimaryText,
                ),
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: hairline,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinishedList extends StatelessWidget {
  const _FinishedList({
    required this.rows,
    required this.onOpen,
  });

  final List<StatsItemRow> rows;
  final void Function(ReadingItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return AppSettingsGroup(
      children: [
        for (final row in rows)
          _FinishedRow(
            row: row,
            onTap: () => onOpen(row.item),
          ),
      ],
    );
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({
    required this.row,
    required this.onTap,
  });

  final StatsItemRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 54,
                child: SoftCoverFrame(
                  child: _FileCover(path: row.item.coverPath),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.appListTitleSize,
                        fontWeight: FontWeight.w600,
                        color: context.settingsPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '已读完',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        color: context.settingsSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                KaijuanIcons.chevronRight,
                size: 18,
                color: context.settingsMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: context.appListTitleSize,
                fontWeight: FontWeight.w500,
                color: context.settingsPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: context.appListTitleSize,
              fontWeight: FontWeight.w600,
              color: context.settingsSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCover extends StatelessWidget {
  const _FileCover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final canvas = Theme.of(context).scaffoldBackgroundColor;
    if (path == null) {
      return ColoredBox(color: canvas);
    }
    return Image.file(
      File(path!),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => ColoredBox(color: canvas),
    );
  }
}

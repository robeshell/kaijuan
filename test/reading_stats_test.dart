import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/backup/backup_format.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/library/stats/reading_stats.dart';
import 'package:kaijuan/library/stats/reading_day_counters.dart';
import 'package:kaijuan/library/stats/reading_time_tracker.dart';
import 'package:kaijuan/presentation/controllers/reading_stats_controller.dart';
import 'package:kaijuan/readers/comic/comic_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildReadingStats', () {
    // Local wall time so day keys align with localDayKey() on any timezone.
    final now = DateTime(2026, 8, 4, 12);

    LibraryEntry entry({
      required String id,
      required ReaderKind kind,
      DateTime? lastOpenedAt,
      double? progress,
    }) {
      final item = ReadingItem(
        id: id,
        kind: kind.storageValue,
        format: kind == ReaderKind.comic
            ? ReaderFormat.cbz.storageValue
            : ReaderFormat.epub.storageValue,
        title: id,
        filePath: '/tmp/$id',
        contentHash: 'hash-$id',
        coverPath: null,
        seriesName: null,
        pageCount: kind == ReaderKind.comic ? 10 : 0,
        pageOrderVersion: ComicPageOrder.version,
        onShelf: false,
        addedAt: now.subtract(const Duration(days: 40)),
        updatedAt: now,
        lastOpenedAt: lastOpenedAt,
      );
      return LibraryEntry(item: item, progressFraction: progress);
    }

    test('classifies unread / reading / finished and kind counts', () {
      final snap = buildReadingStats(
        entries: [
          entry(id: 'u', kind: ReaderKind.comic),
          entry(
            id: 'r',
            kind: ReaderKind.book,
            lastOpenedAt: now,
            progress: 0.4,
          ),
          entry(
            id: 'f',
            kind: ReaderKind.comic,
            lastOpenedAt: now.subtract(const Duration(days: 2)),
            progress: 0.99,
          ),
        ],
        bookmarkCount: 3,
        annotationCount: 5,
        period: StatsPeriod.all,
        now: now,
      );

      expect(snap.totalCount, 3);
      expect(snap.comicCount, 2);
      expect(snap.bookCount, 1);
      expect(snap.unreadCount, 1);
      expect(snap.readingCount, 1);
      expect(snap.finishedCount, 1);
      expect(snap.openedInPeriod, 2);
      expect(snap.bookmarkCount, 3);
      expect(snap.annotationCount, 5);
      expect(snap.averageProgress, closeTo((0.4 + 0.99) / 2, 1e-9));
      expect(snap.finished, hasLength(1));
      expect(snap.finished.single.item.id, 'f');
    });

    test('week window only counts lastOpened within 7 days', () {
      final snap = buildReadingStats(
        entries: [
          entry(
            id: 'recent',
            kind: ReaderKind.book,
            lastOpenedAt: now.subtract(const Duration(days: 3)),
            progress: 0.2,
          ),
          entry(
            id: 'old',
            kind: ReaderKind.book,
            lastOpenedAt: now.subtract(const Duration(days: 10)),
            progress: 0.5,
          ),
        ],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.week,
        now: now,
      );

      expect(snap.openedInPeriod, 1);
      expect(snap.recent, hasLength(1));
      expect(snap.recent.single.item.id, 'recent');
      expect(snap.readingCount, 2);
      expect(snap.totalCount, 2);
    });

    test('sums duration for period and builds last-7 bars', () {
      final today = AppDatabase.localDayKey(now);
      final threeDaysAgo = AppDatabase.localDayKey(
        now.subtract(const Duration(days: 3)),
      );
      final tenDaysAgo = AppDatabase.localDayKey(
        now.subtract(const Duration(days: 10)),
      );

      final snap = buildReadingStats(
        entries: const [],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.week,
        now: now,
        dayStats: [
          ReadingDayStat(
            day: today,
            activeSeconds: 600,
            comicSeconds: 400,
            bookSeconds: 200,
            sessionsCount: 1,
          ),
          ReadingDayStat(
            day: threeDaysAgo,
            activeSeconds: 120,
            comicSeconds: 0,
            bookSeconds: 120,
            sessionsCount: 1,
          ),
          ReadingDayStat(
            day: tenDaysAgo,
            activeSeconds: 9999,
            comicSeconds: 9999,
            bookSeconds: 0,
            sessionsCount: 1,
          ),
        ],
      );

      // Week excludes the 10-day-old row.
      expect(snap.periodActiveSeconds, 720);
      expect(snap.periodComicSeconds, 400);
      expect(snap.periodBookSeconds, 320);
      expect(snap.last7Days, hasLength(7));
      expect(snap.last7Days.last.dayKey, today);
      expect(snap.last7Days.last.seconds, 600);
      expect(snap.last7Days.last.isToday, isTrue);
      expect(snap.hasStoredDuration, isTrue);
    });

    test('week duration matches 7 calendar days (today-6..today), not 8', () {
      // Skeptic case: now=2026-08-04 12:00, only day 2026-07-28 has seconds.
      // Inclusive week starts 2026-07-29; 07-28 must not enter period totals,
      // and last7Days bars (07-29..08-04) are all zero.
      final nowLocal = DateTime(2026, 8, 4, 12);
      final snap = buildReadingStats(
        entries: const [],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.week,
        now: nowLocal,
        dayStats: const [
          ReadingDayStat(
            day: '2026-07-28',
            activeSeconds: 999,
            comicSeconds: 999,
            bookSeconds: 0,
            sessionsCount: 1,
          ),
        ],
      );

      expect(StatsPeriod.week.inclusiveStartDayKey(nowLocal), '2026-07-29');
      expect(snap.periodActiveSeconds, 0);
      expect(snap.periodComicSeconds, 0);
      expect(snap.last7Days, hasLength(7));
      expect(snap.last7Days.first.dayKey, '2026-07-29');
      expect(snap.last7Days.last.dayKey, '2026-08-04');
      expect(snap.last7Days.every((b) => b.seconds == 0), isTrue);
      // Stored orphan day still flagged so empty-library UI can clear.
      expect(snap.hasStoredDuration, isTrue);
      expect(snap.isEmptyLibrary, isTrue);
    });

    test('month duration uses 30 calendar days (today-29..today)', () {
      final nowLocal = DateTime(2026, 8, 4, 12);
      // today-29 = 2026-07-06; day 2026-07-05 is outside.
      final snap = buildReadingStats(
        entries: const [],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.month,
        now: nowLocal,
        dayStats: const [
          ReadingDayStat(
            day: '2026-07-05',
            activeSeconds: 500,
            comicSeconds: 500,
            bookSeconds: 0,
            sessionsCount: 1,
          ),
          ReadingDayStat(
            day: '2026-07-06',
            activeSeconds: 100,
            comicSeconds: 0,
            bookSeconds: 100,
            sessionsCount: 1,
          ),
        ],
      );
      expect(StatsPeriod.month.inclusiveStartDayKey(nowLocal), '2026-07-06');
      expect(snap.periodActiveSeconds, 100);
      expect(snap.periodBookSeconds, 100);
    });

    test('formatReadingDuration', () {
      expect(formatReadingDuration(0), '暂无阅读时长');
      expect(formatReadingDuration(45), '不足 1 分钟');
      expect(formatReadingDuration(120), '2 分钟');
      expect(formatReadingDuration(3600), '1 小时');
      expect(formatReadingDuration(3660), '1 小时 1 分');
    });

    test('current streak ends on today or yesterday', () {
      final nowLocal = DateTime(2026, 8, 4, 12);
      final byDay = <String, ReadingDayStat>{
        '2026-08-04': const ReadingDayStat(
          day: '2026-08-04',
          activeSeconds: 60,
          comicSeconds: 60,
          bookSeconds: 0,
          sessionsCount: 1,
        ),
        '2026-08-03': const ReadingDayStat(
          day: '2026-08-03',
          activeSeconds: 60,
          comicSeconds: 0,
          bookSeconds: 60,
          sessionsCount: 1,
        ),
        '2026-08-01': const ReadingDayStat(
          day: '2026-08-01',
          activeSeconds: 60,
          comicSeconds: 60,
          bookSeconds: 0,
          sessionsCount: 1,
        ),
      };
      expect(buildCurrentStreakDays(byDay: byDay, now: nowLocal), 2);

      // Today empty → streak continues from yesterday.
      byDay.remove('2026-08-04');
      expect(buildCurrentStreakDays(byDay: byDay, now: nowLocal), 1);
    });

    test('heatmap is weeks×7 and ends on this week', () {
      final nowLocal = DateTime(2026, 8, 4, 12); // Tuesday
      final cells = buildHeatmapCells(
        byDay: {
          '2026-08-04': const ReadingDayStat(
            day: '2026-08-04',
            activeSeconds: 120,
            comicSeconds: 0,
            bookSeconds: 120,
            sessionsCount: 1,
          ),
        },
        now: nowLocal,
        weeks: 4,
      );
      expect(cells, hasLength(28));
      // 2026-08-04 is Tuesday → weekday 2 → row index 1 within week column.
      final todayCell = cells.firstWhere((c) => c.isToday);
      expect(todayCell.dayKey, '2026-08-04');
      expect(todayCell.seconds, 120);
      expect(cells.where((c) => c.inFuture).length, greaterThan(0));
    });

    test('default heatmap is 53 weeks; contribution levels are 0–4', () {
      final nowLocal = DateTime(2026, 8, 4, 12);
      final cells = buildHeatmapCells(byDay: const {}, now: nowLocal);
      expect(cells, hasLength(53 * 7));
      expect(contributionLevel(0), 0);
      expect(contributionLevel(10 * 60), 1);
      expect(contributionLevel(20 * 60), 2);
      expect(contributionLevel(45 * 60), 3);
      expect(contributionLevel(60 * 60), 4);
    });

    test('finished threshold matches library (≥ 0.98)', () {
      final snap = buildReadingStats(
        entries: [
          entry(
            id: 'almost',
            kind: ReaderKind.book,
            lastOpenedAt: now,
            progress: 0.979,
          ),
          entry(
            id: 'done',
            kind: ReaderKind.book,
            lastOpenedAt: now,
            progress: 0.98,
          ),
        ],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.all,
        now: now,
      );
      expect(snap.readingCount, 1);
      expect(snap.finishedCount, 1);
      expect(snap.finished.single.item.id, 'done');
    });

    test('finished progress wins when legacy lastOpenedAt is missing', () {
      final snap = buildReadingStats(
        entries: [entry(id: 'restored', kind: ReaderKind.book, progress: 1)],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.all,
        now: now,
      );
      expect(snap.finishedCount, 1);
      expect(snap.unreadCount, 0);
      expect(snap.finished.single.item.id, 'restored');
    });

    test('recent reading excludes finished and future-opened items', () {
      final snap = buildReadingStats(
        entries: [
          entry(
            id: 'reading',
            kind: ReaderKind.book,
            lastOpenedAt: now,
            progress: 0.5,
          ),
          entry(
            id: 'finished',
            kind: ReaderKind.book,
            lastOpenedAt: now,
            progress: 1,
          ),
          entry(
            id: 'future',
            kind: ReaderKind.book,
            lastOpenedAt: DateTime(2026, 8, 5),
            progress: 0.2,
          ),
        ],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.week,
        now: now,
      );
      expect(snap.openedInPeriod, 2);
      expect(snap.recent.map((row) => row.item.id), ['reading']);
    });

    test('period duration excludes future rows', () {
      final snap = buildReadingStats(
        entries: const [],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.all,
        now: now,
        dayStats: const [
          ReadingDayStat(
            day: '2026-08-05',
            activeSeconds: 600,
            comicSeconds: 0,
            bookSeconds: 600,
            sessionsCount: 1,
          ),
        ],
      );
      expect(snap.periodActiveSeconds, 0);
      expect(snap.hasStoredDuration, isTrue);
    });

    test('empty library snapshot', () {
      final snap = buildReadingStats(
        entries: const [],
        bookmarkCount: 0,
        annotationCount: 0,
        period: StatsPeriod.week,
        now: now,
      );
      expect(snap.isEmptyLibrary, isTrue);
      expect(snap.comicShare, 0);
      expect(StatsPeriod.week.openedLabel(0), '近 7 天打开 0 本');
      expect(StatsPeriod.month.openedLabel(2), '近 30 天打开 2 本');
      expect(StatsPeriod.all.openedLabel(5), '打开过 5 本');
    });
  });

  group('AppDatabase reading time', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    Future<void> insertItem(String id, {ReaderKind kind = ReaderKind.book}) {
      final now = DateTime.utc(2026, 1, 1);
      return database.upsertReadingItem(
        ReadingItemsCompanion.insert(
          id: id,
          kind: kind.storageValue,
          format: kind == ReaderKind.comic
              ? ReaderFormat.cbz.storageValue
              : ReaderFormat.epub.storageValue,
          title: id,
          filePath: '/tmp/$id',
          contentHash: 'hash-$id',
          pageCount: Value(kind == ReaderKind.comic ? 10 : 0),
          pageOrderVersion: Value(ComicPageOrder.version),
          addedAt: now,
          updatedAt: now,
        ),
      );
    }

    test('countAllBookmarks and countAllAnnotations', () async {
      await insertItem('a');
      await insertItem('b');
      expect(await database.countAllBookmarks(), 0);
      expect(await database.countAllAnnotations(), 0);

      await database.addBookmark(
        itemId: 'a',
        locatorJson: '{"x":1}',
        label: 'p1',
      );
      await database.addBookmark(itemId: 'b', locatorJson: '{"x":2}');
      await database.upsertAnnotation(
        itemId: 'a',
        cfi: 'epubcfi(/6/2)',
        type: 'highlight',
        color: '#ff0',
        selectedText: 'hello',
      );

      expect(await database.countAllBookmarks(), 2);
      expect(await database.countAllAnnotations(), 1);
    });

    test('addReadingSeconds rolls up day and item totals', () async {
      await insertItem('a', kind: ReaderKind.comic);
      await insertItem('b', kind: ReaderKind.book);

      await database.addReadingSeconds(
        dayKey: '2026-08-01',
        itemId: 'a',
        kind: ReaderKind.comic,
        seconds: 100,
        countSession: true,
      );
      await database.addReadingSeconds(
        dayKey: '2026-08-01',
        itemId: 'b',
        kind: ReaderKind.book,
        seconds: 50,
      );
      await database.addReadingSeconds(
        dayKey: '2026-08-02',
        itemId: 'a',
        kind: ReaderKind.comic,
        seconds: 30,
        countSession: true,
      );

      final days = await database.watchAllDayStats().first;
      expect(days, hasLength(2));
      final d1 = days.firstWhere((d) => d.day == '2026-08-01');
      expect(d1.activeSeconds, 150);
      expect(d1.comicSeconds, 100);
      expect(d1.bookSeconds, 50);
      expect(d1.sessionsCount, 1);

      expect(await database.itemReadingSeconds('a'), 130);
      expect(await database.itemReadingSeconds('b'), 50);

      await database.clearReadingTimeData();
      expect(await database.watchAllDayStats().first, isEmpty);
      expect(await database.itemReadingSeconds('a'), 0);
    });

    test('ReadingTimeTracker flushes seconds with fake clock', () async {
      await insertItem('x', kind: ReaderKind.book);
      var now = DateTime(2026, 8, 4, 10, 0, 0);
      final tracker = ReadingTimeTracker(
        database: database,
        itemId: 'x',
        kind: ReaderKind.book,
        flushInterval: const Duration(hours: 1),
        clock: () => now,
      );

      // Avoid WidgetsBinding: exercise persist via setCountingEnabled false
      // after manually starting is hard without attach. Use addReadingSeconds
      // path by calling private through public detach after attach needs binding.
      // Instead unit-test midnight split through public DB API + tracker
      // setCountingEnabled with attach under testWidgets.
      tracker.attach();
      tracker.setContentReady(true);
      now = DateTime(2026, 8, 4, 10, 5, 0); // +5 min
      await tracker.detach();

      final days = await database.watchAllDayStats().first;
      expect(days, hasLength(1));
      expect(days.single.day, '2026-08-04');
      expect(days.single.activeSeconds, 5 * 60);
      expect(await database.itemReadingSeconds('x'), 5 * 60);
    });

    test('ReadingTimeTracker does not count while disabled (TTS)', () async {
      await insertItem('x', kind: ReaderKind.book);
      var now = DateTime(2026, 8, 4, 12, 0, 0);
      final tracker = ReadingTimeTracker(
        database: database,
        itemId: 'x',
        kind: ReaderKind.book,
        flushInterval: const Duration(hours: 1),
        clock: () => now,
      );
      tracker.attach();
      tracker.setContentReady(true);
      now = DateTime(2026, 8, 4, 12, 2, 0); // +2 min counted
      tracker.setCountingEnabled(false); // TTS on — flush 2 min, stop
      now = DateTime(2026, 8, 4, 12, 20, 0); // +18 min ignored
      tracker.setCountingEnabled(true);
      now = DateTime(2026, 8, 4, 12, 21, 0); // +1 min
      await tracker.detach();

      expect(await database.itemReadingSeconds('x'), 3 * 60);
    });

    test('clearReadingTimeData keeps books and progress', () async {
      await insertItem('keep', kind: ReaderKind.comic);
      await database.upsertProgress(
        itemId: 'keep',
        locatorJson: const ComicLocator(pageIndex: 2).encode(),
        progressFraction: 0.3,
        updatedAt: DateTime(2026, 8, 1),
      );
      await database.addReadingSeconds(
        dayKey: '2026-08-01',
        itemId: 'keep',
        kind: ReaderKind.comic,
        seconds: 90,
      );

      await database.clearReadingTimeData();

      final item = await database.readingItemById('keep');
      expect(item, isNotNull);
      expect(item!.title, 'keep');
      final progress = await database.progressFor('keep');
      expect(progress, isNotNull);
      expect(progress!.progressFraction, closeTo(0.3, 1e-9));
      expect(await database.itemReadingSeconds('keep'), 0);
      expect(await database.watchAllDayStats().first, isEmpty);
    });

    test('ReadingTimeTracker splits seconds across local midnight', () async {
      await insertItem('night', kind: ReaderKind.book);
      // 23:50 → 00:10 next day = 10 min + 10 min.
      var now = DateTime(2026, 8, 4, 23, 50, 0);
      final tracker = ReadingTimeTracker(
        database: database,
        itemId: 'night',
        kind: ReaderKind.book,
        flushInterval: const Duration(hours: 2),
        clock: () => now,
      );
      tracker.attach();
      tracker.setContentReady(true);
      now = DateTime(2026, 8, 5, 0, 10, 0);
      await tracker.detach();

      final days = await database.watchAllDayStats().first;
      expect(days, hasLength(2));
      final d1 = days.firstWhere((d) => d.day == '2026-08-04');
      final d2 = days.firstWhere((d) => d.day == '2026-08-05');
      expect(d1.activeSeconds, 10 * 60);
      expect(d2.activeSeconds, 10 * 60);
      expect(await database.itemReadingSeconds('night'), 20 * 60);
    });

    test('ReadingTimeTracker stops on background lifecycle', () async {
      await insertItem('bg', kind: ReaderKind.comic);
      var now = DateTime(2026, 8, 4, 9, 0, 0);
      final tracker = ReadingTimeTracker(
        database: database,
        itemId: 'bg',
        kind: ReaderKind.comic,
        flushInterval: const Duration(hours: 1),
        clock: () => now,
      );
      tracker.attach();
      tracker.setContentReady(true);
      now = DateTime(2026, 8, 4, 9, 3, 0); // +3 min foreground
      tracker.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = DateTime(2026, 8, 4, 9, 30, 0); // +27 min background ignored
      tracker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = DateTime(2026, 8, 4, 9, 32, 0); // +2 min
      await tracker.detach();

      expect(await database.itemReadingSeconds('bg'), 5 * 60);
    });

    test(
      'ReadingTimeTracker waits for content and pauses behind a route',
      () async {
        await insertItem('visible', kind: ReaderKind.book);
        var now = DateTime(2026, 8, 4, 9);
        final tracker = ReadingTimeTracker(
          database: database,
          itemId: 'visible',
          kind: ReaderKind.book,
          flushInterval: const Duration(hours: 1),
          clock: () => now,
        );
        tracker.attach();
        now = DateTime(2026, 8, 4, 9, 5); // loading: ignored
        tracker.setContentReady(true);
        now = DateTime(2026, 8, 4, 9, 8); // visible: +3m
        tracker.setRouteVisible(false);
        now = DateTime(2026, 8, 4, 9, 20); // covered: ignored
        tracker.setRouteVisible(true);
        now = DateTime(2026, 8, 4, 9, 22); // visible: +2m
        await tracker.detach();

        expect(await database.itemReadingSeconds('visible'), 5 * 60);
        final days = await database.watchAllDayStats().first;
        expect(days.single.sessionsCount, 1);
      },
    );
  });

  group('ReadingStatsController', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('rebuilds snapshot from library + day streams', () async {
      final now = DateTime(2026, 8, 4, 15);
      await database.upsertReadingItem(
        ReadingItemsCompanion.insert(
          id: 'c1',
          kind: ReaderKind.comic.storageValue,
          format: ReaderFormat.cbz.storageValue,
          title: 'Comic One',
          filePath: '/tmp/c1.cbz',
          contentHash: 'hash-c1',
          pageCount: const Value(12),
          pageOrderVersion: Value(ComicPageOrder.version),
          addedAt: now,
          updatedAt: now,
          lastOpenedAt: Value(now),
        ),
      );
      await database.upsertProgress(
        itemId: 'c1',
        locatorJson: const ComicLocator(pageIndex: 3).encode(),
        progressFraction: 0.25,
        updatedAt: now,
      );
      await database.addReadingSeconds(
        dayKey: AppDatabase.localDayKey(now),
        itemId: 'c1',
        kind: ReaderKind.comic,
        seconds: 180,
      );

      final controller = ReadingStatsController(
        database: database,
        clock: () => DateTime(2026, 8, 4, 15),
      );
      addTearDown(controller.dispose);

      // Wait for first library + day stream emissions.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (var i = 0; i < 20 && !controller.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(controller.isReady, isTrue);
      expect(controller.snapshot.totalCount, 1);
      expect(controller.snapshot.readingCount, 1);
      expect(controller.snapshot.periodActiveSeconds, 180);

      controller.setPeriod(StatsPeriod.month);
      expect(controller.period, StatsPeriod.month);
      expect(controller.snapshot.periodActiveSeconds, 180);

      await controller.clearReadingTime();
      expect(controller.snapshot.periodActiveSeconds, 0);
      // Book remains.
      expect(controller.snapshot.totalCount, 1);
    });
  });

  group('stats wiring source contracts', () {
    test('shell and settings expose 统计; readers attach tracker', () {
      final shell = File('lib/presentation/app_shell.dart').readAsStringSync();
      expect(shell, contains("label: '统计'"));
      expect(shell, contains('_openReadingStats'));
      expect(shell, contains('ReadingStatsScreen'));
      expect(shell, contains('readingStatsActive'));
      expect(shell, contains('_readingStatsOpen'));
      // Still three root destinations only.
      expect(shell, contains("label: '书架'"));
      expect(shell, contains("label: '书库'"));
      expect(shell, contains("label: '设置'"));
      // Stats is not a bottom destination entry.
      final destinationsBlock = RegExp(
        r'static const _destinations = \[([\s\S]*?)\];',
      ).firstMatch(shell)!.group(1)!;
      expect(destinationsBlock, isNot(contains('统计')));
      expect(destinationsBlock, isNot(contains('stats')));

      final settings = File(
        'lib/presentation/screens/settings_screen.dart',
      ).readAsStringSync();
      expect(settings, contains("label: '阅读统计'"));
      expect(settings, contains('ReadingStatsScreen.open'));
      expect(settings, contains('comicReadingPreferences'));
      expect(settings, contains('bookReadingPreferences'));
      final shellOpen = File(
        'lib/presentation/app_shell.dart',
      ).readAsStringSync();
      expect(
        shellOpen,
        contains('comicReadingPreferences: widget.readingPreferences'),
      );
      expect(
        shellOpen,
        contains('bookReadingPreferences: widget.bookReadingPreferences'),
      );

      final comic = File(
        'lib/presentation/screens/comic_reader_screen.dart',
      ).readAsStringSync();
      expect(comic, contains('ReadingTimeTracker'));
      expect(comic, contains('ReaderKind.comic'));

      final book = File(
        'lib/presentation/screens/book_reader_screen.dart',
      ).readAsStringSync();
      expect(book, contains('ReadingTimeTracker'));
      expect(book, contains('setCountingEnabled'));
      expect(book, contains('ttsPlaying'));

      final db = File(
        'lib/library/persistence/app_database.dart',
      ).readAsStringSync();
      expect(db, contains('class ReadingDayStats'));
      expect(db, contains('class ReadingItemTime'));
      expect(db, contains('schemaVersion => 6'));
      expect(db, contains('from < 6'));

      final detail = File(
        'lib/presentation/screens/item_detail_sheet.dart',
      ).readAsStringSync();
      expect(detail, contains('itemReadingSeconds'));
      expect(detail, contains('累计阅读'));

      final exporter = File(
        'lib/library/backup/backup_exporter.dart',
      ).readAsStringSync();
      expect(exporter, contains('dayStats'));
      expect(exporter, contains('itemTime'));
      expect(exporter, contains('readingDayStats'));
    });
  });

  group('BackupRecords duration fields', () {
    test('round-trips dayStats and itemTime; older payloads omit them', () {
      final full = BackupRecords(
        items: const [],
        progress: const [],
        bookmarks: const [],
        annotations: const [],
        readingLists: const [],
        readingListMembers: const [],
        collections: const [],
        collectionMembers: const [],
        dayStats: const [
          {
            'day': '2026-08-01',
            'activeSeconds': 90,
            'comicSeconds': 90,
            'bookSeconds': 0,
            'sessionsCount': 1,
          },
        ],
        itemTime: const [
          {
            'contentHash': 'abc',
            'activeSeconds': 90,
            'updatedAt': '2026-08-01T00:00:00.000Z',
          },
        ],
      );
      final decoded = BackupRecords.fromJson(
        // ignore: inference_failure_on_collection_literal
        {...full.toJson()},
      );
      expect(decoded, isNotNull);
      expect(decoded!.dayStats, hasLength(1));
      expect(decoded.dayStats.single['activeSeconds'], 90);
      expect(decoded.itemTime, hasLength(1));

      // Pre-duration snapshot: no dayStats/itemTime keys.
      final legacy = BackupRecords.fromJson({
        'format': KaijuanBackupFormat.id,
        'version': KaijuanBackupFormat.version,
        'items': <Object?>[],
        'progress': <Object?>[],
        'bookmarks': <Object?>[],
        'annotations': <Object?>[],
        'readingLists': <Object?>[],
        'readingListMembers': <Object?>[],
        'collections': <Object?>[],
        'collectionMembers': <Object?>[],
      });
      expect(legacy, isNotNull);
      expect(legacy!.dayStats, isEmpty);
      expect(legacy.itemTime, isEmpty);
    });
  });

  group('ReadingDayCounters', () {
    test('normalizes invalid breakdown and chooses one coherent row', () {
      final local = ReadingDayCounters.normalized(
        activeSeconds: 100,
        comicSeconds: 100,
        bookSeconds: 0,
        sessionsCount: 1,
      );
      final remote = ReadingDayCounters.normalized(
        activeSeconds: 120,
        comicSeconds: 0,
        bookSeconds: 120,
        sessionsCount: 2,
      );
      final chosen = ReadingDayCounters.chooseLarger(local, remote);
      expect(chosen.activeSeconds, 120);
      expect(chosen.comicSeconds, 0);
      expect(chosen.bookSeconds, 120);
      expect(chosen.activeSeconds, chosen.comicSeconds + chosen.bookSeconds);

      final corrupt = ReadingDayCounters.normalized(
        activeSeconds: 20,
        comicSeconds: 30,
        bookSeconds: 40,
        sessionsCount: -1,
      );
      expect(corrupt.activeSeconds, 70);
      expect(corrupt.sessionsCount, 0);

      final bounded = ReadingDayCounters.normalized(
        activeSeconds: 0x7FFFFFFFFFFFFFFF,
        comicSeconds: 0x7FFFFFFFFFFFFFFF,
        bookSeconds: 0x7FFFFFFFFFFFFFFF,
        sessionsCount: 0x7FFFFFFFFFFFFFFF,
      );
      expect(bounded.activeSeconds, 0x3FFFFFFFFFFFFFFF);
      expect(bounded.comicSeconds, 0x3FFFFFFFFFFFFFFF);
      expect(bounded.bookSeconds, 0);
      expect(bounded.comicSeconds + bounded.bookSeconds, bounded.activeSeconds);
      expect(isValidReadingDayKey('2026-02-29'), isFalse);
      expect(isValidReadingDayKey('2028-02-29'), isTrue);
    });
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/app/book_reading_preferences.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/book_reader_controller.dart';
import 'package:kaijuan/readers/book/book_models.dart';
import 'package:kaijuan/readers/book/book_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaika_book_ctrl_');
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ReadingItem> insertBook({
    required String id,
    String title = 'Test Book',
  }) async {
    final now = DateTime.utc(2026, 1, 1);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: id,
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: title,
        filePath: '/tmp/$id.epub',
        contentHash: 'hash-$id',
        pageCount: const Value(3),
        addedAt: now,
        updatedAt: now,
      ),
    );
    return database.readingItemById(id).then((r) => r!);
  }

  const sectionMap = BookSectionMap(
    startIndices: [0, 10, 25],
    totalParagraphs: 40,
  );
  const tocTitles = ['Chapter 1', 'Chapter 2', 'Chapter 3'];

  group('defaults', () {
    test('without prefs', () async {
      final item = await insertBook(id: 'defaults');
      final controller = BookReaderController(database: database, item: item);

      expect(controller.fontSize, 18.0);
      expect(controller.lineHeight, 1.6);
      expect(controller.readingTheme, BookReadingTheme.paper);
      expect(controller.margin, 24.0);
      expect(controller.readingMode, BookReadingMode.page);
      expect(controller.isReady, isFalse);
      expect(controller.chromeVisible, isFalse);

      controller.dispose();
    });

    test('with prefs', () async {
      final prefs = await BookReadingPreferences.load(
        supportDirectory: tempDir,
      );
      await prefs.setFontSize(22);
      await prefs.setLineHeight(1.8);
      await prefs.setReadingTheme(BookReadingTheme.sepia);
      await prefs.setMargin(32);
      await prefs.setReadingMode(BookReadingMode.page);

      final item = await insertBook(id: 'with-prefs');
      final controller = BookReaderController(
        database: database,
        item: item,
        readingPreferences: prefs,
      );

      expect(controller.fontSize, 22.0);
      expect(controller.lineHeight, 1.8);
      expect(controller.readingTheme, BookReadingTheme.sepia);
      expect(controller.margin, 32.0);
      expect(controller.readingMode, BookReadingMode.page);

      controller.dispose();
    });
  });

  test('attachEngine makes controller ready and exposes metadata', () async {
    final item = await insertBook(id: 'attach');
    final controller = BookReaderController(database: database, item: item);

    final attaching = controller.attachEngine(sectionMap, tocTitles);
    expect(controller.isReady, isFalse);
    await attaching;

    expect(controller.isReady, isTrue);
    expect(controller.sectionCount, 3);
    expect(controller.tocTitles, tocTitles);
    expect(controller.sectionLabel, '1 / 3');

    controller.dispose();
  });

  test('desktop capability rejects scroll mode', () async {
    final item = await insertBook(id: 'page-only');
    final controller = BookReaderController(
      database: database,
      item: item,
      scrollModeEnabled: false,
    );

    await controller.setReadingMode(BookReadingMode.scroll);

    expect(controller.readingMode, BookReadingMode.page);
    expect(controller.scrollModeEnabled, isFalse);
    controller.dispose();
  });

  test('font size and line height clamp', () async {
    final item = await insertBook(id: 'clamp');
    final controller = BookReaderController(database: database, item: item);

    await controller.setFontSize(5);
    expect(controller.fontSize, 14.0);

    await controller.setFontSize(50);
    expect(controller.fontSize, 28.0);

    await controller.setLineHeight(0.5);
    expect(controller.lineHeight, 1.2);

    await controller.setLineHeight(5);
    expect(controller.lineHeight, 2.2);

    controller.dispose();
  });

  test('pureBlack theme is preserved', () async {
    final item = await insertBook(id: 'pure-black');
    final controller = BookReaderController(database: database, item: item);

    await controller.setReadingTheme(BookReadingTheme.pureBlack);
    expect(controller.readingTheme, BookReadingTheme.pureBlack);

    controller.dispose();
  });

  group('progress', () {
    test('restores BookLocator from DB', () async {
      final item = await insertBook(id: 'restore');
      await database.upsertProgress(
        itemId: item.id,
        locatorJson: const BookLocator(
          sectionIndex: 1,
          progressInSection: 0.5,
        ).encode(),
        progressFraction: 0.5,
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);

      // Restore is async; wait for it.
      await pumpEventQueue();

      expect(controller.sectionIndex, 1);
      expect(controller.progressInSection, closeTo(0.5, 1e-9));
      final jump = controller.pendingJump;
      expect(jump, isNotNull);
      expect(jump!.sectionIndex, 1);
      expect(jump.progressInSection, closeTo(0.5, 1e-9));
      controller.clearPendingJump();
      expect(controller.pendingJump, isNull);

      controller.dispose();
    });

    test('migrates legacy katbook paragraph JSON', () async {
      final legacyItem = await insertBook(id: 'legacy');
      await database.upsertProgress(
        itemId: legacyItem.id,
        locatorJson: '{"paragraphIndex": 12, "totalParagraphs": 40}',
        progressFraction: 0.3,
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final legacyController = BookReaderController(
        database: database,
        item: legacyItem,
      );
      await legacyController.attachEngine(sectionMap, tocTitles);
      await pumpEventQueue();

      expect(legacyController.sectionIndex, 1);
      expect(legacyController.progressInSection, closeTo(2 / 15, 1e-9));

      legacyController.dispose();
    });

    test('rendition CFI location persists', () async {
      final item = await insertBook(id: 'persist');
      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);
      await pumpEventQueue();

      controller.reportRenditionLocation(
        sectionIndex: 1,
        progress: 0.49,
        cfi: 'epubcfi(/6/4!/4/2)',
      );
      expect(controller.sectionIndex, 1);
      expect(controller.currentLocator.cfi, 'epubcfi(/6/4!/4/2)');

      // Wait for the 500 ms debounce.
      await Future.delayed(const Duration(milliseconds: 600));

      final progress = await database.progressFor(item.id);
      expect(progress, isNotNull);
      final locator = BookLocator.tryDecode(progress!.locatorJson);
      expect(locator, isNotNull);
      expect(locator!.sectionIndex, 1);
      expect(locator.cfi, 'epubcfi(/6/4!/4/2)');

      controller.dispose();
    });
  });

  group('navigation', () {
    test('goToSection and prev/next clamp at bounds', () async {
      final item = await insertBook(id: 'nav');
      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);

      controller.goToSection(2);
      expect(controller.sectionIndex, 2);
      expect(controller.progressInSection, 0.0);
      expect(controller.pendingJump, isNotNull);
      controller.clearPendingJump();
      expect(controller.pendingJump, isNull);

      controller.goNextSection();
      expect(controller.sectionIndex, 2); // clamped

      controller.goPreviousSection();
      expect(controller.sectionIndex, 1);

      controller.goToSection(-1);
      expect(controller.sectionIndex, 0);

      controller.dispose();
    });

    test(
      'setReadingMode keeps a semantic locator for Foliate reflow',
      () async {
        final item = await insertBook(id: 'scroll-handoff');
        final controller = BookReaderController(database: database, item: item);
        await controller.attachEngine(sectionMap, tocTitles);
        controller.goToSection(2, progressInSection: 0.42);

        await controller.setReadingMode(BookReadingMode.scroll);

        expect(controller.readingMode, BookReadingMode.scroll);
        expect(controller.pendingJump?.sectionIndex, 2);
        expect(controller.pendingJump?.progressInSection, closeTo(0.42, 0.001));

        controller.dispose();
      },
    );

    test('page actions delegate only to the active rendition', () async {
      final item = await insertBook(id: 'rendition-navigation');
      final controller = BookReaderController(database: database, item: item);
      var nextCount = 0;
      var previousCount = 0;

      expect(controller.hasPageMode, isFalse);
      controller.attachExternalPageNavigation(
        nextPage: () => nextCount++,
        previousPage: () => previousCount++,
      );
      expect(controller.hasPageMode, isTrue);

      controller.goNextPage();
      controller.goPreviousPage();
      expect(nextCount, 1);
      expect(previousCount, 1);

      controller.detachExternalPageNavigation();
      expect(controller.hasPageMode, isFalse);
      controller.dispose();
    });
  });

  test('bookmarks sort by locator, toggle, and jump', () async {
    final item = await insertBook(id: 'bookmark-controller');
    final controller = BookReaderController(database: database, item: item);
    await controller.attachEngine(sectionMap, tocTitles);
    await pumpEventQueue();

    await database.addBookmark(
      itemId: item.id,
      locatorJson: const BookLocator(
        sectionIndex: 2,
        progressInSection: 0.5,
      ).encode(),
    );
    await database.addBookmark(
      itemId: item.id,
      locatorJson: const BookLocator(
        sectionIndex: 0,
        progressInSection: 0.25,
      ).encode(),
    );
    await pumpEventQueue();

    expect(controller.bookmarks, hasLength(2));
    expect(
      controller.bookmarkLabel(controller.bookmarks.first),
      'Chapter 1 · 25%',
    );

    controller.goToBookmark(controller.bookmarks.first);
    expect(controller.sectionIndex, 0);
    expect(controller.progressInSection, closeTo(0.25, 1e-9));
    expect(controller.isCurrentPositionBookmarked, isTrue);

    await controller.toggleBookmark();
    await pumpEventQueue();
    expect(controller.bookmarks, hasLength(1));
    expect(controller.isCurrentPositionBookmarked, isFalse);

    await controller.toggleBookmark();
    await pumpEventQueue();
    expect(controller.bookmarks, hasLength(2));
    expect(controller.isCurrentPositionBookmarked, isTrue);

    controller.dispose();
  });

  test('preferences are persisted through controller setters', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    final item = await insertBook(id: 'prefs-persist');
    final controller = BookReaderController(
      database: database,
      item: item,
      readingPreferences: prefs,
    );

    await controller.setFontSize(20);
    await controller.setLineHeight(1.8);
    await controller.setReadingTheme(BookReadingTheme.dark);
    await controller.setMargin(40);
    await controller.setReadingMode(BookReadingMode.page);
    await controller.setPageTurnEffect(BookPageTurnEffect.none);

    final reloaded = await BookReadingPreferences.load(
      supportDirectory: tempDir,
    );
    expect(reloaded.fontSize, 20.0);
    expect(reloaded.lineHeight, 1.8);
    expect(reloaded.readingTheme, BookReadingTheme.dark);
    expect(reloaded.margin, 40.0);
    expect(reloaded.readingMode, BookReadingMode.page);
    expect(reloaded.pageTurnEffect, BookPageTurnEffect.none);

    controller.dispose();
  });
}

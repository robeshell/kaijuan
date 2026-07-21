import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/app/book_reading_preferences.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/persistence/app_database.dart';
import 'package:kaika/presentation/controllers/book_reader_controller.dart';
import 'package:kaika/readers/book/book_models.dart';
import 'package:kaika/readers/book/book_theme.dart';

void main() {
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
      final controller = BookReaderController(
        database: database,
        item: item,
      );

      expect(controller.fontSize, 18.0);
      expect(controller.lineHeight, 1.6);
      expect(controller.readingTheme, BookReadingTheme.paper);
      expect(controller.margin, 24.0);
      expect(controller.readingMode, BookReadingMode.page);
      expect(controller.isReady, isFalse);

      controller.dispose();
    });

    test('with prefs', () async {
      final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
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
    final controller = BookReaderController(
      database: database,
      item: item,
    );

    controller.attachEngine(sectionMap, tocTitles);

    expect(controller.isReady, isTrue);
    expect(controller.sectionCount, 3);
    expect(controller.tocTitles, tocTitles);
    expect(controller.sectionLabel, '1 / 3');

    controller.dispose();
  });

  test('font size and line height clamp', () async {
    final item = await insertBook(id: 'clamp');
    final controller = BookReaderController(
      database: database,
      item: item,
    );

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
    final controller = BookReaderController(
      database: database,
      item: item,
    );

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

      final controller = BookReaderController(
        database: database,
        item: item,
      );
      controller.attachEngine(sectionMap, tocTitles);

      // Restore is async; wait for it.
      await pumpEventQueue();

      expect(controller.sectionIndex, 1);
      expect(controller.progressInSection, closeTo(0.5, 1e-9));
      expect(
        controller.consumePendingJump(),
        sectionMap.paragraphFromLocator(
          const BookLocator(sectionIndex: 1, progressInSection: 0.5),
        ),
      );
      expect(controller.consumePendingJump(), isNull);

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
      legacyController.attachEngine(sectionMap, tocTitles);
      await pumpEventQueue();

      expect(legacyController.sectionIndex, 1);
      expect(legacyController.progressInSection, closeTo(2 / 15, 1e-9));

      legacyController.dispose();
    });

    test('reportPosition maps to BookLocator and persists', () async {
      final item = await insertBook(id: 'persist');
      final controller = BookReaderController(
        database: database,
        item: item,
      );
      controller.attachEngine(sectionMap, tocTitles);
      await pumpEventQueue();

      controller.reportPosition(17, 0);
      expect(controller.sectionIndex, 1);
      expect(controller.progressInSection, closeTo(7 / 15, 1e-9));

      // Wait for the 500 ms debounce.
      await Future.delayed(const Duration(milliseconds: 600));

      final progress = await database.progressFor(item.id);
      expect(progress, isNotNull);
      final locator = BookLocator.tryDecode(progress!.locatorJson);
      expect(locator, isNotNull);
      expect(locator!.sectionIndex, 1);
      expect(locator.progressInSection, closeTo(7 / 15, 1e-9));

      controller.dispose();
    });
  });

  group('navigation', () {
    test('goToSection and prev/next clamp at bounds', () async {
      final item = await insertBook(id: 'nav');
      final controller = BookReaderController(
        database: database,
        item: item,
      );
      controller.attachEngine(sectionMap, tocTitles);

      controller.goToSection(2);
      expect(controller.sectionIndex, 2);
      expect(controller.progressInSection, 0.0);
      expect(controller.consumePendingJump(), isNotNull);
      expect(controller.consumePendingJump(), isNull);

      controller.goNextSection();
      expect(controller.sectionIndex, 2); // clamped

      controller.goPreviousSection();
      expect(controller.sectionIndex, 1);

      controller.goToSection(-1);
      expect(controller.sectionIndex, 0);

      controller.dispose();
    });
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

    final reloaded =
        await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(reloaded.fontSize, 20.0);
    expect(reloaded.lineHeight, 1.8);
    expect(reloaded.readingTheme, BookReadingTheme.dark);
    expect(reloaded.margin, 40.0);
    expect(reloaded.readingMode, BookReadingMode.page);

    controller.dispose();
  });
}

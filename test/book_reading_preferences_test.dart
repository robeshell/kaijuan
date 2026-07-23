import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/app/book_reading_preferences.dart';
import 'package:kaijuan/readers/book/book_theme.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaika_book_prefs_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('defaults when file is missing', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.fontSize, 18.0);
    expect(prefs.lineHeight, 1.7);
    expect(prefs.readingTheme, BookReadingTheme.paper);
    expect(prefs.margin, 24.0);
    expect(prefs.verticalMargin, 26.0);
    expect(prefs.bold, isFalse);
    expect(prefs.brightness, 1.0);
    expect(
      prefs.fontSelection,
      BookFontSelection.system(BookSystemFont.defaultId),
    );
    expect(prefs.letterSpacing, 0.0);
    expect(prefs.paragraphSpacing, 0.35);
    expect(prefs.textAlign, BookTextAlign.justify);
    expect(prefs.firstLineIndent, isTrue);
    expect(prefs.hyphenate, isFalse);
    expect(prefs.readingMode, BookReadingMode.page);
    expect(prefs.pageTurnEffect, BookPageTurnEffect.slide);
  });

  test('persists all fields', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    await prefs.setFontSize(22);
    await prefs.setLineHeight(1.8);
    await prefs.setReadingTheme(BookReadingTheme.sepia);
    await prefs.setMargin(32);
    await prefs.setVerticalMargin(12);
    await prefs.setBold(true);
    await prefs.setBrightness(0.6);
    await prefs.setFontSelection(
      BookFontSelection.system(BookSystemFont.songtiId),
    );
    await prefs.setLetterSpacing(-0.1);
    await prefs.setParagraphSpacing(0.7);
    await prefs.setTextAlign(BookTextAlign.start);
    await prefs.setFirstLineIndent(false);
    await prefs.setHyphenate(true);
    await prefs.setReadingMode(BookReadingMode.page);
    await prefs.setPageTurnEffect(BookPageTurnEffect.none);

    final reloaded = await BookReadingPreferences.load(
      supportDirectory: tempDir,
    );
    expect(reloaded.fontSize, 22.0);
    expect(reloaded.lineHeight, 1.8);
    expect(reloaded.readingTheme, BookReadingTheme.sepia);
    expect(reloaded.margin, 32.0);
    expect(reloaded.verticalMargin, 12.0);
    expect(reloaded.bold, isTrue);
    expect(reloaded.brightness, 0.6);
    expect(
      reloaded.fontSelection,
      BookFontSelection.system(BookSystemFont.songtiId),
    );
    expect(reloaded.letterSpacing, -0.1);
    expect(reloaded.paragraphSpacing, 0.7);
    expect(reloaded.textAlign, BookTextAlign.start);
    expect(reloaded.firstLineIndent, isFalse);
    expect(reloaded.hyphenate, isTrue);
    expect(reloaded.readingMode, BookReadingMode.page);
    expect(reloaded.pageTurnEffect, BookPageTurnEffect.none);
  });

  test('clamps out-of-range values', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    await prefs.setFontSize(5);
    expect(prefs.fontSize, 14.0);
    await prefs.setLineHeight(0.5);
    expect(prefs.lineHeight, 1.2);
    await prefs.setMargin(100);
    expect(prefs.margin, 48.0);
    await prefs.setVerticalMargin(100);
    expect(prefs.verticalMargin, 48.0);
    await prefs.setLetterSpacing(-5);
    expect(prefs.letterSpacing, -1.0);
    await prefs.setParagraphSpacing(9);
    expect(prefs.paragraphSpacing, 2.0);
  });

  test('migrates old ComicReadingTheme storage strings', () async {
    final file = File('${tempDir.path}/book_reading.json');
    await file.writeAsString(
      '{"fontSize":20,"lineHeight":1.7,"readingTheme":"dark"}',
      flush: true,
    );

    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.readingTheme, BookReadingTheme.dark);
    expect(prefs.margin, 24.0);
    expect(prefs.verticalMargin, 26.0);
    expect(prefs.bold, isFalse);
    expect(
      prefs.fontSelection,
      BookFontSelection.system(BookSystemFont.defaultId),
    );
    expect(prefs.readingMode, BookReadingMode.page);
    expect(prefs.pageTurnEffect, BookPageTurnEffect.slide);
  });

  test('migrates legacy bodyFont string', () async {
    final file = File('${tempDir.path}/book_reading.json');
    await file.writeAsString(
      '{"bodyFont":"georgia","fontSize":18}',
      flush: true,
    );
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(
      prefs.fontSelection,
      BookFontSelection.system(BookSystemFont.songtiId),
    );
  });

  test('curl resolves to slide until curl renderer ships', () {
    expect(BookPageTurnEffect.curl.resolved, BookPageTurnEffect.slide);
    expect(BookPageTurnEffect.slide.resolved, BookPageTurnEffect.slide);
    expect(BookPageTurnEffect.none.resolved, BookPageTurnEffect.none);
  });

  test('corrupted file falls back to defaults', () async {
    final file = File('${tempDir.path}/book_reading.json');
    await file.writeAsString('not-json', flush: true);

    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.fontSize, 18.0);
    expect(prefs.readingTheme, BookReadingTheme.paper);
  });
}

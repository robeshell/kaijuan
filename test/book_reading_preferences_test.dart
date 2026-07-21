import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/app/book_reading_preferences.dart';
import 'package:kaika/readers/book/book_theme.dart';

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
    expect(prefs.lineHeight, 1.6);
    expect(prefs.readingTheme, BookReadingTheme.paper);
    expect(prefs.margin, 24.0);
    expect(prefs.readingMode, BookReadingMode.page);
  });

  test('persists all fields', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    await prefs.setFontSize(22);
    await prefs.setLineHeight(1.8);
    await prefs.setReadingTheme(BookReadingTheme.sepia);
    await prefs.setMargin(32);
    await prefs.setReadingMode(BookReadingMode.page);

    final reloaded =
        await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(reloaded.fontSize, 22.0);
    expect(reloaded.lineHeight, 1.8);
    expect(reloaded.readingTheme, BookReadingTheme.sepia);
    expect(reloaded.margin, 32.0);
    expect(reloaded.readingMode, BookReadingMode.page);
  });

  test('clamps out-of-range values', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    await prefs.setFontSize(5);
    expect(prefs.fontSize, 14.0);
    await prefs.setLineHeight(0.5);
    expect(prefs.lineHeight, 1.2);
    await prefs.setMargin(100);
    expect(prefs.margin, 48.0);
  });

  test('migrates old ComicReadingTheme storage strings', () async {
    final file = File('${tempDir.path}/book_reading.json');
    await file.writeAsString(
      '{"fontSize":20,"lineHeight":1.7,"readingTheme":"dark"}',
      flush: true,
    );

    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.readingTheme, BookReadingTheme.dark);
    expect(prefs.margin, 24.0); // default
    expect(prefs.readingMode, BookReadingMode.page); // default
  });

  test('corrupted file falls back to defaults', () async {
    final file = File('${tempDir.path}/book_reading.json');
    await file.writeAsString('not-json', flush: true);

    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.fontSize, 18.0);
    expect(prefs.readingTheme, BookReadingTheme.paper);
  });
}

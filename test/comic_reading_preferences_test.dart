import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/app/comic_reading_preferences.dart';
import 'package:kaika/readers/comic/comic_models.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaika_prefs_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('defaults when file is missing', () async {
    final prefs = await ComicReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.mode, ComicReaderMode.slide);
    expect(prefs.direction, ComicReadDirection.ltr);
    expect(prefs.readingTheme, ComicReadingTheme.comicDefault);
  });

  test('persists mode direction and reading theme', () async {
    final prefs = await ComicReadingPreferences.load(supportDirectory: tempDir);
    await prefs.setMode(ComicReaderMode.vertical);
    await prefs.setDirection(ComicReadDirection.rtl);
    await prefs.setReadingTheme(ComicReadingTheme.paper);

    final reloaded =
        await ComicReadingPreferences.load(supportDirectory: tempDir);
    expect(reloaded.mode, ComicReaderMode.vertical);
    expect(reloaded.direction, ComicReadDirection.rtl);
    expect(reloaded.readingTheme, ComicReadingTheme.paper);
  });

  test('corrupted file falls back to defaults', () async {
    final file = File('${tempDir.path}/comic_reading.json');
    await file.writeAsString('not-json', flush: true);

    final prefs = await ComicReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.mode, ComicReaderMode.slide);
    expect(prefs.readingTheme, ComicReadingTheme.comicDefault);
  });
}

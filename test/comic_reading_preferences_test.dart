import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/app/comic_reading_preferences.dart';
import 'package:kaijuan/readers/comic/comic_models.dart';

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
    expect(prefs.brightness, ComicReadingPreferences.defaultBrightness);
  });

  test('persists mode direction reading theme and brightness', () async {
    final prefs = await ComicReadingPreferences.load(supportDirectory: tempDir);
    await prefs.setMode(ComicReaderMode.vertical);
    await prefs.setDirection(ComicReadDirection.rtl);
    await prefs.setReadingTheme(ComicReadingTheme.paper);
    await prefs.setBrightness(0.4);

    final reloaded =
        await ComicReadingPreferences.load(supportDirectory: tempDir);
    expect(reloaded.mode, ComicReaderMode.vertical);
    expect(reloaded.direction, ComicReadDirection.rtl);
    expect(reloaded.readingTheme, ComicReadingTheme.paper);
    expect(reloaded.brightness, 0.4);
  });

  test('corrupted file falls back to defaults', () async {
    final file = File('${tempDir.path}/comic_reading.json');
    await file.writeAsString('not-json', flush: true);

    final prefs = await ComicReadingPreferences.load(supportDirectory: tempDir);
    expect(prefs.mode, ComicReaderMode.slide);
    expect(prefs.readingTheme, ComicReadingTheme.comicDefault);
  });
}

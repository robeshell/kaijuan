import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../readers/comic/comic_models.dart';

/// Global comic reader defaults (mode / direction / content theme).
/// Persisted as JSON in app support, same pattern as [ThemePreferences].
class ComicReadingPreferences extends ChangeNotifier {
  ComicReadingPreferences._(
    this._file,
    this._mode,
    this._direction,
    this._readingTheme,
  );

  final File _file;
  ComicReaderMode _mode;
  ComicReadDirection _direction;
  ComicReadingTheme _readingTheme;

  ComicReaderMode get mode => _mode;
  ComicReadDirection get direction => _direction;
  ComicReadingTheme get readingTheme => _readingTheme;

  static Future<ComicReadingPreferences> load({
    Directory? supportDirectory,
    ComicReadingTheme? defaultReadingTheme,
  }) async {
    final dir = supportDirectory ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'comic_reading.json'));
    final fallbackTheme = defaultReadingTheme ?? ComicReadingTheme.comicDefault;
    try {
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return ComicReadingPreferences._(
          file,
          ComicReaderMode.fromStorage(json['mode'] as String?),
          ComicReadDirection.fromStorage(json['direction'] as String?),
          ComicReadingTheme.fromStorage(json['readingTheme'] as String?),
        );
      }
    } catch (_) {
      // Corrupted file — fall back to defaults.
    }
    return ComicReadingPreferences._(
      file,
      ComicReaderMode.slide,
      ComicReadDirection.ltr,
      fallbackTheme,
    );
  }

  Future<void> setMode(ComicReaderMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setDirection(ComicReadDirection direction) async {
    if (direction == _direction) return;
    _direction = direction;
    notifyListeners();
    await _save();
  }

  Future<void> setReadingTheme(ComicReadingTheme theme) async {
    if (theme == _readingTheme) return;
    _readingTheme = theme;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'mode': _mode.storageValue,
        'direction': _direction.storageValue,
        'readingTheme': _readingTheme.storageValue,
      }),
      flush: true,
    );
  }
}

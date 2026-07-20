import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../readers/comic/comic_models.dart';

/// Book reflow defaults (font size / line height / reading theme).
class BookReadingPreferences extends ChangeNotifier {
  BookReadingPreferences._(
    this._file,
    this._fontSize,
    this._lineHeight,
    this._readingTheme,
  );

  final File _file;
  double _fontSize;
  double _lineHeight;
  ComicReadingTheme _readingTheme;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  ComicReadingTheme get readingTheme => _readingTheme;

  static Future<BookReadingPreferences> load({
    Directory? supportDirectory,
    ComicReadingTheme? defaultReadingTheme,
  }) async {
    final dir = supportDirectory ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'book_reading.json'));
    final fallbackTheme = defaultReadingTheme ?? ComicReadingTheme.paper;
    try {
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return BookReadingPreferences._(
          file,
          (json['fontSize'] as num?)?.toDouble() ?? 18,
          (json['lineHeight'] as num?)?.toDouble() ?? 1.6,
          ComicReadingTheme.fromStorage(json['readingTheme'] as String?),
        );
      }
    } catch (_) {}
    return BookReadingPreferences._(file, 18, 1.6, fallbackTheme);
  }

  Future<void> setFontSize(double size) async {
    final next = size.clamp(14.0, 28.0);
    if (next == _fontSize) return;
    _fontSize = next;
    notifyListeners();
    await _save();
  }

  Future<void> setLineHeight(double height) async {
    final next = height.clamp(1.2, 2.2);
    if (next == _lineHeight) return;
    _lineHeight = next;
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
        'fontSize': _fontSize,
        'lineHeight': _lineHeight,
        'readingTheme': _readingTheme.storageValue,
      }),
      flush: true,
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../readers/book/book_theme.dart';

/// Book reflow reading mode.
enum BookReadingMode {
  scroll,
  page;

  static BookReadingMode fromStorage(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return page;
  }

  String get storageValue => name;

  String get label => switch (this) {
    scroll => '滚动',
    page => '翻页',
  };
}

/// Page-mode turn effect. [curl] is persisted / selectable but falls back to
/// [slide] until a real page-curl renderer ships.
enum BookPageTurnEffect {
  slide,
  none,
  curl;

  static BookPageTurnEffect fromStorage(String? value) {
    for (final effect in values) {
      if (effect.storageValue == value) return effect;
    }
    return slide;
  }

  String get storageValue => name;

  String get label => switch (this) {
    slide => '滑动',
    none => '无效果',
    curl => '仿真翻页',
  };

  /// Effect the engine should actually apply (curl → slide for now).
  BookPageTurnEffect get resolved => this == curl ? slide : this;
}

/// Book reflow defaults (font size / line height / reading theme / margin /
/// reading mode / page-turn effect).
class BookReadingPreferences extends ChangeNotifier {
  static const double defaultFontSize = 18.0;
  static const double minFontSize = 14.0;
  static const double maxFontSize = 28.0;

  static const double defaultLineHeight = 1.6;
  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 2.2;

  static const double defaultMargin = 24.0;
  static const double minMargin = 8.0;
  static const double maxMargin = 48.0;
  static const List<double> marginPresets = [8.0, 24.0, 48.0];

  static const BookReadingMode defaultReadingMode = BookReadingMode.page;
  static const BookPageTurnEffect defaultPageTurnEffect =
      BookPageTurnEffect.slide;

  BookReadingPreferences._(
    this._file,
    this._fontSize,
    this._lineHeight,
    this._readingTheme,
    this._margin,
    this._readingMode,
    this._pageTurnEffect,
  );

  final File _file;
  double _fontSize;
  double _lineHeight;
  BookReadingTheme _readingTheme;
  double _margin;
  BookReadingMode _readingMode;
  BookPageTurnEffect _pageTurnEffect;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  BookReadingTheme get readingTheme => _readingTheme;
  double get margin => _margin;
  BookReadingMode get readingMode => _readingMode;
  BookPageTurnEffect get pageTurnEffect => _pageTurnEffect;

  static Future<BookReadingPreferences> load({
    Directory? supportDirectory,
    BookReadingTheme? defaultReadingTheme,
  }) async {
    final dir = supportDirectory ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'book_reading.json'));
    final fallbackTheme = defaultReadingTheme ?? BookReadingTheme.paper;
    try {
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return BookReadingPreferences._(
          file,
          (json['fontSize'] as num?)?.toDouble() ?? defaultFontSize,
          (json['lineHeight'] as num?)?.toDouble() ?? defaultLineHeight,
          BookReadingTheme.fromStorage(json['readingTheme'] as String?),
          (json['margin'] as num?)?.toDouble() ?? defaultMargin,
          BookReadingMode.fromStorage(json['readingMode'] as String?),
          BookPageTurnEffect.fromStorage(json['pageTurnEffect'] as String?),
        );
      }
    } catch (_) {}
    return BookReadingPreferences._(
      file,
      defaultFontSize,
      defaultLineHeight,
      fallbackTheme,
      defaultMargin,
      defaultReadingMode,
      defaultPageTurnEffect,
    );
  }

  Future<void> setFontSize(double size) async {
    final next = size.clamp(minFontSize, maxFontSize);
    if (next == _fontSize) return;
    _fontSize = next;
    notifyListeners();
    await _save();
  }

  Future<void> setLineHeight(double height) async {
    final next = height.clamp(minLineHeight, maxLineHeight);
    if (next == _lineHeight) return;
    _lineHeight = next;
    notifyListeners();
    await _save();
  }

  Future<void> setReadingTheme(BookReadingTheme theme) async {
    if (theme == _readingTheme) return;
    _readingTheme = theme;
    notifyListeners();
    await _save();
  }

  Future<void> setMargin(double margin) async {
    final next = margin.clamp(minMargin, maxMargin);
    if (next == _margin) return;
    _margin = next;
    notifyListeners();
    await _save();
  }

  Future<void> setReadingMode(BookReadingMode mode) async {
    if (mode == _readingMode) return;
    _readingMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setPageTurnEffect(BookPageTurnEffect effect) async {
    if (effect == _pageTurnEffect) return;
    _pageTurnEffect = effect;
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
        'margin': _margin,
        'readingMode': _readingMode.storageValue,
        'pageTurnEffect': _pageTurnEffect.storageValue,
      }),
      flush: true,
    );
  }
}

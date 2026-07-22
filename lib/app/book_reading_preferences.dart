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

/// Body text alignment for Kaika style bridge.
enum BookTextAlign {
  start,
  justify;

  static BookTextAlign fromStorage(String? value) {
    for (final align in values) {
      if (align.storageValue == value) return align;
    }
    return justify;
  }

  String get storageValue => name;
}

/// Built-in reading faces. Specialty names use CSS stacks with system fallbacks
/// (no bundled font files in v1); [system] is Foliate's `system-ui` token.
enum BookBodyFont {
  defaultFont,
  system,
  crimsonPro,
  georgia,
  lexend,
  libreBaskerville,
  lora,
  notoSerif,
  nunito,
  ptSans,
  ptSerif,
  publicSans;

  static BookBodyFont fromStorage(String? value) {
    for (final font in values) {
      if (font.storageValue == value) return font;
    }
    return defaultFont;
  }

  String get storageValue => name;

  String get label => switch (this) {
    defaultFont => '默认字体',
    system => '系统字体',
    crimsonPro => 'CrimsonPro',
    georgia => 'Georgia',
    lexend => 'Lexend',
    libreBaskerville => 'LibreBaskerville',
    lora => 'Lora',
    notoSerif => 'NotoSerif',
    nunito => 'Nunito',
    ptSans => 'PT Sans',
    ptSerif => 'PT Serif',
    publicSans => 'Public Sans',
  };

  /// Value for Foliate `fontName` (CSS list, or `system` token).
  String get cssFontName => switch (this) {
    defaultFont => BookReadingTheme.cssReadingFontFamily,
    system => 'system',
    crimsonPro =>
      '"Crimson Pro", "CrimsonPro", Georgia, "Songti SC", "Noto Serif SC", serif',
    georgia => '"Georgia", "Times New Roman", "Songti SC", serif',
    lexend => '"Lexend", "PingFang SC", "Noto Sans SC", sans-serif',
    libreBaskerville =>
      '"Libre Baskerville", Georgia, "Songti SC", "Noto Serif SC", serif',
    lora => '"Lora", Georgia, "Songti SC", "Noto Serif SC", serif',
    notoSerif => '"Noto Serif", "Noto Serif SC", "Songti SC", Georgia, serif',
    nunito => '"Nunito", "PingFang SC", "Noto Sans SC", sans-serif',
    ptSans => '"PT Sans", "PingFang SC", "Noto Sans SC", sans-serif',
    ptSerif => '"PT Serif", Georgia, "Songti SC", "Noto Serif SC", serif',
    publicSans => '"Public Sans", "PingFang SC", "Noto Sans SC", sans-serif',
  };

  /// Optional Flutter preview family (may fall back if not installed).
  String? get previewFamily => switch (this) {
    defaultFont || system => null,
    crimsonPro => 'Crimson Pro',
    georgia => 'Georgia',
    lexend => 'Lexend',
    libreBaskerville => 'Libre Baskerville',
    lora => 'Lora',
    notoSerif => 'Noto Serif',
    nunito => 'Nunito',
    ptSans => 'PT Sans',
    ptSerif => 'PT Serif',
    publicSans => 'Public Sans',
  };
}

/// Book reflow defaults (typography + reading mode / page-turn effect).
class BookReadingPreferences extends ChangeNotifier {
  static const double defaultFontSize = 18.0;
  static const double minFontSize = 14.0;
  static const double maxFontSize = 28.0;

  static const double defaultLineHeight = 1.7;
  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 2.2;

  static const double defaultMargin = 24.0;
  static const double minMargin = 8.0;
  static const double maxMargin = 48.0;
  static const List<double> marginPresets = [8.0, 24.0, 48.0];

  /// Extra vertical inset beyond the chapter/progress label band.
  static const double defaultVerticalMargin = 26.0;
  static const double minVerticalMargin = 0.0;
  static const double maxVerticalMargin = 48.0;

  static const bool defaultBold = false;
  static const BookBodyFont defaultBodyFont = BookBodyFont.defaultFont;

  /// In-reader dimming (1 = none). Does not change system screen brightness.
  static const double defaultBrightness = 1.0;
  static const double minBrightness = 0.15;
  static const double maxBrightness = 1.0;

  /// Foliate letter-spacing in px.
  static const double defaultLetterSpacing = 0.0;
  static const double minLetterSpacing = -1.0;
  static const double maxLetterSpacing = 2.0;

  static const double defaultParagraphSpacing = 0.35;
  static const double minParagraphSpacing = 0.0;
  static const double maxParagraphSpacing = 2.0;

  static const BookTextAlign defaultTextAlign = BookTextAlign.justify;
  static const bool defaultFirstLineIndent = true;
  static const bool defaultHyphenate = false;

  static const BookReadingMode defaultReadingMode = BookReadingMode.page;
  static const BookPageTurnEffect defaultPageTurnEffect =
      BookPageTurnEffect.slide;

  BookReadingPreferences._(
    this._file,
    this._fontSize,
    this._lineHeight,
    this._readingTheme,
    this._margin,
    this._verticalMargin,
    this._bold,
    this._brightness,
    this._bodyFont,
    this._letterSpacing,
    this._paragraphSpacing,
    this._textAlign,
    this._firstLineIndent,
    this._hyphenate,
    this._readingMode,
    this._pageTurnEffect,
  );

  final File _file;
  double _fontSize;
  double _lineHeight;
  BookReadingTheme _readingTheme;
  double _margin;
  double _verticalMargin;
  bool _bold;
  double _brightness;
  BookBodyFont _bodyFont;
  double _letterSpacing;
  double _paragraphSpacing;
  BookTextAlign _textAlign;
  bool _firstLineIndent;
  bool _hyphenate;
  BookReadingMode _readingMode;
  BookPageTurnEffect _pageTurnEffect;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  BookReadingTheme get readingTheme => _readingTheme;
  double get margin => _margin;
  double get verticalMargin => _verticalMargin;
  bool get bold => _bold;
  double get brightness => _brightness;
  BookBodyFont get bodyFont => _bodyFont;
  double get letterSpacing => _letterSpacing;
  double get paragraphSpacing => _paragraphSpacing;
  BookTextAlign get textAlign => _textAlign;
  bool get firstLineIndent => _firstLineIndent;
  bool get hyphenate => _hyphenate;
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
          (json['verticalMargin'] as num?)?.toDouble() ?? defaultVerticalMargin,
          json['bold'] as bool? ?? defaultBold,
          (json['brightness'] as num?)?.toDouble() ?? defaultBrightness,
          BookBodyFont.fromStorage(json['bodyFont'] as String?),
          (json['letterSpacing'] as num?)?.toDouble() ?? defaultLetterSpacing,
          (json['paragraphSpacing'] as num?)?.toDouble() ??
              defaultParagraphSpacing,
          BookTextAlign.fromStorage(json['textAlign'] as String?),
          json['firstLineIndent'] as bool? ?? defaultFirstLineIndent,
          json['hyphenate'] as bool? ?? defaultHyphenate,
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
      defaultVerticalMargin,
      defaultBold,
      defaultBrightness,
      defaultBodyFont,
      defaultLetterSpacing,
      defaultParagraphSpacing,
      defaultTextAlign,
      defaultFirstLineIndent,
      defaultHyphenate,
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

  Future<void> setVerticalMargin(double margin) async {
    final next = margin.clamp(minVerticalMargin, maxVerticalMargin);
    if (next == _verticalMargin) return;
    _verticalMargin = next;
    notifyListeners();
    await _save();
  }

  Future<void> setBold(bool bold) async {
    if (bold == _bold) return;
    _bold = bold;
    notifyListeners();
    await _save();
  }

  Future<void> setBrightness(double value) async {
    final next = value.clamp(minBrightness, maxBrightness);
    if (next == _brightness) return;
    _brightness = next;
    notifyListeners();
    await _save();
  }

  Future<void> setBodyFont(BookBodyFont font) async {
    if (font == _bodyFont) return;
    _bodyFont = font;
    notifyListeners();
    await _save();
  }

  Future<void> setLetterSpacing(double spacing) async {
    final next = spacing.clamp(minLetterSpacing, maxLetterSpacing);
    if (next == _letterSpacing) return;
    _letterSpacing = next;
    notifyListeners();
    await _save();
  }

  Future<void> setParagraphSpacing(double spacing) async {
    final next = spacing.clamp(minParagraphSpacing, maxParagraphSpacing);
    if (next == _paragraphSpacing) return;
    _paragraphSpacing = next;
    notifyListeners();
    await _save();
  }

  Future<void> setTextAlign(BookTextAlign align) async {
    if (align == _textAlign) return;
    _textAlign = align;
    notifyListeners();
    await _save();
  }

  Future<void> setFirstLineIndent(bool enabled) async {
    if (enabled == _firstLineIndent) return;
    _firstLineIndent = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> setHyphenate(bool enabled) async {
    if (enabled == _hyphenate) return;
    _hyphenate = enabled;
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
        'verticalMargin': _verticalMargin,
        'bold': _bold,
        'brightness': _brightness,
        'bodyFont': _bodyFont.storageValue,
        'letterSpacing': _letterSpacing,
        'paragraphSpacing': _paragraphSpacing,
        'textAlign': _textAlign.storageValue,
        'firstLineIndent': _firstLineIndent,
        'hyphenate': _hyphenate,
        'readingMode': _readingMode.storageValue,
        'pageTurnEffect': _pageTurnEffect.storageValue,
      }),
      flush: true,
    );
  }
}

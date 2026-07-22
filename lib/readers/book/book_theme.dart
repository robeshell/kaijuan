/// Height of the book reader's top chrome bar (icon row inside SafeArea).
const double kBookReaderChromeBarHeight = 56.0;

/// Height of the book reader's bottom chrome content band (padding + icons).
/// Keep in sync with [BookReaderChrome] bottom `EdgeInsets` + IconButton (48).
const double kBookReaderChromeBottomHeight = 8 + 48 + 12;

/// Reading themes for the reflow book reader.
///
/// Storage values intentionally match [ComicReadingTheme.name] for the shared
/// values, so existing `book_reading.json` files migrate without conversion.
///
/// Color tokens are Readium-inspired (token-level only, not full CSS import).
enum BookReadingTheme {
  paper,
  sepia,
  dark,
  pureBlack;

  static BookReadingTheme fromStorage(String? value) {
    for (final theme in values) {
      if (theme.storageValue == value) return theme;
    }
    return paper;
  }

  String get storageValue => name;

  bool get isDark => this == dark || this == pureBlack;

  String get label => switch (this) {
    paper => '纸白',
    sepia => '米色',
    dark => '深灰',
    pureBlack => '纯黑',
  };

  int get backgroundArgb => switch (this) {
    paper => 0xFFFFFFFF,
    sepia => 0xFFFAF4E8,
    dark => 0xFF121212,
    pureBlack => 0xFF000000,
  };

  int get foregroundArgb => switch (this) {
    paper => 0xFF121212,
    sepia => 0xFF5F4B32,
    dark => 0xFFB0B0B0,
    pureBlack => 0xFFFEFEFE,
  };

  /// Hyperlink color (distinct from body on light themes).
  int get linkColorArgb => switch (this) {
    paper => 0xFF1A0DAB,
    sepia => 0xFF6B5344,
    dark => 0xFF63CAFF,
    pureBlack => 0xFF63CAFF,
  };

  /// Headings: same hue family as body, slightly softer emphasis.
  int get headingColorArgb => switch (this) {
    paper => 0xFF2A2A2A,
    sepia => 0xFF4A3A28,
    dark => 0xFFCCCCCC,
    pureBlack => 0xFFE8E8E8,
  };

  /// Primary serif for Latin body text (CJK via [serifFontFamilyFallback]).
  static const String serifFontFamily = 'Georgia';

  /// Latin serif fallbacks plus platform CJK serif system fonts.
  static const List<String> serifFontFamilyFallback = [
    'Charter',
    'Palatino',
    'Palatino Linotype',
    'PingFang SC',
    'Songti SC',
    'Noto Serif SC',
    'serif',
  ];
}

/// Default heading scale and vertical rhythm (relative to user font size).
double bookHeadingScale(String tag) => switch (tag) {
  'h1' => 1.75,
  'h2' => 1.45,
  'h3' => 1.25,
  'h4' => 1.15,
  'h5' => 1.10,
  'h6' => 1.05,
  _ => 1.0,
};

({double top, double bottom}) bookHeadingMargins(String tag, double fontSize) =>
    switch (tag) {
      'h1' => (top: fontSize * 1.4, bottom: fontSize * 0.9),
      'h2' => (top: fontSize * 1.2, bottom: fontSize * 0.75),
      'h3' => (top: fontSize * 1.0, bottom: fontSize * 0.6),
      'h4' => (top: fontSize * 0.8, bottom: fontSize * 0.5),
      'h5' => (top: fontSize * 0.7, bottom: fontSize * 0.45),
      'h6' => (top: fontSize * 0.6, bottom: fontSize * 0.4),
      _ => (top: fontSize * 0.6, bottom: fontSize * 0.4),
    };

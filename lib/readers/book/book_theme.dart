/// Height of the book reader's top/bottom chrome bars.
const double kBookReaderChromeBarHeight = 56.0;

/// Reading themes for the reflow book reader.
///
/// Storage values intentionally match [ComicReadingTheme.name] for the shared
/// values, so existing `book_reading.json` files migrate without conversion.
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
        paper => 0xFFFAFAF8,
        sepia => 0xFFF5F0E6,
        dark => 0xFF1C1C1E,
        pureBlack => 0xFF000000,
      };

  int get foregroundArgb => isDark ? 0xFFF2F2F4 : 0xFF1C1C1E;
}

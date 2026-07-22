import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_theme.dart';

void main() {
  group('BookReadingTheme tokens', () {
    test('paper uses Readium-inspired light palette', () {
      const theme = BookReadingTheme.paper;
      expect(theme.backgroundArgb, 0xFFFFFFFF);
      expect(theme.foregroundArgb, 0xFF121212);
      expect(theme.linkColorArgb, 0xFF1A0DAB);
      expect(theme.headingColorArgb, 0xFF2A2A2A);
      expect(theme.isDark, isFalse);
    });

    test('sepia uses warm foreground and link', () {
      const theme = BookReadingTheme.sepia;
      expect(theme.backgroundArgb, 0xFFFAF4E8);
      expect(theme.foregroundArgb, 0xFF5F4B32);
      expect(theme.linkColorArgb, 0xFF6B5344);
      expect(theme.headingColorArgb, 0xFF4A3A28);
    });

    test('dark and pureBlack share link accent', () {
      expect(BookReadingTheme.dark.linkColorArgb, 0xFF63CAFF);
      expect(BookReadingTheme.pureBlack.linkColorArgb, 0xFF63CAFF);
      expect(BookReadingTheme.dark.backgroundArgb, 0xFF121212);
      expect(BookReadingTheme.pureBlack.backgroundArgb, 0xFF000000);
    });

    test('serif stack includes CJK fallbacks', () {
      expect(BookReadingTheme.serifFontFamily, 'Georgia');
      expect(
        BookReadingTheme.serifFontFamilyFallback,
        containsAll(['PingFang SC', 'Songti SC', 'Noto Serif SC', 'serif']),
      );
    });
  });

  group('bookHeadingScale', () {
    test('default heading ladder', () {
      expect(bookHeadingScale('h1'), 1.75);
      expect(bookHeadingScale('h2'), 1.45);
      expect(bookHeadingScale('h3'), 1.25);
    });
  });

  group('bookHeadingMargins', () {
    test('h1 has largest vertical rhythm', () {
      const fontSize = 18.0;
      final h1 = bookHeadingMargins('h1', fontSize);
      final h3 = bookHeadingMargins('h3', fontSize);
      expect(h1.top, greaterThan(h3.top));
      expect(h1.bottom, greaterThan(h3.bottom));
    });
  });
}

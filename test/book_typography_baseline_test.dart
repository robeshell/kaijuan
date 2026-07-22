import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/app/book_reading_preferences.dart';
import 'package:kaika/readers/book/book_theme.dart';
import 'package:kaika/readers/book/foliate_js_bridge.dart';

void main() {
  test('Kaika reading face is WeChat-like sans, not system-ui alone', () {
    final family = BookReadingTheme.cssReadingFontFamily;
    expect(family, contains('PingFang SC'));
    expect(family, contains('sans-serif'));
    expect(family.split(',').first.trim(), isNot('system-ui'));
  });

  test('paper theme matches WeChat off-white / charcoal', () {
    expect(BookReadingTheme.paper.backgroundArgb, 0xFFF7F7F7);
    expect(BookReadingTheme.paper.foregroundArgb, 0xFF333333);
    expect(BookReadingTheme.paper.metaColorArgb, 0xFF999999);
  });

  test('book reading defaults match Kaika baseline rhythm', () {
    expect(BookReadingPreferences.defaultLineHeight, 1.7);
    expect(BookReadingPreferences.defaultFontSize, 18.0);
    expect(bookHeadingScale('h1'), 1.75);
    expect(bookHeadingScale('h2'), 1.45);
    expect(bookHeadingMargins('h1', 1).top, 1.4);
  });

  test('FoliateRelocation parses chapter title and book pages', () {
    final relocation = FoliateRelocation.fromHandlerArguments([
      {
        'cfi': '/4/2',
        'percentage': 0.2,
        'chapterTitle': '第二章 灾难',
        'chapterHref': 'ch2.xhtml',
        'bookCurrentPage': 20,
        'bookTotalPages': 5856,
      },
    ]);
    expect(relocation?.chapterTitle, '第二章 灾难');
    expect(relocation?.bookCurrentPage, 20);
    expect(relocation?.bookTotalPages, 5856);
  });
}

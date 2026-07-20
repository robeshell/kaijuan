import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/readers/comic/comic_models.dart';

void main() {
  group('ComicLocator', () {
    test('round-trips through JSON', () {
      const original = ComicLocator(pageIndex: 7, pageOrderVersion: 1);
      final restored = ComicLocator.tryDecode(original.encode());
      expect(restored?.pageIndex, 7);
      expect(restored?.pageOrderVersion, 1);
    });

    test('invalidates when page-order version mismatches', () {
      const locator = ComicLocator(pageIndex: 2, pageOrderVersion: 1);
      expect(
        locator.validated(pageCount: 10, itemPageOrderVersion: 2),
        isNull,
      );
      expect(
        locator.validated(pageCount: 10, itemPageOrderVersion: 1)?.pageIndex,
        2,
      );
    });

    test('invalidates out-of-range index', () {
      const locator = ComicLocator(pageIndex: 99, pageOrderVersion: 1);
      expect(
        locator.validated(pageCount: 5, itemPageOrderVersion: 1),
        isNull,
      );
    });

    test('accepts legacy version 0 as unknown', () {
      const locator = ComicLocator(pageIndex: 1, pageOrderVersion: 0);
      expect(
        locator.validated(pageCount: 5, itemPageOrderVersion: 1)?.pageIndex,
        1,
      );
    });
  });

  group('PageSpread', () {
    test('pairs pages for even anchors', () {
      // Exercised via controller logic; keep model smoke coverage here.
      expect(ComicPageOrder.version, 1);
      const spread = PageSpread.double(primaryPage: 2, secondaryPage: 3);
      expect(spread.usesSpreadLayout, isTrue);
      expect(spread.primaryPage, 2);
    });
  });
}

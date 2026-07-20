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
      expect(ComicPageOrder.version, 1);
      const spread = PageSpread.double(primaryPage: 2, secondaryPage: 3);
      expect(spread.usesSpreadLayout, isTrue);
      expect(spread.primaryPage, 2);
    });
  });

  group('comicSpread helpers', () {
    test('primary is even floor of index', () {
      expect(comicSpreadPrimary(0), 0);
      expect(comicSpreadPrimary(1), 0);
      expect(comicSpreadPrimary(4), 4);
      expect(comicSpreadPrimary(5), 4);
    });

    test('steps by two pages and clamps', () {
      expect(
        comicSpreadStep(0, delta: 1, pageCount: 10),
        2,
      );
      expect(
        comicSpreadStep(3, delta: 1, pageCount: 10),
        4,
      );
      expect(
        comicSpreadStep(8, delta: 1, pageCount: 10),
        9,
      );
      expect(
        comicSpreadStep(1, delta: -1, pageCount: 10),
        0,
      );
      expect(
        comicSpreadStep(0, delta: -1, pageCount: 10),
        0,
      );
    });

    test('comicSpreadFor pairs until last odd singleton', () {
      final mid = comicSpreadFor(3, pageCount: 5);
      expect(mid.usesSpreadLayout, isTrue);
      expect(mid.primaryPage, 2);
      expect(mid.secondaryPage, 3);

      final last = comicSpreadFor(4, pageCount: 5);
      expect(last.usesSpreadLayout, isFalse);
      expect(last.primaryPage, 4);
    });
  });

  group('comicVertical helpers', () {
    test('maps scroll offset to page index', () {
      expect(
        comicVerticalPageIndex(
          scrollOffset: 0,
          itemExtent: 100,
          pageCount: 5,
        ),
        0,
      );
      expect(
        comicVerticalPageIndex(
          scrollOffset: 149,
          itemExtent: 100,
          pageCount: 5,
        ),
        1,
      );
      expect(
        comicVerticalPageIndex(
          scrollOffset: 150,
          itemExtent: 100,
          pageCount: 5,
        ),
        2,
      );
      expect(
        comicVerticalPageIndex(
          scrollOffset: 999,
          itemExtent: 100,
          pageCount: 5,
        ),
        4,
      );
    });

    test('offset for page is index * extent', () {
      expect(
        comicVerticalOffsetForPage(
          pageIndex: 3,
          itemExtent: 120,
          pageCount: 10,
        ),
        360,
      );
    });
  });
}

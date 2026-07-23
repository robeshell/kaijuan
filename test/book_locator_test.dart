import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/readers/book/book_models.dart';

void main() {
  group('BookLocator', () {
    test('encode/decode round-trip', () {
      const loc = BookLocator(
        sectionIndex: 2,
        progressInSection: 0.4,
        cfi: 'epubcfi(/6/6!/4/2/2)',
      );
      final decoded = BookLocator.tryDecode(loc.encode())!;
      expect(decoded.sectionIndex, 2);
      expect(decoded.progressInSection, closeTo(0.4, 1e-9));
      expect(decoded.cfi, 'epubcfi(/6/6!/4/2/2)');
      expect(decoded.spineVersion, BookLocator.spineVersionCurrent);
    });

    test('validated clamps progress and rejects out-of-range index', () {
      const withinRange = BookLocator(sectionIndex: 1, progressInSection: 1.2);
      final valid = withinRange.validated(sectionCount: 3)!;
      expect(valid.sectionIndex, 1);
      expect(valid.progressInSection, 1.0);

      expect(
        const BookLocator(sectionIndex: -1).validated(sectionCount: 3),
        isNull,
      );
      expect(
        const BookLocator(sectionIndex: 3).validated(sectionCount: 3),
        isNull,
      );
    });

    test('spineVersion mismatch rejects', () {
      const loc = BookLocator(sectionIndex: 0, spineVersion: 999);
      expect(loc.validated(sectionCount: 3), isNull);
    });

    test('tryDecode returns null for invalid JSON', () {
      expect(BookLocator.tryDecode('not json'), isNull);
      expect(BookLocator.tryDecode('{"foo": 1}'), isNull);
    });
  });

  group('BookSectionMap', () {
    const map = BookSectionMap(startIndices: [0, 10, 25], totalParagraphs: 40);

    test('locatorFromParagraph maps boundaries correctly', () {
      final first = map.locatorFromParagraph(paragraphIndex: 0);
      expect(first.sectionIndex, 0);
      expect(first.progressInSection, closeTo(0.0, 1e-9));

      final lastOfFirst = map.locatorFromParagraph(paragraphIndex: 9);
      expect(lastOfFirst.sectionIndex, 0);
      expect(lastOfFirst.progressInSection, closeTo(0.9, 1e-9));

      final firstOfSecond = map.locatorFromParagraph(paragraphIndex: 10);
      expect(firstOfSecond.sectionIndex, 1);
      expect(firstOfSecond.progressInSection, closeTo(0.0, 1e-9));

      final last = map.locatorFromParagraph(paragraphIndex: 39);
      expect(last.sectionIndex, 2);
      expect(last.progressInSection, closeTo(14 / 15, 1e-9));
    });

    test('locatorFromParagraph clamps out-of-range and uses offset', () {
      final under = map.locatorFromParagraph(paragraphIndex: -5);
      expect(under.sectionIndex, 0);
      expect(under.progressInSection, closeTo(0.0, 1e-9));

      final over = map.locatorFromParagraph(paragraphIndex: 100);
      expect(over.sectionIndex, 2);
      expect(over.progressInSection, closeTo(14 / 15, 1e-9));

      final withOffset = map.locatorFromParagraph(
        paragraphIndex: 5,
        paragraphOffset: 0.5,
      );
      expect(withOffset.sectionIndex, 0);
      expect(withOffset.progressInSection, closeTo(0.55, 1e-9));
    });

    test('paragraphFromLocator inverts locatorFromParagraph', () {
      for (var p = 0; p < map.totalParagraphs; p++) {
        final loc = map.locatorFromParagraph(paragraphIndex: p);
        final back = map.paragraphFromLocator(loc);
        // Rounding is allowed because progress is a ratio.
        expect((back - p).abs(), lessThanOrEqualTo(1));
      }
    });

    test('empty map returns safe defaults', () {
      const empty = BookSectionMap(startIndices: [], totalParagraphs: 0);
      final loc = empty.locatorFromParagraph(paragraphIndex: 5);
      expect(loc.sectionIndex, 0);
      expect(loc.progressInSection, 0.0);
      expect(empty.paragraphFromLocator(loc), 0);
    });
  });
}

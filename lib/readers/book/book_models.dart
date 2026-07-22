import 'dart:convert';

/// One row in the reader TOC, mapped onto the EPUB spine.
///
/// This is a renderer-facing model rather than an import-parser detail. Both
/// the Foliate bridge and import probe may produce it without coupling the
/// presentation controller to either implementation.
class BookTocEntry {
  const BookTocEntry({
    required this.title,
    required this.href,
    this.fragment,
    this.sectionIndex,
    this.depth = 0,
  });

  final String title;
  final String href;
  final String? fragment;
  final int? sectionIndex;
  final int depth;
}

/// Format-owned book locator. DB stores [encode] opaquely.
class BookLocator {
  const BookLocator({
    required this.sectionIndex,
    this.progressInSection = 0,
    this.cfi,
    this.spineVersion = spineVersionCurrent,
  });

  static const int spineVersionCurrent = 1;

  final int sectionIndex;
  final double progressInSection;
  final String? cfi;
  final int spineVersion;

  Map<String, Object?> toJson() => {
    'sectionIndex': sectionIndex,
    'progressInSection': progressInSection,
    if (cfi != null) 'cfi': cfi,
    'spineVersion': spineVersion,
  };

  String encode() => jsonEncode(toJson());

  static BookLocator? tryDecode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final index = map['sectionIndex'];
      if (index is! int) return null;
      final progress = map['progressInSection'];
      final version = map['spineVersion'];
      final cfi = map['cfi'];
      return BookLocator(
        sectionIndex: index,
        progressInSection: progress is num ? progress.toDouble() : 0,
        cfi: cfi is String && cfi.isNotEmpty ? cfi : null,
        spineVersion: version is int ? version : 0,
      );
    } catch (_) {
      return null;
    }
  }

  BookLocator? validated({required int sectionCount}) {
    if (spineVersion != 0 && spineVersion != spineVersionCurrent) {
      return null;
    }
    if (sectionCount <= 0) return null;
    if (sectionIndex < 0 || sectionIndex >= sectionCount) return null;
    return BookLocator(
      sectionIndex: sectionIndex,
      progressInSection: progressInSection.clamp(0.0, 1.0),
      cfi: cfi,
      spineVersion: spineVersionCurrent,
    );
  }
}

/// Paragraph index boundaries for a reflow engine that thinks in flat
/// paragraphs but must expose spine-style section coordinates.
class BookSectionMap {
  const BookSectionMap({
    required this.startIndices,
    required this.totalParagraphs,
  });

  /// Start paragraph index of every section/chapter, in ascending order.
  final List<int> startIndices;

  /// Total number of paragraphs in the book.
  final int totalParagraphs;

  int get sectionCount => startIndices.length;

  /// Page/paragraph count for [index], or 0 when the section is a windowed
  /// placeholder (same start as the next entry / total).
  int sectionLength(int index) {
    if (index < 0 || index >= startIndices.length) return 0;
    return _sectionLength(index);
  }

  /// True when [index] has at least one paginated page/paragraph.
  bool sectionHasContent(int index) => sectionLength(index) > 0;

  int _sectionLength(int index) {
    final start = startIndices[index];
    final end = index + 1 < startIndices.length
        ? startIndices[index + 1]
        : totalParagraphs;
    return end - start;
  }

  /// Maps a flat paragraph position to a [BookLocator].
  BookLocator locatorFromParagraph({
    required int paragraphIndex,
    double paragraphOffset = 0,
  }) {
    if (startIndices.isEmpty || totalParagraphs <= 0) {
      return const BookLocator(sectionIndex: 0);
    }
    final clamped = paragraphIndex.clamp(0, totalParagraphs - 1);

    // Binary search for the section containing [clamped].
    var low = 0;
    var high = startIndices.length - 1;
    var section = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (startIndices[mid] <= clamped) {
        section = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    final start = startIndices[section];
    final length = _sectionLength(section);
    final local = (clamped - start).clamp(0, length);
    final progress = length <= 0
        ? 0.0
        : ((local + paragraphOffset) / length).clamp(0.0, 1.0);
    return BookLocator(sectionIndex: section, progressInSection: progress);
  }

  /// Maps a [BookLocator] back to a flat paragraph index suitable for the
  /// engine's `jumpToIndex`.
  int paragraphFromLocator(BookLocator locator) {
    if (startIndices.isEmpty || totalParagraphs <= 0) return 0;
    final section = locator.sectionIndex.clamp(0, startIndices.length - 1);
    final start = startIndices[section];
    final length = _sectionLength(section);
    final local = (locator.progressInSection * length).floor();
    return (start + local).clamp(0, totalParagraphs - 1);
  }
}

/// Formats the reader supports. Parsing is case-insensitive and tolerant of
/// leading dots so it can consume file extensions directly.
enum ReaderFormat {
  epub,
  txt,
  markdown,
  cbz,
  zip,
  pdf,
  mobi;

  static ReaderFormat? fromExtension(String extension) {
    final normalized = extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    return switch (normalized) {
      'epub' => ReaderFormat.epub,
      'txt' => ReaderFormat.txt,
      'md' || 'markdown' => ReaderFormat.markdown,
      'cbz' => ReaderFormat.cbz,
      'zip' => ReaderFormat.zip,
      'pdf' => ReaderFormat.pdf,
      'mobi' => ReaderFormat.mobi,
      _ => null,
    };
  }

  /// Wire format for drift / JSON. Never write [name] ad-hoc at call sites.
  String get storageValue => name;

  static ReaderFormat? fromStorage(String value) {
    for (final format in ReaderFormat.values) {
      if (format.name == value) return format;
    }
    return null;
  }
}

enum ReaderKind {
  book,
  comic;

  String get storageValue => name;

  static ReaderKind? fromStorage(String value) {
    for (final kind in ReaderKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// A reading position. The JSON payload is format-owned: comic readers store
/// a page index, reflow readers store sectionID/anchor/range. Keeping it
/// opaque here is deliberate — stable annotation identity is designed inside
/// each format's locator, not bolted on at the database layer.
class ReaderLocator {
  const ReaderLocator({required this.format, required this.payloadJson});

  final ReaderFormat format;
  final String payloadJson;
}

/// Comic page-order contract. Progress locators store a page index; if the
/// sort rules change, bump [version] so restored progress can be invalidated
/// instead of silently pointing at the wrong page.
abstract final class ComicPageOrder {
  /// Natural sort of image entry names (see [ComicArchive.naturalCompare]).
  static const int version = 1;
}

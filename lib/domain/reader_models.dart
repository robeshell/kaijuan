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
}

enum ReaderKind { book, comic }

/// A reading position. The JSON payload is format-owned: comic readers store
/// a page index, reflow readers store sectionID/anchor/range. Keeping it
/// opaque here is deliberate — stable annotation identity is designed inside
/// each format's locator, not bolted on at the database layer.
class ReaderLocator {
  const ReaderLocator({required this.format, required this.payloadJson});

  final ReaderFormat format;
  final String payloadJson;
}

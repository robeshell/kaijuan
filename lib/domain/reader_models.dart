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

/// Engine-agnostic bookmark metadata. [locatorJson] remains format-owned and
/// is interpreted only by the matching reader controller.
class ReaderBookmark {
  const ReaderBookmark({
    required this.id,
    required this.locatorJson,
    required this.createdAt,
    this.label,
  });

  final int id;
  final String locatorJson;
  final String? label;
  final DateTime createdAt;
}

/// Foliate overlayer style for book markings.
enum BookAnnotationType {
  highlight,
  underline,
  wavy;

  String get storageValue => name;

  static BookAnnotationType? fromStorage(String value) {
    for (final type in BookAnnotationType.values) {
      if (type.name == value) return type;
    }
    if (value == 'squiggly') return BookAnnotationType.wavy;
    return null;
  }
}

/// Five highlight/underline swatches (CSS for Foliate, ARGB for Flutter).
enum BookHighlightColor {
  yellow(id: 'yellow', css: '#FACC15', argb: 0xFFFACC15, label: '黄'),
  green(id: 'green', css: '#4ADE80', argb: 0xFF4ADE80, label: '绿'),
  blue(id: 'blue', css: '#60A5FA', argb: 0xFF60A5FA, label: '蓝'),
  pink(id: 'pink', css: '#F472B6', argb: 0xFFF472B6, label: '粉'),
  purple(id: 'purple', css: '#C084FC', argb: 0xFFC084FC, label: '紫');

  const BookHighlightColor({
    required this.id,
    required this.css,
    required this.argb,
    required this.label,
  });

  final String id;
  final String css;
  final int argb;
  final String label;

  static BookHighlightColor fromCss(String value) {
    final normalized = value.trim().toLowerCase();
    for (final color in BookHighlightColor.values) {
      if (color.css.toLowerCase() == normalized || color.id == normalized) {
        return color;
      }
    }
    return BookHighlightColor.yellow;
  }
}

/// Persisted Foliate range annotation (highlight / underline).
class BookAnnotation {
  const BookAnnotation({
    required this.id,
    required this.cfi,
    required this.type,
    required this.colorCss,
    required this.createdAt,
    this.selectedText,
    this.note,
  });

  final int id;
  final String cfi;
  final BookAnnotationType type;
  final String colorCss;
  final String? selectedText;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toFoliateJson() => {
    'id': id,
    'value': cfi,
    'type': type.storageValue,
    'color': colorCss,
    if (note != null && note!.isNotEmpty) 'note': note,
  };
}

/// Active selection / annotation-click menu payload (normalized viewport box).
enum BookSelectionMenuPhase {
  /// Compact action strip after a fresh selection.
  actions,

  /// Markup editor (line style + colors) after「划线」or annotation tap.
  markup,
}

class BookSelectionMenu {
  const BookSelectionMenu({
    required this.cfi,
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.phase = BookSelectionMenuPhase.actions,
    this.annotationId,
    this.annotationType,
    this.annotationColorCss,
    this.note,
    this.fromAnnotation = false,
  });

  final String cfi;
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final BookSelectionMenuPhase phase;
  final int? annotationId;
  final BookAnnotationType? annotationType;
  final String? annotationColorCss;
  final String? note;
  final bool fromAnnotation;

  bool get isExistingAnnotation => fromAnnotation || annotationId != null;

  bool get hasNote => note != null && note!.trim().isNotEmpty;

  BookSelectionMenu copyWith({
    BookSelectionMenuPhase? phase,
    int? annotationId,
    BookAnnotationType? annotationType,
    String? annotationColorCss,
    String? note,
    bool clearNote = false,
    bool? fromAnnotation,
  }) {
    return BookSelectionMenu(
      cfi: cfi,
      text: text,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      phase: phase ?? this.phase,
      annotationId: annotationId ?? this.annotationId,
      annotationType: annotationType ?? this.annotationType,
      annotationColorCss: annotationColorCss ?? this.annotationColorCss,
      note: clearNote ? null : (note ?? this.note),
      fromAnnotation: fromAnnotation ?? this.fromAnnotation,
    );
  }
}

/// Comic page-order contract. Progress locators store a page index; if the
/// sort rules change, bump [version] so restored progress can be invalidated
/// instead of silently pointing at the wrong page.
abstract final class ComicPageOrder {
  /// Listing algorithm version:
  /// - CBZ/ZIP: natural sort of image entry names
  /// - EPUB: OPF spine → images (fallback: natural-sorted images)
  /// See [ComicArchive.listPagesDetailed].
  static const int version = 1;
}

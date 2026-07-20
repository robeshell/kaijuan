import 'dart:convert';

import '../../domain/reader_models.dart';

/// How pages are laid out and animated in the comic reader.
enum ComicReaderMode {
  /// Horizontal PageView with slide animation.
  slide,

  /// Instant page change, no slide animation (still one page / spread).
  staticView,

  /// Continuous vertical scroll of all pages.
  vertical,

  /// Two pages side-by-side when width allows; otherwise single page.
  spread;

  String get storageValue => name;

  static ComicReaderMode fromStorage(String? value) {
    for (final mode in ComicReaderMode.values) {
      if (mode.name == value) return mode;
    }
    return ComicReaderMode.slide;
  }

  String get label => switch (this) {
        ComicReaderMode.slide => '滑动',
        ComicReaderMode.staticView => '静态',
        ComicReaderMode.vertical => '纵向',
        ComicReaderMode.spread => '双页',
      };
}

/// Reading direction for horizontal modes (slide / static / spread).
enum ComicReadDirection {
  /// Left-to-right: next page is to the right (western).
  ltr,

  /// Right-to-left: next page is to the left (manga default).
  rtl;

  String get storageValue => name;

  static ComicReadDirection fromStorage(String? value) {
    for (final d in ComicReadDirection.values) {
      if (d.name == value) return d;
    }
    return ComicReadDirection.ltr;
  }

  String get label => switch (this) {
        ComicReadDirection.ltr => '从左到右',
        ComicReadDirection.rtl => '从右到左',
      };
}

/// Content-area theme, independent of App chrome theme.
enum ComicReadingTheme {
  paper,
  sepia,
  dark,
  pureBlack;

  /// Default for comics per reader-chrome spec.
  static const ComicReadingTheme comicDefault = ComicReadingTheme.dark;

  String get storageValue => name;

  static ComicReadingTheme fromStorage(String? value) {
    for (final t in ComicReadingTheme.values) {
      if (t.name == value) return t;
    }
    return comicDefault;
  }

  /// Background behind page images.
  int get backgroundArgb => switch (this) {
        ComicReadingTheme.paper => 0xFFFAFAF8,
        ComicReadingTheme.sepia => 0xFFF5F0E6,
        ComicReadingTheme.dark => 0xFF1C1C1E,
        ComicReadingTheme.pureBlack => 0xFF000000,
      };

  bool get isDark =>
      this == ComicReadingTheme.dark || this == ComicReadingTheme.pureBlack;

  String get label => switch (this) {
        ComicReadingTheme.paper => '纸白',
        ComicReadingTheme.sepia => '米色',
        ComicReadingTheme.dark => '深灰',
        ComicReadingTheme.pureBlack => '纯黑',
      };
}

/// Format-owned comic locator payload. Database stores [toJson] as opaque text.
class ComicLocator {
  const ComicLocator({
    required this.pageIndex,
    this.pageOrderVersion = ComicPageOrder.version,
  });

  final int pageIndex;
  final int pageOrderVersion;

  Map<String, Object?> toJson() => {
        'pageIndex': pageIndex,
        'pageOrderVersion': pageOrderVersion,
      };

  String encode() => jsonEncode(toJson());

  static ComicLocator? tryDecode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final index = map['pageIndex'];
      if (index is! int) return null;
      final version = map['pageOrderVersion'];
      return ComicLocator(
        pageIndex: index,
        pageOrderVersion: version is int ? version : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns null when page-order rules changed and progress is unsafe.
  ComicLocator? validated({
    required int pageCount,
    required int itemPageOrderVersion,
  }) {
    if (pageCount <= 0) return null;
    if (pageOrderVersion != 0 &&
        itemPageOrderVersion != 0 &&
        pageOrderVersion != itemPageOrderVersion) {
      return null;
    }
    if (pageIndex < 0 || pageIndex >= pageCount) return null;
    return this;
  }
}

/// A single page or a two-page spread, always anchored on [primaryPage].
class PageSpread {
  const PageSpread.single(this.primaryPage)
      : secondaryPage = null,
        usesSpreadLayout = false;

  const PageSpread.double({
    required this.primaryPage,
    required this.secondaryPage,
  }) : usesSpreadLayout = true;

  final int primaryPage;
  final int? secondaryPage;
  final bool usesSpreadLayout;
}

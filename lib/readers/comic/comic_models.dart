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
  /// Paired pages are laid out edge-to-edge (no gutter gap).
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

  /// Chrome / control foreground on top of [backgroundArgb].
  int get foregroundArgb => isDark ? 0xFFF2F2F4 : 0xFF1C1C1E;

  /// Secondary chrome text (page label, captions).
  int get metaColorArgb => isDark ? 0x99F2F2F4 : 0x991C1C1E;

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

/// Even primary of the spread that contains [pageIndex] (0-1, 2-3, …).
int comicSpreadPrimary(int pageIndex) {
  if (pageIndex < 0) return 0;
  return (pageIndex ~/ 2) * 2;
}

/// Next/previous spread anchor. [delta] is +1 (forward) or -1 (backward).
int comicSpreadStep(
  int pageIndex, {
  required int delta,
  required int pageCount,
}) {
  if (pageCount <= 0) return 0;
  final primary = comicSpreadPrimary(pageIndex);
  return (primary + delta * 2).clamp(0, pageCount - 1);
}

/// Build the spread shown for [anchor] under comic spread pairing rules.
PageSpread comicSpreadFor(int anchor, {required int pageCount}) {
  if (pageCount <= 0) return const PageSpread.single(0);
  final primary = comicSpreadPrimary(anchor.clamp(0, pageCount - 1));
  final secondary = primary + 1;
  if (secondary < pageCount) {
    return PageSpread.double(primaryPage: primary, secondaryPage: secondary);
  }
  return PageSpread.single(primary);
}

/// Which page index is "current" for a vertical list of equal [itemExtent].
/// Uses the page whose midpoint is closest to the viewport top (offset).
int comicVerticalPageIndex({
  required double scrollOffset,
  required double itemExtent,
  required int pageCount,
}) {
  if (pageCount <= 0 || itemExtent <= 0) return 0;
  final index = (scrollOffset / itemExtent).round();
  return index.clamp(0, pageCount - 1);
}

/// Scroll offset that puts [pageIndex] at the top of a fixed-extent list.
double comicVerticalOffsetForPage({
  required int pageIndex,
  required double itemExtent,
  required int pageCount,
}) {
  if (pageCount <= 0 || itemExtent <= 0) return 0;
  final index = pageIndex.clamp(0, pageCount - 1);
  return index * itemExtent;
}

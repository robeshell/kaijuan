import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../presentation/controllers/book_reader_controller.dart';
import '../../readers/book/book_epub.dart';
import '../../readers/book/book_html_preprocessor.dart';
import '../../readers/book/book_models.dart';
import 'pagination/paginator.dart';
import 'pagination/paged_mode_view.dart';
import 'prepared_section.dart';
import 'scroll_mode_view.dart';
import '../../readers/book/book_theme.dart';

/// Adapter that wires [BookReaderController] to a flutter_html-based engine.
class FlutterHtmlBookEngineAdapter {
  FlutterHtmlBookEngineAdapter({required this.readerController});

  final BookReaderController readerController;

  String? _filePath;
  List<PreparedSection> _sections = const [];
  final _byteCache = <String, Uint8List>{};

  // Page-mode pagination cache.
  PaginatorResult? _pageResult;
  Size? _pageSize;
  bool _paginating = false;
  int? _lastPaginationKey;

  /// Opens the EPUB, pre-processes every section, and attaches to the
  /// controller.
  Future<void> open(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在：$filePath');
      }

      final doc = await BookEpub.open(filePath);
      final prepared = <PreparedSection>[];
      for (final section in doc.sections) {
        prepared.add(
          PreparedSection(
            href: section.href,
            title: section.title,
            html: BookHtmlPreprocessor.prepareSection(
              rawHtml: section.rawHtml,
              baseHref: section.href,
              stylesheets: doc.stylesheets,
            ),
          ),
        );
      }

      _filePath = filePath;
      _sections = prepared;
      _pageResult = null;
      _pageSize = null;
      _lastPaginationKey = null;

      readerController.attachEngine(
        BookSectionMap(
          startIndices: List.generate(prepared.length, (i) => i),
          totalParagraphs: prepared.length,
        ),
        [for (final s in prepared) s.title],
      );
    } catch (e) {
      readerController.engineFailed(e);
    }
  }

  /// Starts listening to controller changes. Idempotent.
  ///
  /// The surrounding screen already rebuilds via [ListenableBuilder], so the
  /// adapter does not need its own listener.
  void attach() {}

  /// Builds the reader widget. Call only after [isReady] is true.
  Widget buildView(BuildContext context) {
    final theme = readerController.readingTheme;
    final sectionIndex = readerController.sectionIndex;
    final progressInSection = readerController.progressInSection;

    final safe = MediaQuery.paddingOf(context);
    const chromeHeight = kBookReaderChromeBarHeight;
    final contentInsets = EdgeInsets.only(
      top: safe.top + chromeHeight,
      bottom: safe.bottom + chromeHeight,
    );

    return ColoredBox(
      color: Color(theme.backgroundArgb),
      child: Padding(
        padding: contentInsets,
        child: readerController.readingMode == BookReadingMode.page
            ? _buildPagedView(context)
            : ScrollModeView(
                sections: _sections,
                readBytes: _readBytes,
                initialSection: sectionIndex,
                initialProgress: progressInSection,
                jumpTargetSection: _consumeJumpSection(),
                onPositionChanged: (section, progress) {
                  readerController.reportPosition(section, progress);
                },
                fontSize: readerController.fontSize,
                lineHeight: readerController.lineHeight,
                margin: readerController.margin,
                theme: theme,
              ),
      ),
    );
  }

  Widget _buildPagedView(BuildContext context) {
    final key = Object.hash(
      readerController.fontSize,
      readerController.lineHeight,
      readerController.margin,
      readerController.readingTheme,
    );

    if (_pageResult == null || key != _lastPaginationKey) {
      _lastPaginationKey = key;
      _pageResult = null;
      _pageSize = null;
      _schedulePagination(context);
    }

    final result = _pageResult;
    final pageSize = _pageSize;
    if (result == null || pageSize == null || _paginating) {
      return const Center(child: CircularProgressIndicator());
    }

    final jumpTargetPage = _consumeJumpPage(result);

    return PagedModeView(
      result: result,
      readBytes: _readBytes,
      initialPage: readerController.pageIndex,
      jumpTargetPage: jumpTargetPage,
      onPageChanged: readerController.reportPage,
      pageSize: pageSize,
      theme: readerController.readingTheme,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  void _schedulePagination(BuildContext context) {
    if (_paginating) return;
    _paginating = true;

    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    const chromeHeight = kBookReaderChromeBarHeight;
    final pageSize = Size(
      size.width - readerController.margin * 2,
      size.height - safe.top - safe.bottom - chromeHeight * 2,
    );

    final theme = readerController.readingTheme;
    final paginator = Paginator(
      pageSize: pageSize,
      fontSize: readerController.fontSize,
      lineHeight: readerController.lineHeight,
      textColor: Color(theme.foregroundArgb),
      readBytes: _readBytes,
      textScaler: MediaQuery.textScalerOf(context),
    );

    paginator.paginate(_sections).then((result) {
      _pageResult = result;
      _pageSize = pageSize;
      _paginating = false;
      readerController.attachPageMap(
        BookSectionMap(
          startIndices: result.sectionStartPageIndices,
          totalParagraphs: result.pages.length,
        ),
      );
      // Clear any stale section-based pending jump; pageIndex is now authoritative.
      readerController.consumePendingJump();
    }).catchError((Object error) {
      _paginating = false;
      debugPrint('[FlutterHtmlBookEngineAdapter] pagination failed: $error');
    });
  }

  void dispose() {
    _byteCache.clear();
  }

  // ------------------------------------------------------------------
  // Controller -> engine
  // ------------------------------------------------------------------

  int? _consumeJumpSection() {
    final jump = readerController.consumePendingJump();
    if (jump == null) return null;
    final map = readerController.sectionMap;
    if (map == null) return null;
    return map
        .locatorFromParagraph(paragraphIndex: jump, paragraphOffset: 0)
        .sectionIndex;
  }

  int? _consumeJumpPage(PaginatorResult result) {
    final jump = readerController.consumePendingJump();
    if (jump == null) return null;
    // If the jump is smaller than the section count, treat it as a section
    // index (e.g. from the TOC) and map it to the section's first page.
    if (jump < result.sectionStartPageIndices.length) {
      return result.sectionStartPageIndices[jump];
    }
    return jump.clamp(0, result.pages.length - 1);
  }

  // ------------------------------------------------------------------
  // Archive reads
  // ------------------------------------------------------------------

  Future<Uint8List?> _readBytes(String entry) async {
    final cached = _byteCache[entry];
    if (cached != null) return cached;

    final path = _filePath;
    if (path == null) return null;

    final bytes = await BookEpub.readEntry(path, entry);
    if (bytes != null && bytes.isNotEmpty) {
      _byteCache[entry] = bytes;
    }
    return bytes;
  }
}

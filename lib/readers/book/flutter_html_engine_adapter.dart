import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/book_reading_preferences.dart';
import '../../presentation/controllers/book_reader_controller.dart';
import '../../readers/book/book_epub.dart';
import '../../readers/book/book_footnotes.dart';
import '../../readers/book/book_html_preprocessor.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/book_theme.dart';
import 'pagination/paginator.dart';
import 'pagination/paged_mode_view.dart';
import 'prepared_section.dart';
import 'scroll_mode_view.dart';

/// Adapter that wires [BookReaderController] to a flutter_html-based engine.
class FlutterHtmlBookEngineAdapter {
  FlutterHtmlBookEngineAdapter({required this.readerController});

  final BookReaderController readerController;

  BookEpubSession? _session;
  List<PreparedSection> _sections = const [];
  List<String> _packageStylesheets = const [];
  final _prepared = <int>{};
  final _prepareInflight = <int, Future<void>>{};
  final _byteCache = <String, Uint8List>{};

  // Page-mode pagination cache.
  PaginatorResult? _pageResult;
  Size? _pageSize;
  int? _lastPaginationKey;

  /// Bumped to cancel an in-flight progressive pagination run.
  int _paginationGen = 0;

  /// Large books only paginate a window around the current section.
  static const _largeSectionThreshold = 80;
  static const _pageWindowRadius = 2;

  bool get _isLargeBook => _sections.length > _largeSectionThreshold;

  /// OPF manifest CSS loaded once per open book (shared by all sections).
  List<String> get packageStylesheets => _packageStylesheets;

  /// Opens the EPUB lazily and attaches once the restore window is ready.
  Future<void> open(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在：$filePath');
      }

      final session = await BookEpub.openSession(filePath);
      final doc = session.document;
      final stubs = [
        for (final section in doc.sections)
          PreparedSection(
            href: section.href,
            title: section.title,
            html: '',
          ),
      ];

      _session = session;
      _sections = stubs;
      _packageStylesheets = await session.stylesheets();
      _prepared.clear();
      _prepareInflight.clear();
      _byteCache.clear();
      _pageResult = null;
      _pageSize = null;
      _lastPaginationKey = null;
      _paginationGen++;

      readerController.attachEngine(
        BookSectionMap(
          startIndices: List.generate(stubs.length, (i) => i),
          totalParagraphs: stubs.length,
        ),
        [for (final s in stubs) s.title],
        tocEntries: doc.toc,
      );

      // Warm the restore window so the first paint has real HTML.
      final start = readerController.sectionIndex.clamp(0, stubs.length - 1);
      await ensureSectionPrepared(start);
      if (start > 0) await ensureSectionPrepared(start - 1);
      if (start + 1 < stubs.length) await ensureSectionPrepared(start + 1);
    } catch (e) {
      readerController.engineFailed(e);
    }
  }

  /// Ensures spine section [index] HTML is loaded and preprocessed.
  Future<void> ensureSectionPrepared(int index) {
    if (index < 0 || index >= _sections.length) {
      return Future<void>.value();
    }
    if (_prepared.contains(index)) return Future<void>.value();
    return _prepareInflight.putIfAbsent(index, () async {
      try {
        final session = _session;
        if (session == null) return;
        final href = _sections[index].href;
        final rawHtml = await session.readHtml(href);
        final linkedHrefs = BookHtmlPreprocessor.linkedStylesheetHrefs(rawHtml);
        final sectionStylesheets = <String>[];
        for (final linkHref in linkedHrefs) {
          final resolved = BookEpub.resolveHref(href, linkHref).path;
          final css = await session.readCss(resolved);
          if (css != null) sectionStylesheets.add(css);
        }
        final preparedHtml = BookHtmlPreprocessor.prepareSection(
          rawHtml: rawHtml,
          baseHref: href,
          // Package CSS stays on the adapter; section link CSS is separate.
          stylesheets: const [],
        );
        _sections[index] = PreparedSection(
          href: href,
          title: _sections[index].title,
          html: preparedHtml.html,
          sectionStylesheets: List.unmodifiable(sectionStylesheets),
          footnotes: preparedHtml.footnotes,
        );
        _prepared.add(index);
      } finally {
        _prepareInflight.remove(index);
      }
    });
  }

  /// Starts listening to controller changes. Idempotent.
  ///
  /// The surrounding screen already rebuilds via [ListenableBuilder], so the
  /// adapter does not need its own listener.
  void attach() {}

  /// Builds the reader widget. Call only after [isReady] is true.
  Widget buildView(BuildContext context) {
    return _BookEngineView(adapter: this);
  }

  Widget _buildContent(
    BuildContext context, {
    required void Function(String url, {String baseHref}) onLinkTap,
  }) {
    final theme = readerController.readingTheme;
    final sectionIndex = readerController.sectionIndex;
    final progressInSection = readerController.progressInSection;

    final safe = MediaQuery.paddingOf(context);
    final contentInsets = EdgeInsets.only(
      top: safe.top + kBookReaderChromeBarHeight,
      bottom: safe.bottom + kBookReaderChromeBottomHeight,
    );

    return ColoredBox(
      color: Color(theme.backgroundArgb),
      child: Padding(
        padding: contentInsets,
        child: readerController.readingMode == BookReadingMode.page
            ? _buildPagedView(context, onLinkTap: onLinkTap)
            : ScrollModeView(
                sections: _sections,
                readBytes: _readBytes,
                ensureSection: ensureSectionPrepared,
                initialSection: sectionIndex,
                initialProgress: progressInSection,
                jumpTarget: readerController.pendingJump,
                onJumpApplied: readerController.clearPendingJump,
                onPositionChanged: (section, progress) {
                  readerController.reportPosition(section, progress);
                },
                onLinkTap: onLinkTap,
                fontSize: readerController.fontSize,
                lineHeight: readerController.lineHeight,
                margin: readerController.margin,
                theme: theme,
              ),
      ),
    );
  }

  Widget _buildPagedView(
    BuildContext context, {
    required void Function(String url, {String baseHref}) onLinkTap,
  }) {
    final key = Object.hash(
      readerController.fontSize,
      readerController.lineHeight,
      readerController.margin,
      readerController.readingTheme,
      MediaQuery.sizeOf(context),
      MediaQuery.paddingOf(context),
      MediaQuery.textScalerOf(context),
      // Large books re-paginate when the restore/current section moves.
      _isLargeBook ? readerController.sectionIndex : 0,
    );

    if (key != _lastPaginationKey) {
      _lastPaginationKey = key;
      _pageResult = null;
      _pageSize = null;
      // Capture layout inputs now; run pagination after this frame.
      final size = MediaQuery.sizeOf(context);
      final safe = MediaQuery.paddingOf(context);
      final pageSize = Size(
        size.width - readerController.margin * 2,
        size.height -
            safe.top -
            safe.bottom -
            kBookReaderChromeBarHeight -
            kBookReaderChromeBottomHeight,
      );
      final textScaler = MediaQuery.textScalerOf(context);
      final theme = readerController.readingTheme;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _schedulePagination(
          pageSize: pageSize,
          textScaler: textScaler,
          theme: theme,
        );
      });
    }

    final result = _pageResult;
    final pageSize = _pageSize;
    // Show partial pages as soon as the restore chapter is ready; remaining
    // chapters keep paginating in the background.
    if (result == null || pageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return PagedModeView(
      result: result,
      readBytes: _readBytes,
      controller: readerController,
      onPageChanged: readerController.reportPage,
      onLinkTap: onLinkTap,
      pageSize: pageSize,
      theme: readerController.readingTheme,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  /// Opens an NCX/nav TOC row (resolves optional `#fragment` progress).
  void openTocEntry(BookTocEntry entry) {
    final index = entry.sectionIndex;
    if (index == null || index < 0 || index >= _sections.length) return;
    unawaited(() async {
      await ensureSectionPrepared(index);
      final progress = BookEpub.fragmentProgress(
        _sections[index].html,
        entry.fragment,
      );
      readerController.goToTocEntry(entry, progressInSection: progress);
    }());
  }

  /// Looks up footnote plain text for [fragment] in [preferredIndex] then all.
  String? footnoteText(String? fragment, {int? preferredIndex}) {
    if (fragment == null || fragment.isEmpty) return null;
    if (preferredIndex != null &&
        preferredIndex >= 0 &&
        preferredIndex < _sections.length) {
      final local = _sections[preferredIndex].footnotes[fragment];
      if (local != null) return local;
    }
    for (final section in _sections) {
      final text = section.footnotes[fragment];
      if (text != null) return text;
    }
    return null;
  }

  /// Handles hyperlinks from scroll or page mode.
  ///
  /// Returns footnote text when the link is a footnote (caller shows popup);
  /// otherwise navigates or opens an external URL and returns null.
  Future<String?> openInternalLink(
    String url, {
    String baseHref = '',
    void Function(String message)? onLinkError,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http:') ||
        lower.startsWith('https:') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('www.')) {
      final opened = await _launchExternalUrl(trimmed);
      if (!opened) onLinkError?.call('无法打开链接');
      return null;
    }

    final resolved = baseHref.isEmpty
        ? BookEpub.resolveHref('', trimmed)
        : BookEpub.resolveHref(baseHref, trimmed);
    if (resolved.path.contains(':')) return null;

    final fragment = resolved.fragment;
    final isFootnote = BookFootnotes.looksLikeFootnoteFragment(fragment);

    final targetPath = resolved.path.toLowerCase();
    var index = _sectionIndexForPath(targetPath);
    // Same-document `#fragment` / unresolved path: prefer current section.
    if (index < 0) {
      index = readerController.sectionIndex.clamp(0, _sections.length - 1);
    }

    if (isFootnote) {
      await ensureSectionPrepared(index);
      final note = footnoteText(fragment, preferredIndex: index);
      // Never navigate for footnote markers — aside targets are stripped.
      return (note == null || note.isEmpty) ? '暂无注释' : note;
    }

    await ensureSectionPrepared(index);
    final note = footnoteText(fragment, preferredIndex: index);
    if (note != null) return note;

    final progress = BookEpub.fragmentProgress(
      _sections[index].html,
      fragment,
    );
    readerController.goToLocator(
      BookLocator(sectionIndex: index, progressInSection: progress),
    );
    return null;
  }

  Future<bool> _launchExternalUrl(String url) async {
    var uri = Uri.tryParse(url);
    if (uri == null && url.toLowerCase().startsWith('www.')) {
      uri = Uri.tryParse('https://$url');
    }
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  int _sectionIndexForPath(String targetPath) {
    if (targetPath.isEmpty) return -1;
    final exact = _sections.indexWhere(
      (s) => s.href.toLowerCase() == targetPath,
    );
    if (exact >= 0) return exact;
    // Basename fallback (OPF-relative vs zip-absolute mismatch).
    final base = targetPath.split('/').last;
    return _sections.indexWhere(
      (s) => s.href.toLowerCase().split('/').last == base,
    );
  }

  void _schedulePagination({
    required Size pageSize,
    required TextScaler textScaler,
    required BookReadingTheme theme,
  }) {
    final gen = ++_paginationGen;
    unawaited(
      _paginateProgressively(
        gen: gen,
        pageSize: pageSize,
        textScaler: textScaler,
        theme: theme,
      ),
    );
  }

  Future<void> _paginateProgressively({
    required int gen,
    required Size pageSize,
    required TextScaler textScaler,
    required BookReadingTheme theme,
  }) async {
    // Yield so we never invalidate/notify in the same sync turn as build.
    await Future<void>.delayed(Duration.zero);
    if (gen != _paginationGen) return;
    readerController.invalidatePageMap();

    final paginator = Paginator(
      pageSize: pageSize,
      fontSize: readerController.fontSize,
      lineHeight: readerController.lineHeight,
      textColor: Color(theme.foregroundArgb),
      readBytes: _readBytes,
      textScaler: textScaler,
    );

    final lastIndex = _sections.isEmpty ? 0 : _sections.length - 1;
    var targetSection = readerController.sectionIndex.clamp(0, lastIndex);
    final pendingSection = readerController.pendingJump?.sectionIndex;
    if (pendingSection != null) {
      targetSection = pendingSection.clamp(0, lastIndex);
    }

    final windowed = _isLargeBook;
    final from = windowed
        ? (targetSection - _pageWindowRadius).clamp(0, lastIndex)
        : 0;
    final to = windowed
        ? (targetSection + _pageWindowRadius).clamp(0, lastIndex)
        : lastIndex;

    // Ensure HTML exists before measuring.
    for (var i = from; i <= to; i++) {
      if (gen != _paginationGen) return;
      await ensureSectionPrepared(i);
    }
    if (gen != _paginationGen) return;

    final allPages = <PageSpec>[];
    final startIndices = List<int>.filled(_sections.length, 0);
    var published = false;

    try {
      for (var i = 0; i < _sections.length; i++) {
        if (gen != _paginationGen) return;

        if (i < from || i > to) {
          startIndices[i] = allPages.length;
          continue;
        }

        startIndices[i] = allPages.length;
        final pages = await paginator.paginateSection(_sections[i]);
        if (gen != _paginationGen) return;
        allPages.addAll(pages);

        final reachedTarget = i >= targetSection;
        final finishedWindow = i >= to;
        final finishedBook = !windowed && i == lastIndex;
        if ((!published && reachedTarget) ||
            finishedWindow ||
            finishedBook) {
          // Fill trailing start indices for unpaginated sections.
          for (var j = i + 1; j < _sections.length; j++) {
            startIndices[j] = allPages.length;
          }
          _publishPagination(
            pages: allPages,
            startIndices: startIndices,
            pageSize: pageSize,
            complete: finishedBook,
          );
          published = true;
        }

        await Future<void>.delayed(Duration.zero);
      }

      if (gen == _paginationGen && !published) {
        _publishPagination(
          pages: allPages,
          startIndices: startIndices,
          pageSize: pageSize,
          complete: !windowed,
        );
      }
    } catch (error) {
      if (gen == _paginationGen) {
        debugPrint(
          '[FlutterHtmlBookEngineAdapter] pagination failed: $error',
        );
      }
    }
  }

  void _publishPagination({
    required List<PageSpec> pages,
    required List<int> startIndices,
    required Size pageSize,
    required bool complete,
  }) {
    final result = PaginatorResult(
      pages: List.unmodifiable(pages),
      sectionStartPageIndices: List.unmodifiable(startIndices),
    );
    _pageResult = result;
    _pageSize = pageSize;
    readerController.attachPageMap(
      BookSectionMap(
        startIndices: result.sectionStartPageIndices,
        totalParagraphs: result.pages.length,
      ),
      complete: complete,
    );
  }

  void dispose() {
    _paginationGen++;
    _byteCache.clear();
    _prepared.clear();
    _prepareInflight.clear();
    _packageStylesheets = const [];
    _session = null;
  }

  Future<Uint8List?> _readBytes(String entry) async {
    final cached = _byteCache[entry];
    if (cached != null) return cached;

    final session = _session;
    if (session == null) return null;

    final bytes = await session.readBytes(entry);
    if (bytes != null && bytes.isNotEmpty) {
      _byteCache[entry] = bytes;
    }
    return bytes;
  }
}

/// Hosts reader content and a dismissible footnote bubble.
class _BookEngineView extends StatefulWidget {
  const _BookEngineView({required this.adapter});

  final FlutterHtmlBookEngineAdapter adapter;

  @override
  State<_BookEngineView> createState() => _BookEngineViewState();
}

class _BookEngineViewState extends State<_BookEngineView> {
  String? _footnoteText;

  void _onLinkTap(String url, {String baseHref = ''}) {
    unawaited(() async {
      final note = await widget.adapter.openInternalLink(
        url,
        baseHref: baseHref,
        onLinkError: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
      );
      if (!mounted || note == null) return;
      setState(() => _footnoteText = note);
    }());
  }

  void _dismissFootnote() {
    if (_footnoteText == null) return;
    setState(() => _footnoteText = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.adapter.readerController.readingTheme;
    final fg = Color(theme.foregroundArgb);
    final bg = Color(theme.backgroundArgb);
    final note = _footnoteText;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.adapter._buildContent(context, onLinkTap: _onLinkTap),
        if (note != null) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissFootnote,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.55),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: bg,
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Text(
                      note,
                      style: TextStyle(
                        color: fg,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

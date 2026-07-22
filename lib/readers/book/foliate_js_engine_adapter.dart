import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/book_reading_preferences.dart';
import '../../presentation/controllers/book_reader_controller.dart';
import 'book_rendition_session.dart';
import 'book_models.dart';
import 'book_theme.dart';
import 'foliate_js_bridge.dart';

/// Kaika bridge for the MIT foliate-js reader shipped by Anx Reader.
///
/// Book parsing, pagination, touch direction locking, snap animation and
/// resize reflow stay in the upstream WebView implementation. This adapter is
/// deliberately limited to controller state, CFI persistence and app chrome.
class FoliateJsBookEngineAdapter extends ChangeNotifier {
  FoliateJsBookEngineAdapter({required this.readerController});

  final BookReaderController readerController;

  BookRenditionSession? _session;
  BookRenditionWebLease? _webLease;
  List<String> _sectionHrefs = const [];
  String _initialCfi = '';
  bool _disposed = false;
  int _openGeneration = 0;
  bool _webReady = false;
  bool _metadataAttached = false;
  bool _engineAttached = false;
  bool _firstRelocationReported = false;
  bool _awaitingRendererRecovery = false;
  bool _relocationSuspended = false;
  String? _viewportTransitionCfi;
  double _safeTop = 0;
  double _safeBottom = 0;
  double? _lastFontSize;
  double? _lastLineHeight;
  double? _lastMargin;
  BookReadingTheme? _lastTheme;
  BookReadingMode? _lastMode;
  BookPageTurnEffect? _lastEffect;

  bool get rendererReady => _webReady;

  Future<void> open(String filePath) async {
    final generation = ++_openGeneration;
    try {
      _webReady = false;
      _metadataAttached = false;
      _engineAttached = false;
      _firstRelocationReported = false;
      _awaitingRendererRecovery = false;
      _sectionHrefs = const [];
      _session?.invalidateWebView(_webLease);
      _webLease = null;
      final previous = _session;
      _session = null;
      // Locator DB read and loopback mount run together so the first reader
      // frame is not gated on a serial await chain.
      final locatorFuture = readerController.loadInitialLocator();
      final sessionFuture = () async {
        if (previous != null) await previous.close();
        return BookRenditionSession.open(
          File(filePath),
          onTiming: (timing) => debugPrint('[BookRendition] $timing'),
        );
      }();
      final locator = await locatorFuture;
      if (_disposed || generation != _openGeneration) {
        await sessionFuture.then((session) => session.close());
        return;
      }
      _initialCfi = locator?.cfi ?? '';
      final session = await sessionFuture;
      if (_disposed || generation != _openGeneration) {
        await session.close();
        return;
      }
      _session = session;
      notifyListeners();
    } catch (error) {
      if (_disposed || generation != _openGeneration) return;
      await _session?.close();
      _session = null;
      readerController.engineFailed(error);
    }
  }

  void attach() {
    readerController.attachExternalPageNavigation(
      nextPage: _nextPage,
      previousPage: _previousPage,
    );
    readerController.addListener(_onControllerChanged);
  }

  Widget buildView(BuildContext context) {
    final themeBg = Color(readerController.readingTheme.backgroundArgb);
    final session = _session;
    if (session == null) {
      // Match the reading canvas immediately; never flash a spinner hole.
      return ColoredBox(color: themeBg);
    }
    final media = MediaQuery.of(context);
    _safeTop = media.viewPadding.top;
    _safeBottom = media.viewPadding.bottom;
    return ColoredBox(
      color: themeBg,
      child: _FoliateJsEngineView(
        adapter: this,
        readerUri: _readerUri(session),
      ),
    );
  }

  void openTocEntry(BookTocEntry entry) {
    if (entry.sectionIndex == null) return;
    final href = entry.fragment == null || entry.fragment!.isEmpty
        ? entry.href
        : '${entry.href}#${entry.fragment}';
    if (_webReady && href.isNotEmpty) {
      // Keep fragment and Foliate history semantics intact. The relocation
      // callback updates controller/DB after the rendition reaches the target.
      unawaited(_evaluate('window.goToHref(${jsonEncode(href)})'));
      return;
    }
    readerController.goToTocEntry(entry);
  }

  Uri _readerUri(BookRenditionSession session) {
    return session.readerUri({
      'importing': jsonEncode(false),
      'url': jsonEncode(session.bookUri.toString()),
      'initialCfi': jsonEncode(_initialCfi),
      'style': jsonEncode(_styleJson()),
      'readingRules': jsonEncode({
        'convertChineseMode': 'none',
        'bionicReadingMode': false,
      }),
    });
  }

  void _nextPage() {
    if (!_webReady) return;
    unawaited(_evaluate('window.nextPage()'));
  }

  void _previousPage() {
    if (!_webReady) return;
    unawaited(_evaluate('window.prevPage()'));
  }

  void _onControllerChanged() {
    if (!_webReady || _disposed) return;
    _applyPreferences();
    _applyPendingJump();
  }

  Future<void> _onLoadEnd(BookRenditionWebLease lease) async {
    if (_metadataAttached || _disposed || !lease.isCurrent) return;
    _metadataAttached = true;
    _session?.mark('renderer-load-end');
    debugPrint('[FoliateJs] onLoadEnd');
    try {
      final raw = await _evaluateFor(lease, '''
        JSON.stringify({
          sections: (reader.view.book.sections || []).map((section, index) =>
            String(section.href || section.id || index)),
          toc: reader.view.book.toc || []
        })
      ''');
      if (!lease.isCurrent || _disposed) return;
      if (raw is! String) throw Exception('Anx Reader 返回了无效的 EPUB 元数据');
      final publication = FoliatePublicationSnapshot.fromJsonString(raw);
      if (publication.sectionHrefs.isEmpty) {
        throw Exception('EPUB 没有可阅读的正文');
      }

      _sectionHrefs = publication.sectionHrefs;
      final titles = List<String>.generate(
        _sectionHrefs.length,
        (index) => '第 ${index + 1} 节',
      );
      final tocEntries = <BookTocEntry>[];
      _flattenToc(publication.toc, 0, tocEntries, titles);

      if (!_engineAttached) {
        await readerController.attachEngine(
          BookSectionMap(
            startIndices: List.generate(_sectionHrefs.length, (index) => index),
            totalParagraphs: _sectionHrefs.length,
          ),
          titles,
          tocEntries: tocEntries,
        );
        if (!lease.isCurrent || _disposed) return;
        _engineAttached = true;
      }
      if (_disposed) return;

      _webReady = true;
      _session?.mark('publication-attached');
      debugPrint('[FoliateJs] reader ready');
      // The complete style was already supplied in the initial URL. Priming
      // the snapshot avoids an identical changeStyle() and a second reflow on
      // the first visible frame.
      _rememberPreferenceState();
      final pending = readerController.pendingJump;
      if (pending?.cfi == _initialCfi && _initialCfi.isNotEmpty) {
        readerController.clearPendingJump();
      } else {
        _applyPendingJump();
      }
      notifyListeners();
    } catch (error) {
      if (!lease.isCurrent || _disposed) return;
      _metadataAttached = false;
      readerController.engineFailed(error);
    }
  }

  void _flattenToc(
    List<FoliateTocNode> nodes,
    int depth,
    List<BookTocEntry> output,
    List<String> titles,
  ) {
    for (final node in nodes) {
      final title = node.title;
      final href = node.href;
      final sectionIndex = _sectionIndexFromHref(href);
      if (title.isNotEmpty) {
        if (sectionIndex != null && titles[sectionIndex].startsWith('第 ')) {
          titles[sectionIndex] = title;
        }
        output.add(
          BookTocEntry(
            title: title,
            href: href.split('#').first,
            fragment: href.contains('#')
                ? href.split('#').skip(1).join('#')
                : null,
            sectionIndex: sectionIndex,
            depth: depth.clamp(0, 12),
          ),
        );
      }
      _flattenToc(node.children, depth + 1, output, titles);
    }
  }

  void _onRelocated(FoliateRelocation relocation) {
    if (_sectionHrefs.isEmpty || !_webReady || _relocationSuspended) return;
    final sectionIndex =
        _sectionIndexFromCfi(relocation.cfi) ??
        _sectionIndexFromHref(relocation.chapterHref) ??
        0;
    if (_awaitingRendererRecovery) {
      _awaitingRendererRecovery = false;
      _session?.mark('renderer-recovered');
    } else if (!_firstRelocationReported) {
      _firstRelocationReported = true;
      _session?.mark('first-relocation');
    }
    readerController.reportRenditionLocation(
      sectionIndex: sectionIndex.clamp(0, _sectionHrefs.length - 1),
      progress: relocation.percentage,
      cfi: relocation.cfi,
      chapterTitle: relocation.chapterTitle,
      bookCurrentPage: relocation.bookCurrentPage,
      bookTotalPages: relocation.bookTotalPages,
    );
  }

  void _onClick(FoliateViewportClick click) {
    if (readerController.readingMode == BookReadingMode.page) {
      if (click.x < 0.25) {
        _previousPage();
      } else if (click.x > 0.75) {
        _nextPage();
      } else {
        readerController.toggleChrome();
      }
    } else {
      readerController.toggleChrome();
    }
  }

  void _applyPendingJump() {
    final pending = readerController.pendingJump;
    if (pending == null) return;
    if (pending.cfi?.isNotEmpty ?? false) {
      unawaited(_evaluate('window.goToCfi(${jsonEncode(pending.cfi)})'));
    } else if (pending.sectionIndex >= 0 &&
        pending.sectionIndex < _sectionHrefs.length) {
      unawaited(
        _evaluate(
          'reader.view.renderer.goTo({index:${pending.sectionIndex},'
          'anchor:()=>${pending.progressInSection}})',
        ),
      );
    }
    readerController.clearPendingJump();
  }

  void _applyPreferences({bool force = false}) {
    final fontSize = readerController.fontSize;
    final lineHeight = readerController.lineHeight;
    final margin = readerController.margin;
    final theme = readerController.readingTheme;
    final mode = readerController.readingMode;
    final effect = readerController.pageTurnEffect;
    if (!force &&
        fontSize == _lastFontSize &&
        lineHeight == _lastLineHeight &&
        margin == _lastMargin &&
        theme == _lastTheme &&
        mode == _lastMode &&
        effect == _lastEffect) {
      return;
    }
    _rememberPreferenceState();
    unawaited(_evaluate('window.changeStyle(${jsonEncode(_styleJson())})'));
  }

  void _rememberPreferenceState() {
    _lastFontSize = readerController.fontSize;
    _lastLineHeight = readerController.lineHeight;
    _lastMargin = readerController.margin;
    _lastTheme = readerController.readingTheme;
    _lastMode = readerController.readingMode;
    _lastEffect = readerController.pageTurnEffect;
  }

  void _rendererProcessGone(
    RenderProcessGoneDetail detail,
    BookRenditionWebLease? lease,
  ) {
    if (_disposed || lease == null || !lease.isCurrent) return;
    debugPrint('[FoliateJs] renderer process gone: $detail');
    final currentCfi =
        _viewportTransitionCfi ?? readerController.currentLocator.cfi;
    if (currentCfi != null && currentCfi.isNotEmpty) {
      _initialCfi = currentCfi;
    }
    _awaitingRendererRecovery = true;
    _session?.mark('renderer-gone');
    _session?.invalidateWebView(lease);
    _webLease = null;
    _webReady = false;
    _metadataAttached = false;
    notifyListeners();
  }

  Future<void> _openExternalLink(List<dynamic> arguments) async {
    final link = FoliateExternalLink.fromHandlerArguments(arguments);
    final uri = link?.uri;
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[FoliateJs] open external link failed: $uri ($error)');
    }
  }

  void _beginViewportTransition() {
    if (_disposed || _relocationSuspended) return;
    _viewportTransitionCfi = readerController.currentLocator.cfi;
    _relocationSuspended = true;
  }

  Future<void> _endViewportTransition() async {
    if (_disposed || !_relocationSuspended) return;
    final cfi = _viewportTransitionCfi;
    if (_webReady && cfi != null && cfi.isNotEmpty) {
      await _evaluate('window.goToCfi(${jsonEncode(cfi)})');
      // Ignore the transient relocation emitted while the paginator is still
      // snapping to the preserved anchor. The controller already owns this
      // exact CFI, so accepting it again is unnecessary.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (_disposed) return;
    _relocationSuspended = false;
    _viewportTransitionCfi = null;
  }

  Map<String, Object?> _styleJson() {
    final theme = readerController.readingTheme;
    final turnStyle = readerController.readingMode == BookReadingMode.scroll
        ? 'scroll'
        : readerController.pageTurnEffect.resolved == BookPageTurnEffect.none
        ? 'noAnimation'
        : 'slide';
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    // Foliate `gap` is the TOTAL gutter; each side gets gap/2 in padding.
    // Mobile: ~5% per side at margin=24. Desktop: milder — single column is
    // already centered by the paginator grid, so large gap looks sparse.
    final sideMargin = mobile
        ? (6 + readerController.margin / 6).clamp(8.0, 16.0)
        : (3 + readerController.margin / 8).clamp(4.0, 8.0);
    // Meta band for chapter / progress. Phone needs more air; desktop less.
    // Desktop top gets +20 so the chapter label sits clearer under the title bar.
    final topMetaBand = mobile ? 50.0 : 52.0;
    final bottomMetaBand = mobile ? 50.0 : 32.0;
    return {
      'fontSize': readerController.fontSize / 16,
      // WeChat Reading–like sans stack for the default reading face.
      'fontName': BookReadingTheme.cssReadingFontFamily,
      'fontPath': '',
      'fontWeight': 400,
      'letterSpacing': 0,
      'spacing': readerController.lineHeight,
      // Indent + mild paragraph gap (WeChat-like air, not web-article gaps).
      'paragraphSpacing': 0.35,
      'textIndent': 2,
      'fontColor': _cssColor(Color(theme.foregroundArgb)),
      'backgroundColor': _cssColor(Color(theme.backgroundArgb)),
      'linkColor': _cssColor(Color(theme.linkColorArgb)),
      'headingColor': _cssColor(Color(theme.headingColorArgb)),
      'topMargin': _safeTop + topMetaBand,
      'bottomMargin': _safeBottom + bottomMetaBand,
      'sideMargin': sideMargin,
      'justify': true,
      'hyphenate': false,
      'pageTurnStyle': turnStyle,
      // Keep Foliate auto columns (desktop may spread to two).
      'maxColumnCount': 0,
      'columnThreshold': 720,
      'writingMode': 'horizontal-tb',
      'textAlign': 'justify',
      'backgroundImage': 'none',
      'bgimgBlur': 0,
      'bgimgOpacity': 1,
      'bgimgFit': 'cover',
      'allowScript': false,
      'customCSS': '',
      'customCSSEnabled': false,
      'useBookStyles': false,
      'headingFontSize': 1,
      'headingScales': {
        for (final tag in const ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'])
          tag: bookHeadingScale(tag),
      },
      'headingMargins': {
        for (final tag in const ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'])
          tag: {
            'top': bookHeadingMargins(tag, 1).top,
            'bottom': bookHeadingMargins(tag, 1).bottom,
          },
      },
      'codeHighlightTheme': 'off',
    };
  }

  String _cssColor(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2)}';
  }

  int? _sectionIndexFromHref(String? href) {
    if (href == null || href.isEmpty) return null;
    final target = _cleanHref(href);
    final index = _sectionHrefs.indexWhere((value) {
      final section = _cleanHref(value);
      return section == target ||
          target.endsWith('/$section') ||
          section.endsWith('/$target');
    });
    return index < 0 ? null : index;
  }

  String _cleanHref(String value) {
    final path = value.split('#').first;
    try {
      return Uri.decodeFull(path);
    } catch (_) {
      return path;
    }
  }

  int? _sectionIndexFromCfi(String cfi) {
    final match = RegExp(r'^epubcfi\(/6/(\d+)').firstMatch(cfi);
    final step = int.tryParse(match?.group(1) ?? '');
    if (step == null || step < 2) return null;
    final index = step ~/ 2 - 1;
    return index >= 0 && index < _sectionHrefs.length ? index : null;
  }

  Future<dynamic> _evaluate(String source) async {
    final lease = _webLease;
    if (lease == null) return null;
    return _evaluateFor(lease, source);
  }

  Future<dynamic> _evaluateFor(BookRenditionWebLease lease, String source) {
    final session = _session;
    if (session == null || _disposed) return Future.value();
    return session.evaluate(lease, source);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _openGeneration++;
    readerController.removeListener(_onControllerChanged);
    readerController.detachExternalPageNavigation();
    _session?.invalidateWebView(_webLease);
    _webLease = null;
    unawaited(_session?.close());
    _session = null;
    super.dispose();
  }
}

class _FoliateJsEngineView extends StatefulWidget {
  const _FoliateJsEngineView({required this.adapter, required this.readerUri});

  final FoliateJsBookEngineAdapter adapter;
  final Uri readerUri;

  @override
  State<_FoliateJsEngineView> createState() => _FoliateJsEngineViewState();
}

class _FoliateJsEngineViewState extends State<_FoliateJsEngineView>
    with WidgetsBindingObserver {
  bool _rendererGone = false;
  bool _reloadScheduled = false;
  Timer? _viewportTimer;
  BookRenditionWebLease? _lease;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
    widget.adapter._session?.invalidateWebView(_lease);
    if (identical(widget.adapter._webLease, _lease)) {
      widget.adapter._webLease = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_rendererGone) _scheduleRendererReload();
      _scheduleViewportResume(const Duration(milliseconds: 240));
    } else {
      _viewportTimer?.cancel();
      widget.adapter._beginViewportTransition();
    }
  }

  @override
  void didChangeMetrics() {
    widget.adapter._beginViewportTransition();
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _scheduleViewportResume(const Duration(milliseconds: 240));
    }
  }

  void _scheduleViewportResume(Duration delay) {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(delay, () {
      if (!mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      unawaited(widget.adapter._endViewportTransition());
    });
  }

  void _handleRendererGone(RenderProcessGoneDetail detail) {
    widget.adapter._rendererProcessGone(detail, _lease);
    if (!mounted) return;
    setState(() => _rendererGone = true);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _scheduleRendererReload();
    }
  }

  void _scheduleRendererReload() {
    if (_reloadScheduled) return;
    _reloadScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _reloadScheduled = false;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      setState(() => _rendererGone = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_rendererGone) {
      return ColoredBox(
        color: Color(
          widget.adapter.readerController.readingTheme.backgroundArgb,
        ),
      );
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(widget.readerUri)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: true,
        useHybridComposition: true,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (controller) {
        final session = widget.adapter._session;
        if (session == null || session.isClosed) return;
        final lease = session.attachWebView(
          (source) => controller.evaluateJavascript(source: source),
        );
        _lease = lease;
        widget.adapter._webLease = lease;
        widget.adapter._webReady = false;
        widget.adapter._metadataAttached = false;
        controller.addJavaScriptHandler(
          handlerName: 'onLoadEnd',
          callback: (_) {
            // Return to JavaScript before evaluating metadata. Android WebView
            // serializes bridge calls; awaiting a nested evaluation here would
            // deadlock the onLoadEnd call.
            unawaited(widget.adapter._onLoadEnd(lease));
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onRelocated',
          callback: (arguments) {
            if (!lease.isCurrent) return null;
            final relocation = FoliateRelocation.fromHandlerArguments(
              arguments,
            );
            if (relocation != null) widget.adapter._onRelocated(relocation);
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onClick',
          callback: (arguments) {
            if (!lease.isCurrent) return null;
            final click = FoliateViewportClick.fromHandlerArguments(arguments);
            if (click != null) widget.adapter._onClick(click);
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onExternalLink',
          callback: (arguments) {
            if (!lease.isCurrent) return null;
            unawaited(widget.adapter._openExternalLink(arguments));
            return null;
          },
        );
        for (final name in const [
          'renderAnnotations',
          'onSetToc',
          'onSelectionEnd',
          'onSelectionCleared',
          'onAnnotationClick',
          'onImageClick',
          'onFootnoteClose',
          'onPullUp',
          'handleBookmark',
          'translateText',
          'onPushState',
          'onSearch',
          'onMetadata',
        ]) {
          controller.addJavaScriptHandler(
            handlerName: name,
            callback: (_) => null,
          );
        }
      },
      onConsoleMessage: (_, message) {
        if (_lease?.isCurrent != true) return;
        if (kDebugMode) debugPrint('[FoliateJs] ${message.message}');
      },
      onReceivedError: (_, request, error) {
        if (_lease?.isCurrent != true ||
            request.isForMainFrame != true ||
            widget.adapter._webReady) {
          return;
        }
        widget.adapter.readerController.engineFailed(
          Exception('阅读内核加载失败：${error.description}'),
        );
      },
      onRenderProcessGone: (_, detail) => _handleRendererGone(detail),
    );
  }
}

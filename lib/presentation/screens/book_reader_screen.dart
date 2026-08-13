import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../ai/ai_chat_store.dart';
import '../../ai/ai_action_journal.dart';
import '../../ai/ai_graph_store.dart';
import '../../ai/ai_workflow_contract.dart';
import '../../app/book_reading_preferences.dart';
import '../../core/platform_window.dart';
import '../../core/text_editing_focus.dart';
import '../../core/theme.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_time_tracker.dart';
import '../../library/storage/library_paths.dart';
import '../../readers/book/book_open_trace.dart';
import '../../readers/book/book_reader_capabilities.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/foliate_js_engine_adapter.dart';
import '../controllers/ai_settings_controller.dart';
import '../controllers/book_reader_controller.dart';
import '../navigation/app_route_observer.dart';
import '../navigation/cover_open_page_route.dart';
import '../widgets/ai_settings_scope.dart';
import '../widgets/app_overlays.dart';
import '../widgets/reader/book_annotation_note_sheet.dart';
import '../widgets/reader/book_cover_hero.dart';
import '../widgets/reader/book_image_viewer.dart';
import '../widgets/reader/book_nav_drawer.dart';
import '../widgets/reader/book_page_meta_overlay.dart';
import '../widgets/reader/book_reader_chrome.dart';
import '../widgets/reader/book_search_panel.dart';
import '../widgets/reader/book_selection_menu_overlay.dart';
import '../widgets/reader/reader_waiting_cover.dart';

/// Full-screen reflow book reader.
///
/// Open UX: the library cover travels along a slight arc while growing into
/// the waiting frame; Foliate then dissolves that cover into the text. Close
/// reverses the same path back to the card.
class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.database,
    required this.item,
    this.readingPreferences,
    this.aiSettings,
    this.sourceCoverRect,
  });

  final AppDatabase database;
  final ReadingItem item;
  final BookReadingPreferences? readingPreferences;

  /// Optional; when null the screen resolves [AiSettingsScope] from context.
  final AiSettingsController? aiSettings;

  /// Global bounds of the tapped cover; used to keep the waiting frame
  /// aligned with the flying cover after the route animation settles.
  final Rect? sourceCoverRect;

  static Future<void> open(
    BuildContext context, {
    required AppDatabase database,
    required ReadingItem item,
    BookReadingPreferences? readingPreferences,
    Rect? sourceCoverRect,
  }) {
    // Resolve from the navigator context (fully mounted) so initState of the
    // new route does not miss the inherited scope.
    final aiSettings = AiSettingsScope.maybeOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final captured =
        sourceCoverRect ?? CoverFlightHandle.resolve(context, item.id);
    final source = reduceMotion ? null : captured;
    final backdrop = Color(
      readingPreferences?.readingTheme.backgroundArgb ??
          BookReadingTheme.paper.backgroundArgb,
    );
    return Navigator.of(context, rootNavigator: true).push<void>(
      CoverOpenPageRoute<void>(
        sourceRect: source,
        coverPath: item.coverPath,
        title: item.title,
        backdropColor: backdrop,
        itemId: item.id,
        builder: (context) {
          return BookReaderScreen(
            database: database,
            item: item,
            readingPreferences: readingPreferences,
            aiSettings: aiSettings ?? AiSettingsScope.maybeOf(context),
            sourceCoverRect: source,
          );
        },
      ),
    );
  }

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final BookReaderController _controller;
  late final FoliateJsBookEngineAdapter _engine;
  late final ReadingTimeTracker _timeTracker;
  late final FocusNode _focusNode;
  late final AnimationController _reveal;
  bool _showReveal = true;
  bool _revealStarted = false;
  bool _lastTtsPlaying = false;
  ModalRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  bool _allowEngineView = false;
  bool _closing = false;
  bool _preparedClose = false;
  bool _openScheduled = false;

  @override
  void initState() {
    super.initState();
    final scrollModeEnabled =
        BookReaderCapabilities.supportsScrollModeOnCurrentPlatform;
    _controller = BookReaderController(
      database: widget.database,
      item: widget.item,
      readingPreferences: widget.readingPreferences,
      aiSettings: widget.aiSettings ?? AiSettingsScope.maybeOf(context),
      scrollModeEnabled: scrollModeEnabled,
    );
    // AI JSON stores wait until Foliate has painted. Attaching in initState
    // raced the EPUB open on disk and rebuilt the WebView tree mid-load.
    if (!scrollModeEnabled &&
        widget.readingPreferences?.readingMode == BookReadingMode.scroll) {
      unawaited(
        widget.readingPreferences?.setReadingMode(BookReadingMode.page),
      );
    }
    _engine = FoliateJsBookEngineAdapter(readerController: _controller);
    _engine.addListener(_onBookEngineTick);
    _controller.attachPlatformFocusClearer(_engine.clearPlatformFocus);
    _controller.annotations.onOpenNoteEditor = _presentNoteEditor;
    _controller.addListener(_onBookControllerTick);
    _timeTracker = ReadingTimeTracker(
      database: widget.database,
      itemId: widget.item.id,
      kind: ReaderKind.book,
    )..attach();
    _onBookControllerTick();
    _onBookEngineTick();
    _focusNode = FocusNode();
    // Phase A (~first half): cover dissolves into reading backdrop.
    // Phase B (~second half): backdrop eases away into the text.
    _reveal = AnimationController(
      vsync: this,
      // Duration may shrink to zero when reduce-motion is on
      // (see [didChangeDependencies]).
      duration: const Duration(milliseconds: 420),
    );
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showReveal = false);
      }
    });
    _engine.attach();
    // When AI/search/note TextFields take focus, drop WKWebView first-responder
    // so Cmd/Ctrl+C·V reach Flutter instead of the platform view.
    FocusManager.instance.addListener(_onGlobalFocusChange);
    // File I/O + WebView must not share the first cover-flight frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback(_startDeferredOpen);
    });
  }

  bool _aiStoresAttachStarted = false;
  LibraryPaths? _libraryPaths;
  BookOpenTrace? _openTrace;

  Future<void> _attachAiStores() async {
    if (_aiStoresAttachStarted) return;
    _aiStoresAttachStarted = true;
    try {
      final paths = _libraryPaths ?? await LibraryPaths.forApp();
      if (!mounted) return;
      _controller.attachChatHistoryStore(
        JsonAiChatHistoryStore(paths.aiChatDirectory),
      );
      _controller.attachAiGraphStore(AiGraphStore(paths.aiGraphDirectory));
      _controller.attachAiActionJournalStore(
        JsonAiActionJournalStore(paths.aiActionJournalDirectory),
      );
      _controller.attachAiWorkflowStores(
        checkpoints: JsonAiWorkflowCheckpointStore(
          paths.aiWorkflowCheckpointDirectory,
        ),
        artifacts: JsonAiArtifactRepository(paths.aiArtifactDirectory),
      );
      _controller.aiWorkspace.markAiStoresReady(ready: true);
      _openTrace?.mark('ai-stores-ready');
    } catch (error) {
      debugPrint('[AI] failed to attach reader stores: $error');
      _openTrace?.mark('ai-stores-failed', detail: '$error');
      if (!mounted) return;
      _controller.aiWorkspace.markAiStoresReady(
        ready: false,
        error: 'AI 本地存储未就绪，请重新打开本书后再试',
      );
    }
  }

  Timer? _platformFocusClearTimer;
  bool _primaryWasTextEditing = false;

  /// When a Flutter [TextField] gains focus, optionally nudge the book
  /// WebView to resign first-responder so desktop paste shortcuts work.
  ///
  /// Critical rules (macOS + InAppWebView):
  /// - Only on the **edge** into text editing, never on every FocusManager tick
  ///   (IME / dictation fire many ticks and clearFocus races composition).
  /// - Defer to a post-frame callback so we never schedule rebuilds while
  ///   semantics/paint is still flushing (see "Build scheduled during frame"
  ///   when TextEditingController notifies mid-drawFrame).
  /// - Skip entirely when a root modal (AI side panel / sheets) is open — the
  ///   barrier already owns input; clearing the WebView under it only hurts.
  void _onGlobalFocusChange() {
    if (!mounted) return;
    final editing = primaryFocusIsTextEditing();
    if (!editing) {
      _primaryWasTextEditing = false;
      _platformFocusClearTimer?.cancel();
      _platformFocusClearTimer = null;
      return;
    }
    if (_primaryWasTextEditing) return;
    _primaryWasTextEditing = true;

    // AI panel / search / note sheets are root routes above the reader.
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      return;
    }

    _platformFocusClearTimer?.cancel();
    _platformFocusClearTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || !primaryFocusIsTextEditing()) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) return;
      // Never touch platform focus during an active frame/semantics flush.
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase != SchedulerPhase.idle &&
          phase != SchedulerPhase.postFrameCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !primaryFocusIsTextEditing()) return;
          unawaited(_engine.clearPlatformFocus());
        });
        return;
      }
      unawaited(_engine.clearPlatformFocus());
    });
  }

  /// TTS playback must not accumulate reading time (PRODUCT §4.8).
  void _onBookControllerTick() {
    final playing = _controller.ttsPlaying;
    if (playing != _lastTtsPlaying) {
      _lastTtsPlaying = playing;
      _timeTracker.setCountingEnabled(!playing);
    }
    if (_controller.openError != null) {
      _timeTracker.setContentReady(false);
    }
  }

  void _onBookEngineTick() {
    _timeTracker.setContentReady(
      _engine.rendererReady && _controller.openError == null,
    );
    if (_engine.rendererReady || _controller.openError != null) {
      unawaited(_attachAiStores());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
      _timeTracker.setRouteVisible(route?.isCurrent ?? true);
    }
    // Re-bind if initState missed the scope (route edge cases).
    _controller.bindAiSettings(
      widget.aiSettings ?? AiSettingsScope.maybeOf(context),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _reveal.duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 420);
    final routeAnim = route?.animation;
    if (routeAnim != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation?.removeListener(_onRouteAnimationTick);
      _routeAnimation = routeAnim;
      _routeAnimation?.addStatusListener(_onRouteAnimationStatus);
      _routeAnimation?.addListener(_onRouteAnimationTick);
    }
  }

  void _startDeferredOpen(Duration _) {
    if (!mounted || _closing || _openScheduled) return;
    _openScheduled = true;
    unawaited(_openBookFile());
    _onRouteAnimationTick();
  }

  void _onRouteAnimationTick() {
    if (_allowEngineView || _closing || !mounted) return;
    final anim = _routeAnimation;
    if (anim == null ||
        anim.isCompleted ||
        anim.value >= 0.72 ||
        !CoverFlightGeometry.isUsable(widget.sourceCoverRect)) {
      _mountEngineView();
    }
  }

  void _mountEngineView() {
    if (!mounted || _allowEngineView || _closing) return;
    setState(() => _allowEngineView = true);
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      _mountEngineView();
      _maybeStartReveal(_engine.rendererReady);
    }
  }

  bool get _routeFlightActive {
    final anim = _routeAnimation;
    if (anim == null) return false;
    return !anim.isCompleted && !anim.isDismissed;
  }

  Future<void> _openBookFile() async {
    final item = widget.item;
    final trace = BookOpenTrace(title: item.title, format: item.format);
    _openTrace = trace;
    trace.mark('open-start');
    final paths = await LibraryPaths.forApp();
    _libraryPaths = paths;
    trace.mark('paths-ready');
    final resolved = await paths.resolveExistingPath(
      item.filePath,
      contentHash: item.contentHash,
    );
    if (!mounted) return;
    trace.mark(
      'file-resolved',
      detail: resolved == null ? 'missing-fallback' : 'ok',
    );
    await _engine.open(resolved ?? item.filePath, trace: trace);
  }

  void _maybeStartReveal(bool contentReady) {
    if (!contentReady || _revealStarted || !_showReveal) return;
    if (_routeFlightActive) return;
    _revealStarted = true;
    _openTrace?.mark('cover-reveal-started');
    unawaited(_reveal.forward());
  }

  bool get _needsPreparedClose {
    return CoverFlightGeometry.isUsable(widget.sourceCoverRect) &&
        !MediaQuery.disableAnimationsOf(context);
  }

  Future<void> _prepareCoverClose() async {
    if (_preparedClose) return;
    _preparedClose = true;
    _reveal.stop();
    _reveal.value = 0;
    if (mounted) {
      setState(() {
        _closing = true;
        _allowEngineView = false;
        _showReveal = true;
      });
    }
    final route = ModalRoute.of(context);
    if (route is CoverOpenPageRoute<void>) {
      route.preparePreviousRoute();
    }
  }

  void _exit() {
    unawaited(_controller.stopTts());
    if (_controller.chromeVisible) _controller.hideChrome();
    unawaited(_popReader());
  }

  Future<void> _popReader() async {
    if (_needsPreparedClose) {
      await _prepareCoverClose();
      if (!mounted) return;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  Widget _waitingCover(BuildContext context) {
    final source = widget.sourceCoverRect;
    if (!CoverFlightGeometry.isUsable(source)) {
      return ReaderWaitingCover(
        coverPath: widget.item.coverPath,
        title: widget.item.title,
      );
    }
    final dest = CoverFlightGeometry.destinationRect(
      viewport: MediaQuery.sizeOf(context),
      safePadding: MediaQuery.paddingOf(context),
      aspectRatio: source!.size.aspectRatio,
      shortViewport: context.appIsShortViewport,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: dest,
          child: CoverFlightLeaf(
            coverPath: widget.item.coverPath,
            title: widget.item.title,
          ),
        ),
      ],
    );
  }

  void _openToc() => _scaffoldKey.currentState?.openDrawer();

  void _presentNoteEditor(BookAnnotation note) {
    if (!mounted) return;
    // Open immediately — post-frame deferral felt like lag on mobile taps.
    unawaited(
      showBookAnnotationNoteSheet(
        context,
        controller: _controller,
        cfi: note.cfi,
        selectedText: note.selectedText ?? '',
        initialNote: note.note ?? '',
        type: note.type,
        colorCss: note.colorCss,
        // Autofocus pulls the keyboard and resizes the WebView (jitter).
        autofocus: false,
      ),
    );
  }

  void _openNoteFromDrawer(BookAnnotation note) {
    _controller.annotations.goToAnnotation(note);
    _presentNoteEditor(note);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Search / AI / notes / any TextField: do not steal Space, T, arrows, etc.
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != node && focusIsTextEditing(primary)) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_controller.search.imageOpen) {
        _controller.search.closeImage();
        return KeyEventResult.handled;
      }
      if (_controller.search.open) {
        _controller.search.closeSearch();
        return KeyEventResult.handled;
      }
      if (_controller.annotations.selectionMenu != null) {
        _controller.annotations.clearSelectionMenu();
        return KeyEventResult.handled;
      }
      if (_controller.chromeVisible) {
        _controller.hideChrome();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      _openToc();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.equal ||
        event.logicalKey == LogicalKeyboardKey.add ||
        event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _controller.preferences.changeFontSize(2);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.minus ||
        event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _controller.preferences.changeFontSize(-2);
      return KeyEventResult.handled;
    }

    final isPage = _controller.preferences.readingMode == BookReadingMode.page;
    if (isPage) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.pageUp) {
        _controller.goPreviousPage();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.pageDown ||
          event.logicalKey == LogicalKeyboardKey.space) {
        _controller.goNextPage();
        return KeyEventResult.handled;
      }
    } else {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _controller.goPreviousSection();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _controller.goNextSection();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final theme = _controller.preferences.readingTheme;
            final bg = Color(theme.backgroundArgb);

            final ttsMessage = _controller.ttsUserMessage;
            if (ttsMessage != null && ttsMessage.isNotEmpty) {
              _controller.ttsUserMessage = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                showAppSnackBar(context, ttsMessage);
              });
            }

            if (_controller.openError != null) {
              return Scaffold(
                backgroundColor: bg,
                body: _ErrorBody(onBack: _exit, theme: theme),
              );
            }

            // Reveal as soon as Foliate has painted; chrome still waits on
            // controller attach (TOC / bookmarks / scrub).
            final contentReady = _engine.rendererReady;
            if (contentReady && !_revealStarted && _showReveal) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _maybeStartReveal(true);
              });
            }

            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            final chromeAnim = reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200);

            return PopScope(
              canPop: !_needsPreparedClose || _preparedClose,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                _exit();
              },
              child: Focus(
                focusNode: _focusNode,
                autofocus: _controller.isReady && !_showReveal,
                onKeyEvent: _handleKeyEvent,
                child: Scaffold(
                  key: _scaffoldKey,
                  resizeToAvoidBottomInset: false,
                  drawerEnableOpenDragGesture: false,
                  drawer: _controller.isReady
                      ? BookNavDrawer(
                          controller: _controller,
                          onOpenTocEntry: _engine.openTocEntry,
                          onOpenNote: _openNoteFromDrawer,
                        )
                      : null,
                  backgroundColor: bg,
                  body: Stack(
                    fit: StackFit.expand,
                    children: [
                      _allowEngineView && !_closing
                          ? _engine.buildView(context)
                          : ColoredBox(color: bg),
                      if (_showReveal)
                        IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _reveal,
                            builder: (context, _) {
                              final coverT = Curves.easeOutCubic.transform(
                                const Interval(
                                  0,
                                  0.52,
                                ).transform(_reveal.value),
                              );
                              final pageT = Curves.easeInOut.transform(
                                const Interval(
                                  0.48,
                                  1,
                                ).transform(_reveal.value),
                              );
                              final coverChild = _waitingCover(context);
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Reading backdrop under the cover; holds until
                                  // the cover is gone, then eases into the text.
                                  Opacity(
                                    opacity: (1 - pageT).clamp(0.0, 1.0),
                                    child: ColoredBox(color: bg),
                                  ),
                                  Opacity(
                                    opacity: (1 - coverT).clamp(0.0, 1.0),
                                    child: reduceMotion
                                        ? coverChild
                                        : Transform.scale(
                                            scale: 1 + 0.1 * coverT,
                                            filterQuality: FilterQuality.low,
                                            child: coverChild,
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      if (_controller.isReady && !_showReveal) ...[
                        BookPageMetaOverlay(controller: _controller),
                        BookSelectionMenuOverlay(controller: _controller),
                        IgnorePointer(
                          ignoring: !_controller.chromeVisible,
                          child: AnimatedOpacity(
                            opacity: _controller.chromeVisible ? 1 : 0,
                            duration: chromeAnim,
                            curve: Curves.easeOut,
                            child: BookReaderChrome(
                              controller: _controller,
                              onBack: _exit,
                              onOpenToc: _openToc,
                            ),
                          ),
                        ),
                        if (_controller.search.open)
                          BookSearchPanel(
                            controller: _controller.search,
                            readingTheme: _controller.preferences.readingTheme,
                          ),
                        if (_controller.search.imageOpen)
                          BookImageViewer(controller: _controller.search),
                      ],
                      // Above WebView + chrome SafeArea pad so the title band
                      // still moves the window (Platform View eats background drag).
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ReaderWindowDragHandle(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _platformFocusClearTimer?.cancel();
    appRouteObserver.unsubscribe(this);
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    _controller.removeListener(_onBookControllerTick);
    _engine.removeListener(_onBookEngineTick);
    unawaited(_timeTracker.detach());
    _controller.annotations.onOpenNoteEditor = null;
    _controller.detachPlatformFocusClearer();
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _routeAnimation?.removeListener(_onRouteAnimationTick);
    _reveal.dispose();
    _focusNode.dispose();
    _engine.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didPush() => _timeTracker.setRouteVisible(true);

  @override
  void didPopNext() => _timeTracker.setRouteVisible(true);

  @override
  void didPushNext() => _timeTracker.setRouteVisible(false);

  @override
  void didPop() => _timeTracker.setRouteVisible(false);
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onBack, required this.theme});

  final VoidCallback onBack;
  final BookReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final fg = Color(theme.foregroundArgb);
    final fgMuted = theme.isDark
        ? const Color(0x99F2F2F4)
        : const Color(0x991C1C1E);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '无法打开此书',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '文件可能已损坏、已移动，或格式不受支持。',
                textAlign: TextAlign.center,
                style: TextStyle(color: fgMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onBack, child: const Text('返回')),
            ],
          ),
        ),
      ),
    );
  }
}

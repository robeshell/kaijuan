import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ai_chat_store.dart';
import '../../ai/ai_graph_store.dart';
import '../../app/book_reading_preferences.dart';
import '../../core/platform_window.dart';
import '../../core/text_editing_focus.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_time_tracker.dart';
import '../../library/storage/library_paths.dart';
import '../../readers/book/book_reader_capabilities.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/foliate_js_engine_adapter.dart';
import '../controllers/ai_settings_controller.dart';
import '../controllers/book_reader_controller.dart';
import '../navigation/app_route_observer.dart';
import '../widgets/ai_settings_scope.dart';
import '../widgets/app_overlays.dart';
import '../widgets/reader/book_annotation_note_sheet.dart';
import '../widgets/reader/book_image_viewer.dart';
import '../widgets/reader/book_nav_drawer.dart';
import '../widgets/reader/book_page_meta_overlay.dart';
import '../widgets/reader/book_reader_chrome.dart';
import '../widgets/reader/book_search_panel.dart';
import '../widgets/reader/book_selection_menu_overlay.dart';
import '../widgets/reader/reader_waiting_cover.dart';

/// Full-screen reflow book reader.
///
/// Open UX follows Apple Books: fitted cover on the reading backdrop, wait for
/// Foliate, dissolve the cover into that backdrop, then ease the backdrop into
/// the text.
class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.database,
    required this.item,
    this.readingPreferences,
    this.aiSettings,
  });

  final AppDatabase database;
  final ReadingItem item;
  final BookReadingPreferences? readingPreferences;

  /// Optional; when null the screen resolves [AiSettingsScope] from context.
  final AiSettingsController? aiSettings;

  static Future<void> open(
    BuildContext context, {
    required AppDatabase database,
    required ReadingItem item,
    BookReadingPreferences? readingPreferences,
  }) {
    // Resolve from the navigator context (fully mounted) so initState of the
    // new route does not miss the inherited scope.
    final aiSettings = AiSettingsScope.maybeOf(context);
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return BookReaderScreen(
            database: database,
            item: item,
            readingPreferences: readingPreferences,
            aiSettings: aiSettings ?? AiSettingsScope.maybeOf(context),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
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
    unawaited(_attachAiStores());
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
    unawaited(_openBookFile());
  }

  Future<void> _attachAiStores() async {
    try {
      final paths = await LibraryPaths.forApp();
      if (!mounted) return;
      _controller.attachChatHistoryStore(
        JsonAiChatHistoryStore(paths.aiChatDirectory),
      );
      _controller.attachAiGraphStore(AiGraphStore(paths.aiGraphDirectory));
    } catch (error) {
      debugPrint('[AI] failed to attach reader stores: $error');
    }
  }

  void _onGlobalFocusChange() {
    if (!mounted) return;
    if (!primaryFocusIsTextEditing()) return;
    unawaited(_engine.clearPlatformFocus());
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
  }

  Future<void> _openBookFile() async {
    final item = widget.item;
    final paths = await LibraryPaths.forApp();
    final resolved = await paths.resolveExistingPath(
      item.filePath,
      contentHash: item.contentHash,
    );
    if (!mounted) return;
    await _engine.open(resolved ?? item.filePath);
  }

  void _maybeStartReveal(bool contentReady) {
    if (!contentReady || _revealStarted || !_showReveal) return;
    _revealStarted = true;
    unawaited(_reveal.forward());
  }

  void _exit() {
    unawaited(_controller.stopTts());
    if (_controller.chromeVisible) _controller.hideChrome();
    Navigator.of(context, rootNavigator: true).pop();
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

            return Focus(
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
                    _engine.buildView(context),
                    if (_showReveal)
                      IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _reveal,
                          builder: (context, _) {
                            final coverT = Curves.easeOutCubic.transform(
                              const Interval(0, 0.52).transform(_reveal.value),
                            );
                            final pageT = Curves.easeInOut.transform(
                              const Interval(0.48, 1).transform(_reveal.value),
                            );
                            final coverChild = ReaderWaitingCover(
                              coverPath: widget.item.coverPath,
                              title: widget.item.title,
                            );
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
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    _controller.removeListener(_onBookControllerTick);
    _engine.removeListener(_onBookEngineTick);
    unawaited(_timeTracker.detach());
    _controller.annotations.onOpenNoteEditor = null;
    _controller.detachPlatformFocusClearer();
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

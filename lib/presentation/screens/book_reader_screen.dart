import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/book_reading_preferences.dart';
import '../../core/platform_window.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_time_tracker.dart';
import '../../library/storage/library_paths.dart';
import '../../readers/book/book_reader_capabilities.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/foliate_js_engine_adapter.dart';
import '../controllers/book_reader_controller.dart';
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
  });

  final AppDatabase database;
  final ReadingItem item;
  final BookReadingPreferences? readingPreferences;

  static Future<void> open(
    BuildContext context, {
    required AppDatabase database,
    required ReadingItem item,
    BookReadingPreferences? readingPreferences,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return BookReaderScreen(
            database: database,
            item: item,
            readingPreferences: readingPreferences,
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
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final BookReaderController _controller;
  late final FoliateJsBookEngineAdapter _engine;
  late final ReadingTimeTracker _timeTracker;
  late final FocusNode _focusNode;
  late final AnimationController _reveal;
  bool _showReveal = true;
  bool _revealStarted = false;
  bool _lastTtsPlaying = false;

  @override
  void initState() {
    super.initState();
    final scrollModeEnabled =
        BookReaderCapabilities.supportsScrollModeOnCurrentPlatform;
    _controller = BookReaderController(
      database: widget.database,
      item: widget.item,
      readingPreferences: widget.readingPreferences,
      scrollModeEnabled: scrollModeEnabled,
    );
    if (!scrollModeEnabled &&
        widget.readingPreferences?.readingMode == BookReadingMode.scroll) {
      unawaited(
        widget.readingPreferences?.setReadingMode(BookReadingMode.page),
      );
    }
    _engine = FoliateJsBookEngineAdapter(readerController: _controller);
    _controller.onOpenNoteEditor = _presentNoteEditor;
    _controller.addListener(_onBookControllerTick);
    _timeTracker = ReadingTimeTracker(
      database: widget.database,
      itemId: widget.item.id,
      kind: ReaderKind.book,
    )..attach();
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
    unawaited(_openBookFile());
  }

  /// TTS playback must not accumulate reading time (PRODUCT §4.8).
  void _onBookControllerTick() {
    final playing = _controller.ttsPlaying;
    if (playing == _lastTtsPlaying) return;
    _lastTtsPlaying = playing;
    _timeTracker.setCountingEnabled(!playing);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _reveal.duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 420);
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
    _controller.goToAnnotation(note);
    _presentNoteEditor(note);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_controller.imageViewerOpen) {
        _controller.closeImageViewer();
        return KeyEventResult.handled;
      }
      if (_controller.searchOpen) {
        _controller.closeSearch();
        return KeyEventResult.handled;
      }
      if (_controller.selectionMenu != null) {
        _controller.clearSelectionMenu();
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
      _controller.changeFontSize(2);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.minus ||
        event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _controller.changeFontSize(-2);
      return KeyEventResult.handled;
    }

    final isPage = _controller.readingMode == BookReadingMode.page;
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
            final theme = _controller.readingTheme;
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
                body: _ErrorBody(
                  error: _controller.openError.toString(),
                  onBack: _exit,
                  theme: theme,
                ),
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
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ReaderWindowDragHandle(),
                    ),
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
                      if (_controller.searchOpen)
                        BookSearchPanel(controller: _controller),
                      if (_controller.imageViewerOpen)
                        BookImageViewer(controller: _controller),
                    ],
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
    _controller.removeListener(_onBookControllerTick);
    unawaited(_timeTracker.detach());
    _controller.onOpenNoteEditor = null;
    _reveal.dispose();
    _focusNode.dispose();
    _engine.dispose();
    _controller.dispose();
    super.dispose();
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.onBack,
    required this.theme,
  });

  final String error;
  final VoidCallback onBack;
  final BookReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final fg = Color(theme.foregroundArgb);
    final fgMuted = theme.isDark
        ? const Color(0x99F2F2F4)
        : const Color(0x991C1C1E);
    final detail = error.trim();

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
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fgMuted.withValues(alpha: 0.75),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: onBack, child: const Text('返回')),
            ],
          ),
        ),
      ),
    );
  }
}

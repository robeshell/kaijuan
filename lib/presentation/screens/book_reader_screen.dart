import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/book_reading_preferences.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_reader_capabilities.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/foliate_js_engine_adapter.dart';
import '../controllers/book_reader_controller.dart';
import '../widgets/reader/book_page_meta_overlay.dart';
import '../widgets/reader/book_reader_chrome.dart';

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
  late final FocusNode _focusNode;
  late final AnimationController _reveal;
  bool _showReveal = true;
  bool _revealStarted = false;

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
    _focusNode = FocusNode();
    // Phase A (~first half): cover dissolves into reading backdrop.
    // Phase B (~second half): backdrop eases away into the text.
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showReveal = false);
      }
    });
    _engine.attach();
    unawaited(_engine.open(widget.item.filePath));
  }

  void _maybeStartReveal(bool contentReady) {
    if (!contentReady || _revealStarted || !_showReveal) return;
    _revealStarted = true;
    unawaited(_reveal.forward());
  }

  void _exit() {
    if (_controller.chromeVisible) _controller.hideChrome();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _openToc() => _scaffoldKey.currentState?.openDrawer();

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
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

            final contentReady = _controller.isReady && _engine.rendererReady;
            if (contentReady && !_revealStarted && _showReveal) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _maybeStartReveal(true);
              });
            }

            return Focus(
              focusNode: _focusNode,
              autofocus: contentReady && !_showReveal,
              onKeyEvent: _handleKeyEvent,
              child: Scaffold(
                key: _scaffoldKey,
                drawerEnableOpenDragGesture: false,
                drawer: _controller.isReady ? _buildTocDrawer() : null,
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
                                  child: Transform.scale(
                                    scale: 1 + 0.1 * coverT,
                                    filterQuality: FilterQuality.low,
                                    child: _WaitingCover(
                                      coverPath: widget.item.coverPath,
                                      title: widget.item.title,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    if (_controller.isReady && !_showReveal) ...[
                      BookPageMetaOverlay(controller: _controller),
                      IgnorePointer(
                        ignoring: !_controller.chromeVisible,
                        child: AnimatedOpacity(
                          opacity: _controller.chromeVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: BookReaderChrome(
                            controller: _controller,
                            onBack: _exit,
                            onOpenToc: _openToc,
                          ),
                        ),
                      ),
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

  Widget _buildTocDrawer() {
    final entries = _controller.tocEntries;
    final currentIndex = _controller.sectionIndex;
    final accent = Theme.of(context).colorScheme.primary;
    final semantics = Theme.of(context).extension<AppSemantics>()!;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Text(
                '目录',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: semantics.textPrimary,
                ),
              ),
            ),
            Divider(height: 1, color: semantics.hairline),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final entry = entries[i];
                  final active = entry.sectionIndex == currentIndex;
                  final indent = (entry.depth * 12.0).clamp(0.0, 48.0);
                  return ListTile(
                    contentPadding: EdgeInsets.only(
                      left: 16 + indent,
                      right: 16,
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? accent : semantics.textPrimary,
                      ),
                    ),
                    selected: active,
                    enabled: entry.sectionIndex != null,
                    dense: true,
                    onTap: entry.sectionIndex == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _engine.openTocEntry(entry);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reveal.dispose();
    _focusNode.dispose();
    _engine.dispose();
    _controller.dispose();
    super.dispose();
  }
}

/// Window-fitted cover art only — backdrop is painted by the reveal layer.
class _WaitingCover extends StatelessWidget {
  const _WaitingCover({
    required this.coverPath,
    required this.title,
  });

  final String? coverPath;
  final String title;

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: Center(
          child: path != null && path.isNotEmpty
              ? Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => _TitleFallback(title: title),
                )
              : _TitleFallback(title: title),
        ),
      ),
    );
  }
}

class _TitleFallback extends StatelessWidget {
  const _TitleFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>();
    final fg = semantics?.textPrimary ?? const Color(0xFF1C1C1E);
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fg.withValues(alpha: 0.72),
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
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
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: fgMuted),
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

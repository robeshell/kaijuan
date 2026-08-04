import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/comic_reading_preferences.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/platform_window.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../library/stats/reading_time_tracker.dart';
import '../../readers/comic/comic_models.dart';
import '../controllers/comic_reader_controller.dart';
import '../widgets/reader/comic_reader_body.dart';
import '../widgets/reader/comic_reader_chrome.dart';
import '../widgets/reader/reader_waiting_cover.dart';

/// Full-screen comic reader host.
///
/// Open UX matches the book reader: zero-duration push (no side-slide), waiting
/// cover on the reading backdrop, dissolve into pages when the session is ready.
class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.database,
    required this.item,
    this.readingPreferences,
  });

  final AppDatabase database;
  final ReadingItem item;
  final ComicReadingPreferences? readingPreferences;

  static Future<void> open(
    BuildContext context, {
    required AppDatabase database,
    required ReadingItem item,
    ComicReadingPreferences? readingPreferences,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ComicReaderScreen(
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
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen>
    with SingleTickerProviderStateMixin {
  late final ComicReaderController _controller;
  late final ReadingTimeTracker _timeTracker;
  final _focusNode = FocusNode();
  late final AnimationController _reveal;
  bool _showReveal = true;
  bool _revealStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = ComicReaderController(
      database: widget.database,
      item: widget.item,
      readingPreferences: widget.readingPreferences,
    )..open();
    _timeTracker = ReadingTimeTracker(
      database: widget.database,
      itemId: widget.item.id,
      kind: ReaderKind.comic,
    )..attach();
    // Phase A (~first half): cover dissolves into reading backdrop.
    // Phase B (~second half): backdrop eases away into the pages.
    _reveal = AnimationController(
      vsync: this,
      // May shrink to zero under reduce-motion (see [didChangeDependencies]).
      duration: const Duration(milliseconds: 420),
    );
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showReveal = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _reveal.duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 420);
  }

  @override
  void dispose() {
    unawaited(_timeTracker.detach());
    _reveal.dispose();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _maybeStartReveal() {
    if (!_controller.isReady || _revealStarted || !_showReveal) return;
    _revealStarted = true;
    unawaited(_reveal.forward());
  }

  /// Toolbar back / error-page back: always leave the reader.
  void _exitReader() {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      // Imperative [pop] — not [maybePop] — so PopScope.canPop cannot block.
      nav.pop();
    }
  }

  /// Escape: dismiss chrome first when visible, then leave.
  void _handleDismiss() {
    if (_controller.chromeVisible) {
      _controller.hideChrome();
      return;
    }
    _exitReader();
  }

  /// Semantic next/prev mapped through reading direction.
  void _turn({required bool forward}) {
    if (forward) {
      _controller.goForward();
    } else {
      _controller.goBackward();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rtl = _controller.direction == ComicReadDirection.rtl;

    if (key == LogicalKeyboardKey.escape) {
      _handleDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.pageDown) {
      _turn(forward: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _turn(forward: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _turn(forward: !rtl);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _turn(forward: rtl);
      return KeyEventResult.handled;
    }
    if (_controller.mode == ComicReaderMode.vertical) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _turn(forward: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _turn(forward: false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final bg = Color(_controller.readingTheme.backgroundArgb);

        final theme = _controller.readingTheme;

        if (_controller.openError != null) {
          return Scaffold(
            backgroundColor: bg,
            body: _ErrorBody(
              detail: _controller.openError.toString(),
              onBack: _exitReader,
              theme: theme,
            ),
          );
        }

        final contentReady = _controller.isReady;
        if (contentReady && !_revealStarted && _showReveal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybeStartReveal();
          });
        }

        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final chromeAnim = reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200);

        return Focus(
          focusNode: _focusNode,
          autofocus: contentReady && !_showReveal,
          onKeyEvent: _onKey,
          child: Scaffold(
            backgroundColor: bg,
            body: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: bg),
                if (contentReady) ComicReaderBody(controller: _controller),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ReaderWindowDragHandle(),
                ),
                if (contentReady && _controller.brightness < 0.999)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: (1.0 - _controller.brightness).clamp(0.0, 1.0),
                      ),
                    ),
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
                if (contentReady && !_showReveal)
                  IgnorePointer(
                    ignoring: !_controller.chromeVisible,
                    child: AnimatedOpacity(
                      opacity: _controller.chromeVisible ? 1 : 0,
                      duration: chromeAnim,
                      curve: Curves.easeOut,
                      child: ComicReaderChrome(
                        controller: _controller,
                        onBack: _exitReader,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.detail,
    required this.onBack,
    required this.theme,
  });

  final String detail;
  final VoidCallback onBack;
  final ComicReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final macLead = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
        ? 78.0
        : 0.0;
    final fg = Color(theme.foregroundArgb);
    final fgMuted = Color(theme.metaColorArgb);
    final trimmed = detail.trim();

    // Top inset from app MediaQuery; left clears traffic lights on macOS.
    return SafeArea(
      minimum: EdgeInsets.only(left: macLead),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(KaijuanIcons.error, size: 48, color: fgMuted),
              const SizedBox(height: 16),
              Text(
                '无法打开此漫画',
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
              if (trimmed.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  trimmed,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fgMuted.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: onBack, child: const Text('返回')),
            ],
          ),
        ),
      ),
    );
  }
}

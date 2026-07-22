import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/book_reading_preferences.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_reader_capabilities.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/foliate_js_engine_adapter.dart';
import '../controllers/book_reader_controller.dart';
import '../widgets/reader/book_reader_chrome.dart';

/// Full-screen reflow book reader.
///
/// The screen itself is stateless: all reading state lives in
/// [BookReaderController], and the actual rendering engine is provided by
/// [FoliateJsBookEngineAdapter]. This mirrors the comic reader architecture while
/// keeping WebView layout details outside the presentation layer.
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
      MaterialPageRoute<void>(
        builder: (_) => BookReaderScreen(
          database: database,
          item: item,
          readingPreferences: readingPreferences,
        ),
      ),
    );
  }

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final BookReaderController _controller;
  late final FoliateJsBookEngineAdapter _engine;
  late final FocusNode _focusNode;

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
    _engine.attach();
    unawaited(_engine.open(widget.item.filePath));
  }

  void _exit() => Navigator.of(context, rootNavigator: true).pop();

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

            return Focus(
              focusNode: _focusNode,
              autofocus: contentReady,
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
                    if (!contentReady)
                      ColoredBox(
                        color: bg,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    if (_controller.isReady)
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

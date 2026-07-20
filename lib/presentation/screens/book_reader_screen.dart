import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/book_reading_preferences.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/comic/comic_models.dart';
import '../controllers/book_reader_controller.dart';

/// Full-screen reflow reader for the book app (text spike).
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
  late final BookReaderController _controller;
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _restoredScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = BookReaderController(
      database: widget.database,
      item: widget.item,
      readingPreferences: widget.readingPreferences,
    )..open();
    _controller.addListener(_onController);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onController() {
    if (!_controller.isReady) return;
    if (!_restoredScroll && _scrollController.hasClients) {
      _restoredScroll = true;
      final max = _scrollController.position.maxScrollExtent;
      final target = max * _controller.progressInSection;
      _scrollController.jumpTo(target.clamp(0.0, max));
    }
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final fraction = max <= 0 ? 0.0 : _scrollController.offset / max;
    _controller.reportScrollProgress(fraction);
  }

  void _exit() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_controller.chromeVisible) {
        _controller.hideChrome();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _restoredScroll = true;
      _controller.goNextSection();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _restoredScroll = true;
      _controller.goPreviousSection();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openToc() async {
    final doc = _controller.document;
    if (doc == null) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            itemCount: doc.sections.length,
            itemBuilder: (_, i) {
              final s = doc.sections[i];
              final active = i == _controller.sectionIndex;
              return ListTile(
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                selected: active,
                onTap: () => Navigator.pop(ctx, i),
              );
            },
          ),
        );
      },
    );
    if (selected != null) {
      _restoredScroll = true;
      _controller.goToSection(selected);
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final theme = _controller.readingTheme;
          final bg = Color(theme.backgroundArgb);
          final fg = theme.isDark
              ? const Color(0xFFF2F2F4)
              : const Color(0xFF1C1C1E);
          final muted = theme.isDark
              ? const Color(0x99F2F2F4)
              : const Color(0x991C1C1E);

          if (_controller.openError != null) {
            return Scaffold(
              backgroundColor: bg,
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _controller.openError.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _exit,
                          child: const Text('返回'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          if (!_controller.isReady) {
            return Scaffold(
              backgroundColor: bg,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final section = _controller.currentSection!;
          final macLead = !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.macOS
              ? 78.0
              : 0.0;

          return Scaffold(
            backgroundColor: bg,
            body: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _controller.toggleChrome,
                  child: SafeArea(
                    child: Scrollbar(
                      controller: _scrollController,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
                        child: SelectableText(
                          section.plainText,
                          style: TextStyle(
                            color: fg,
                            fontSize: _controller.fontSize,
                            height: _controller.lineHeight,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_controller.chromeVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      color: bg.withValues(alpha: 0.92),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.only(left: macLead),
                          child: SizedBox(
                            height: 52,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '返回',
                                  onPressed: _exit,
                                  icon: Icon(
                                    Icons.arrow_back_outlined,
                                    color: fg,
                                    weight: 300,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    widget.item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: fg,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '目录',
                                  onPressed: _openToc,
                                  icon: Icon(
                                    Icons.list_outlined,
                                    color: fg,
                                    weight: 300,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '缩小字号',
                                  onPressed: () => _controller
                                      .setFontSize(_controller.fontSize - 1),
                                  icon: Icon(
                                    Icons.text_decrease_outlined,
                                    color: fg,
                                    weight: 300,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '放大字号',
                                  onPressed: () => _controller
                                      .setFontSize(_controller.fontSize + 1),
                                  icon: Icon(
                                    Icons.text_increase_outlined,
                                    color: fg,
                                    weight: 300,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_controller.chromeVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: bg.withValues(alpha: 0.92),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: '上一节',
                                onPressed: _controller.sectionIndex > 0
                                    ? () {
                                        _restoredScroll = true;
                                        _controller.goPreviousSection();
                                        if (_scrollController.hasClients) {
                                          _scrollController.jumpTo(0);
                                        }
                                      }
                                    : null,
                                icon: Icon(
                                  Icons.chevron_left,
                                  color: muted,
                                  weight: 300,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${section.title} · ${_controller.sectionLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '下一节',
                                onPressed: _controller.sectionIndex <
                                        _controller.sectionCount - 1
                                    ? () {
                                        _restoredScroll = true;
                                        _controller.goNextSection();
                                        if (_scrollController.hasClients) {
                                          _scrollController.jumpTo(0);
                                        }
                                      }
                                    : null,
                                icon: Icon(
                                  Icons.chevron_right,
                                  color: muted,
                                  weight: 300,
                                ),
                              ),
                              PopupMenuButton<ComicReadingTheme>(
                                tooltip: '阅读背景',
                                icon: Icon(
                                  Icons.palette_outlined,
                                  color: muted,
                                  weight: 300,
                                ),
                                onSelected: _controller.setReadingTheme,
                                itemBuilder: (_) => [
                                  for (final t in ComicReadingTheme.values)
                                    PopupMenuItem(
                                      value: t,
                                      child: Text(t.label),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

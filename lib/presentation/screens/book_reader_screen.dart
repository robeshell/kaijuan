import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:katbook_epub_reader/katbook_epub_reader.dart';

import '../../app/book_reading_preferences.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/comic/comic_models.dart';

/// Full-screen reflow reader powered by katbook_epub_reader.
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
  final _controller = KatbookEpubController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _saveDebounce;
  bool _loading = true;
  Object? _error;
  ReadingPosition? _initialPosition;

  ReaderTheme _theme = ReaderTheme.light;
  double _fontSize = 16;
  bool _chromeVisible = true;

  static const _macTrafficLightClearance = 78.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final file = File(widget.item.filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在：${widget.item.filePath}');
      }
      await _controller.openBook(await file.readAsBytes());
      if (!mounted) return;

      final progress = await widget.database.progressFor(widget.item.id);
      if (progress != null) {
        _initialPosition = _tryDecodePosition(progress.locatorJson);
      }

      final prefs = widget.readingPreferences;
      _theme = _toKatbookTheme(prefs?.readingTheme);
      _fontSize = prefs?.fontSize.clamp(10.0, 32.0) ?? 16.0;

      await widget.database.touchLastOpened(widget.item.id, DateTime.now());
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  static ReadingPosition? _tryDecodePosition(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      if (map.containsKey('paragraphIndex')) {
        return ReadingPosition.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  void _savePosition(ReadingPosition pos) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      widget.database.upsertProgress(
        itemId: widget.item.id,
        locatorJson: jsonEncode(pos.toJson()),
        progressFraction: (pos.progressPercent / 100).clamp(0.0, 1.0),
        updatedAt: DateTime.now(),
      );
    });
  }

  void _exit() => Navigator.of(context, rootNavigator: true).pop();

  // ------------------------------------------------------------------
  // Skins
  // ------------------------------------------------------------------

  static ReaderTheme _toKatbookTheme(ComicReadingTheme? theme) {
    return switch (theme) {
      ComicReadingTheme.sepia => ReaderTheme.sepia,
      ComicReadingTheme.dark || ComicReadingTheme.pureBlack => ReaderTheme.dark,
      _ => ReaderTheme.light,
    };
  }

  ReaderThemeData get _themeData => ReaderThemeData.fromTheme(_theme);

  bool get _isDark => _themeData.isDark;

  Color get _fg =>
      _isDark ? const Color(0xFFF2F2F4) : const Color(0xFF1C1C1E);

  Color get _fgMuted =>
      _isDark ? const Color(0x99F2F2F4) : const Color(0x991C1C1E);

  Color get _glassBg =>
      _isDark ? const Color(0xB3212124) : const Color(0xB3FFFFFF);

  double get _macLead =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
          ? _macTrafficLightClearance
          : 0.0;

  double get _progress {
    final pos = _controller.currentPosition;
    if (pos == null || pos.totalParagraphs == 0) return 0.0;
    return (pos.paragraphIndex / pos.totalParagraphs).clamp(0.0, 1.0);
  }

  // ------------------------------------------------------------------
  // Chrome widgets
  // ------------------------------------------------------------------

  Widget _buildAppBar() {
    final pct = (_progress * 100).toStringAsFixed(1);
    return Material(
      color: _glassBg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Centred title + progress.
              Padding(
                padding: EdgeInsets.only(left: _macLead + 44, right: 140),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: TextStyle(color: _fgMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Left: back.
              Row(
                children: [
                  SizedBox(width: _macLead),
                  IconButton(
                    tooltip: '返回',
                    visualDensity: VisualDensity.compact,
                    onPressed: _exit,
                    icon: Icon(Icons.arrow_back_outlined,
                        color: _fg, weight: 300),
                  ),
                  const Spacer(),
                  // Right: TOC.
                  IconButton(
                    tooltip: '目录',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    icon: Icon(Icons.list_outlined, color: _fg, weight: 300),
                  ),
                  // Font size.
                  PopupMenuButton<String>(
                    tooltip: '字号',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.format_size_outlined,
                        color: _fg, weight: 300),
                    onSelected: (v) {
                      setState(() {
                        _fontSize = ((_fontSize + (v == '-' ? -2 : 2)))
                            .clamp(10.0, 32.0);
                      });
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: '-',
                        child:
                            Text('缩小（${_fontSize.toStringAsFixed(0)}）'),
                      ),
                      const PopupMenuItem(value: '+', child: Text('放大')),
                    ],
                  ),
                  // Theme.
                  PopupMenuButton<String>(
                    tooltip: '主题',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.brightness_6_outlined,
                        color: _fg, weight: 300),
                    onSelected: (v) {
                      setState(() {
                        _theme = ReaderTheme.values.firstWhere(
                          (t) => t.name == v,
                          orElse: () => ReaderTheme.light,
                        );
                      });
                    },
                    itemBuilder: (_) => [
                      for (final t in ReaderTheme.values)
                        CheckedPopupMenuItem(
                          value: t.name,
                          checked: _theme == t,
                          child: Text(switch (t) {
                            ReaderTheme.light => '浅色',
                            ReaderTheme.sepia => '米色',
                            ReaderTheme.dark => '深色',
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTocDrawer() {
    final chapters = _controller.tableOfContents;
    final accent = Theme.of(context).colorScheme.primary;
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final currentIndex =
        _controller.currentPosition?.paragraphIndex ?? -1;

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
                itemCount: chapters.length,
                itemBuilder: (_, i) {
                  final ch = chapters[i];
                  final active = ch.startIndex <= currentIndex &&
                      (i + 1 >= chapters.length ||
                          chapters[i + 1].startIndex > currentIndex);
                  return ListTile(
                    title: Text(
                      ch.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? accent : semantics.textPrimary,
                      ),
                    ),
                    selected: active,
                    dense: true,
                    onTap: () {
                      Navigator.pop(context);
                      _controller.jumpToIndex(ch.startIndex);
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

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _themeData.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _themeData.backgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _fgMuted)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _exit, child: const Text('返回')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: false,
      drawer: _buildTocDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Reader — no built-in app bar.
          KatbookEpubReader(
            controller: _controller,
            initialTheme: _theme,
            initialFontSize: _fontSize,
            initialPosition: _initialPosition,
            onPositionChanged: _savePosition,
            showAppBar: false,
            showThemeButton: false,
            showLanguageButton: false,
          ),
          // Custom glass top bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _chromeVisible = !_chromeVisible),
              child: _chromeVisible ? _buildAppBar() : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }
}

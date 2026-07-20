import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:katbook_epub_reader/katbook_epub_reader.dart';

import '../../app/book_reading_preferences.dart';
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
  Timer? _saveDebounce;
  bool _loading = true;
  Object? _error;
  ReadingPosition? _initialPosition;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.item.filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在：${widget.item.filePath}');
      }
      await _controller.openBook(await file.readAsBytes());
      if (!mounted) return;

      // Restore saved position.
      final progress = await widget.database.progressFor(widget.item.id);
      if (progress != null) {
        _initialPosition = _tryDecodePosition(progress.locatorJson);
      }

      await widget.database.touchLastOpened(widget.item.id, DateTime.now());
    } catch (e) {
      _error = e;
    }
    if (mounted) {
      setState(() => _loading = false);
    }
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

  void _onPositionChanged(ReadingPosition pos) {
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

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  static ReaderTheme _toKatbookTheme(ComicReadingTheme? theme) {
    return switch (theme) {
      ComicReadingTheme.sepia => ReaderTheme.sepia,
      ComicReadingTheme.dark || ComicReadingTheme.pureBlack => ReaderTheme.dark,
      _ => ReaderTheme.light,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('返回'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final prefs = widget.readingPreferences;
    return KatbookEpubReader(
      controller: _controller,
      initialTheme: _toKatbookTheme(prefs?.readingTheme),
      initialFontSize:
          prefs?.fontSize.clamp(10.0, 32.0) ?? 16.0,
      initialPosition: _initialPosition,
      onPositionChanged: _onPositionChanged,
      showAppBar: true,
    );
  }
}

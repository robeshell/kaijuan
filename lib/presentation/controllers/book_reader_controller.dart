import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/book_reading_preferences.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_epub.dart';
import '../../readers/book/book_models.dart';
import '../../readers/comic/comic_models.dart';

/// Owns reflow book session: open EPUB, section index, scroll progress, chrome.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required this.database,
    required this.item,
    BookReadingPreferences? readingPreferences,
  })  : _prefs = readingPreferences,
        _fontSize = readingPreferences?.fontSize ?? 18,
        _lineHeight = readingPreferences?.lineHeight ?? 1.6,
        _readingTheme =
            readingPreferences?.readingTheme ?? ComicReadingTheme.paper;

  final AppDatabase database;
  final ReadingItem item;
  final BookReadingPreferences? _prefs;

  BookEpubDocument? _doc;
  Object? _openError;
  bool _ready = false;
  bool _disposed = false;
  bool _chromeVisible = true;

  int _sectionIndex = 0;
  double _progressInSection = 0;
  double _fontSize;
  double _lineHeight;
  ComicReadingTheme _readingTheme;

  Object? get openError => _openError;
  bool get isReady => _ready;
  bool get chromeVisible => _chromeVisible;
  BookEpubDocument? get document => _doc;
  int get sectionIndex => _sectionIndex;
  int get sectionCount => _doc?.sectionCount ?? 0;
  double get progressInSection => _progressInSection;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  ComicReadingTheme get readingTheme => _readingTheme;

  BookSection? get currentSection {
    final doc = _doc;
    if (doc == null || doc.sections.isEmpty) return null;
    final i = _sectionIndex.clamp(0, doc.sections.length - 1);
    return doc.sections[i];
  }

  String get sectionLabel {
    final total = sectionCount;
    if (total <= 0) return '—';
    return '${_sectionIndex + 1} / $total';
  }

  double get progressFraction {
    final total = sectionCount;
    if (total <= 0) return 0;
    if (total == 1) return _progressInSection.clamp(0.0, 1.0);
    return ((_sectionIndex + _progressInSection) / total).clamp(0.0, 1.0);
  }

  Future<void> open() async {
    try {
      final doc = await BookEpub.open(item.filePath);
      if (_disposed) return;
      _doc = doc;
      await _restoreProgress();
      await database.touchLastOpened(item.id, DateTime.now());
      _ready = true;
      _openError = null;
      notifyListeners();
    } catch (e) {
      _openError = e;
      _ready = false;
      notifyListeners();
    }
  }

  Future<void> _restoreProgress() async {
    final row = await database.progressFor(item.id);
    if (row == null || _doc == null) return;
    final locator = BookLocator.tryDecode(row.locatorJson);
    final valid = locator?.validated(sectionCount: _doc!.sectionCount);
    if (valid == null) return;
    _sectionIndex = valid.sectionIndex;
    _progressInSection = valid.progressInSection;
  }

  void toggleChrome() {
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  void hideChrome() {
    if (!_chromeVisible) return;
    _chromeVisible = false;
    notifyListeners();
  }

  void goToSection(int index) {
    final total = sectionCount;
    if (total <= 0) return;
    final next = index.clamp(0, total - 1);
    if (next == _sectionIndex && _progressInSection == 0) return;
    _sectionIndex = next;
    _progressInSection = 0;
    notifyListeners();
    unawaited(_persist());
  }

  void goNextSection() => goToSection(_sectionIndex + 1);

  void goPreviousSection() => goToSection(_sectionIndex - 1);

  void reportScrollProgress(double fraction) {
    final next = fraction.clamp(0.0, 1.0);
    if ((next - _progressInSection).abs() < 0.01) return;
    _progressInSection = next;
    // Avoid notify spam; still persist periodically via callers if needed.
    unawaited(_persist());
  }

  Future<void> setFontSize(double size) async {
    final next = size.clamp(14.0, 28.0);
    if (next == _fontSize) return;
    _fontSize = next;
    notifyListeners();
    await _prefs?.setFontSize(next);
  }

  Future<void> setLineHeight(double height) async {
    final next = height.clamp(1.2, 2.2);
    if (next == _lineHeight) return;
    _lineHeight = next;
    notifyListeners();
    await _prefs?.setLineHeight(next);
  }

  Future<void> setReadingTheme(ComicReadingTheme theme) async {
    if (theme == _readingTheme) return;
    _readingTheme = theme;
    notifyListeners();
    await _prefs?.setReadingTheme(theme);
  }

  Future<void> _persist() async {
    final total = sectionCount;
    if (total <= 0) return;
    final locator = BookLocator(
      sectionIndex: _sectionIndex,
      progressInSection: _progressInSection,
    );
    await database.upsertProgress(
      itemId: item.id,
      locatorJson: locator.encode(),
      progressFraction: progressFraction,
      updatedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_persist());
    super.dispose();
  }
}

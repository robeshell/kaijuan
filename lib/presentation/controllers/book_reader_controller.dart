import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../app/book_reading_preferences.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/book_theme.dart';

/// Owns reflow book session: engine-agnostic state, chrome, progress, prefs.
///
/// The actual rendering engine is injected via [attachEngine] (or reported as
/// failed via [engineFailed]). This keeps every engine-specific import out of
/// the controller and makes the engine replaceable.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required this.database,
    required this.item,
    BookReadingPreferences? readingPreferences,
  })  : _prefs = readingPreferences,
        _fontSize = readingPreferences?.fontSize ??
            BookReadingPreferences.defaultFontSize,
        _lineHeight = readingPreferences?.lineHeight ??
            BookReadingPreferences.defaultLineHeight,
        _readingTheme = readingPreferences?.readingTheme ??
            BookReadingTheme.paper,
        _margin = readingPreferences?.margin ??
            BookReadingPreferences.defaultMargin,
        _readingMode = readingPreferences?.readingMode ??
            BookReadingPreferences.defaultReadingMode;

  final AppDatabase database;
  final ReadingItem item;
  final BookReadingPreferences? _prefs;

  BookSectionMap? _sectionMap;
  List<String> _tocTitles = const [];
  Object? _openError;
  bool _ready = false;
  bool _disposed = false;
  bool _chromeVisible = true;

  int _sectionIndex = 0;
  double _progressInSection = 0;
  double _fontSize;
  double _lineHeight;
  BookReadingTheme _readingTheme;
  double _margin;
  BookReadingMode _readingMode;

  Timer? _saveDebounce;
  int? _pendingJumpParagraph;

  BookSectionMap? _pageMap;
  int _pageIndex = 0;

  // ------------------------------------------------------------------
  // Getters
  // ------------------------------------------------------------------

  Object? get openError => _openError;
  bool get isReady => _ready;
  bool get chromeVisible => _chromeVisible;
  BookSectionMap? get sectionMap => _sectionMap;
  BookSectionMap? get pageMap => _pageMap;
  List<String> get tocTitles => _tocTitles;

  int get sectionCount => _sectionMap?.sectionCount ?? 0;
  int get sectionIndex => _sectionIndex;
  double get progressInSection => _progressInSection;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  BookReadingTheme get readingTheme => _readingTheme;
  double get margin => _margin;
  BookReadingMode get readingMode => _readingMode;

  bool get hasPageMode => pageCount > 0;
  int get pageIndex => _pageIndex;
  int get pageCount => _pageMap?.sectionCount ?? 0;

  String get sectionLabel {
    final total = sectionCount;
    if (total <= 0) return '—';
    return '${_sectionIndex + 1} / $total';
  }

  String get pageLabel {
    final total = pageCount;
    if (total <= 0) return '—';
    return '${_pageIndex + 1} / $total 页';
  }

  String get progressPercentLabel {
    final pct = (progressFraction * 100).toStringAsFixed(1);
    return '$pct%';
  }

  double get progressFraction {
    final total = sectionCount;
    if (total <= 0) return 0;
    if (total == 1) return _progressInSection.clamp(0.0, 1.0);
    return ((_sectionIndex + _progressInSection) / total).clamp(0.0, 1.0);
  }

  // ------------------------------------------------------------------
  // Engine lifecycle
  // ------------------------------------------------------------------

  /// Called by the engine adapter once parsing is done and the flat-paragraph
  /// boundaries are known.
  void attachEngine(BookSectionMap map, List<String> tocTitles) {
    if (_disposed) return;
    _sectionMap = map;
    _tocTitles = List.unmodifiable(tocTitles);
    _restoreProgress();
    _ready = true;
    _openError = null;
    notifyListeners();
    unawaited(database.touchLastOpened(item.id, DateTime.now()));
  }

  /// Called by the engine adapter once pagination is done for page mode.
  /// [pageMap] uses page indices as paragraphs.
  void attachPageMap(BookSectionMap pageMap) {
    if (_disposed) return;
    _pageMap = pageMap;
    _pageIndex = pageMap.paragraphFromLocator(
      BookLocator(
        sectionIndex: _sectionIndex,
        progressInSection: _progressInSection,
      ),
    );
    notifyListeners();
  }

  /// Called by the engine adapter when the book could not be opened.
  void engineFailed(Object error) {
    if (_disposed) return;
    _openError = error;
    _ready = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Progress: engine -> controller -> DB
  // ------------------------------------------------------------------

  /// Engine reports a flat paragraph position; we map it to our spine-style
  /// locator and debounce-persist it.
  void reportPosition(int paragraphIndex, double paragraphOffset) {
    if (_disposed) return;
    final map = _sectionMap;
    if (map == null) return;
    final locator = map.locatorFromParagraph(
      paragraphIndex: paragraphIndex,
      paragraphOffset: paragraphOffset,
    );
    if (locator.sectionIndex == _sectionIndex &&
        (locator.progressInSection - _progressInSection).abs() < 0.005) {
      return;
    }
    _sectionIndex = locator.sectionIndex;
    _progressInSection = locator.progressInSection;
    notifyListeners();
    _debouncedPersist();
  }

  /// Page-mode engine reports a page index; we update the page counter and
  /// derive the spine locator for persistence.
  void reportPage(int pageIndex) {
    if (_disposed) return;
    final count = pageCount;
    if (count <= 0) return;
    final next = pageIndex.clamp(0, count - 1);
    if (next == _pageIndex) return;
    _pageIndex = next;
    _updateSectionFromPage();
    notifyListeners();
    _debouncedPersist();
  }

  void _restoreProgress() {
    final map = _sectionMap;
    if (map == null) return;

    // Engine calls are synchronous; DB is async. We cannot block here, so we
    // kick off a future and update state when it arrives. The screen will show
    // the book at the start until the restore resolves, then jump if needed.
    unawaited(_restoreProgressAsync(map));
  }

  Future<void> _restoreProgressAsync(BookSectionMap map) async {
    final row = await database.progressFor(item.id);
    if (row == null || _disposed) return;

    BookLocator? locator;

    // 1. Native format.
    locator = BookLocator.tryDecode(row.locatorJson)?.validated(
      sectionCount: map.sectionCount,
    );

    // 2. Legacy katbook format migration (paragraphIndex/totalParagraphs).
    locator ??= _tryMigrateLegacyLocator(row.locatorJson, map);

    if (locator == null || _disposed) return;

    _sectionIndex = locator.sectionIndex;
    _progressInSection = locator.progressInSection;
    _pendingJumpParagraph = map.paragraphFromLocator(locator);
    notifyListeners();
  }

  static BookLocator? _tryMigrateLegacyLocator(
    String json,
    BookSectionMap map,
  ) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final paragraphIndex = data['paragraphIndex'];
      if (paragraphIndex is! int) return null;
      return map.locatorFromParagraph(paragraphIndex: paragraphIndex);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Navigation
  // ------------------------------------------------------------------

  void goToSection(int index) {
    final total = sectionCount;
    if (total <= 0) return;
    final next = index.clamp(0, total - 1);
    if (next == _sectionIndex && _progressInSection == 0) return;
    _sectionIndex = next;
    _progressInSection = 0;
    _pendingJumpParagraph = _sectionMap?.paragraphFromLocator(
      BookLocator(sectionIndex: _sectionIndex),
    );
    notifyListeners();
    _debouncedPersist();
  }

  void goNextSection() => goToSection(_sectionIndex + 1);

  void goPreviousSection() => goToSection(_sectionIndex - 1);

  // ------------------------------------------------------------------
  // Page-mode navigation
  // ------------------------------------------------------------------

  void goToPage(int index) {
    final count = pageCount;
    if (count <= 0) return;
    final next = index.clamp(0, count - 1);
    if (next == _pageIndex) return;
    _pageIndex = next;
    _pendingJumpParagraph = next;
    _updateSectionFromPage();
    notifyListeners();
    _debouncedPersist();
  }

  void goNextPage() => goToPage(_pageIndex + 1);

  void goPreviousPage() => goToPage(_pageIndex - 1);

  void _updateSectionFromPage() {
    final map = _pageMap;
    if (map == null) return;
    final locator = map.locatorFromParagraph(
      paragraphIndex: _pageIndex,
      paragraphOffset: 0,
    );
    _sectionIndex = locator.sectionIndex;
    _progressInSection = locator.progressInSection;
  }

  /// Engine adapter pulls the pending jump target once, then clears it.
  int? consumePendingJump() {
    final jump = _pendingJumpParagraph;
    _pendingJumpParagraph = null;
    return jump;
  }

  // ------------------------------------------------------------------
  // Chrome
  // ------------------------------------------------------------------

  void toggleChrome() {
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  void hideChrome() {
    if (!_chromeVisible) return;
    _chromeVisible = false;
    notifyListeners();
  }

  void showChrome() {
    if (_chromeVisible) return;
    _chromeVisible = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Preferences
  // ------------------------------------------------------------------

  Future<void> setFontSize(double size) async {
    final next = size.clamp(
      BookReadingPreferences.minFontSize,
      BookReadingPreferences.maxFontSize,
    );
    if (next == _fontSize) return;
    _fontSize = next;
    notifyListeners();
    await _prefs?.setFontSize(next);
  }

  Future<void> changeFontSize(double delta) async {
    await setFontSize(_fontSize + delta);
  }

  Future<void> setLineHeight(double height) async {
    final next = height.clamp(
      BookReadingPreferences.minLineHeight,
      BookReadingPreferences.maxLineHeight,
    );
    if (next == _lineHeight) return;
    _lineHeight = next;
    notifyListeners();
    await _prefs?.setLineHeight(next);
  }

  Future<void> setReadingTheme(BookReadingTheme theme) async {
    if (theme == _readingTheme) return;
    _readingTheme = theme;
    notifyListeners();
    await _prefs?.setReadingTheme(theme);
  }

  Future<void> setMargin(double margin) async {
    final next = margin.clamp(
      BookReadingPreferences.minMargin,
      BookReadingPreferences.maxMargin,
    );
    if (next == _margin) return;
    _margin = next;
    notifyListeners();
    await _prefs?.setMargin(next);
  }

  Future<void> setReadingMode(BookReadingMode mode) async {
    if (mode == _readingMode) return;
    _readingMode = mode;
    notifyListeners();
    await _prefs?.setReadingMode(mode);
  }

  // ------------------------------------------------------------------
  // Persistence
  // ------------------------------------------------------------------

  void _debouncedPersist() {
    if (_disposed) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _persist);
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
    _saveDebounce?.cancel();
    unawaited(_persist());
    super.dispose();
  }
}

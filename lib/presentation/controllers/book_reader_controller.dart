import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../app/book_reading_preferences.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/book_theme.dart';

/// Owns reflow book session state, chrome, progress, and preferences.
///
/// Rendering details stay in the reader pipeline; this controller is the
/// presentation boundary used by screens and widgets.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required this.database,
    required this.item,
    BookReadingPreferences? readingPreferences,
    this.scrollModeEnabled = true,
  }) : _prefs = readingPreferences,
       _fontSize =
           readingPreferences?.fontSize ??
           BookReadingPreferences.defaultFontSize,
       _lineHeight =
           readingPreferences?.lineHeight ??
           BookReadingPreferences.defaultLineHeight,
       _readingTheme =
           readingPreferences?.readingTheme ?? BookReadingTheme.paper,
       _margin =
           readingPreferences?.margin ?? BookReadingPreferences.defaultMargin,
       _readingMode = scrollModeEnabled
           ? readingPreferences?.readingMode ??
                 BookReadingPreferences.defaultReadingMode
           : BookReadingMode.page,
       _pageTurnEffect =
           readingPreferences?.pageTurnEffect ??
           BookReadingPreferences.defaultPageTurnEffect;

  final AppDatabase database;
  final ReadingItem item;
  final BookReadingPreferences? _prefs;
  final bool scrollModeEnabled;

  BookSectionMap? _sectionMap;
  List<String> _tocTitles = const [];
  List<BookTocEntry> _tocEntries = const [];
  Object? _openError;
  bool _ready = false;
  bool _disposed = false;
  int _attachGeneration = 0;
  bool _chromeVisible = false;

  int _sectionIndex = 0;
  double _progressInSection = 0;
  double _fontSize;
  double _lineHeight;
  BookReadingTheme _readingTheme;
  double _margin;
  BookReadingMode _readingMode;
  BookPageTurnEffect _pageTurnEffect;

  Timer? _saveDebounce;
  BookLocator? _pendingJumpLocator;
  String? _progressLocatorJson;
  List<ReaderBookmark> _bookmarks = const [];
  StreamSubscription<List<ReaderBookmark>>? _bookmarksSubscription;

  VoidCallback? _externalNextPage;
  VoidCallback? _externalPreviousPage;
  String? _renditionCfi;
  double? _renditionProgress;

  // ------------------------------------------------------------------
  // Getters
  // ------------------------------------------------------------------

  Object? get openError => _openError;
  bool get isReady => _ready;
  bool get chromeVisible => _chromeVisible;
  BookSectionMap? get sectionMap => _sectionMap;
  List<String> get tocTitles => _tocTitles;
  List<BookTocEntry> get tocEntries => _tocEntries;

  int get sectionCount => _sectionMap?.sectionCount ?? 0;
  int get sectionIndex => _sectionIndex;
  double get progressInSection => _progressInSection;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  BookReadingTheme get readingTheme => _readingTheme;
  double get margin => _margin;
  BookReadingMode get readingMode => _readingMode;
  BookPageTurnEffect get pageTurnEffect => _pageTurnEffect;

  bool get hasPageMode =>
      _readingMode == BookReadingMode.page && _externalNextPage != null;
  List<ReaderBookmark> get bookmarks => _bookmarks;

  bool get canGoPreviousPage => _externalPreviousPage != null;
  bool get canGoNextPage => _externalNextPage != null;

  /// Pending programmatic jump (restore / TOC / bookmark). Not cleared until
  /// the active view reports success via [clearPendingJump].
  BookLocator? get pendingJump => _pendingJumpLocator;

  BookLocator get currentLocator => BookLocator(
    sectionIndex: _sectionIndex,
    progressInSection: _progressInSection,
    cfi: _renditionCfi,
  );

  ReaderBookmark? get currentBookmark {
    for (final bookmark in _bookmarks) {
      final locator = _validBookmarkLocator(bookmark);
      if (locator != null && _samePosition(locator, currentLocator)) {
        return bookmark;
      }
    }
    return null;
  }

  bool get isCurrentPositionBookmarked => currentBookmark != null;

  String get sectionLabel {
    final total = sectionCount;
    if (total <= 0) return '—';
    return '${_sectionIndex + 1} / $total';
  }

  String get pageLabel {
    return '$sectionLabel 节';
  }

  String get progressPercentLabel {
    final pct = (progressFraction * 100).toStringAsFixed(1);
    return '$pct%';
  }

  double get progressFraction {
    final renditionProgress = _renditionProgress;
    if (renditionProgress != null) {
      return renditionProgress.clamp(0.0, 1.0);
    }
    final total = sectionCount;
    if (total <= 0) return 0;
    if (total == 1) return _progressInSection.clamp(0.0, 1.0);
    return ((_sectionIndex + _progressInSection) / total).clamp(0.0, 1.0);
  }

  // ------------------------------------------------------------------
  // Engine lifecycle
  // ------------------------------------------------------------------

  /// Reads the native CFI before the WebView starts so the renderer can open
  /// directly at the saved position instead of painting page one and jumping.
  Future<BookLocator?> loadInitialLocator() async {
    if (_progressLocatorJson != null) {
      return BookLocator.tryDecode(_progressLocatorJson!);
    }
    final row = await database.progressFor(item.id);
    if (row == null || _disposed) return null;
    _progressLocatorJson = row.locatorJson;
    return BookLocator.tryDecode(row.locatorJson);
  }

  /// Called by the engine adapter once parsing is done and the flat-paragraph
  /// boundaries are known.
  Future<void> attachEngine(
    BookSectionMap map,
    List<String> tocTitles, {
    List<BookTocEntry> tocEntries = const [],
  }) async {
    if (_disposed) return;
    final generation = ++_attachGeneration;
    _ready = false;
    _sectionMap = map;
    _tocTitles = List.unmodifiable(tocTitles);
    _tocEntries = List.unmodifiable(
      tocEntries.isEmpty
          ? [
              for (var i = 0; i < tocTitles.length; i++)
                BookTocEntry(title: tocTitles[i], href: '', sectionIndex: i),
            ]
          : tocEntries,
    );
    final locator = await _restoreProgress(map);
    if (_disposed || generation != _attachGeneration) return;
    if (locator != null) {
      _sectionIndex = locator.sectionIndex;
      _progressInSection = locator.progressInSection;
      _renditionCfi = locator.cfi;
      _pendingJumpLocator = locator;
    }
    _watchBookmarks();
    _ready = true;
    _openError = null;
    notifyListeners();
    unawaited(database.touchLastOpened(item.id, DateTime.now()));
  }

  void attachExternalPageNavigation({
    required VoidCallback nextPage,
    required VoidCallback previousPage,
  }) {
    _externalNextPage = nextPage;
    _externalPreviousPage = previousPage;
  }

  void detachExternalPageNavigation() {
    _externalNextPage = null;
    _externalPreviousPage = null;
  }

  void reportRenditionLocation({
    required int sectionIndex,
    required double progress,
    required String cfi,
  }) {
    if (_disposed || sectionCount <= 0) return;
    final nextSection = sectionIndex.clamp(0, sectionCount - 1);
    final global = progress.clamp(0.0, 1.0);
    final estimatedLocal = (global * sectionCount - nextSection).clamp(
      0.0,
      1.0,
    );
    _sectionIndex = nextSection;
    _progressInSection = estimatedLocal;
    _renditionProgress = global;
    _renditionCfi = cfi;
    _pendingJumpLocator = null;
    notifyListeners();
    _debouncedPersist();
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

  Future<BookLocator?> _restoreProgress(BookSectionMap map) async {
    // Reuse the locator JSON already loaded for the initial CFI so attach
    // does not pay a second progressFor round-trip on every open.
    var locatorJson = _progressLocatorJson;
    if (locatorJson == null) {
      final row = await database.progressFor(item.id);
      if (row == null || _disposed) return null;
      locatorJson = row.locatorJson;
      _progressLocatorJson = locatorJson;
    }

    BookLocator? locator;

    // 1. Native format.
    locator = BookLocator.tryDecode(
      locatorJson,
    )?.validated(sectionCount: map.sectionCount);

    // 2. Legacy katbook format migration (paragraphIndex/totalParagraphs).
    locator ??= _tryMigrateLegacyLocator(locatorJson, map);

    return _disposed ? null : locator;
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

  void goToSection(int index, {double progressInSection = 0}) {
    final total = sectionCount;
    if (total <= 0) return;
    final next = index.clamp(0, total - 1);
    final progress = progressInSection.clamp(0.0, 1.0);
    if (next == _sectionIndex &&
        (progress - _progressInSection).abs() < 0.0005) {
      return;
    }
    _sectionIndex = next;
    _progressInSection = progress;
    _renditionCfi = null;
    _renditionProgress = null;
    _pendingJumpLocator = BookLocator(
      sectionIndex: _sectionIndex,
      progressInSection: _progressInSection,
    );
    notifyListeners();
    _debouncedPersist();
  }

  void goToTocEntry(BookTocEntry entry, {double progressInSection = 0}) {
    final index = entry.sectionIndex;
    if (index == null) return;
    goToSection(index, progressInSection: progressInSection);
  }

  void goToLocator(BookLocator locator) {
    goToSection(
      locator.sectionIndex,
      progressInSection: locator.progressInSection,
    );
  }

  void goNextSection() => goToSection(_sectionIndex + 1);

  void goPreviousSection() => goToSection(_sectionIndex - 1);

  // ------------------------------------------------------------------
  // Page-mode navigation
  // ------------------------------------------------------------------

  void goNextPage() {
    final external = _externalNextPage;
    external?.call();
  }

  void goPreviousPage() {
    final external = _externalPreviousPage;
    external?.call();
  }

  void clearPendingJump() {
    _pendingJumpLocator = null;
  }

  // ------------------------------------------------------------------
  // Bookmarks
  // ------------------------------------------------------------------

  void _watchBookmarks() {
    _bookmarksSubscription?.cancel();
    _bookmarksSubscription = database.watchBookmarksFor(item.id).listen((rows) {
      if (_disposed) return;
      final valid =
          rows.where((row) => _validBookmarkLocator(row) != null).toList()
            ..sort((a, b) {
              final left = _validBookmarkLocator(a)!;
              final right = _validBookmarkLocator(b)!;
              final section = left.sectionIndex.compareTo(right.sectionIndex);
              return section != 0
                  ? section
                  : left.progressInSection.compareTo(right.progressInSection);
            });
      _bookmarks = List.unmodifiable(valid);
      notifyListeners();
    });
  }

  BookLocator? _validBookmarkLocator(ReaderBookmark bookmark) {
    return BookLocator.tryDecode(
      bookmark.locatorJson,
    )?.validated(sectionCount: sectionCount);
  }

  bool _samePosition(BookLocator a, BookLocator b) {
    if (a.cfi != null && b.cfi != null) return a.cfi == b.cfi;
    return a.sectionIndex == b.sectionIndex &&
        (a.progressInSection - b.progressInSection).abs() < 0.01;
  }

  String bookmarkLabel(ReaderBookmark bookmark) {
    final locator = _validBookmarkLocator(bookmark);
    if (locator == null) return '位置不可用';
    final title = locator.sectionIndex < _tocTitles.length
        ? _tocTitles[locator.sectionIndex]
        : '第 ${locator.sectionIndex + 1} 节';
    final percent = (locator.progressInSection * 100).round();
    return '$title · $percent%';
  }

  Future<void> toggleBookmark() async {
    final existing = currentBookmark;
    if (existing != null) {
      await database.deleteBookmark(existing.id);
      return;
    }
    if (sectionCount <= 0) return;
    await database.addBookmark(
      itemId: item.id,
      locatorJson: currentLocator.encode(),
    );
  }

  void goToBookmark(ReaderBookmark bookmark) {
    final locator = _validBookmarkLocator(bookmark);
    if (locator == null) return;
    _sectionIndex = locator.sectionIndex;
    _progressInSection = locator.progressInSection;
    _pendingJumpLocator = locator;
    notifyListeners();
    _debouncedPersist();
  }

  Future<void> removeBookmark(ReaderBookmark bookmark) {
    return database.deleteBookmark(bookmark.id);
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
    if (mode == BookReadingMode.scroll && !scrollModeEnabled) return;
    if (mode == _readingMode) return;
    _readingMode = mode;
    // Foliate reflows in place. Re-applying the stable locator after a mode
    // switch keeps the same semantic position without a Dart page map.
    _pendingJumpLocator = currentLocator;
    notifyListeners();
    await _prefs?.setReadingMode(mode);
  }

  Future<void> setPageTurnEffect(BookPageTurnEffect effect) async {
    if (effect == _pageTurnEffect) return;
    _pageTurnEffect = effect;
    notifyListeners();
    await _prefs?.setPageTurnEffect(effect);
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
    final locator = currentLocator;
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
    _attachGeneration++;
    _saveDebounce?.cancel();
    _externalNextPage = null;
    _externalPreviousPage = null;
    unawaited(_bookmarksSubscription?.cancel());
    unawaited(_persist());
    super.dispose();
  }
}

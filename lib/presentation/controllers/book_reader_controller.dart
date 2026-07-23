import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/book_reading_preferences.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/foliate_js_bridge.dart';

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
       _verticalMargin =
           readingPreferences?.verticalMargin ??
           BookReadingPreferences.defaultVerticalMargin,
       _bold = readingPreferences?.bold ?? BookReadingPreferences.defaultBold,
       _brightness =
           readingPreferences?.brightness ??
           BookReadingPreferences.defaultBrightness,
       _bodyFont =
           readingPreferences?.bodyFont ?? BookReadingPreferences.defaultBodyFont,
       _letterSpacing =
           readingPreferences?.letterSpacing ??
           BookReadingPreferences.defaultLetterSpacing,
       _paragraphSpacing =
           readingPreferences?.paragraphSpacing ??
           BookReadingPreferences.defaultParagraphSpacing,
       _textAlign =
           readingPreferences?.textAlign ??
           BookReadingPreferences.defaultTextAlign,
       _firstLineIndent =
           readingPreferences?.firstLineIndent ??
           BookReadingPreferences.defaultFirstLineIndent,
       _hyphenate =
           readingPreferences?.hyphenate ??
           BookReadingPreferences.defaultHyphenate,
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
  double _verticalMargin;
  bool _bold;
  double _brightness;
  BookBodyFont _bodyFont;
  double _letterSpacing;
  double _paragraphSpacing;
  BookTextAlign _textAlign;
  bool _firstLineIndent;
  bool _hyphenate;
  BookReadingMode _readingMode;
  BookPageTurnEffect _pageTurnEffect;

  Timer? _saveDebounce;
  BookLocator? _pendingJumpLocator;
  String? _progressLocatorJson;
  List<ReaderBookmark> _bookmarks = const [];
  StreamSubscription<List<ReaderBookmark>>? _bookmarksSubscription;
  List<BookAnnotation> _annotations = const [];
  StreamSubscription<List<BookAnnotation>>? _annotationsSubscription;
  BookSelectionMenu? _selectionMenu;
  /// Brief lock while pressing the Flutter bubble / applying a style.
  bool _selectionClearLocked = false;
  Timer? _selectionClearLockTimer;
  /// Foliate asks for annotations at open; DB watch may emit later.
  bool _annotationsHydrated = false;
  bool _annotationsRenderRequested = false;
  /// Ignore overlayer taps right after dismiss (same click would reopen ②).
  DateTime? _ignoreAnnotationClickUntil;
  /// Last tab in the nav drawer (目录 / 书签 / 笔记).
  int _navDrawerTabIndex = 0;

  bool _searchOpen = false;
  String _searchQuery = '';
  bool _searchRunning = false;
  double _searchProgress = 0;
  List<FoliateSearchHit> _searchHits = const [];
  int _searchGeneration = 0;
  String? _imageViewerDataUrl;

  VoidCallback? _externalNextPage;
  VoidCallback? _externalPreviousPage;
  void Function(double fraction)? _externalSeek;
  void Function(List<Map<String, Object?>> annotations)? _renderAnnotations;
  void Function(Map<String, Object?> annotation)? _addAnnotationToEngine;
  void Function(String cfi)? _removeAnnotationFromEngine;
  VoidCallback? _clearWebSelection;
  Future<String> Function()? _getSelectedText;
  void Function(Map<String, double>? zone)? _setMenuCursorZone;
  void Function(bool open)? _setMenuOpen;
  void Function(String query)? _runSearch;
  VoidCallback? _clearSearch;
  String? _renditionCfi;
  double? _renditionProgress;
  String? _chapterTitle;
  int? _bookCurrentPage;
  int? _bookTotalPages;

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
  double get verticalMargin => _verticalMargin;
  bool get bold => _bold;
  double get brightness => _brightness;
  BookBodyFont get bodyFont => _bodyFont;
  double get letterSpacing => _letterSpacing;
  double get paragraphSpacing => _paragraphSpacing;
  BookTextAlign get textAlign => _textAlign;
  bool get firstLineIndent => _firstLineIndent;
  bool get hyphenate => _hyphenate;
  BookReadingMode get readingMode => _readingMode;
  BookPageTurnEffect get pageTurnEffect => _pageTurnEffect;

  bool get hasPageMode =>
      _readingMode == BookReadingMode.page && _externalNextPage != null;
  List<ReaderBookmark> get bookmarks => _bookmarks;
  List<BookAnnotation> get annotations => _annotations;
  BookSelectionMenu? get selectionMenu => _selectionMenu;
  int get navDrawerTabIndex => _navDrawerTabIndex;

  bool get searchOpen => _searchOpen;
  String get searchQuery => _searchQuery;
  bool get searchRunning => _searchRunning;
  double get searchProgress => _searchProgress;
  List<FoliateSearchHit> get searchHits => _searchHits;
  String? get imageViewerDataUrl => _imageViewerDataUrl;
  bool get imageViewerOpen => _imageViewerDataUrl != null;

  /// Opens the note editor (list / note bubble). Set by [BookReaderScreen].
  void Function(BookAnnotation note)? onOpenNoteEditor;

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

  /// Current TOC chapter for the WeChat-style page meta (top-left).
  String get currentChapterTitle {
    final live = _chapterTitle?.trim();
    if (live != null && live.isNotEmpty) return live;
    if (_sectionIndex >= 0 && _sectionIndex < _tocTitles.length) {
      final title = _tocTitles[_sectionIndex].trim();
      if (title.isNotEmpty) return title;
    }
    return item.title;
  }

  /// Whole-book progress for the WeChat-style page meta (bottom-right).
  /// Prefers Foliate location pages (`20 / 5856`); falls back to percent.
  String get bookProgressLabel {
    final current = _bookCurrentPage;
    final total = _bookTotalPages;
    if (current != null && total != null && total > 0) {
      return '$current / $total';
    }
    return progressPercentLabel;
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
    _watchAnnotations();
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

  void attachExternalSeek(void Function(double fraction) seek) {
    _externalSeek = seek;
  }

  void detachExternalSeek() {
    _externalSeek = null;
  }

  void attachAnnotationBridge({
    required void Function(List<Map<String, Object?>> annotations) renderAll,
    required void Function(Map<String, Object?> annotation) add,
    required void Function(String cfi) remove,
    required VoidCallback clearSelection,
    required Future<String> Function() getSelectedText,
    required void Function(Map<String, double>? zone) setMenuCursorZone,
    required void Function(bool open) setMenuOpen,
  }) {
    _renderAnnotations = renderAll;
    _addAnnotationToEngine = add;
    _removeAnnotationFromEngine = remove;
    _clearWebSelection = clearSelection;
    _getSelectedText = getSelectedText;
    _setMenuCursorZone = setMenuCursorZone;
    _setMenuOpen = setMenuOpen;
  }

  void attachSearchBridge({
    required void Function(String query) search,
    required VoidCallback clearSearch,
  }) {
    _runSearch = search;
    _clearSearch = clearSearch;
  }

  void detachSearchBridge() {
    _runSearch = null;
    _clearSearch = null;
  }

  void detachAnnotationBridge() {
    _renderAnnotations = null;
    _addAnnotationToEngine = null;
    _removeAnnotationFromEngine = null;
    _clearWebSelection = null;
    _getSelectedText = null;
    _setMenuCursorZone = null;
    _setMenuOpen = null;
  }

  /// Foliate `renderAnnotations` handler — may arrive before DB watch emits.
  void requestAnnotationsRender() {
    _annotationsRenderRequested = true;
    if (_annotationsHydrated) {
      pushAnnotationsToEngine();
    }
  }

  /// Push current DB annotations into Foliate (open / section overlay / heal).
  void pushAnnotationsToEngine() {
    final render = _renderAnnotations;
    if (render == null) return;
    render([
      for (final annotation in _annotations) annotation.toFoliateJson(),
    ]);
    _annotationsRenderRequested = false;
  }

  /// Optimistic scrub to a whole-book fraction; Foliate relocate confirms CFI.
  void seekToFraction(double fraction) {
    if (_disposed || !_ready) return;
    final next = fraction.clamp(0.0, 1.0);
    _renditionProgress = next;
    notifyListeners();
    _externalSeek?.call(next);
  }

  void reportRenditionLocation({
    required int sectionIndex,
    required double progress,
    required String cfi,
    String? chapterTitle,
    int? bookCurrentPage,
    int? bookTotalPages,
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
    if (chapterTitle != null && chapterTitle.trim().isNotEmpty) {
      _chapterTitle = chapterTitle.trim();
    }
    if (bookCurrentPage != null && bookCurrentPage > 0) {
      _bookCurrentPage = bookCurrentPage;
    }
    if (bookTotalPages != null && bookTotalPages > 0) {
      _bookTotalPages = bookTotalPages;
    }
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
  // Selection / annotations
  // ------------------------------------------------------------------

  void _watchAnnotations() {
    _annotationsSubscription?.cancel();
    _annotationsHydrated = false;
    _annotationsSubscription = database.watchAnnotationsFor(item.id).listen((
      rows,
    ) {
      if (_disposed) return;
      _annotations = List.unmodifiable(rows);
      _annotationsHydrated = true;
      notifyListeners();
      // Heal open race: Foliate may have called renderAnnotations before the
      // first watch emission. addAnnotation replaces by CFI so re-push is safe.
      if (_annotationsRenderRequested) {
        pushAnnotationsToEngine();
      }
    });
  }

  void reportSelectionEnd(FoliateSelectionEnd selection) {
    if (_disposed) return;
    if (selection.footnote) {
      clearSelectionMenu();
      return;
    }
    hideChrome();
    final matched = _annotationForCfi(selection.cfi);
    _selectionMenu = BookSelectionMenu(
      cfi: selection.cfi,
      text: selection.text,
      left: selection.pos.left,
      top: selection.pos.top,
      right: selection.pos.right,
      bottom: selection.pos.bottom,
      phase: BookSelectionMenuPhase.actions,
      annotationId: matched?.id,
      annotationType: matched?.type,
      annotationColorCss: matched?.colorCss,
      note: matched?.note,
      fromAnnotation: matched != null,
    );
    _setMenuOpen?.call(true);
    notifyListeners();
  }

  void reportSelectionCleared() {
    // Deselect → close immediately (Anx default). Only ignore while a bubble
    // press / style write briefly locks to survive focus-loss clears.
    if (_selectionClearLocked) return;
    if (_selectionMenu == null) return;
    clearSelectionMenu(clearWebSelection: false);
  }

  void reportAnnotationClick(FoliateAnnotationClick click) {
    if (_disposed) return;
    final ignoreUntil = _ignoreAnnotationClickUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }
    hideChrome();
    BookAnnotation? matched;
    for (final row in _annotations) {
      if (row.cfi == click.cfi) {
        matched = row;
        break;
      }
    }
    final type = BookAnnotationType.fromStorage(click.type);
    final contextText = click.contextText?.trim() ?? '';
    final storedQuote = matched?.selectedText?.trim() ?? '';
    // Heal older rows that lost selectedText (upsert used to wipe it).
    if (matched != null && storedQuote.isEmpty && contextText.isNotEmpty) {
      unawaited(
        database.upsertAnnotation(
          itemId: item.id,
          cfi: matched.cfi,
          type: matched.type.storageValue,
          color: matched.colorCss,
          selectedText: contextText,
        ),
      );
    }
    _selectionMenu = BookSelectionMenu(
      cfi: click.cfi,
      text: storedQuote.isNotEmpty ? storedQuote : contextText,
      left: click.pos.left,
      top: click.pos.top,
      right: click.pos.right,
      bottom: click.pos.bottom,
      phase: BookSelectionMenuPhase.markup,
      annotationId: matched?.id ?? click.id,
      annotationType: type ?? matched?.type,
      annotationColorCss: click.color,
      note: matched?.note ?? click.note,
      fromAnnotation: true,
    );
    // Clicking an existing mark often collapses any leftover Range; hold
    // briefly so the markup panel is not torn down by that clear.
    retainSelectionMenuForInteraction();
    _setMenuOpen?.call(true);
    notifyListeners();
  }

  /// Enter ②. Fresh selections immediately paint a default underline (Anx
  /// autoMarkSelection equivalent) so the range stays visible after the
  /// native DOM selection collapses when the Flutter bubble takes focus
  /// (macOS/Windows Platform Views; `pointer_interceptor` is iOS/web only).
  Future<void> openMarkupPhase() async {
    final menu = _selectionMenu;
    if (menu == null) return;
    retainSelectionMenuForInteraction();
    if (menu.phase == BookSelectionMenuPhase.markup &&
        menu.annotationId != null) {
      return;
    }
    if (menu.annotationId != null || menu.fromAnnotation) {
      if (menu.phase != BookSelectionMenuPhase.markup) {
        _selectionMenu = menu.copyWith(phase: BookSelectionMenuPhase.markup);
        notifyListeners();
      }
      return;
    }
    // 划线 = commit default mark (kept on menu dismiss; 清空 to delete).
    await applyAnnotationStyle(
      type: BookAnnotationType.underline,
      color: BookHighlightColor.yellow,
      dismissMenu: false,
    );
  }

  void clearSelectionMenu({bool clearWebSelection = true}) {
    _selectionClearLockTimer?.cancel();
    _selectionClearLocked = false;
    // Same pointer that dismissed can hit the overlayer next — ignore briefly.
    _ignoreAnnotationClickUntil =
        DateTime.now().add(const Duration(milliseconds: 800));
    if (_selectionMenu == null) {
      _setMenuOpen?.call(false);
      _setMenuCursorZone?.call(null);
      return;
    }
    _selectionMenu = null;
    _setMenuOpen?.call(false);
    _setMenuCursorZone?.call(null);
    // Anx only clears the native selection when the menu closes.
    if (clearWebSelection) {
      _clearWebSelection?.call();
    }
    notifyListeners();
  }

  /// Call from the bubble on pointer-down so focus-loss selection clears do
  /// not dismiss mid-tap. Auto-unlocks; a later real deselect will close.
  void retainSelectionMenuForInteraction() {
    _selectionClearLocked = true;
    _selectionClearLockTimer?.cancel();
    _selectionClearLockTimer = Timer(const Duration(milliseconds: 500), () {
      _selectionClearLocked = false;
    });
  }

  /// Normalized viewport box for the Flutter menu bubble (Platform View cursor).
  void setMenuCursorZone({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    _setMenuCursorZone?.call({
      'left': left.clamp(0.0, 1.0),
      'top': top.clamp(0.0, 1.0),
      'right': right.clamp(0.0, 1.0),
      'bottom': bottom.clamp(0.0, 1.0),
    });
  }

  /// Returns true when text was written to the clipboard.
  Future<bool> copySelection({String? textOverride}) async {
    var text = (textOverride ?? _selectionMenu?.text ?? '').trim();
    if (text.isEmpty) {
      text = ((await _getSelectedText?.call()) ?? '').trim();
    }
    if (text.isEmpty) {
      _clearWebSelection?.call();
      clearSelectionMenu();
      return false;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _clearWebSelection?.call();
    clearSelectionMenu();
    return true;
  }

  /// Legacy clipboard excerpt helper (金句卡走 [showBookExcerptSheet]).
  Future<bool> copyExcerpt({String? textOverride}) =>
      copySelection(textOverride: textOverride);

  Future<void> applyAnnotationStyle({
    required BookAnnotationType type,
    required BookHighlightColor color,
    String? cfiOverride,
    String? textOverride,
    bool dismissMenu = true,
  }) async {
    final menu = _selectionMenu;
    final cfi = (cfiOverride ?? menu?.cfi ?? '').trim();
    if (cfi.isEmpty) return;
    retainSelectionMenuForInteraction();
    final selectedText = (textOverride ?? menu?.text ?? '').trim();
    final id = await database.upsertAnnotation(
      itemId: item.id,
      cfi: cfi,
      type: type.storageValue,
      color: color.css,
      selectedText: selectedText.isEmpty ? null : selectedText,
    );
    if (_disposed) return;
    // Keep note in the engine payload so the「注」bubble is not dropped on
    // style-only upserts (JS replace-by-cfi).
    final existingNote =
        _selectionMenu?.note ?? _annotationForCfi(cfi)?.note;
    _addAnnotationToEngine?.call({
      'id': id,
      'value': cfi,
      'type': type.storageValue,
      'color': color.css,
      'replace': true,
      if (existingNote != null && existingNote.trim().isNotEmpty)
        'note': existingNote.trim(),
    });
    if (dismissMenu) {
      clearSelectionMenu();
    } else if (menu != null) {
      _selectionMenu = menu.copyWith(
        phase: BookSelectionMenuPhase.markup,
        annotationId: id,
        annotationType: type,
        annotationColorCss: color.css,
        fromAnnotation: true,
      );
      notifyListeners();
    }
  }

  Future<void> removeActiveAnnotation() async {
    final menu = _selectionMenu;
    if (menu == null) return;
    if (menu.annotationId != null) {
      await database.deleteAnnotation(menu.annotationId!);
    } else {
      await database.deleteAnnotationByCfi(itemId: item.id, cfi: menu.cfi);
    }
    if (_disposed) return;
    _removeAnnotationFromEngine?.call(menu.cfi);
    _clearWebSelection?.call();
    clearSelectionMenu();
  }

  /// Annotations that carry a non-empty note (for the notes list).
  List<BookAnnotation> get notes {
    final rows = [
      for (final row in _annotations)
        if (row.note != null && row.note!.trim().isNotEmpty) row,
    ];
    // Newest first (DB watch is ascending by createdAt).
    return List.unmodifiable(rows.reversed);
  }

  String noteLabel(BookAnnotation annotation) {
    final note = annotation.note?.trim() ?? '';
    if (note.isNotEmpty) return note;
    final text = annotation.selectedText?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return '笔记';
  }

  /// Chapter title for a note row (from CFI spine index + TOC titles).
  String? noteChapterTitle(BookAnnotation annotation) {
    final index = BookLocator.sectionIndexFromCfi(annotation.cfi);
    if (index == null) return null;
    if (index >= 0 && index < _tocTitles.length) {
      final title = _tocTitles[index].trim();
      if (title.isNotEmpty) return title;
    }
    for (final entry in _tocEntries) {
      if (entry.sectionIndex == index) {
        final title = entry.title.trim();
        if (title.isNotEmpty) return title;
      }
    }
    if (sectionCount > 0 && index < sectionCount) {
      return '第 ${index + 1} 节';
    }
    return null;
  }

  /// Original quote for the subtitle — always the selected range when stored.
  String? noteExcerpt(BookAnnotation annotation) {
    final text = annotation.selectedText?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// List subtitle: **原文摘录** first. Chapter alone is useless when many notes
  /// share a section — only used as a fallback label when quote is missing.
  String noteListSubtitle(BookAnnotation annotation) {
    final quote = noteExcerpt(annotation);
    if (quote != null) return quote;
    final chapter = noteChapterTitle(annotation);
    if (chapter != null) return '$chapter（无原文）';
    return '（无原文摘录）';
  }

  void setNavDrawerTabIndex(int index) {
    final next = index.clamp(0, 2);
    if (next == _navDrawerTabIndex) return;
    _navDrawerTabIndex = next;
  }

  BookAnnotation? _annotationForCfi(String cfi) {
    final key = cfi.trim();
    if (key.isEmpty) return null;
    for (final row in _annotations) {
      if (row.cfi == key) return row;
    }
    return null;
  }

  void goToAnnotation(BookAnnotation annotation) {
    final cfi = annotation.cfi.trim();
    if (cfi.isEmpty) return;
    final fromCfi = BookLocator.sectionIndexFromCfi(cfi);
    final sectionIndex = (fromCfi != null &&
            (sectionCount <= 0 || fromCfi < sectionCount))
        ? fromCfi
        : _sectionIndex;
    _sectionIndex = sectionIndex;
    _pendingJumpLocator = BookLocator(
      sectionIndex: sectionIndex,
      progressInSection: _progressInSection,
      cfi: cfi,
    );
    notifyListeners();
  }

  void openSearch({String? initialQuery}) {
    clearSelectionMenu();
    hideChrome();
    final query = initialQuery?.trim() ?? '';
    _searchOpen = true;
    if (query.isNotEmpty) {
      _searchQuery = query;
      notifyListeners();
      submitSearch(query);
      return;
    }
    notifyListeners();
  }

  void closeSearch() {
    if (!_searchOpen && !_searchRunning && _searchHits.isEmpty) return;
    _searchGeneration++;
    _searchOpen = false;
    _searchRunning = false;
    _searchProgress = 0;
    _searchHits = const [];
    _clearSearch?.call();
    notifyListeners();
  }

  void submitSearch(String query) {
    final trimmed = query.trim();
    _searchQuery = trimmed;
    if (trimmed.isEmpty) {
      _searchGeneration++;
      _searchRunning = false;
      _searchProgress = 0;
      _searchHits = const [];
      _clearSearch?.call();
      notifyListeners();
      return;
    }
    final generation = ++_searchGeneration;
    _searchRunning = true;
    _searchProgress = 0;
    _searchHits = const [];
    notifyListeners();
    _clearSearch?.call();
    _runSearch?.call(trimmed);
    // Stale generations are ignored in reportSearchEvent.
    if (generation != _searchGeneration) return;
  }

  void reportSearchEvent(FoliateSearchEvent event) {
    if (_disposed || !_searchOpen) return;
    final generation = _searchGeneration;
    switch (event) {
      case FoliateSearchProgress(:final fraction):
        if (generation != _searchGeneration) return;
        _searchProgress = fraction;
        notifyListeners();
      case FoliateSearchDone():
        if (generation != _searchGeneration) return;
        _searchRunning = false;
        _searchProgress = 1;
        notifyListeners();
      case FoliateSearchChapterHits(:final hits):
        if (generation != _searchGeneration) return;
        _searchHits = [..._searchHits, ...hits];
        notifyListeners();
    }
  }

  void goToSearchHit(FoliateSearchHit hit) {
    final cfi = hit.cfi.trim();
    if (cfi.isEmpty) return;
    final fromCfi = BookLocator.sectionIndexFromCfi(cfi);
    final sectionIndex = (fromCfi != null &&
            (sectionCount <= 0 || fromCfi < sectionCount))
        ? fromCfi
        : _sectionIndex;
    _sectionIndex = sectionIndex;
    _pendingJumpLocator = BookLocator(
      sectionIndex: sectionIndex,
      progressInSection: _progressInSection,
      cfi: cfi,
    );
    // 关掉面板看正文；引擎高亮保留到下次搜索或点关闭。
    _searchOpen = false;
    _searchRunning = false;
    notifyListeners();
  }

  void openImageViewer(String dataUrl) {
    final url = dataUrl.trim();
    if (!url.startsWith('data:')) return;
    clearSelectionMenu();
    hideChrome();
    _imageViewerDataUrl = url;
    notifyListeners();
  }

  void closeImageViewer() {
    if (_imageViewerDataUrl == null) return;
    _imageViewerDataUrl = null;
    notifyListeners();
  }

  /// Write or clear the note on a range. Empty [noteText] clears note only;
  /// creates a default underline if the range has no annotation yet.
  Future<void> saveAnnotationNote({
    required String cfi,
    required String noteText,
    String? selectedText,
    BookAnnotationType? type,
    String? colorCss,
  }) async {
    final key = cfi.trim();
    if (key.isEmpty) return;
    final trimmed = noteText.trim();
    final existing = _annotationForCfi(key);
    if (trimmed.isEmpty && existing == null) return;

    final resolvedType =
        type ??
        existing?.type ??
        BookAnnotationType.underline;
    final resolvedColor = BookHighlightColor.fromCss(
      colorCss ?? existing?.colorCss ?? BookHighlightColor.yellow.css,
    );
    // Empty string from UI must not erase a previously stored quote.
    final incoming = selectedText?.trim() ?? '';
    final text = incoming.isNotEmpty
        ? incoming
        : (existing?.selectedText?.trim() ?? '');
    final noteValue = trimmed.isEmpty ? null : trimmed;

    final id = await database.upsertAnnotation(
      itemId: item.id,
      cfi: key,
      type: resolvedType.storageValue,
      color: resolvedColor.css,
      selectedText: text.isEmpty ? null : text,
      note: noteValue,
      writeNote: true,
    );
    if (_disposed) return;
    _addAnnotationToEngine?.call({
      'id': id,
      'value': key,
      'type': resolvedType.storageValue,
      'color': resolvedColor.css,
      'replace': true,
      'note': ?noteValue,
    });
  }

  /// Clear note from the list; keeps underline / highlight.
  Future<void> clearAnnotationNote(BookAnnotation annotation) {
    return saveAnnotationNote(
      cfi: annotation.cfi,
      noteText: '',
      selectedText: annotation.selectedText,
      type: annotation.type,
      colorCss: annotation.colorCss,
    );
  }

  /// Note bubble / list: jump optional caller, then present the editor.
  void openNoteEditor(BookAnnotation annotation) {
    clearSelectionMenu(clearWebSelection: false);
    onOpenNoteEditor?.call(annotation);
  }

  /// Foliate note-marker tap — open editor, not markup ②.
  void reportAnnotationNoteClick(FoliateAnnotationClick click) {
    if (_disposed) return;
    // Keep WebView selection untouched; clearing it reflows the paginator.
    if (_selectionMenu != null) {
      clearSelectionMenu(clearWebSelection: false);
    }
    final matched = _annotationForCfi(click.cfi);
    final noteText = (matched?.note ?? click.note)?.trim() ?? '';
    final forEditor =
        matched ??
        BookAnnotation(
          id: click.id ?? 0,
          cfi: click.cfi,
          type:
              BookAnnotationType.fromStorage(click.type) ??
              BookAnnotationType.underline,
          colorCss: click.color,
          selectedText: matched?.selectedText,
          note: noteText.isEmpty ? null : noteText,
          createdAt: DateTime.now(),
        );
    onOpenNoteEditor?.call(forEditor);
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

  Future<void> setVerticalMargin(double margin) async {
    final next = margin.clamp(
      BookReadingPreferences.minVerticalMargin,
      BookReadingPreferences.maxVerticalMargin,
    );
    if (next == _verticalMargin) return;
    _verticalMargin = next;
    notifyListeners();
    await _prefs?.setVerticalMargin(next);
  }

  Future<void> setBold(bool bold) async {
    if (bold == _bold) return;
    _bold = bold;
    notifyListeners();
    await _prefs?.setBold(bold);
  }

  Future<void> setBrightness(double value) async {
    final next = value.clamp(
      BookReadingPreferences.minBrightness,
      BookReadingPreferences.maxBrightness,
    );
    if (next == _brightness) {
      await _prefs?.setBrightness(next);
      return;
    }
    _brightness = next;
    notifyListeners();
    await _prefs?.setBrightness(next);
  }

  /// Live dimming while dragging; persist with [setBrightness] on drag end.
  void previewBrightness(double value) {
    final next = value.clamp(
      BookReadingPreferences.minBrightness,
      BookReadingPreferences.maxBrightness,
    );
    if (next == _brightness) return;
    _brightness = next;
    notifyListeners();
  }

  Future<void> setBodyFont(BookBodyFont font) async {
    if (font == _bodyFont) return;
    _bodyFont = font;
    notifyListeners();
    await _prefs?.setBodyFont(font);
  }

  Future<void> setLetterSpacing(double spacing) async {
    final next = spacing.clamp(
      BookReadingPreferences.minLetterSpacing,
      BookReadingPreferences.maxLetterSpacing,
    );
    if (next == _letterSpacing) return;
    _letterSpacing = next;
    notifyListeners();
    await _prefs?.setLetterSpacing(next);
  }

  Future<void> setParagraphSpacing(double spacing) async {
    final next = spacing.clamp(
      BookReadingPreferences.minParagraphSpacing,
      BookReadingPreferences.maxParagraphSpacing,
    );
    if (next == _paragraphSpacing) return;
    _paragraphSpacing = next;
    notifyListeners();
    await _prefs?.setParagraphSpacing(next);
  }

  Future<void> setTextAlign(BookTextAlign align) async {
    if (align == _textAlign) return;
    _textAlign = align;
    notifyListeners();
    await _prefs?.setTextAlign(align);
  }

  Future<void> setFirstLineIndent(bool enabled) async {
    if (enabled == _firstLineIndent) return;
    _firstLineIndent = enabled;
    notifyListeners();
    await _prefs?.setFirstLineIndent(enabled);
  }

  Future<void> setHyphenate(bool enabled) async {
    if (enabled == _hyphenate) return;
    _hyphenate = enabled;
    notifyListeners();
    await _prefs?.setHyphenate(enabled);
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
    _selectionClearLockTimer?.cancel();
    _externalNextPage = null;
    _externalPreviousPage = null;
    _externalSeek = null;
    detachAnnotationBridge();
    detachSearchBridge();
    unawaited(_bookmarksSubscription?.cancel());
    unawaited(_annotationsSubscription?.cancel());
    unawaited(_persist());
    super.dispose();
  }
}

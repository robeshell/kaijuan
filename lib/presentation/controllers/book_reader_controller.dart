import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_chat_service.dart';
import '../../ai/ai_chat_tools.dart';
import '../../ai/ai_graph.dart';
import '../../ai/ai_graph_service.dart';
import '../../ai/ai_log.dart';
import '../../ai/ai_language_service.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_outline.dart';
import '../../ai/ai_provider.dart';
import '../../ai/ai_search.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_translation.dart';
import '../../app/book_reading_preferences.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/book/book_language_actions.dart';
import '../../readers/book/foliate_js_bridge.dart';
import 'ai_settings_controller.dart';

/// Listen-to-book playback state (system TTS).
enum BookTtsStatus { idle, playing, paused }

/// Owns reflow book session state, chrome, progress, and preferences.
///
/// Rendering details stay in the reader pipeline; this controller is the
/// presentation boundary used by screens and widgets.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required this.database,
    required this.item,
    BookReadingPreferences? readingPreferences,
    BookLanguageProvider? languageProvider,
    AiSettingsController? aiSettings,
    this.scrollModeEnabled = true,
  }) : languageProvider =
           languageProvider ?? const PlatformBookLanguageProvider(),
       _prefs = readingPreferences,
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
       _fontSelection =
           readingPreferences?.fontSelection ??
           BookReadingPreferences.defaultFontSelection,
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
           BookReadingPreferences.defaultPageTurnEffect {
    readingPreferences?.fontStore.addListener(_onFontStoreChanged);
    bindAiSettings(aiSettings);
  }

  void _onFontStoreChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  final AppDatabase database;
  final ReadingItem item;
  final BookLanguageProvider languageProvider;
  AiSettingsController? _aiSettings;
  AiLanguageService? _aiLanguage;
  final BookReadingPreferences? _prefs;
  final bool scrollModeEnabled;
  Future<void> Function()? _clearPlatformFocus;

  /// Wire / re-wire BYOK AI after the widget tree can resolve [AiSettingsScope].
  /// Safe to call repeatedly; no-ops when the controller identity is unchanged.
  void bindAiSettings(AiSettingsController? aiSettings) {
    if (identical(_aiSettings, aiSettings) &&
        (aiSettings == null) == (_aiLanguage == null) &&
        (aiSettings == null) == (_aiChat == null) &&
        (aiSettings == null) == (_aiOutline == null) &&
        (aiSettings == null) == (_aiGraph == null)) {
      return;
    }
    _aiSettings = aiSettings;
    _aiLanguage = aiSettings == null
        ? null
        : AiLanguageService(
            isAvailable: () => aiSettings.isReadyForRequests,
            openProvider: () => aiSettings.openProvider(),
            // Always read live settings so translation prefs pick up changes
            // made while the reader is already open.
            settings: () => aiSettings.settings,
          );
    _aiChat = aiSettings == null
        ? null
        : AiChatService(
            isAvailable: () => aiSettings.isReadyForRequests,
            openProvider: () => aiSettings.openProvider(),
            settings: () => aiSettings.settings,
          );
    _aiOutline = aiSettings == null
        ? null
        : AiBookOutlineService(
            isAvailable: () => aiSettings.isReadyForRequests,
            openProvider: () => aiSettings.openProvider(),
            settings: () => aiSettings.settings,
          );
    _aiGraph = aiSettings == null
        ? null
        : AiBookGraphService(
            isAvailable: () => aiSettings.isReadyForRequests,
            openProvider: () => aiSettings.openProvider(),
            settings: () => aiSettings.settings,
          );
    if (!_disposed) notifyListeners();
  }

  /// True when BYOK AI is enabled and ready for dictionary / translation / chat.
  bool get canUseAiLanguage => _aiLanguage?.isAvailable ?? false;

  /// Same readiness gate as language tools (shared provider + key).
  bool get canUseAiChat => _aiChat?.isAvailable ?? false;

  /// Search API key configured (chat 联网 switch).
  bool get canUseWebSearch => _aiSettings?.isSearchReady ?? false;

  AiSettingsController? get aiSettingsController => _aiSettings;

  /// Live translation prefs from the shared settings controller (not a snapshot).
  AiTranslationPreferences get translationPreferences =>
      _aiSettings?.settings.translation ?? const AiTranslationPreferences();

  /// Authors from EPUB metadata when the book is open (may be empty).
  List<String> get bookAuthors => _bookAuthors;

  /// Display label for AI prompts / UI ("甲、乙").
  String get bookAuthorsLabel => _bookAuthors.join('、');

  /// Called when Foliate reports OPF/publication metadata after open.
  void setPublicationAuthors(List<String> authors) {
    final cleaned = authors
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (_listEqualsString(_bookAuthors, cleaned)) return;
    _bookAuthors = cleaned;
    if (!_disposed) notifyListeners();
  }

  static bool _listEqualsString(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> _bookAuthors = const [];

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
  BookFontSelection _fontSelection;
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

  /// Until this instant, the mobile Flutter dismiss-barrier ignores taps.
  ///
  /// Opening the menu often races the same finger-up that finished the
  /// selection; without a grace window that pointer hits the barrier and used
  /// to dismiss (and historically also page-turn on edge zones).
  DateTime? _selectionMenuBarrierArmAt;

  /// Until this instant, edge/tap page-turns from the WebView are ignored.
  /// Covers the race where `onClick` arrives before/with `onSelectionEnd`.
  DateTime? _suppressPageTurnUntil;

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
  Future<String> Function()? _getChapterText;
  Future<String> Function(int maxChars)? _getReadSoFarText;
  Future<String> Function(int maxChars, {bool toc})? _getBookPlainText;
  Future<({String before, String after})?> Function(int before, int after)?
  _getSelectionContext;
  void Function(Map<String, double>? zone)? _setMenuCursorZone;
  void Function(bool open)? _setMenuOpen;
  AiChatService? _aiChat;
  AiBookOutlineService? _aiOutline;
  AiBookGraphService? _aiGraph;
  AiChatHistoryStore? _chatHistoryStore;
  AiGraphStore? _aiGraphStore;
  AiBookOutline? _bookOutline;

  /// Work key of [_bookOutline] for collections (null = plain book / whole
  /// book). The outline tab follows the reading position: loading/saving
  /// routes to `session.workOutlines[key]`.
  String? _bookOutlineWorkKey;
  AiOutlineProgress? _bookOutlineProgress;
  String? _bookOutlineError;
  CancelToken? _bookOutlineCancel;
  Future<void>? _bookOutlineGeneration;
  AiBookGraph? _bookGraph;

  /// Graph of the work currently shown/generated when viewing a collection
  /// (null for whole-book graphs / plain books).
  AiGraphWorkCandidate? _activeGraphWork;

  /// Per-work graphs of the current collection, keyed by workKey.
  Map<String, AiBookGraph> _workGraphs = {};

  /// Work being generated right now (null = whole book / not generating).
  AiGraphProgress? _bookGraphProgress;
  String? _bookGraphError;

  CancelToken? _bookGraphCancel;
  Future<void>? _bookGraphGeneration;
  Future<void> _chatSessionWriteQueue = Future<void>.value();

  /// Cached multi-section plain text for book chat (per open).
  String? _cachedBookPlainText;
  int _cachedBookPlainTextBudget = 0;
  String? _cachedGraphPlainText;
  int _cachedGraphPlainTextBudget = 0;
  String? _cachedGraphSpineText;
  int _cachedGraphSpineTextBudget = 0;
  void Function(String query)? _runSearch;
  VoidCallback? _clearSearch;
  Future<String?> Function()? _ttsHere;
  Future<String?> Function()? _ttsNext;
  Future<String?> Function()? _ttsPrev;
  Future<void> Function()? _ttsStopEngine;

  FlutterTts? _flutterTts;
  BookTtsStatus _ttsStatus = BookTtsStatus.idle;
  double _ttsRate = 1.0;
  String? _ttsCurrentText;
  int _ttsGeneration = 0;

  /// Completes when the active play loop exits.
  Completer<void>? _ttsLoopIdle;

  /// Completes when the armed utterance ends (complete / cancel).
  Completer<void>? _ttsUtteranceDone;

  /// Only accept engine complete/cancel after [setStartHandler] for this speak.
  /// Prevents a stale `stop()` cancel from closing the *next* utterance gate
  /// (that race was advancing Foliate on rate change).
  bool _ttsUtteranceArmed = false;

  /// Optional one-shot message for UI snackbars (cleared by screen).
  String? ttsUserMessage;
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
  BookFontSelection get fontSelection => _fontSelection;
  BookFontStore? get fontStore => _prefs?.fontStore;
  String get fontLabel {
    switch (_fontSelection.kind) {
      case BookFontKind.book:
        return '图书自带';
      case BookFontKind.system:
        return BookSystemFont.byId(_fontSelection.systemId!)?.label ?? '默认字体';
      case BookFontKind.user:
        return fontStore?.byId(_fontSelection.userFontId!)?.displayName ??
            '用户字体';
    }
  }

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

  /// Whether the full-screen mobile dismiss barrier should honor a tap.
  bool get selectionMenuBarrierAcceptsDismiss {
    if (_selectionMenu == null) return false;
    final armAt = _selectionMenuBarrierArmAt;
    if (armAt == null) return true;
    return !DateTime.now().isBefore(armAt);
  }

  void _armSelectionMenuDismissBarrier() {
    // Long enough to absorb selection finger-up / iOS Platform View handoff.
    _selectionMenuBarrierArmAt = DateTime.now().add(
      const Duration(milliseconds: 450),
    );
  }

  /// True while a just-finished selection should not trigger edge page-turns.
  bool get shouldSuppressPageTurnFromClick {
    final until = _suppressPageTurnUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _armPageTurnSuppressAfterSelection() {
    _suppressPageTurnUntil = DateTime.now().add(
      const Duration(milliseconds: 900),
    );
  }

  int get navDrawerTabIndex => _navDrawerTabIndex;

  bool get searchOpen => _searchOpen;
  String get searchQuery => _searchQuery;
  bool get searchRunning => _searchRunning;
  double get searchProgress => _searchProgress;
  List<FoliateSearchHit> get searchHits => _searchHits;
  String? get imageViewerDataUrl => _imageViewerDataUrl;
  bool get imageViewerOpen => _imageViewerDataUrl != null;

  BookTtsStatus get ttsStatus => _ttsStatus;
  bool get ttsActive => _ttsStatus != BookTtsStatus.idle;
  bool get ttsPlaying => _ttsStatus == BookTtsStatus.playing;
  bool get ttsPaused => _ttsStatus == BookTtsStatus.paused;
  double get ttsRate => _ttsRate;

  static const ttsRatePresets = <double>[0.8, 1.0, 1.25, 1.5];

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

  void attachPlatformFocusClearer(Future<void> Function() clear) {
    _clearPlatformFocus = clear;
  }

  void detachPlatformFocusClearer() {
    _clearPlatformFocus = null;
  }

  Future<void> clearPlatformFocus() async {
    await _clearPlatformFocus?.call();
  }

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
    Future<String> Function()? getChapterText,
    Future<String> Function(int maxChars)? getReadSoFarText,
    Future<String> Function(int maxChars, {bool toc})? getBookPlainText,
    Future<({String before, String after})?> Function(int before, int after)?
    getSelectionContext,
  }) {
    _renderAnnotations = renderAll;
    _addAnnotationToEngine = add;
    _removeAnnotationFromEngine = remove;
    _clearWebSelection = clearSelection;
    _getSelectedText = getSelectedText;
    _setMenuCursorZone = setMenuCursorZone;
    _setMenuOpen = setMenuOpen;
    _getChapterText = getChapterText;
    _getReadSoFarText = getReadSoFarText;
    _getBookPlainText = getBookPlainText;
    _getSelectionContext = getSelectionContext;
  }

  /// Optional chat history store (per contentHash). Null → memory-only session.
  void attachChatHistoryStore(AiChatHistoryStore? store) {
    _chatHistoryStore = store;
  }

  /// Optional graph cache store (per contentHash under `ai_graph/`).
  void attachAiGraphStore(AiGraphStore? store) {
    _aiGraphStore = store;
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

  void attachTtsBridge({
    required Future<String?> Function() here,
    required Future<String?> Function() next,
    required Future<String?> Function() prev,
    required Future<void> Function() stop,
  }) {
    _ttsHere = here;
    _ttsNext = next;
    _ttsPrev = prev;
    _ttsStopEngine = stop;
  }

  void detachTtsBridge() {
    _ttsHere = null;
    _ttsNext = null;
    _ttsPrev = null;
    _ttsStopEngine = null;
  }

  void detachAnnotationBridge() {
    _renderAnnotations = null;
    _addAnnotationToEngine = null;
    _removeAnnotationFromEngine = null;
    _clearWebSelection = null;
    _getSelectedText = null;
    _getChapterText = null;
    _getReadSoFarText = null;
    _getBookPlainText = null;
    _setMenuCursorZone = null;
    _setMenuOpen = null;
    _cachedBookPlainText = null;
    _cachedBookPlainTextBudget = 0;
    _cachedGraphPlainText = null;
    _cachedGraphPlainTextBudget = 0;
    _cachedGraphSpineText = null;
    _cachedGraphSpineTextBudget = 0;
  }

  /// Load or create the chat session for this book (isolated by contentHash).
  Future<AiChatSession> loadChatSession() async {
    final hash = item.contentHash;
    final store = _chatHistoryStore;
    if (store == null) {
      return AiChatSession(contentHash: hash, itemId: item.id);
    }
    return await store.read(contentHash: hash, itemId: item.id) ??
        AiChatSession(contentHash: hash, itemId: item.id);
  }

  Future<void> saveChatSession(AiChatSession session) async {
    await _enqueueChatSessionWrite(() async {
      final store = _chatHistoryStore;
      if (store == null) return;
      // The chat sheet and outline job save independently. Serialize those
      // read-modify-write operations so neither can overwrite the other.
      final current = await store.read(
        contentHash: item.contentHash,
        itemId: item.id,
      );
      // Disk wins for per-work data the sheet snapshot predates: outlines
      // (generation writes there) and workMessages (other works' chats the
      // in-memory session may not carry, e.g. after a whole-book clear reset
      // the snapshot). Merge both so a later _persist never wipes disk.
      final merged = session.copyWith(
        outline: current?.outline != null && session.outline == null
            ? current!.outline
            : session.outline,
        workOutlines: {
          ...session.workOutlines,
          if (current != null) ...current.workOutlines,
        },
        workMessages: {
          if (current != null) ...current.workMessages,
          // The sheet is the live writer for the works it knows about — its
          // entries win over disk for those keys; disk keeps the rest.
          ...session.workMessages,
        },
      );
      await store.write(merged);
    });
  }

  Future<void> _enqueueChatSessionWrite(Future<void> Function() operation) {
    final queued = _chatSessionWriteQueue.then<void>(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _chatSessionWriteQueue = queued.catchError((_) {});
    return queued;
  }

  /// User-initiated only. Do **not** call from library delete — same contentHash
  /// re-import must restore this session (PRODUCT / ai.md §7.3).
  ///
  /// [workKey]: clear only that collection work's messages, leaving the rest
  /// of the session (other works' chats, outlines) intact. Null clears the
  /// whole-book message list (plain books).
  Future<void> clearChatSession({String? workKey}) async {
    await _enqueueChatSessionWrite(() async {
      final store = _chatHistoryStore;
      if (store == null) return;
      final current = await store.read(
        contentHash: item.contentHash,
        itemId: item.id,
      );
      if (current == null) return;
      if (workKey != null) {
        // Collection: drop this work's chat; keep everything else.
        final remaining = {...current.workMessages}..remove(workKey);
        await store.write(current.copyWith(workMessages: remaining));
        return;
      }
      if (current.outline != null ||
          current.workOutlines.isNotEmpty ||
          current.workMessages.isNotEmpty) {
        await store.write(current.copyWith(messages: const []));
      } else {
        await store.delete(item.contentHash);
      }
    });
  }

  AiBookOutline? get bookOutline => _bookOutline;
  AiOutlineProgress? get bookOutlineProgress => _bookOutlineProgress;
  String? get bookOutlineError => _bookOutlineError;
  bool get isGeneratingBookOutline => _bookOutlineGeneration != null;

  /// Loads the cached outline for this exact content hash. This does not call
  /// the model; a book is only generated when the user explicitly requests it.
  Future<AiBookOutline?> loadBookOutline({AiChatSession? session}) async {
    final work = currentReadingWork;
    final workKey = work == null ? null : workKeyFor(work);
    // Memory already holds this work's outline (just generated, still in the
    // async write queue, or freshly loaded) — trust it instead of re-reading
    // the disk snapshot which may be stale and would wipe the result.
    if (_bookOutlineWorkKey == workKey && _bookOutline != null) {
      return _bookOutline;
    }
    // 翻到另一部作品（workKey 变了）就立刻丢掉旧大纲——否则 await session
    // 期间 UI 仍显示上一部作品的内容，标题已是新作品、正文还是旧的。
    if (_bookOutlineWorkKey != workKey) {
      _bookOutline = null;
      _bookOutlineWorkKey = workKey;
      if (!_disposed) notifyListeners();
    }
    final resolvedSession = session ?? await loadChatSession();
    final outline = workKey == null
        ? resolvedSession.outline
        : resolvedSession.workOutlines[workKey];
    if (!identical(_bookOutline, outline) || _bookOutlineWorkKey != workKey) {
      _bookOutline = outline;
      _bookOutlineWorkKey = workKey;
      if (!_disposed) notifyListeners();
    }
    return outline;
  }

  /// Generates a chapter outline in batches. The controller owns the job, so
  /// closing the AI sheet does not cancel it while the reader remains open.
  Future<void> generateBookOutline() {
    final active = _bookOutlineGeneration;
    if (active != null) return active;
    final done = Completer<void>();
    _bookOutlineGeneration = done.future;
    unawaited(() async {
      try {
        await _generateBookOutline();
        done.complete();
      } catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }());
    unawaited(
      done.future.whenComplete(() {
        _bookOutlineGeneration = null;
        _bookOutlineCancel = null;
        if (!_disposed) notifyListeners();
      }),
    );
    return done.future;
  }

  Future<void> _generateBookOutline() async {
    final service = _aiOutline;
    if (service == null || !canUseAiChat) {
      _bookOutlineError = 'AI 未启用或未配置';
      if (!_disposed) notifyListeners();
      return;
    }
    _bookOutlineError = null;
    final cancel = CancelToken();
    _bookOutlineCancel = cancel;
    if (!_disposed) notifyListeners();
    try {
      // 合集：大纲 = 当前阅读作品（篇目级，与图谱同源）；单本：整本。
      // Capture the work key ONCE: generation runs for seconds and the user
      // may flip pages — the content must be stored under the key it was
      // generated from, never re-read at save time.
      var work = currentReadingWork;
      // 单本书首次生成：currentReadingWork 为 null。做一次结构识别——
      // 如果它把当前阅读位置定位进某个卷/作品（合集、上下卷），就按该
      // 范围生成；定位不到（普通单本书被 LLM 拆出前言/附录等多个 group）
      // 就退回整本大纲，绝不能因此拒绝生成。
      if (work == null) {
        final resolved = await resolveGraphWorkCandidates(
          cancel: cancel,
        );
        if (resolved != null && resolved.length > 1) {
          work = currentReadingWork;
        }
      }
      // 真合集且不在任何作品内（封面/目录/前言页）：合集没有整本大纲的
      // 展示位，引导用户翻到某部作品再生成。普通单本书 work 为 null 时
      // hasCollectionWorks 为 false，不会走到这里。
      if (hasCollectionWorks && work == null) {
        throw AiProviderException('翻到某部作品后，再生成它的知识图谱大纲');
      }
      final startWorkKey = work == null ? null : workKeyFor(work);

      final List<AiBookSectionSlice> sections;
      if (work != null) {
        sections = (await _graphSectionsForWork(work))
            .where((s) => s.text.trim().isNotEmpty)
            .toList(growable: false);
      } else {
        final body = await _loadBookPlainTextCached(
          AiBookOutlineService.maxBookBodyChars,
        );
        sections = AiChatRetrieve.splitSections(body);
      }
      if (sections.isEmpty) throw AiProviderException('无法读取本书正文');
      final titled = _withTitles(
        sections,
        fallback: _titleForOutlineSection,
      );
      final outlineSections = _filterOutlineSections(titled);
      if (outlineSections.isEmpty) {
        throw AiProviderException('没有可用于生成大纲的正文');
      }
      AiLog.d(
        'outline sections=${outlineSections.length} '
        'range=${work == null ? 'whole-book' : '${work.startSection}..${work.endSectionExclusive}'}',
      );
      final outline = await service.generate(
        bookTitle: work?.title ?? item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        collectionTitle: work == null ? null : item.title,
        sections: outlineSections,
        cancelToken: cancel,
        onProgress: (progress) {
          _bookOutlineProgress = progress;
          if (!_disposed) notifyListeners();
        },
      );
      // The user explicitly asked for this outline — show it. A page flip
      // during generation must not hide the result: the saved data is keyed
      // by startWorkKey and the following 翻页/切 Tab reload switches to the
      // then-current work. (A plain book has no work key and always matches.)
      _bookOutline = outline;
      _bookOutlineWorkKey = startWorkKey;
      _bookOutlineProgress = null;
      await _saveBookOutline(outline, workKey: startWorkKey);
      if (!_disposed) notifyListeners();
    } on AiProviderException catch (error) {
      _bookOutlineProgress = null;
      AiLog.d('outline failed: ${error.message}');
      if (!cancel.isCancelled) {
        _bookOutlineError = error.message;
      }
      if (!_disposed) notifyListeners();
    } catch (error, stack) {
      _bookOutlineProgress = null;
      AiLog.d('outline failed: $error\n$stack');
      if (!cancel.isCancelled) {
        _bookOutlineError = '生成大纲失败，请稍后重试';
      }
      if (!_disposed) notifyListeners();
    }
  }

  String _titleForOutlineSection(int sectionIndex1Based) {
    final toc = _tocTitles;
    final index = sectionIndex1Based - 1;
    if (index >= 0 && index < toc.length && toc[index].trim().isNotEmpty) {
      return toc[index].trim();
    }
    return '第 $sectionIndex1Based 节';
  }

  /// EPUB spine often contains a TOC, copyright page and other paratext.
  /// Structure planning belongs to [AiBookOutlineService]; this controller
  /// only removes unambiguous metadata before the model sees the body.
  List<AiBookSectionSlice> _filterOutlineSections(
    List<AiBookSectionSlice> sections,
  ) {
    return sections
        .where((section) => !_isOutlineMetadataSection(section))
        .toList(growable: false);
  }

  /// Graph-scoped filter on top of the outline metadata filter: appendix-like
  /// units (bibliographies, appendices, indices, acknowledgements, afterwords)
  /// carry little character-relationship value, are the densest LLM outputs
  /// (finish=length), and pollute the graph with one-off names.
  List<AiBookSectionSlice> _graphEligibleSections(
    List<AiBookSectionSlice> sections,
  ) {
    return sections
        .where((section) => !_isGraphAppendixSection(section))
        .toList(growable: false);
  }

  bool _isGraphAppendixSection(AiBookSectionSlice section) =>
      _isGraphAppendixLabel(section.label);

  /// Word lists come from AI settings (defaults = built-in lists). Compiled
  /// once per word-list change; empty lists disable the rule entirely.
  String? _appendixWordsKey;
  RegExp? _appendixWordsRegExp;
  String? _metadataWordsKey;
  RegExp? _metadataWordsRegExp;

  AiGraphRuleWords get _graphRuleWords =>
      _aiSettings?.settings.graphRuleWords ?? const AiGraphRuleWords();

  /// Never-matches regex used when a word list is empty (rule disabled).
  static final RegExp _neverMatches = RegExp(r'$.^');

  /// Lines are prefix-matched; a leading `!` turns a line into a negative
  /// lookahead (e.g. `!序曲` keeps 序曲, a body opening, out of the rule).
  static RegExp _prefixWordsRegExp(List<String> words) {
    final positives = <String>[];
    final negatives = <String>[];
    for (final word in words) {
      final t = word.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('!')) {
        final exclude = t.substring(1).trim();
        if (exclude.isNotEmpty) negatives.add(RegExp.escape(exclude));
      } else {
        positives.add(RegExp.escape(t));
      }
    }
    if (positives.isEmpty) return _neverMatches; // rule disabled
    final candidates = positives.join('|');
    if (negatives.isEmpty) return RegExp('^(?:$candidates)');
    return RegExp('^(?!(?:${negatives.join('|')}))(?:$candidates)');
  }

  static RegExp _exactWordsRegExp(List<String> words) {
    final escaped = <String>[
      for (final word in words)
        if (word.trim().isNotEmpty) RegExp.escape(word.trim()),
    ];
    if (escaped.isEmpty) return _neverMatches; // rule disabled
    return RegExp('^(?:${escaped.join('|')})\$');
  }

  bool _isGraphAppendixLabel(String raw) {
    final label = raw.trim().replaceAll(RegExp(r'\s+'), '');
    final words = _graphRuleWords.appendixUnits;
    final key = words.join('\u0001');
    if (key != _appendixWordsKey) {
      _appendixWordsKey = key;
      _appendixWordsRegExp = _prefixWordsRegExp(words);
    }
    return _appendixWordsRegExp!.hasMatch(label);
  }

  /// A TOC top-level title that names a chapter/section of a single work
  /// (第一章 / 序章 / 第3回 / Chapter 1 ...) — reading-order divisions, not
  /// independent works. Volumes (第一部/卷一) are matched separately by
  /// [_volumeTitlePattern]: a volume-split book IS multi-work.
  static final RegExp _chapterTitlePattern = RegExp(
    r'^('
    r'第[0-9零一二三四五六七八九十百千两]+[章节回篇集讲则]'
    r'|[章节回篇集讲][0-9零一二三四五六七八九十百千两]+'
    r'|(序章|楔子|引子|尾声|终章|番外|前言|序言|自序|序|跋|后记|引论|导论|绪论)'
    r'|(chapter|section|prologue|epilogue|introduction)\s*[0-9ivxlcdm]*'
    r')',
    caseSensitive: false,
  );

  /// A volume/part container (第一部 / 卷二 / Part III / Book 2). A book
  /// split into volumes behaves like a collection — each volume gets its own
  /// outline/graph — so these are NOT chapter-modeled single-work markers.
  static final RegExp _volumeTitlePattern = RegExp(
    r'^('
    r'第[0-9零一二三四五六七八九十百千两]+[部卷]'
    r'|[部卷][0-9零一二三四五六七八九十百千两]+'
    r'|(part|book|volume|vol\.?)\s*[0-9ivxlcdm]+'
    r')',
    caseSensitive: false,
  );

  bool _isChapterTocTitle(String raw) =>
      _chapterTitlePattern.hasMatch(raw.trim());

  bool _isVolumeTocTitle(String raw) => _volumeTitlePattern.hasMatch(raw.trim());

  bool _isOutlineMetadataTitle(String value) {
    final title = value.trim().replaceAll(RegExp(r'\s+'), '');
    final words = _graphRuleWords.metadataUnits;
    final key = words.join('\u0001');
    if (key != _metadataWordsKey) {
      _metadataWordsKey = key;
      _metadataWordsRegExp = _exactWordsRegExp(words);
    }
    return _metadataWordsRegExp!.hasMatch(title);
  }

  bool _isOutlineMetadataSection(AiBookSectionSlice section) {
    if (_isOutlineMetadataTitle(section.label)) return true;
    // A navigation target is already a named work/volume boundary. MOBI
    // collections often put that work's own contents page before its body;
    // treating the prefix as global metadata would discard the whole work.
    if (section.isNavigationUnit) return false;
    final text = section.text.trim();
    if (text.isEmpty) {
      // An empty body is metadata — unless it is a book/volume container
      // (JS emits an explicit #level marker with a real title like 呐喊),
      // which must survive to rebuild the chooser tree.
      return section.label.trim().isEmpty;
    }
    final prefix = text.length > 640 ? text.substring(0, 640) : text;
    final compact = prefix.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^(目录|目次)(?:[：:]|$)').hasMatch(compact)) return true;
    final hasCopyrightSignal = RegExp(
      r'ISBN|图书在版编目|版权所有|版权归属|版权信息',
    ).hasMatch(prefix);
    return hasCopyrightSignal && RegExp(r'出版|出版社|版权|编目').hasMatch(prefix);
  }

  Future<void> _saveBookOutline(AiBookOutline outline, {String? workKey}) async {
    await _enqueueChatSessionWrite(() async {
      final store = _chatHistoryStore;
      if (store == null) return;
      final current = await store.read(
        contentHash: item.contentHash,
        itemId: item.id,
      );
      final base = current ??
          AiChatSession(contentHash: item.contentHash, itemId: item.id);
      await store.write(
        workKey == null
            ? base.copyWith(outline: outline)
            : base.copyWith(
                workOutlines: {...base.workOutlines, workKey: outline},
              ),
      );
    });
  }

  Future<void> deleteBookOutline() async {
    if (isGeneratingBookOutline) return;
    await _enqueueChatSessionWrite(() async {
      final store = _chatHistoryStore;
      if (store != null) {
        final current = await store.read(
          contentHash: item.contentHash,
          itemId: item.id,
        );
        if (current != null) {
          final work = currentReadingWork;
          final workKey = work == null ? null : workKeyFor(work);
          // 只清当前作用域的大纲；删整个文件仅在所有内容都空时——否则会把
          // 其他作品的大纲和聊天记录一起抹掉（合集整本 messages 恒为空，
          // 不能只凭 messages.isEmpty 判断）。
          final cleared = workKey == null
              ? current.copyWith(clearOutline: true)
              : current.copyWith(clearWorkOutlineKey: workKey);
          final empty = cleared.messages.isEmpty &&
              cleared.outline == null &&
              cleared.workOutlines.isEmpty &&
              cleared.workMessages.isEmpty;
          if (empty) {
            await store.delete(item.contentHash);
          } else {
            await store.write(cleared);
          }
        }
      }
    });
    _bookOutline = null;
    _bookOutlineWorkKey = null;
    _bookOutlineError = null;
    if (!_disposed) notifyListeners();
  }

  void cancelBookOutlineGeneration() {
    _bookOutlineCancel?.cancel();
  }

  // ------------------------------------------------------------------
  // Book knowledge graph (AI M5) — see docs/specs/ai-graph.md
  // ------------------------------------------------------------------

  AiBookGraph? get bookGraph => _bookGraph;

  /// Collection work currently shown in the graph tab, or null for a
  /// whole-book graph / plain book.
  AiGraphWorkCandidate? get activeGraphWork => _activeGraphWork;

  bool get hasActiveWorkGraph => _activeGraphWork != null;

  static String workKeyFor(AiGraphWorkCandidate work) => 's${work.startSection}';

  /// Single source for the collection's works: the one-shot structural
  /// recognition (work-granular, stable keys) wins; outline-derived
  /// candidates are the fallback. All collection getters must read this.
  List<AiGraphWorkCandidate>? get _works => _resolvedGraphWorks;

  /// The collection work the reader is currently inside (current spine →
  /// work range), or null when the current section belongs to no work (plain
  /// book / front matter / whole-book view). Drives the「读到哪本跟哪本」
  /// behavior: graph/dialog/outline anchor to the work under the reading
  /// position instead of the whole collection.
  AiGraphWorkCandidate? get currentReadingWork {
    // 作品级 works（结构识别）优先：大纲章节推导的 works 在合集下可能是
    // 篇目级伪作品，用它们算 workKey 会漂移（s5 生成 → s7 查询），大纲
    // 因此查空。结构识别结果稳定在作品粒度，先于大纲章节来源使用。
    final works = _works;
    if (works == null) return null;
    final spine = _sectionIndex + 1; // reader is 0-based
    for (final work in works) {
      if (work.contains(spine)) return work;
    }
    return null;
  }

  /// Chat context scope: false = only the work under the reading position is
  /// sampled for tools (「读到哪本跟哪本」); true = the whole book.
  /// Collection decision: always the current work — the whole-book switch was
  /// removed, so this is a constant false and kept only for tool plumbing.

  /// Last structural-recognition result (no-outline collections), cached so
  /// [currentReadingWork] and other sync getters see the same works the
  /// graph picker lists.
  List<AiGraphWorkCandidate>? _resolvedGraphWorks;

  /// Public view of the cached structural-recognition result (null = not
  /// resolved yet or no works); the sheet uses it to decide the loading
  /// state without holding a duplicate cache.
  List<AiGraphWorkCandidate>? get resolvedGraphWorks => _resolvedGraphWorks;

  /// Whether this book is a collection (works known from the outline or from
  /// the one-shot structural recognition) — gates the collection-only UI
  /// (graph picker, chat scope switch) without waiting for the outline.
  bool get hasCollectionWorks => _works?.isNotEmpty ?? false;

  /// True when a graph was already generated for [work] of this collection.
  bool hasWorkGraph(AiGraphWorkCandidate work) =>
      _workGraphs.containsKey(workKeyFor(work));

  /// Whether [work]'s saved graph already carries a display plan — a fresh
  /// per-work generation must not reuse the whole-book plan's existence.
  bool workGraphHasNarration(AiGraphWorkCandidate work) =>
      _workGraphs[workKeyFor(work)]?.narration != null;

  /// Saved graph of [work], or null when not generated yet.
  AiBookGraph? workGraphFor(AiGraphWorkCandidate work) =>
      _workGraphs[workKeyFor(work)];

  /// Shows the generated graph of [work] (collection picker → work view).
  void openWorkGraph(AiGraphWorkCandidate work) {
    final graph = _workGraphs[workKeyFor(work)];
    if (graph == null) return;
    _bookGraph = graph;
    _activeGraphWork = work;
    if (!_disposed) notifyListeners();
  }

  /// Back to the collection picker (work view → list).
  void closeWorkGraph() {
    _activeGraphWork = null;
    _bookGraph = null;
    if (!_disposed) notifyListeners();
  }
  AiGraphProgress? get bookGraphProgress => _bookGraphProgress;
  String? get bookGraphError => _bookGraphError;
  bool get isGeneratingBookGraph => _bookGraphGeneration != null;

  /// Loads the cached graph for this book (no model calls).
  Future<void> loadBookGraph() async {
    final store = _aiGraphStore;
    if (store == null) return;
    final graph = await store.read(item.contentHash);
    final works = await store.readAllFor(item.contentHash);
    _workGraphs = works;
    if (graph != null && !identical(graph, _bookGraph)) {
      _bookGraph = graph;
      _activeGraphWork = null;
      // Legacy: the pre-per-work dialog-era graph lives in $hash.json. If it
      // demonstrably covers a single work, migrate it to that work's file so
      // the picker shows it as that work's 已生成 instead of a bogus
      // whole-book graph.
      await _migrateLegacyWholeBookGraph(graph);
      if (!_disposed) notifyListeners();
    }
  }

  /// Moves a legacy whole-book graph file to its owning work's per-work file,
  /// when the outline lets us attribute it. Leaves the file untouched when
  /// the graph spans multiple works (a real whole-book graph) or the outline
  /// is unavailable.
  Future<void> _migrateLegacyWholeBookGraph(AiBookGraph graph) async {
    final store = _aiGraphStore;
    if (store == null) return;
    try {
      final works = _resolvedGraphWorks;
      if (works == null || works.length < 2) return;
      final target = _matchingWorkForGraph(works, graph);
      if (target == null) return;
      final key = workKeyFor(target);
      if (_workGraphs.containsKey(key)) return; // already migrated
      await store.write(
        graph.copyWith(contentHash: item.contentHash),
        workKey: key,
      );
      await store.delete(item.contentHash);
      _workGraphs[key] = graph;
      _bookGraph = null;
    } catch (_) {
      // A failed migration must never break loading the sheet: the legacy
      // whole-book row keeps the graph reachable instead.
    }
  }

  /// The single work whose spine range covers the whole graph's entity span
  /// (min..max first/last section). Null when the span crosses works or is
  /// ambiguous — those stay whole-book.
  AiGraphWorkCandidate? _matchingWorkForGraph(
    List<AiGraphWorkCandidate> works,
    AiBookGraph graph,
  ) {
    if (works.length < 2 || graph.entities.isEmpty) return null;
    var first = graph.entities.first.firstSection;
    var last = graph.entities.first.lastSection;
    for (final entity in graph.entities.skip(1)) {
      if (entity.firstSection < first) first = entity.firstSection;
      if (entity.lastSection > last) last = entity.lastSection;
    }
    final candidates = works
        .where((work) => work.contains(first) && work.contains(last))
        .toList(growable: false);
    return candidates.length == 1 ? candidates.single : null;
  }

  Future<void> generateBookGraph({
    AiGraphWorkCandidate? only,
    bool force = false,
    AiNarrationPlan? narrationOverride,
    Set<int>? excludedGraphSectionIndices,
  }) {
    final active = _bookGraphGeneration;
    if (active != null) return active;
    final done = Completer<void>();
    _bookGraphGeneration = done.future;
    unawaited(() async {
      try {
        await _generateBookGraph(
          only: only,
          force: force,
          narrationOverride: narrationOverride,
          excludedGraphSectionIndices: excludedGraphSectionIndices,
        );
        done.complete();
      } catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }());
    unawaited(
      done.future.whenComplete(() {
        _bookGraphGeneration = null;
        _bookGraphCancel = null;
        if (!_disposed) notifyListeners();
      }),
    );
    return done.future;
  }

  /// Detect collections / multi-volume books from the TOC, not from LLM
  /// structural recognition: a collection titles its top-level TOC entries
  /// after the contained works, while a single book titles them by reading
  /// order (第X章/节/回 ...). LLM grouping proved unreliable for this (it
  /// silently dropped chapters and mislabeled a single book's front/back
  /// matter as works). Returns null for a single book (or no usable TOC) →
  /// the caller generates a whole-book outline/graph.
  Future<List<AiGraphWorkCandidate>?> resolveGraphWorkCandidates({
    CancelToken? cancel,
  }) async {
    if (_resolvedGraphWorks != null) return _resolvedGraphWorks;
    cancel?.throwIfCancelled();
    try {
      return _resolvedGraphWorks = await _resolveWorks(cancel);
    } catch (error) {
      // A corpus-extraction failure (WebView reload mid-read, JS callback
      // error) must not wedge the caller: the graph tab's「识别中」spinner
      // keys off _graphWorksLoading and would otherwise spin forever.
      AiLog.d('resolveGraphWorkCandidates failed: $error');
      return null;
    }
  }

  Future<List<AiGraphWorkCandidate>?> _resolveWorks(CancelToken? cancel) async {
    // Derive works from the book's own body labels, not the reader TOC: the
    // `[§logical@spine label]` markers in the plain-text corpus are produced
    // by the same JS that already resolves every format's TOC→spine mapping
    // (epub NCX, mobi/azw3 flat nav, txt single spine). The Dart-side
    // `_tocEntries` href→spine match is unreliable for azw3 (every entry
    // came back sectionIndex=null), so reading the corpus labels is the one
    // cross-format source that always carries a resolved spine.
    final body = await _loadBookGraphPlainTextCached(
      AiBookOutlineService.maxBookBodyChars,
    );
    cancel?.throwIfCancelled();
    if (body.isEmpty) {
      AiLog.d('resolveGraphWorkCandidates(toc): null (empty corpus)');
      return null;
    }

    // ── 目录标题（仅用于命名，不用于边界）────────────────────────────
    final sections = AiChatRetrieve.splitSections(body);
    final labeled = <(int, String)>[
      for (final s in sections)
        if (s.sourceSectionIndex != null && s.label.trim().isNotEmpty)
          (s.sourceSectionIndex!, s.label.trim()),
    ];
    final bySpine = <int, String>{};
    for (final (spine, label) in labeled) {
      bySpine.putIfAbsent(spine, () => label);
    }
    final tocTitles = bySpine.entries
        .map((e) => e.value)
        .where((t) => !_isOutlineMetadataTitle(t) && !_isGraphAppendixLabel(t))
        .toList(growable: false);

    // ── 边界从正文 spine 结构推，不信目录→正文映射 ────────────────────
    // 合集制作参差不齐：萧红/石评梅共享同一份正文，目录 href→spine 对不齐。
    // 但正文 spine 自己的结构是可靠的——每个作品的正文载体是一个有实质内容
    // 的 spine（前言+各篇），其前一个 spine 常是「目录页」（列出该作品篇目）。
    // spine 模式（toc:false）把每个正文 spine 拆成篇目级 slice，@spine 相同。
    final spineBody = await _loadBookGraphSpineTextCached(
      AiBookOutlineService.maxBookBodyChars,
    );
    final spineSections = AiChatRetrieve.splitSections(spineBody);
    final contentSpines = <int>[]; // 有实质正文的作品载体 spine
    final charCount = <int, int>{};
    for (final s in spineSections) {
      final spine = s.originSectionIndex;
      charCount[spine] = (charCount[spine] ?? 0) + s.text.trim().length;
    }
    // 相对 + 绝对双阈值（OR）：字符数 >2000 即保留（绝对达标——短篇散文
    // 一两千字正文不被排除）；相对阈值只兜底元数据页——正文页相对最长
    // 作品过小（<3%）视为目录/版权页。参差合集（主长篇+短篇）里短篇靠
    // 绝对阈值保住，不因 max 被长篇拉大而误杀。
    final maxChars = charCount.values.fold<int>(0, (a, b) => a > b ? a : b);
    for (final spine in charCount.keys.toList()..sort()) {
      final chars = charCount[spine] ?? 0;
      if (chars < 2000 && chars * 100 < maxChars * 3) continue;
      contentSpines.add(spine);
    }

    // 单本：只有一个正文 spine，或目录标题明显是章节模式（多数决）。
    final chapterCount =
        tocTitles.where(_isChapterTocTitle).length;
    final chapterMajority = chapterCount * 2 > tocTitles.length;
    final volumeCount = tocTitles.where(_isVolumeTocTitle).length;
    final volumeMajority = volumeCount * 2 > tocTitles.length;
    // 结构性信号（不依赖章名模式）：单本一章一文件，每个正文 spine 内部
    // 只拆出 ~1 个篇目标题；合集一作品一文件，每个正文 spine 内部拆出多
    // 篇（前言+第一辑+各篇）。篇目密度 ≫1 → 合集，≈1 → 单本。
    final pieceCount = spineSections
        .where((s) => s.label.trim().isNotEmpty && s.text.trim().isNotEmpty)
        .length;
    final piecesPerSpine = contentSpines.isEmpty
        ? 0.0
        : pieceCount / contentSpines.length;
    // 合集：目录多条 + （分卷模式 或 非章节多数）+ 每个作品含多篇目。
    // 章名不规则的单本（章名是意象词）多数决会漏，但篇目密度≈1 兜住；
    // 各作品自身分章的合集章名多数是"第X章"，多数决会误判单本，但篇目
    // 密度≫1 救回。两个方向的边界都由结构信号兜底，不只靠目录命名。
    final namedCollection =
        tocTitles.length >= 2 && (volumeMajority || !chapterMajority);
    final structuralCollection = contentSpines.length >= 2 &&
        contentSpines.length <= 60 &&
        piecesPerSpine >= 3;
    final looksCollection = namedCollection && structuralCollection;
    AiLog.d(
      'resolveGraphWorkCandidates(gate): named=$namedCollection '
      'structural=$structuralCollection contentSpines=${contentSpines.length} '
      'pieces=$pieceCount density=${piecesPerSpine.toStringAsFixed(1)} '
      'chapterMaj=$chapterMajority volumeMaj=$volumeMajority '
      '→ ${looksCollection ? 'COLLECTION' : 'SINGLE'}',
    );
    if (!looksCollection) {
      _resolvedGraphWorks = null;
      AiLog.d(
        'resolveGraphWorkCandidates(spine): null '
        '(contentSpines=${contentSpines.length} tocTitles=${tocTitles.length} '
        'piecesPerSpine=${piecesPerSpine.toStringAsFixed(1)})',
      );
      if (!_disposed) notifyListeners();
      return null;
    }

    // 标题按目录顺序对齐到各正文 spine（目录本身对，错的是映射）。标题数与
    // 正文 spine 数不一致时（如共享正文导致多/少），取较少者按顺序对齐。
    final titles = tocTitles;
    final count = contentSpines.length < titles.length
        ? contentSpines.length
        : titles.length;
    final works = <AiGraphWorkCandidate>[];
    for (var i = 0; i < count; i++) {
      final start = contentSpines[i];
      final end = i + 1 < count ? contentSpines[i + 1] : null;
      works.add(
        AiGraphWorkCandidate(
          title: titles[i],
          startSection: start,
          endSectionExclusive: end,
        ),
      );
    }
    final resolved = works.length >= 2 ? works : null;
    _resolvedGraphWorks = resolved;
    AiLog.d(
      'resolveGraphWorkCandidates(spine): ${resolved == null ? 'null' : resolved.map((w) => '${w.title}[${w.startSection}-${w.endSectionExclusive ?? '∞'}]').join(', ')}',
    );
    if (!_disposed) notifyListeners();
    return resolved;
  }

  Future<void> _generateBookGraph({
    AiGraphWorkCandidate? only,
    bool force = false,
    AiNarrationPlan? narrationOverride,
    Set<int>? excludedGraphSectionIndices,
  }) async {
    // Carry the manual slice so a failed partial save doesn't silently drop
    // it for the next incremental run (catch block is out of try scope).
    var carryExcluded = const <int>[];
    final service = _aiGraph;
    if (service == null || !canUseAiChat) {
      _bookGraphError = 'AI 未启用或未配置';
      if (!_disposed) notifyListeners();
      return;
    }
    final work = only ?? _activeGraphWork;
    final workKey = work == null ? null : workKeyFor(work);
    // Regeneration starts from scratch: the previous graph may come from a
    // different corpus granularity (piece vs section) and must not leak into
    // the new one via incremental merge.
    final existing = force
        ? null
        : (workKey == null ? _bookGraph : _workGraphs[workKey]);
    _bookGraphError = null;
    final cancel = CancelToken();
    _bookGraphCancel = cancel;
    if (!_disposed) notifyListeners();
    try {
      final allowUnread = _aiSettings?.settings.allowUnreadContext ?? false;
      final deduped = await _graphSectionsForWork(work);
      // Manual slice persists on the graph: a fresh regeneration carries the
      // previous exclusions unless the user changed them in the dialog;
      // incremental runs keep excluding the same sections too.
      final effectiveExcluded =
          excludedGraphSectionIndices ??
          existing?.excludedGraphSections.toSet() ??
          const <int>{};
      final sections = excludeGraphSections(deduped, effectiveExcluded)
          // Container nodes (book/volume level, empty body) exist only to
          // group the chooser tree — extraction works on the leaves.
          .where((s) => s.text.trim().isNotEmpty)
          .toList(growable: false);
      if (sections.isEmpty) {
        throw AiProviderException('所选章节都被排除了，请至少保留一节正文');
      }
      carryExcluded = (effectiveExcluded.toList()..sort()).toList(growable: false);
      final graph = await service.generate(
        bookTitle: item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        sections: sections,
        sectionScheme: work == null ? 'toc' : 'spine',
        includesUnread: allowUnread,
        readThroughSection: allowUnread ? null : sectionIndex + 1,
        existing: existing,
        plannedNarration: narrationOverride,
        cancelToken: cancel,
        onProgress: (progress) {
          _bookGraphProgress = progress;
          if (!_disposed) notifyListeners();
        },
      );
      final saved = graph.copyWith(
        excludedGraphSections: carryExcluded,
      );
      _bookGraph = saved;
      if (work != null) _activeGraphWork = work;
      _bookGraphProgress = null;
      await _saveBookGraph(saved, workKey: workKey);
      if (!_disposed) notifyListeners();
    } on AiGraphGenerationException catch (error) {
      _bookGraphProgress = null;
      if (!cancel.isCancelled) {
        final partial = error.partial;
        if (partial != null && !identical(partial, _bookGraph)) {
          // contentHash is re-stamped by _saveBookGraph; on a first
          // generation the partial carries an empty hash. Keep the manual
          // slice on the partial so incremental runs keep excluding.
          final savedPartial = partial.copyWith(
            excludedGraphSections: carryExcluded,
          );
          _bookGraph = savedPartial;
          await _saveBookGraph(savedPartial, workKey: workKey);
        }
        _bookGraphError = error.message;
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      _bookGraphProgress = null;
      if (!cancel.isCancelled) {
        _bookGraphError = '生成图谱失败，请稍后重试';
      }
      if (!_disposed) notifyListeners();
    }
  }

  /// Wraps raw slices with a non-empty label, falling back to a title for
  /// untitled pieces (metadata blocks produce empty labels). Shared by the
  /// outline, graph and recognition pipelines so they see identical labels.
  List<AiBookSectionSlice> _withTitles(
    List<AiBookSectionSlice> sections, {
    String Function(int index)? fallback,
  }) =>
      [
        for (final section in sections)
          AiBookSectionSlice(
            index: section.index,
            label: section.label.trim().isNotEmpty
                ? section.label.trim()
                : (fallback?.call(section.index) ?? section.label),
            text: section.text,
            sourceSectionIndex: section.sourceSectionIndex,
            isNavigationUnit: section.isNavigationUnit,
            level: section.level,
          ),
      ];


  /// Loads + slices the graph corpus for [work] (null = whole book) with the
  /// exact same filtering / spine-dedupe as generation, so re-analysis and
  /// generation always agree on scope (single source of truth).
  Future<List<AiBookSectionSlice>> _graphSectionsForWork(
    AiGraphWorkCandidate? work,
  ) async {
    final body = work == null
        ? await _loadBookGraphPlainTextCached(
            AiBookGraphService.maxBookBodyChars,
          )
        : await _loadBookGraphSpineTextCached(
            AiBookGraphService.maxBookBodyChars,
          );
    final sections = AiChatRetrieve.splitSections(body);
    if (sections.isEmpty) throw AiProviderException('无法读取本书正文');
    final titled = _withTitles(
      sections,
      fallback: (index) => work == null
          ? _titleForOutlineSection(index)
          : '第 $index 节',
    );
    final graphSections = _graphEligibleSections(
      _filterOutlineSections(titled),
    );
    final scoped = work == null
        ? graphSections
        : graphSections
              .where(
                (section) =>
                    work.contains(section.sourceSectionIndex ?? section.index),
              )
              .toList(growable: false);
    if (scoped.isEmpty) {
      throw AiProviderException('所选著作没有可用于生成图谱的正文');
    }
    // Whole-book (TOC mode): one spine section can yield several logical
    // sections inside a merged unit — dedupe so the progress count and the
    // picker's count agree, and each spine is extracted once. Per-work
    // (spine mode) keeps every logical piece: a heading split inside one
    // spine document is exactly the piece granularity the user wants to
    // choose (狂人日记/孔乙己/药 are separate pieces of the same spine file).
    if (work != null) return scoped;
    final seenSpines = <int>{};
    final deduped = <AiBookSectionSlice>[
      for (final section in scoped)
        if (seenSpines.add(section.originSectionIndex)) section,
    ];
    AiLog.d(
      'graph scope: work=${work?.title ?? 'whole-book'} '
      'range=${work == null ? '-' : '${work.startSection}..${work.endSectionExclusive}'} '
      'sections=${graphSections.length} scoped=${scoped.length} '
      'deduped=${deduped.length}',
    );
    return deduped;
  }

  /// The exact graph corpus the generation will use for [work] (null = whole
  /// book), after the automatic metadata/appendix filter and spine-dedupe —
  /// single source of truth for the pre-generation section chooser.
  /// Throws on empty body.
  Future<List<AiBookSectionSlice>> graphSectionChoices(
    AiGraphWorkCandidate? work,
  ) {
    return _graphSectionsForWork(work);
  }

  /// Applies the user-confirmed manual slice on top of the automatic filter
  /// (the dialog showed exactly the [sections] list, so [excluded] indices
  /// line up). Throws when nothing remains.
  @visibleForTesting
  static List<AiBookSectionSlice> excludeGraphSections(
    List<AiBookSectionSlice> sections,
    Set<int> excluded,
  ) {
    if (excluded.isEmpty) return sections;
    final kept = [
      for (final section in sections)
        if (!excluded.contains(section.index)) section,
    ];
    if (kept.isEmpty) {
      throw AiProviderException('所选章节都被排除了，请至少保留一节正文');
    }
    return kept;
  }

  /// Runs the step-0 display plan for [work] (null = whole book) and returns
  /// it — used by the pre-generation confirm dialog. Null on any failure
  /// (the dialog then offers retry / cancel). Does not save anything.
  Future<AiNarrationPlan?> analyzeActiveGraphNarration({    AiGraphWorkCandidate? work,
  }) async {
    final service = _aiGraph;
    if (service == null || !canUseAiChat) return null;
    try {
      final sections = await _graphSectionsForWork(work);
      return await service.analyzeNarration(
        bookTitle: item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        sections: sections,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveBookGraph(AiBookGraph graph, {String? workKey}) async {
    final store = _aiGraphStore;
    if (store == null) return;
    await store.write(
      graph.copyWith(contentHash: item.contentHash),
      workKey: workKey,
    );
    if (workKey != null) _workGraphs[workKey] = graph;
  }

  Future<void> deleteBookGraph() async {
    if (isGeneratingBookGraph) return;
    final store = _aiGraphStore;
    final work = _activeGraphWork;
    final workKey = work == null ? null : workKeyFor(work);
    if (store != null) {
      await store.delete(item.contentHash, workKey: workKey);
    }
    if (workKey == null) {
      _bookGraph = null;
    } else {
      _workGraphs.remove(workKey);
      _bookGraph = null;
      _activeGraphWork = null;
    }
    _bookGraphError = null;
    if (!_disposed) notifyListeners();
  }

  void cancelBookGraphGeneration() {
    _bookGraphCancel?.cancel();
  }

  /// Text for AI chat attachment: menu first, then live WebView selection.
  Future<String> peekSelectedText() async {
    final fromMenu = _selectionMenu?.text.trim() ?? '';
    if (fromMenu.isNotEmpty) return fromMenu;
    return ((await _getSelectedText?.call()) ?? '').trim();
  }

  /// Dismiss the selection **bubble** but keep page highlight when possible.
  /// Call after [peekSelectedText] when opening 本书 AI.
  void dismissSelectionMenuKeepHighlight() {
    // Survive focus moving into the AI panel (WebView may fire selectionchange).
    retainSelectionMenuForInteraction(
      duration: const Duration(milliseconds: 2000),
    );
    clearSelectionMenu(clearWebSelection: false);
  }

  /// Lean chat seed: current chapter + selection + TOC titles (no whole-book dump).
  Future<AiChatContextBundle> loadAiChatContext({
    String? selectionOverride,
  }) async {
    try {
      var selection = selectionOverride?.trim() ?? '';
      if (selection.isEmpty) {
        selection = _selectionMenu?.text.trim() ?? '';
      }
      if (selection.isEmpty) {
        selection = ((await _getSelectedText?.call()) ?? '').trim();
      }
      final chapter = ((await _getChapterText?.call()) ?? '').trim();
      final work = currentReadingWork;
      // 合集读哪本跟哪本：目录也裁到当前作品范围，否则全书 TOC 会让模型
      // 综述整个合集。下标保持全书 1-based，与 get_toc 工具口径一致。
      var outline = _tocTitles
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
      if (work != null) {
        outline = [
          for (var i = 0; i < _tocTitles.length; i++)
            if (work.contains(i + 1) && _tocTitles[i].trim().isNotEmpty)
              _tocTitles[i].trim(),
        ];
      }
      return AiChatContextBundle(
        chapterTitle: currentChapterTitle,
        chapterText: chapter,
        selectionText: selection,
        tocOutline: outline,
        scopeLabel: work?.title.trim().isNotEmpty == true ? work!.title : null,
      );
    } catch (_) {
      return AiChatContextBundle(chapterTitle: currentChapterTitle);
    }
  }

  /// Graph-pipeline corpus: one piece per spine section (toc:false), cached
  /// separately from the outline/chat piece-level cache. Evidence quotes then
  /// resolve to the exact section instead of a multi-section work's start.
  /// Graph corpus loader: **TOC mode** (`toc: true`). The user picked
  /// "按目录读": sections are the book's own table-of-contents units, so the
  /// pre-generation chooser shows readable titles (出版说明/中文版序言/第一
  /// 章…) instead of file paths, and manual exclusion becomes trustworthy.
  /// Evidence jumps land on the unit's starting spine (chapter-level), which
  /// matches the graph's chapter-level granularity; books without a usable
  /// TOC fall back to per-spine sections inside the JS engine.
  Future<String> _loadBookGraphPlainTextCached(int maxChars) async {
    final budget = maxChars.clamp(2000, 1500000);
    final cached = _cachedGraphPlainText;
    if (cached != null &&
        cached.isNotEmpty &&
        _cachedGraphPlainTextBudget >= budget) {
      return cached.length > budget ? cached.substring(0, budget) : cached;
    }
    final loaded =
        ((await _getBookPlainText?.call(budget, toc: true)) ?? '').trim();
    if (loaded.isNotEmpty) {
      _cachedGraphPlainText = loaded;
      _cachedGraphPlainTextBudget = budget;
      return loaded;
    }
    return ((await _getChapterText?.call()) ?? '').trim();
  }

  /// Graph corpus loader for **per-work** range: **spine mode** (`toc:false`,
  /// one logical section per heading inside each spine document). A collection
  /// work (e.g. 鲁迅小说精品) then offers its internal pieces (狂人日记/孔乙己/药…)
  /// in the pre-generation chooser instead of the single merged unit, and
  /// evidence quotes resolve to the exact piece. The whole-book range keeps
  /// [TOC 模式](_loadBookGraphPlainTextCached) (作品级) — the two caches are
  /// independent and the graph packages they feed are stored per range.
  Future<String> _loadBookGraphSpineTextCached(int maxChars) async {
    final budget = maxChars.clamp(2000, 1500000);
    final cached = _cachedGraphSpineText;
    if (cached != null &&
        cached.isNotEmpty &&
        _cachedGraphSpineTextBudget >= budget) {
      return cached.length > budget ? cached.substring(0, budget) : cached;
    }
    final loaded =
        ((await _getBookPlainText?.call(budget, toc: false)) ?? '').trim();
    if (loaded.isNotEmpty) {
      _cachedGraphSpineText = loaded;
      _cachedGraphSpineTextBudget = budget;
      return loaded;
    }
    return _loadBookGraphPlainTextCached(maxChars);
  }

  Future<String> _loadBookPlainTextCached(int maxChars) async {
    // Corpus-level budget: must cover the whole book so search / sample see
    // later chapters (books are commonly 300–700k chars). Per-prompt truncation
    // happens later in AiChatRetrieve / tool packers.
    final budget = maxChars.clamp(2000, 1500000);
    final cached = _cachedBookPlainText;
    if (cached != null &&
        cached.isNotEmpty &&
        _cachedBookPlainTextBudget >= budget) {
      return cached.length > budget ? cached.substring(0, budget) : cached;
    }
    final loaded = ((await _getBookPlainText?.call(budget)) ?? '').trim();
    if (loaded.isNotEmpty) {
      _cachedBookPlainText = loaded;
      _cachedBookPlainTextBudget = budget;
      return loaded;
    }
    // Fallback: current chapter only if spine extract failed.
    return ((await _getChapterText?.call()) ?? '').trim();
  }

  /// Loads the chat tool corpus: **TOC mode** (`toc: true`). Collections in
  /// this app commonly pack one work per spine section (萧红散文精品 = one
  /// spine), so the spine-mode corpus can't address a work by `contains`
  /// (span = 1) — the scope filter misses and chat bled the whole book into
  /// the prompt. TOC mode emits a navigation marker per work (`[§@spine~
  /// 作品名]`), which is the unit chat scope cuts on; the per-piece sampling
  /// inside one work isn't needed for retrieval.
  Future<String> _loadChatCorpus(int maxChars) =>
      _loadBookGraphPlainTextCached(maxChars);

  /// Tool host for on-demand body (toc / chapter / search / sample).
  AiChatToolHost get chatToolHost => _BookChatToolHost(this);

  /// Stream an assistant reply for book chat. Null when AI is unavailable.
  Stream<String>? streamBookChat({
    required String userText,
    required List<AiChatMessage> history,
    required AiChatContextBundle context,
    List<AiWebSearchHit>? webHits,
    CancelToken? cancelToken,
    void Function(String? status)? onToolStatus,
  }) {
    final service = _aiChat;
    if (service == null || !service.isAvailable) return null;
    return service.streamReply(
      userText: userText,
      history: history,
      context: context,
      bookTitle: item.title,
      bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
      webHits: webHits,
      tools: chatToolHost,
      cancelToken: cancelToken,
      onToolStatus: onToolStatus,
    );
  }

  /// A short, answer-specific follow-up prompt. Failure is intentionally an
  /// empty result so the chat sheet can keep its stable fallback suggestions.
  Future<List<String>> suggestBookChatFollowUps({
    required String userText,
    required String answer,
    required AiChatContextBundle context,
    CancelToken? cancelToken,
  }) async {
    final service = _aiChat;
    if (service == null || !service.isAvailable) return const [];
    return service.suggestFollowUpQuestions(
      userText: userText,
      answer: answer,
      context: context,
      bookTitle: item.title,
      bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
      cancelToken: cancelToken,
    );
  }

  /// BYOK web search for chat 联网. Empty list if not configured.
  Future<List<AiWebSearchHit>> searchWebForChat(String query) async {
    final ai = _aiSettings;
    if (ai == null || !ai.isSearchReady) {
      throw AiProviderException('请先在设置中配置联网搜索 Key');
    }
    final q = buildAiWebSearchQuery(
      userText: query,
      bookTitle: item.title,
      bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
    );
    return ai.searchWeb(q);
  }

  /// Surrounding text around the current WebView selection (translation
  /// context, ai-translation §4.5). Null when unavailable (selection gone /
  /// legacy bundle without `window.selectionContext`).
  Future<({String before, String after})?> loadSelectionContext({
    int before = 100,
    int after = 100,
  }) async {
    final fn = _getSelectionContext;
    if (fn == null) return null;
    try {
      return await fn(before, after);
    } catch (_) {
      return null;
    }
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
    render([for (final annotation in _annotations) annotation.toFoliateJson()]);
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
    _armSelectionMenuDismissBarrier();
    _armPageTurnSuppressAfterSelection();
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
    _armSelectionMenuDismissBarrier();
    _setMenuOpen?.call(true);
    notifyListeners();
  }

  /// Enter ②. Fresh selections immediately paint a default underline (Anx
  /// autoMarkSelection equivalent) so the range stays visible after the
  /// native DOM selection collapses.
  ///
  /// Desktop Platform Views often collapse selection when the Flutter bubble
  /// takes focus; mobile keeps selection handles. Always clear the web
  /// selection after the mark is drawn so both feel the same: 划线 → paint →
  /// 取消选中, menu stays on ② for style/color.
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
    if (_disposed) return;
    // Hold the lock so the deselect's onSelectionCleared does not tear down ②.
    retainSelectionMenuForInteraction();
    _clearWebSelection?.call();
  }

  void clearSelectionMenu({bool clearWebSelection = true}) {
    _selectionClearLockTimer?.cancel();
    _selectionClearLocked = false;
    _selectionMenuBarrierArmAt = null;
    // Same pointer that dismissed can hit the overlayer next — ignore briefly.
    _ignoreAnnotationClickUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
    if (_selectionMenu == null) {
      _setMenuOpen?.call(false);
      _clearMenuCursorZone();
      return;
    }
    _selectionMenu = null;
    _setMenuOpen?.call(false);
    _clearMenuCursorZone();
    // Anx only clears the native selection when the menu closes.
    if (clearWebSelection) {
      _clearWebSelection?.call();
    }
    notifyListeners();
  }

  /// Call from the bubble on pointer-down so focus-loss selection clears do
  /// not dismiss mid-tap. Auto-unlocks; a later real deselect will close.
  void retainSelectionMenuForInteraction({
    Duration duration = const Duration(milliseconds: 500),
  }) {
    _selectionClearLocked = true;
    _selectionClearLockTimer?.cancel();
    _selectionClearLockTimer = Timer(duration, () {
      _selectionClearLocked = false;
    });
  }

  Map<String, double>? _lastMenuCursorZone;

  /// Normalized viewport box for the Flutter menu bubble (Platform View cursor).
  ///
  /// Skips identical updates — the selection overlay rebuilds often, and
  /// re-pushing the same zone into the WebView makes the desktop cursor flicker.
  void setMenuCursorZone({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final zone = <String, double>{
      'left': left.clamp(0.0, 1.0),
      'top': top.clamp(0.0, 1.0),
      'right': right.clamp(0.0, 1.0),
      'bottom': bottom.clamp(0.0, 1.0),
    };
    final prev = _lastMenuCursorZone;
    if (prev != null &&
        prev['left'] == zone['left'] &&
        prev['top'] == zone['top'] &&
        prev['right'] == zone['right'] &&
        prev['bottom'] == zone['bottom']) {
      return;
    }
    _lastMenuCursorZone = zone;
    _setMenuCursorZone?.call(zone);
  }

  void _clearMenuCursorZone() {
    if (_lastMenuCursorZone == null) {
      // Still tell the engine — it may hold a zone after a hot restart / race.
      _setMenuCursorZone?.call(null);
      return;
    }
    _lastMenuCursorZone = null;
    _setMenuCursorZone?.call(null);
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

  Future<BookLanguageActionResult> performLanguageAction({
    required BookLanguageOperation operation,
    String? textOverride,
  }) {
    return performPlatformLanguageAction(
      operation: operation,
      textOverride: textOverride,
    );
  }

  /// Always uses the platform dictionary / translation path (system apps).
  Future<BookLanguageActionResult> performPlatformLanguageAction({
    required BookLanguageOperation operation,
    String? textOverride,
  }) {
    final menu = _selectionMenu;
    final text = (textOverride ?? _selectionMenu?.text ?? '').trim();
    return languageProvider.execute(
      BookLanguageRequest(
        operation: operation,
        text: text,
        itemId: item.id,
        cfi: menu?.cfi,
      ),
    );
  }

  /// AI stream for in-app dictionary / translation. Null when AI is unavailable.
  Stream<String>? streamLanguageAssist({
    required BookLanguageOperation operation,
    required String text,
    CancelToken? cancelToken,
    AiTranslationRequestOptions? translationOptions,
  }) {
    final service = _aiLanguage;
    if (service == null || !service.isAvailable) return null;
    if (operation == BookLanguageOperation.fullBookTranslation) {
      return null;
    }
    // Always attach work identity so the model can prefer established names.
    final chapter = currentChapterTitle.trim();
    final title = item.title.trim();
    final authors = bookAuthorsLabel.trim();
    final merged = AiTranslationRequestOptions(
      targetLanguage: translationOptions?.targetLanguage,
      directionMode: translationOptions?.directionMode,
      style: translationOptions?.style,
      contextBefore: translationOptions?.contextBefore,
      contextAfter: translationOptions?.contextAfter,
      bookTitle: (translationOptions?.bookTitle?.trim().isNotEmpty ?? false)
          ? translationOptions!.bookTitle
          : (title.isEmpty ? null : title),
      bookAuthor: (translationOptions?.bookAuthor?.trim().isNotEmpty ?? false)
          ? translationOptions!.bookAuthor
          : (authors.isEmpty ? null : authors),
      chapterTitle:
          (translationOptions?.chapterTitle?.trim().isNotEmpty ?? false)
          ? translationOptions!.chapterTitle
          : (chapter.isEmpty ? null : chapter),
    );
    return service.streamAssist(
      operation: operation,
      text: text,
      cancelToken: cancelToken,
      translationOptions: merged,
    );
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
    final existingNote = _selectionMenu?.note ?? _annotationForCfi(cfi)?.note;
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
    final sectionIndex =
        (fromCfi != null && (sectionCount <= 0 || fromCfi < sectionCount))
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
    final sectionIndex =
        (fromCfi != null && (sectionCount <= 0 || fromCfi < sectionCount))
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

    final resolvedType = type ?? existing?.type ?? BookAnnotationType.underline;
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

  Future<void> setFontSelection(BookFontSelection selection) async {
    if (selection == _fontSelection) return;
    if (selection.kind == BookFontKind.user) {
      final id = selection.userFontId;
      if (id == null || fontStore?.byId(id) == null) return;
    }
    _fontSelection = selection;
    notifyListeners();
    await _prefs?.setFontSelection(selection);
  }

  Future<String?> downloadCatalogFont(BookCatalogFont catalog) async {
    final store = fontStore;
    if (store == null) return '字体存储未就绪';
    try {
      final font = await store.downloadCatalogFont(catalog);
      await setFontSelection(BookFontSelection.user(font.id));
      return null;
    } catch (error) {
      debugPrint('[Font] download failed: $error');
      return '字体下载失败';
    }
  }

  Future<String?> importFontFile(String path) async {
    final store = fontStore;
    if (store == null) return '字体存储未就绪';
    try {
      final font = await store.importFontFile(path);
      await setFontSelection(BookFontSelection.user(font.id));
      return null;
    } catch (error) {
      debugPrint('[Font] import failed: $error');
      return '字体导入失败';
    }
  }

  Future<void> deleteUserFont(String id) async {
    final store = fontStore;
    if (store == null) return;
    final wasSelected =
        _fontSelection.kind == BookFontKind.user &&
        _fontSelection.userFontId == id;
    await store.deleteUserFont(id);
    if (wasSelected) {
      await setFontSelection(BookReadingPreferences.defaultFontSelection);
    } else {
      notifyListeners();
    }
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
    _bookOutlineCancel?.cancel();
    _bookGraphCancel?.cancel();
    _attachGeneration++;
    _ttsGeneration++;
    _prefs?.fontStore.removeListener(_onFontStoreChanged);
    _saveDebounce?.cancel();
    _selectionClearLockTimer?.cancel();
    unawaited(_tearDownTts());
    _externalNextPage = null;
    _externalPreviousPage = null;
    _externalSeek = null;
    detachAnnotationBridge();
    detachSearchBridge();
    detachTtsBridge();
    unawaited(_bookmarksSubscription?.cancel());
    unawaited(_annotationsSubscription?.cancel());
    unawaited(_persist());
    super.dispose();
  }

  // ------------------------------------------------------------------
  // TTS (听书) — 对齐 Anx SystemTts 模型
  //
  // Foliate = 句游标 + 高亮；Dart = 发声。
  // Apple 连续播：speak 完 → 仅当仍 playing 才 ttsNext（Anx 同款门槛）。
  // 改速 = Anx restart：停音频后重读；我们保留当前句文本（不 here+next），
  //   避免 Foliate 高亮跳句。
  // Apple didCancel 不结束 speak Future → 用 completion/cancel 门闩；
  //   门闩只在 setStartHandler 之后 arm，防止 stop 的迟到 cancel 误关下一句。
  // ------------------------------------------------------------------

  Future<FlutterTts> _ensureTts() async {
    final existing = _flutterTts;
    if (existing != null) return existing;
    final tts = FlutterTts();
    _flutterTts = tts;
    if (!kIsWeb && Platform.isIOS) {
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    // Apple: awaitSpeakCompletion(true) + stop() 会挂死 speak Future。
    await tts.awaitSpeakCompletion(false);
    await _applyTtsRate(tts);
    tts.setStartHandler(() {
      _ttsUtteranceArmed = true;
    });
    tts.setCompletionHandler(_onUtteranceEngineSignal);
    tts.setCancelHandler(_onUtteranceEngineSignal);
    tts.setErrorHandler((message) {
      _onUtteranceEngineSignal();
      debugPrint('[TTS] error: $message');
    });
    return tts;
  }

  void _onUtteranceEngineSignal() {
    if (!_ttsUtteranceArmed) return;
    _ttsUtteranceArmed = false;
    final gate = _ttsUtteranceDone;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void _forceUnblockUtteranceWait() {
    _ttsUtteranceArmed = false;
    final gate = _ttsUtteranceDone;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _applyTtsRate(FlutterTts tts) async {
    // UI 1.0 = 正常。flutter_tts 全平台 0.5 ≈ normal。
    await tts.setSpeechRate(_mapSpeechRate(_ttsRate));
  }

  static double _mapSpeechRate(double uiRate) {
    return (uiRate * 0.5).clamp(0.1, 1.0);
  }

  /// Speaks [text]; returns true only if this generation still owns playback
  /// after the utterance ends (Anx: state still playing → may advance).
  Future<bool> _speakSentence(
    FlutterTts tts,
    String text,
    int generation,
  ) async {
    if (text.isEmpty) return false;
    _ttsUtteranceArmed = false;
    final gate = Completer<void>();
    _ttsUtteranceDone = gate;
    try {
      await tts.speak(text);
      await gate.future;
    } finally {
      if (identical(_ttsUtteranceDone, gate)) _ttsUtteranceDone = null;
      _ttsUtteranceArmed = false;
    }
    if (_disposed || generation != _ttsGeneration) return false;
    if (_ttsStatus != BookTtsStatus.playing) return false;
    return true;
  }

  Future<void> _drainTtsLoop() async {
    final idle = _ttsLoopIdle?.future;
    if (idle == null) return;
    try {
      await idle.timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  /// Stop audio without moving Foliate. Bumps generation so in-flight loops
  /// cannot ttsNext (Anx: stop → state stopped → speak 后不前进).
  Future<void> _interruptAudio({required bool bumpGeneration}) async {
    if (bumpGeneration) _ttsGeneration++;
    _forceUnblockUtteranceWait();
    try {
      await _flutterTts?.stop();
    } catch (_) {}
    await _drainTtsLoop();
  }

  Future<void> _tearDownTts() async {
    _ttsGeneration++;
    _forceUnblockUtteranceWait();
    final tts = _flutterTts;
    _flutterTts = null;
    _ttsStatus = BookTtsStatus.idle;
    _ttsCurrentText = null;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (_) {}
  }

  Future<void> startTts() async {
    if (_disposed || !_ready) return;
    clearSelectionMenu();
    await _interruptAudio(bumpGeneration: true);
    final generation = _ttsGeneration;
    final here = _ttsHere;
    if (here == null) {
      ttsUserMessage = '听书引擎未就绪';
      notifyListeners();
      return;
    }
    final text = (await here())?.trim();
    if (_disposed || generation != _ttsGeneration) return;
    if (text == null || text.isEmpty) {
      ttsUserMessage = '当前位置没有可读文本';
      notifyListeners();
      return;
    }
    _ttsCurrentText = text;
    _ttsStatus = BookTtsStatus.playing;
    showChrome();
    notifyListeners();
    unawaited(_runTtsLoop(generation));
  }

  /// Anx Apple loop: speak → if still playing → ttsNext → speak …
  Future<void> _runTtsLoop(int generation) async {
    final idle = Completer<void>();
    _ttsLoopIdle = idle;
    try {
      final tts = await _ensureTts();
      if (_disposed || generation != _ttsGeneration) return;

      while (!_disposed &&
          generation == _ttsGeneration &&
          _ttsStatus == BookTtsStatus.playing) {
        final text = _ttsCurrentText?.trim() ?? '';
        if (text.isEmpty) {
          ttsUserMessage = '已读完';
          await stopTts();
          return;
        }

        final finishedCleanly = await _speakSentence(tts, text, generation);
        // Anx: `if (ttsStateNotifier.value == playing) getNext…`
        if (!finishedCleanly) return;
        if (_disposed || generation != _ttsGeneration) return;
        if (_ttsStatus != BookTtsStatus.playing) return;

        final fetch = _ttsNext;
        if (fetch == null) {
          await stopTts();
          return;
        }
        String? nextText;
        try {
          nextText = (await fetch())?.trim();
        } catch (error) {
          debugPrint('[TTS] ttsNext failed: $error');
          nextText = null;
        }

        if (_disposed || generation != _ttsGeneration) {
          if (nextText != null && nextText.isNotEmpty) {
            try {
              await _ttsPrev?.call();
            } catch (_) {}
          }
          return;
        }
        if (nextText == null || nextText.isEmpty) {
          ttsUserMessage = '已读完';
          await stopTts();
          return;
        }
        _ttsCurrentText = nextText;
        notifyListeners();
        if (_ttsStatus != BookTtsStatus.playing) return;
      }
    } finally {
      if (!idle.isCompleted) idle.complete();
      if (identical(_ttsLoopIdle, idle)) _ttsLoopIdle = null;
    }
  }

  Future<void> pauseTts() async {
    if (_disposed || _ttsStatus != BookTtsStatus.playing) return;
    // Anx pause: stop audio, keep _currentVoiceText, state=paused.
    _ttsStatus = BookTtsStatus.paused;
    notifyListeners();
    await _interruptAudio(bumpGeneration: true);
  }

  Future<void> resumeTts() async {
    if (_disposed || _ttsStatus != BookTtsStatus.paused) return;
    final text = _ttsCurrentText?.trim();
    if (text == null || text.isEmpty) {
      await startTts();
      return;
    }
    // Anx Apple resume: speak(content: _currentVoiceText) from sentence start.
    final generation = ++_ttsGeneration;
    _ttsStatus = BookTtsStatus.playing;
    notifyListeners();
    unawaited(_runTtsLoop(generation));
  }

  Future<void> toggleTtsPlayPause() async {
    switch (_ttsStatus) {
      case BookTtsStatus.idle:
        await startTts();
      case BookTtsStatus.playing:
        await pauseTts();
      case BookTtsStatus.paused:
        await resumeTts();
    }
  }

  Future<void> stopTts() async {
    if (_disposed) return;
    await _interruptAudio(bumpGeneration: true);
    await _ttsStopEngine?.call();
    if (_disposed) return;
    _ttsStatus = BookTtsStatus.idle;
    _ttsCurrentText = null;
    notifyListeners();
  }

  /// Anx `rate` setter → `restart()`，但保留当前句（不 here+next）。
  Future<void> setTtsRate(double rate) async {
    final next = rate.clamp(0.5, 2.0);
    if ((next - _ttsRate).abs() < 0.001) return;
    _ttsRate = next;
    notifyListeners();

    if (_ttsStatus == BookTtsStatus.idle) {
      final tts = _flutterTts;
      if (tts != null) await _applyTtsRate(tts);
      return;
    }

    final keep = _ttsCurrentText;
    final wasPaused = _ttsStatus == BookTtsStatus.paused;
    // Invalidate loop first (Anx stop → state stopped → 旧 speak 不会前进).
    await _interruptAudio(bumpGeneration: true);
    if (_disposed) return;

    final tts = await _ensureTts();
    await _applyTtsRate(tts);
    if (_disposed) return;

    _ttsCurrentText = keep;
    if (wasPaused || keep == null || keep.trim().isEmpty) {
      _ttsStatus = wasPaused ? BookTtsStatus.paused : BookTtsStatus.idle;
      notifyListeners();
      return;
    }

    final generation = _ttsGeneration;
    _ttsStatus = BookTtsStatus.playing;
    notifyListeners();
    unawaited(_runTtsLoop(generation));
  }

  Future<void> ttsSkipNext() async {
    if (_disposed || !ttsActive) return;
    await _skipTts(next: true);
  }

  Future<void> ttsSkipPrevious() async {
    if (_disposed || !ttsActive) return;
    await _skipTts(next: false);
  }

  Future<void> _skipTts({required bool next}) async {
    await _interruptAudio(bumpGeneration: true);
    if (_disposed) return;
    final generation = _ttsGeneration;

    final fetch = next ? _ttsNext : _ttsPrev;
    if (fetch == null) {
      await stopTts();
      return;
    }
    final text = (await fetch())?.trim();
    if (_disposed || generation != _ttsGeneration) return;
    if (text == null || text.isEmpty) {
      ttsUserMessage = next ? '已读完' : '已到开头';
      await stopTts();
      return;
    }
    _ttsCurrentText = text;
    _ttsStatus = BookTtsStatus.playing;
    notifyListeners();
    unawaited(_runTtsLoop(generation));
  }
}

/// On-demand book body for [AiChatService] tools (no whole-book prompt dump).
class _BookChatToolHost implements AiChatToolHost {
  _BookChatToolHost(this._c);

  final BookReaderController _c;

  /// Restricts [body] to the work under the reading position unless the user
  /// switched chat scope to the whole book. Plain books (no works) pass
  /// through unchanged. The re-assembled text keeps the original logical
  /// indices so toolGetChapter/sectionText still address the same slices.
  String _scopedBody(String body) => scopeChatBodyToWork(
        body,
        _c.currentReadingWork,
        // Collection decision: always the current work, never the whole
        // book — the switch UI was removed.
        wholeBook: false,
      );

  @override
  Future<String> toolGetToc() async {
    final titles = _c.tocTitles;
    if (titles.isEmpty) {
      final body = _scopedBody(
        await _c._loadChatCorpus(AiChatService.maxBookBodyChars),
      );
      final sections = AiChatRetrieve.splitSections(body);
      if (sections.isNotEmpty) {
        return AiChatBookCorpus.formatTocFromSlices(sections);
      }
      return '(目录不可用)';
    }
    final buf = StringBuffer();
    // 读哪本跟哪本: the toc tool must answer for the reading work only —
    // a collection's whole-book toc would let the model talk about all 30
    // works even though chat scope is the current one.
    final work = _c.currentReadingWork;
    for (var i = 0; i < titles.length; i++) {
      if (work != null && !work.contains(i + 1)) continue;
      final t = titles[i].trim();
      buf.writeln('§${i + 1} ${t.isEmpty ? '（无标题）' : t}');
    }
    return buf.toString().trimRight();
  }

  @override
  Future<String> toolGetCurrentChapter({int maxChars = 10000}) async {
    var text = ((await _c._getChapterText?.call()) ?? '').trim();
    if (text.isEmpty) {
      text = ((await _c._getReadSoFarText?.call(maxChars)) ?? '').trim();
    }
    if (text.isEmpty) return '(当前章正文不可用)';
    final title = _c.currentChapterTitle.trim();
    final body = text.length > maxChars
        ? '${text.substring(0, maxChars)}…'
        : text;
    if (title.isEmpty) return body;
    return '[$title]\n$body';
  }

  @override
  Future<String> toolGetChapter(
    int sectionIndex1Based, {
    int maxChars = 10000,
  }) async {
    final body = _scopedBody(
      await _c._loadChatCorpus(AiChatService.maxBookBodyChars),
    );
    final sections = AiChatRetrieve.splitSections(body);
    if (sections.isEmpty) {
      // Fallback: only current chapter known.
      if (sectionIndex1Based == _c.sectionIndex + 1) {
        return toolGetCurrentChapter(maxChars: maxChars);
      }
      return 'Error: book body not loaded; try get_current_chapter.';
    }
    return AiChatBookCorpus.sectionText(
      sections,
      sectionIndex1Based,
      maxChars: maxChars,
    );
  }

  @override
  Future<String> toolSearchBook(String query, {int maxChars = 12000}) async {
    final body = _scopedBody(
      await _c._loadChatCorpus(AiChatService.maxBookBodyChars),
    );
    if (body.isEmpty) return '(书中无正文可检索)';
    final packed = AiChatRetrieve.pack(
      userText: query,
      selection: '',
      bookBody: body,
      maxSections: 10,
      maxRelatedChars: maxChars,
    );
    final formatted = packed.formatRelatedForPrompt(maxChars: maxChars);
    if (formatted.isEmpty) {
      return 'No keyword hits for "$query". Try sample_book or get_toc.';
    }
    return 'Search "$query" (${packed.note}):\n$formatted';
  }

  @override
  Future<String> toolSampleBook({int maxChars = 36000}) async {
    final body = _scopedBody(
      await _c._loadChatCorpus(AiChatService.maxBookBodyChars),
    );
    if (body.isEmpty) return '(书中无正文可取样)';
    final packed = AiChatRetrieve.pack(
      userText: '请根据提供的各部分正文，概括整本书的主线与主题',
      selection: '',
      bookBody: body,
      maxSections: 16,
      maxRelatedChars: maxChars,
    );
    final formatted = packed.formatRelatedForPrompt(maxChars: maxChars);
    final outline = packed.sectionOutline.isEmpty
        ? ''
        : 'Parts: ${packed.sectionOutline.join(' · ')}\n\n';
    if (formatted.isEmpty) return '$outline(empty samples)';
    return '$outline$formatted';
  }
}

/// Restricts a getBookPlainText body to [work]'s unit (「读到哪本跟哪本」
/// chat scope). `wholeBook` or a null work passes the body through unchanged.
///
/// The chat corpus is TOC-mode: one slice per work, with the work's own
/// navigation marker (`[§@spine~ 作品名]`) as its label. We cut on the slice
/// whose label matches [work].title — NOT on `work.contains(spine)`, because
/// collections in this app commonly pack one work per spine section, making
/// the spine span 1 and `contains` unreliable. Falls back to spine-contains
/// for spine-mode bodies (tests / non-collection).
@visibleForTesting
String scopeChatBodyToWork(
  String body,
  AiGraphWorkCandidate? work, {
  required bool wholeBook,
}) {
  if (wholeBook || work == null) return body;
  final sections = AiChatRetrieve.splitSections(body);
  final wanted = work.title.trim();
  var kept = sections.where((s) => s.label.trim() == wanted).toList();
  var byLabel = true;
  if (kept.isEmpty) {
    byLabel = false;
    kept = sections
        .where((s) => work.contains(s.originSectionIndex))
        .toList(growable: false);
  }
  AiLog.d(
    'scopeChatBodyToWork: work=${work.title} by=${
      byLabel ? 'label' : 'spine'
    } sections=${sections.length} kept=${kept.length}',
  );
  if (kept.isEmpty || kept.length == sections.length) return body;
  final buf = StringBuffer();
  for (final s in kept) {
    final nav = s.isNavigationUnit ? '~' : '';
    buf.writeln('[§${s.index}@${s.sourceSectionIndex ?? s.index}$nav ${s.label}]');
    buf.writeln(s.text.trim());
    buf.writeln();
  }
  return buf.toString().trim();
}

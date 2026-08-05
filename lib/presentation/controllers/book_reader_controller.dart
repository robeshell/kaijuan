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
  Future<List<AiBookOutlineCandidate>> Function({
    required int startSectionIndex,
    required int? endSectionIndexExclusive,
    required int maxChars,
  })?
  _getOutlineChildren;
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
  AiOutlineProgress? _bookOutlineProgress;
  String? _bookOutlineError;
  CancelToken? _bookOutlineCancel;
  Future<void>? _bookOutlineGeneration;
  AiBookGraph? _bookGraph;

  /// Graph of the work currently shown/generated when viewing a collection
  /// (null for whole-book graphs / plain books).
  AiGraphWorkCandidate? _activeGraphWork;

  /// True while the legacy whole-book graph ($hash.json of a collection) is
  /// being viewed — keeps the picker from swallowing it.
  bool _wholeBookGraphView = false;

  /// Per-work graphs of the current collection, keyed by workKey.
  Map<String, AiBookGraph> _workGraphs = {};

  /// Work being generated right now (null = whole book / not generating).
  AiGraphWorkCandidate? _generatingGraphWork;
  AiGraphProgress? _bookGraphProgress;
  String? _bookGraphError;
  CancelToken? _bookGraphCancel;
  Future<void>? _bookGraphGeneration;
  final Map<String, Future<void>> _bookOutlineDetailGenerations = {};
  final Map<String, CancelToken> _bookOutlineDetailCancels = {};
  final Map<String, AiOutlineProgress> _bookOutlineDetailProgress = {};
  final Map<String, String> _bookOutlineDetailErrors = {};
  Future<void> _chatSessionWriteQueue = Future<void>.value();

  /// Cached multi-section plain text for book chat (per open).
  String? _cachedBookPlainText;
  int _cachedBookPlainTextBudget = 0;
  String? _cachedGraphPlainText;
  int _cachedGraphPlainTextBudget = 0;
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
    Future<List<AiBookOutlineCandidate>> Function({
      required int startSectionIndex,
      required int? endSectionIndexExclusive,
      required int maxChars,
    })?
    getOutlineChildren,
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
    _getOutlineChildren = getOutlineChildren;
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
    _getOutlineChildren = null;
    _setMenuCursorZone = null;
    _setMenuOpen = null;
    _cachedBookPlainText = null;
    _cachedBookPlainTextBudget = 0;
    _cachedGraphPlainText = null;
    _cachedGraphPlainTextBudget = 0;
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
      await store.write(
        current?.outline != null && session.outline == null
            ? session.copyWith(outline: current!.outline)
            : session,
      );
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
  Future<void> clearChatSession() async {
    await _enqueueChatSessionWrite(() async {
      final store = _chatHistoryStore;
      if (store == null) return;
      final current = await store.read(
        contentHash: item.contentHash,
        itemId: item.id,
      );
      if (current?.outline != null) {
        await store.write(current!.copyWith(messages: const []));
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
    final resolvedSession = session ?? await loadChatSession();
    final outline = resolvedSession.outline;
    if (!identical(_bookOutline, outline)) {
      _bookOutline = outline;
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
      final body = await _loadBookPlainTextCached(
        AiBookOutlineService.maxBookBodyChars,
      );
      var sections = AiChatBookCorpus.parseSections(body);
      if (sections.isEmpty) throw AiProviderException('无法读取本书正文');
      AiLog.d(
        'outline extracted=${sections.length} '
        'navigation=${sections.where((section) => section.isNavigationUnit).length} '
        'labels=${sections.take(24).map((section) => section.label).join(' | ')}',
      );
      // A book outline is explicitly whole-book work. Restricting it to the
      // current spine position turns a collection opened at its front matter
      // into a one-item "outline".
      const includeUnread = true;
      final titled = [
        for (final section in sections)
          AiBookSectionSlice(
            index: section.index,
            label: section.label.trim().isNotEmpty
                ? section.label.trim()
                : _titleForOutlineSection(section.index),
            text: section.text,
            sourceSectionIndex: section.sourceSectionIndex,
            isNavigationUnit: section.isNavigationUnit,
          ),
      ];
      final outlineSections = _filterOutlineSections(titled);
      if (outlineSections.isEmpty) {
        throw AiProviderException('没有可用于生成大纲的正文');
      }
      AiLog.d(
        'outline usable=${outlineSections.length} '
        'navigation=${outlineSections.where((section) => section.isNavigationUnit).length} '
        'indexes=${outlineSections.map((section) => section.index).join(',')}',
      );
      final outline = await service.generate(
        bookTitle: item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        sections: outlineSections,
        includesUnread: includeUnread,
        cancelToken: cancel,
        onProgress: (progress) {
          _bookOutlineProgress = progress;
          if (!_disposed) notifyListeners();
        },
      );
      _bookOutline = outline;
      _bookOutlineProgress = null;
      await _saveBookOutline(outline);
      if (!_disposed) notifyListeners();
    } on AiProviderException catch (error) {
      _bookOutlineProgress = null;
      if (!cancel.isCancelled) {
        _bookOutlineError = error.message;
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      _bookOutlineProgress = null;
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

  bool _isGraphAppendixLabel(String raw) {
    final label = raw.trim().replaceAll(RegExp(r'\s+'), '');
    return RegExp(
      r'^(附录|参考书目|参考文献|索引|致谢|后记|跋|注释|年表|'
      r'前言|序言|序|自序|代序|凡例|出版说明|编者按|导读|题记)',
    ).hasMatch(label);
  }

  bool _isOutlineMetadataTitle(String value) {
    final title = value.trim().replaceAll(RegExp(r'\s+'), '');
    return RegExp(
      r'^(目录|总目录|全书目录|章节目录|目次|版权(?:信息)?|出版(?:信息|说明)?|图书在版编目|封面|封底|扉页|书名页)$',
    ).hasMatch(title);
  }

  bool _isOutlineMetadataSection(AiBookSectionSlice section) {
    if (_isOutlineMetadataTitle(section.label)) return true;
    // A navigation target is already a named work/volume boundary. MOBI
    // collections often put that work's own contents page before its body;
    // treating the prefix as global metadata would discard the whole work.
    if (section.isNavigationUnit) return false;
    final text = section.text.trim();
    if (text.isEmpty) return true;
    final prefix = text.length > 640 ? text.substring(0, 640) : text;
    final compact = prefix.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^(目录|目次)(?:[：:]|$)').hasMatch(compact)) return true;
    final hasCopyrightSignal = RegExp(
      r'ISBN|图书在版编目|版权所有|版权归属|版权信息',
    ).hasMatch(prefix);
    return hasCopyrightSignal && RegExp(r'出版|出版社|版权|编目').hasMatch(prefix);
  }

  Future<void> _saveBookOutline(AiBookOutline outline) async {
    await _enqueueChatSessionWrite(() async {
      final store = _chatHistoryStore;
      if (store == null) return;
      final current = await store.read(
        contentHash: item.contentHash,
        itemId: item.id,
      );
      await store.write(
        (current ??
                AiChatSession(contentHash: item.contentHash, itemId: item.id))
            .copyWith(outline: outline),
      );
    });
  }

  bool isGeneratingBookOutlineChildren(AiBookOutlineChapter chapter) =>
      _bookOutlineDetailGenerations.containsKey(chapter.stableNodeId);

  AiOutlineProgress? bookOutlineChildrenProgress(
    AiBookOutlineChapter chapter,
  ) => _bookOutlineDetailProgress[chapter.stableNodeId];

  String? bookOutlineChildrenError(AiBookOutlineChapter chapter) =>
      _bookOutlineDetailErrors[chapter.stableNodeId];

  bool canGenerateBookOutlineChildren(AiBookOutlineChapter chapter) {
    final children = chapter.children;
    if (children != null) return children.isNotEmpty;
    final outline = _bookOutline;
    if (outline == null) return false;
    final range = _outlineRangeFor(chapter, outline.chapters);
    final end = range.endSectionIndexExclusive;
    return end == null || end > range.startSectionIndex + 1;
  }

  /// Generates one reader-derived outline range when the reader explicitly
  /// requests it. A successful empty result is persisted as a leaf.
  Future<void> generateBookOutlineChildren(
    AiBookOutlineChapter chapter, {
    bool force = false,
  }) {
    if (!force && chapter.children != null) return Future<void>.value();
    final nodeId = chapter.stableNodeId;
    final active = _bookOutlineDetailGenerations[nodeId];
    if (active != null) return active;
    final done = Completer<void>();
    _bookOutlineDetailGenerations[nodeId] = done.future;
    unawaited(() async {
      try {
        await _generateBookOutlineChildren(chapter);
        done.complete();
      } catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }());
    unawaited(
      done.future.whenComplete(() {
        _bookOutlineDetailGenerations.remove(nodeId);
        _bookOutlineDetailCancels.remove(nodeId);
        _bookOutlineDetailProgress.remove(nodeId);
        if (!_disposed) notifyListeners();
      }),
    );
    return done.future;
  }

  Future<void> _generateBookOutlineChildren(
    AiBookOutlineChapter chapter,
  ) async {
    final service = _aiOutline;
    final bridge = _getOutlineChildren;
    final current = _bookOutline;
    if (service == null || !canUseAiChat || bridge == null || current == null) {
      _bookOutlineDetailErrors[chapter.stableNodeId] = '无法读取本书的子级结构';
      if (!_disposed) notifyListeners();
      return;
    }
    final range = _outlineRangeFor(chapter, current.chapters);
    final cancel = CancelToken();
    _bookOutlineDetailCancels[chapter.stableNodeId] = cancel;
    _bookOutlineDetailErrors.remove(chapter.stableNodeId);
    if (!_disposed) notifyListeners();
    try {
      final candidates = await bridge(
        startSectionIndex: range.startSectionIndex,
        endSectionIndexExclusive: range.endSectionIndexExclusive,
        maxChars: 240000,
      );
      cancel.throwIfCancelled();
      AiLog.d(
        'outline children parent=${chapter.stableNodeId} '
        'range=${range.startSectionIndex}-${range.endSectionIndexExclusive ?? 'end'} '
        'candidates=${candidates.length}',
      );
      final children = await service.generateChildren(
        bookTitle: item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        parentNodeId: chapter.stableNodeId,
        candidates: candidates,
        cancelToken: cancel,
        onProgress: (progress) {
          _bookOutlineDetailProgress[chapter.stableNodeId] = progress;
          if (!_disposed) notifyListeners();
        },
      );
      cancel.throwIfCancelled();
      final outline = _bookOutline;
      if (outline == null) return;
      final updatedChapters = _replaceOutlineChildren(
        outline.chapters,
        chapter.stableNodeId,
        children,
      );
      final attachedCount = _outlineChildrenCount(
        updatedChapters,
        chapter.stableNodeId,
      );
      if (attachedCount == null) {
        _bookOutlineDetailErrors[chapter.stableNodeId] = '无法更新下级大纲';
        AiLog.d(
          'outline children attach failed parent=${chapter.stableNodeId} '
          'roots=${outline.chapters.length}',
        );
        if (!_disposed) notifyListeners();
        return;
      }
      _bookOutline = outline.copyWith(chapters: updatedChapters);
      if (!_disposed) notifyListeners();
      // The result is ready for the open sheet. Persistence is serialized with
      // chat writes and must not delay replacing the expanded tree on screen.
      AiLog.d(
        'outline children ready parent=${chapter.stableNodeId} '
        'count=${children.length} attached=$attachedCount',
      );
      await _saveBookOutline(_bookOutline!);
      AiLog.d('outline children persisted parent=${chapter.stableNodeId}');
    } on AiProviderException catch (error) {
      if (!cancel.isCancelled) {
        _bookOutlineDetailErrors[chapter.stableNodeId] = error.message;
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      if (!cancel.isCancelled) {
        _bookOutlineDetailErrors[chapter.stableNodeId] = '生成子级大纲失败，请稍后重试';
      }
      if (!_disposed) notifyListeners();
    }
  }

  ({int startSectionIndex, int? endSectionIndexExclusive}) _outlineRangeFor(
    AiBookOutlineChapter target,
    List<AiBookOutlineChapter> roots,
  ) {
    ({int startSectionIndex, int? endSectionIndexExclusive})? find(
      List<AiBookOutlineChapter> siblings,
    ) {
      for (var index = 0; index < siblings.length; index++) {
        final node = siblings[index];
        if (node.stableNodeId == target.stableNodeId) {
          final start = node.sourceSectionIndex ?? node.sectionIndex;
          final nextStart = index + 1 < siblings.length
              ? siblings[index + 1].sourceSectionIndex ??
                    siblings[index + 1].sectionIndex
              : null;
          final end = node.endSectionIndexExclusive ?? nextStart;
          return (
            startSectionIndex: start,
            endSectionIndexExclusive: end != null && end > start ? end : null,
          );
        }
        final children = node.children;
        if (children != null) {
          final nested = find(children);
          if (nested != null) return nested;
        }
      }
      return null;
    }

    return find(roots) ??
        (
          startSectionIndex: target.sourceSectionIndex ?? target.sectionIndex,
          endSectionIndexExclusive: target.endSectionIndexExclusive,
        );
  }

  List<AiBookOutlineChapter> _replaceOutlineChildren(
    List<AiBookOutlineChapter> nodes,
    String parentNodeId,
    List<AiBookOutlineChapter> children,
  ) {
    return [
      for (final node in nodes)
        if (node.stableNodeId == parentNodeId)
          node.copyWith(children: children)
        else if (node.children != null)
          node.copyWith(
            children: _replaceOutlineChildren(
              node.children!,
              parentNodeId,
              children,
            ),
          )
        else
          node,
    ];
  }

  int? _outlineChildrenCount(
    List<AiBookOutlineChapter> nodes,
    String targetNodeId,
  ) {
    for (final node in nodes) {
      if (node.stableNodeId == targetNodeId) return node.children?.length;
      final children = node.children;
      if (children != null) {
        final nested = _outlineChildrenCount(children, targetNodeId);
        if (nested != null) return nested;
      }
    }
    return null;
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
          if (current.messages.isEmpty) {
            await store.delete(item.contentHash);
          } else {
            await store.write(current.copyWith(clearOutline: true));
          }
        }
      }
    });
    _bookOutline = null;
    _bookOutlineError = null;
    if (!_disposed) notifyListeners();
  }

  void cancelBookOutlineGeneration() {
    _bookOutlineCancel?.cancel();
    for (final cancel in _bookOutlineDetailCancels.values) {
      cancel.cancel();
    }
  }

  // ------------------------------------------------------------------
  // Book knowledge graph (AI M5) — see docs/specs/ai-graph.md
  // ------------------------------------------------------------------

  AiBookGraph? get bookGraph => _bookGraph;

  /// Collection work currently shown in the graph tab, or null for a
  /// whole-book graph / plain book.
  AiGraphWorkCandidate? get activeGraphWork => _activeGraphWork;

  bool get hasActiveWorkGraph => _activeGraphWork != null;

  /// True while the legacy whole-book graph of a collection is being viewed.
  bool get viewingWholeBookGraph => _wholeBookGraphView;

  /// Opens the legacy whole-book graph ($hash.json — pre-per-work files).
  void openWholeBookGraph() {
    if (_bookGraph == null || _activeGraphWork != null) return;
    _wholeBookGraphView = true;
    if (!_disposed) notifyListeners();
  }

  /// Work currently being generated, or null (whole book / idle). The graph
  /// picker uses this to show per-row progress.
  AiGraphWorkCandidate? get generatingGraphWork => _generatingGraphWork;

  static String workKeyFor(AiGraphWorkCandidate work) => 's${work.startSection}';

  /// True when a graph was already generated for [work] of this collection.
  bool hasWorkGraph(AiGraphWorkCandidate work) =>
      _workGraphs.containsKey(workKeyFor(work));

  /// Opens the graph view of [work] even while it is generating (the picker
  /// lets you jump back into the in-flight generation to watch/stop it).
  void enterGraphWork(AiGraphWorkCandidate work) {
    if (_activeGraphWork == work) return;
    _activeGraphWork = work;
    _wholeBookGraphView = false;
    _bookGraph = _workGraphs[workKeyFor(work)];
    if (!_disposed) notifyListeners();
  }

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
    _wholeBookGraphView = false;
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
    final works = graphWorkCandidates;
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
  }) {
    final active = _bookGraphGeneration;
    if (active != null) return active;
    _generatingGraphWork = only ?? _activeGraphWork;
    final done = Completer<void>();
    _bookGraphGeneration = done.future;
    unawaited(() async {
      try {
        await _generateBookGraph(only: only, force: force);
        done.complete();
      } catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }());
    unawaited(
      done.future.whenComplete(() {
        _bookGraphGeneration = null;
        _bookGraphCancel = null;
        _generatingGraphWork = null;
        if (!_disposed) notifyListeners();
      }),
    );
    return done.future;
  }

  /// Non-null when the outline reveals a collection / multi-volume book:
  /// at least two outline units each spanning multiple spine sections
  /// (a plain book's chapters are one-section units). Each candidate is one
  /// work the user can generate the graph for; the sheet shows a picker.
  ///
  /// The outline does not persist `endSectionIndexExclusive` for every unit
  /// (see real collection caches), so a work's end is derived from the next
  /// unit's start; the last work is open-ended (spans to the book's tail).
  List<AiGraphWorkCandidate>? get graphWorkCandidates {
    final outline = _bookOutline;
    if (outline == null) return null;
    final rows = <(int, String, int?, String)>[
      for (final chapter in outline.chapters)
        if (chapter.sourceSectionIndex != null)
          (chapter.sourceSectionIndex!, chapter.title,
              chapter.endSectionIndexExclusive, chapter.summary.trim()),
    ];
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return _worksFromRows(rows);
  }

  /// Same as [graphWorkCandidates], but when no outline exists yet it runs a
  /// one-shot structural recognition (a single short call vs. the dozens of
  /// extraction calls a generation makes) to detect collections. Returns null
  /// on recognition failure → caller falls back to full-book generation.
  Future<List<AiGraphWorkCandidate>?> resolveGraphWorkCandidates() async {
    final fromOutline = graphWorkCandidates;
    if (fromOutline != null || _bookOutline != null) return fromOutline;
    final service = _aiOutline;
    if (service == null || !canUseAiChat) return null;
    try {
      final body = await _loadBookGraphPlainTextCached(
        AiBookOutlineService.maxBookBodyChars,
      );
      var sections = AiChatBookCorpus.parseSections(body);
      if (sections.isEmpty) return null;
      final titled = [
        for (final section in sections)
          AiBookSectionSlice(
            index: section.index,
            label: section.label.trim().isNotEmpty
                ? section.label.trim()
                : _titleForOutlineSection(section.index),
            text: section.text,
            sourceSectionIndex: section.sourceSectionIndex,
            isNavigationUnit: section.isNavigationUnit,
          ),
      ];
      final eligible =
          _graphEligibleSections(_filterOutlineSections(titled));
      if (eligible.isEmpty) return null;
      final units = await service.planStructure(
        bookTitle: item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        sections: eligible,
      );
      final rows = <(int, String, int?, String)>[
        for (final unit in units)
          if (unit.sourceSectionIndex != null)
            (unit.sourceSectionIndex!, unit.label, null, ''),
      ];
      rows.sort((a, b) => a.$1.compareTo(b.$1));
      return _worksFromRows(rows);
    } catch (_) {
      return null;
    }
  }

  /// [rows] are (startSection, title, optional persisted end). A missing end
  /// is derived from the next row's start; the last row stays open-ended.
  List<AiGraphWorkCandidate>? _worksFromRows(
    List<(int, String, int?, String)> rows,
  ) {
    final works = <AiGraphWorkCandidate>[];
    for (var i = 0; i < rows.length; i++) {
      final (start, rawTitle, persistedEnd, sample) = rows[i];
      final end =
          persistedEnd ?? (i + 1 < rows.length ? rows[i + 1].$1 : null);
      if (end != null && end - start < 2) continue;
      final title = rawTitle.trim();
      if (title.isEmpty || _isGraphAppendixLabel(title)) continue;
      if (_isOutlineMetadataTitle(title)) continue;
      works.add(
        AiGraphWorkCandidate(
          title: title,
          startSection: start,
          endSectionExclusive: end,
          sample: sample,
        ),
      );
    }
    if (works.length < 2) return null;
    return works;
  }

  Future<void> _generateBookGraph({
    AiGraphWorkCandidate? only,
    bool force = false,
  }) async {
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
      final body = await _loadBookGraphPlainTextCached(
        AiBookGraphService.maxBookBodyChars,
      );
      var sections = AiChatBookCorpus.parseSections(body);
      if (sections.isEmpty) throw AiProviderException('无法读取本书正文');
      final allowUnread = _aiSettings?.settings.allowUnreadContext ?? true;
      final titled = [
        for (final section in sections)
          AiBookSectionSlice(
            index: section.index,
            label: section.label.trim().isNotEmpty
                ? section.label.trim()
                : _titleForOutlineSection(section.index),
            text: section.text,
            sourceSectionIndex: section.sourceSectionIndex,
            isNavigationUnit: section.isNavigationUnit,
          ),
      ];
      final graphSections = _graphEligibleSections(
        _filterOutlineSections(titled),
      );
      final scoped = only == null
          ? graphSections
          : graphSections
                .where(
                  (section) =>
                      only.contains(section.sourceSectionIndex ?? section.index),
                )
                .toList(growable: false);
      if (scoped.isEmpty) {
        throw AiProviderException('所选著作没有可用于生成图谱的正文');
      }
      final graph = await service.generate(
        bookTitle: item.title,
        bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
        sections: scoped,
        includesUnread: allowUnread,
        readThroughSection: allowUnread ? null : sectionIndex + 1,
        existing: existing,
        cancelToken: cancel,
        onProgress: (progress) {
          _bookGraphProgress = progress;
          if (!_disposed) notifyListeners();
        },
      );
      _bookGraph = graph;
      if (work != null) _activeGraphWork = work;
      _bookGraphProgress = null;
      await _saveBookGraph(graph, workKey: workKey);
      if (!_disposed) notifyListeners();
    } on AiGraphGenerationException catch (error) {
      _bookGraphProgress = null;
      if (!cancel.isCancelled) {
        final partial = error.partial;
        if (partial != null &&
            partial.contentHash == item.contentHash &&
            !identical(partial, _bookGraph)) {
          _bookGraph = partial;
          await _saveBookGraph(partial, workKey: workKey);
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
      final outline = _tocTitles
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
      return AiChatContextBundle(
        chapterTitle: currentChapterTitle,
        chapterText: chapter,
        selectionText: selection,
        tocOutline: outline,
      );
    } catch (_) {
      return AiChatContextBundle(chapterTitle: currentChapterTitle);
    }
  }

  /// Graph-pipeline corpus: one piece per spine section (toc:false), cached
  /// separately from the outline/chat piece-level cache. Evidence quotes then
  /// resolve to the exact section instead of a multi-section work's start.
  Future<String> _loadBookGraphPlainTextCached(int maxChars) async {
    final budget = maxChars.clamp(2000, 1500000);
    final cached = _cachedGraphPlainText;
    if (cached != null &&
        cached.isNotEmpty &&
        _cachedGraphPlainTextBudget >= budget) {
      return cached.length > budget ? cached.substring(0, budget) : cached;
    }
    final loaded =
        ((await _getBookPlainText?.call(budget, toc: false)) ?? '').trim();
    if (loaded.isNotEmpty) {
      _cachedGraphPlainText = loaded;
      _cachedGraphPlainTextBudget = budget;
      return loaded;
    }
    return ((await _getChapterText?.call()) ?? '').trim();
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

  @override
  Future<String> toolGetToc() async {
    final titles = _c.tocTitles;
    if (titles.isEmpty) {
      final body = await _c._loadBookPlainTextCached(
        AiChatService.maxBookBodyChars,
      );
      final sections = AiChatBookCorpus.parseSections(body);
      if (sections.isNotEmpty) {
        return AiChatBookCorpus.formatTocFromSlices(sections);
      }
      return '(目录不可用)';
    }
    final buf = StringBuffer();
    for (var i = 0; i < titles.length; i++) {
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
    final body = await _c._loadBookPlainTextCached(
      AiChatService.maxBookBodyChars,
    );
    final sections = AiChatBookCorpus.parseSections(body);
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
    final body = await _c._loadBookPlainTextCached(
      AiChatService.maxBookBodyChars,
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
    final body = await _c._loadBookPlainTextCached(
      AiChatService.maxBookBodyChars,
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

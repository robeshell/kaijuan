import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../ai/ai_chat.dart';
import '../../ai/ai_agent_runtime.dart';
import '../../ai/ai_agent_runtime_gate.dart';
import '../../ai/ai_chat_store.dart';
import '../../ai/ai_book_mind_map_service.dart';
import '../../ai/ai_book_mind_map_action_gateway.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_chat_tools.dart';
import '../../ai/ai_conversation_intent.dart';
import '../../ai/ai_book_structure.dart';
import '../../ai/ai_book_structure_session.dart';
import '../../ai/ai_book_corpus.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_graph.dart';
import '../../ai/ai_graph_store.dart';
import '../../ai/ai_graph_scope.dart';
import '../../ai/ai_graph_service.dart';
import '../../ai/ai_log.dart';
import '../../ai/ai_language_service.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_mind_map.dart';
import '../../ai/ai_outline.dart';
import '../../ai/ai_product_action.dart';
import '../../ai/ai_product_action_protocol.dart';
import '../../ai/ai_workflow_contract.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_run_orchestrator.dart';
import '../../ai/ai_search.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_structure_supplements.dart';
import '../../ai/ai_translation.dart';
import '../../ai/ai_user_error.dart';
import '../../ai/legacy_ai_agent_runtime.dart';
import '../../app/book_reading_preferences.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/book_language_actions.dart';
import '../../readers/book/foliate_js_bridge.dart';
import 'ai_settings_controller.dart';
import 'book_annotations_controller.dart';
import 'book_ai_mind_map_controller.dart';
import 'book_ai_reader_gateway.dart';
import 'book_ai_workspace_controller.dart';
import 'book_reader_bridge.dart';
import 'book_reader_preferences_controller.dart';
import 'book_search_controller.dart';
import 'book_tts_controller.dart';

typedef BookMindMapRevisionInput = ({
  AiBookWork? work,
  String label,
  List<AiBookSectionSlice> frozenSections,
  int estimatedSections,
});

/// Owns reflow book session state, chrome, progress, and preferences.
///
/// Rendering details stay in the reader pipeline; this controller is the
/// presentation boundary used by screens and widgets.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required this.database,
    required this.item,
    AiActionJournalStore? actionJournal,
    BookReadingPreferences? readingPreferences,
    BookLanguageProvider? languageProvider,
    AiSettingsController? aiSettings,
    this.agentRuntimeFactory = createLegacyAiAgentRuntime,
    this.genkitAgentRuntimeFactory,
    this.requestedAgentRuntime = AiAgentRuntimeKind.compatible,
    this.genkitAgentCapabilities = AiAgentRuntimeCapabilities.genkitDart0151,
    this.scrollModeEnabled = true,
  }) : languageProvider =
           languageProvider ?? const PlatformBookLanguageProvider() {
    bridge.onContentDetached = _aiCorpus.clear;
    _preferences = BookReaderPreferencesController(
      preferences: readingPreferences,
      scrollModeEnabled: scrollModeEnabled,
      onReadingModeWillChange: () {
        _pendingJumpLocator = currentLocator;
      },
    )..addListener(_notifyPreferencesChanged);
    _annotationState = BookAnnotationsController(
      database: database,
      item: item,
      languageProvider: this.languageProvider,
      beforeOpenMenu: hideChrome,
      tocTitles: () => _tocTitles,
      tocEntries: () => _tocEntries,
      sectionCount: () => sectionCount,
      onGoToCfi: _goToAnnotationCfi,
    )..addListener(_notifyAnnotationsChanged);
    _search = BookSearchController(
      beforeOpenOverlay: () {
        _annotationState.clearSelectionMenu();
        hideChrome();
      },
      onSearchHitSelected: _goToSearchHit,
    )..addListener(_notifySearchChanged);
    _aiWorkspace = BookAiWorkspaceController(
      saveChatSession: saveChatSession,
      actionJournal: actionJournal,
      agentRuntimeFactory: agentRuntimeFactory,
      genkitAgentRuntimeFactory: genkitAgentRuntimeFactory,
      requestedAgentRuntime: requestedAgentRuntime,
      genkitAgentCapabilities: genkitAgentCapabilities,
      onChanged: _notifyAiWorkspaceChanged,
    );
    bindAiSettings(aiSettings);
  }

  void _notifyAiWorkspaceChanged() {
    if (!_disposed) notifyListeners();
  }

  void _notifyPreferencesChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  void _notifySearchChanged() {
    if (!_disposed) notifyListeners();
  }

  void _notifyAnnotationsChanged() {
    if (!_disposed) notifyListeners();
  }

  final AppDatabase database;
  final ReadingItem item;
  final BookLanguageProvider languageProvider;
  final AiAgentRuntimeFactory agentRuntimeFactory;
  final AiAgentRuntimeFactory? genkitAgentRuntimeFactory;
  final AiAgentRuntimeKind requestedAgentRuntime;
  final AiAgentRuntimeCapabilities genkitAgentCapabilities;
  late final BookAiWorkspaceController _aiWorkspace;
  late final BookAnnotationsController _annotationState;
  final BookReaderBridge bridge = BookReaderBridge();
  late final BookReaderPreferencesController _preferences;
  late final BookSearchController _search;
  final bool scrollModeEnabled;
  Future<void> Function()? _clearPlatformFocus;

  /// Wire / re-wire BYOK AI after the widget tree can resolve [AiSettingsScope].
  /// Safe to call repeatedly; no-ops when the controller identity is unchanged.
  void bindAiSettings(AiSettingsController? aiSettings) {
    if (_aiWorkspace.bindSettings(aiSettings) && !_disposed) notifyListeners();
  }

  /// True when BYOK AI is enabled and ready for dictionary / translation / chat.
  bool get canUseAiLanguage => _aiWorkspace.canUseLanguage;

  /// Same readiness gate as language tools (shared provider + key).
  bool get canUseAiChat => _aiWorkspace.canUseChat;

  /// Search API key configured (chat 联网 switch).
  bool get canUseWebSearch => _aiWorkspace.canUseWebSearch;

  bool get supportsDeepThinking {
    return _aiWorkspace.supportsDeepThinking;
  }

  bool get defaultDeepThinkingEnabled =>
      _aiWorkspace.defaultDeepThinkingEnabled;

  AiSettingsController? get aiSettingsController =>
      _aiWorkspace.settingsController;

  BookAiWorkspaceController get aiWorkspace => _aiWorkspace;

  /// Initial scope recommendation for graph generation. The confirmation
  /// sheet may let the user override it; once confirmed, that explicit range
  /// is authoritative.
  bool get allowUnreadGraphContext => _aiWorkspace.allowUnreadGraphContext;

  /// Live translation prefs from the shared settings controller (not a snapshot).
  AiTranslationPreferences get translationPreferences =>
      _aiWorkspace.translationPreferences;

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
  Timer? _saveDebounce;
  BookLocator? _pendingJumpLocator;
  String? _progressLocatorJson;
  List<ReaderBookmark> _bookmarks = const [];
  StreamSubscription<List<ReaderBookmark>>? _bookmarksSubscription;

  AiChatHistoryStore? _chatHistoryStore;
  AiGraphStore? _aiGraphStore;
  AiBookOutline? _bookOutline;

  /// Work key of [_bookOutline] for collections (null = plain book / whole
  /// book). The outline tab follows the reading position: loading/saving
  /// routes to `session.workOutlines[key]`.
  String? _bookOutlineWorkKey;
  String? _bookOutlineError;
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

  Map<String, AiRunState> get aiRunStates => _aiWorkspace.runStates;

  AiRunState? get activeAiRunState => _aiWorkspace.activeRunState;

  Future<T> _executeAiWorkflow<T>({
    required AiRunDescriptor descriptor,
    required AiRunBudget budget,
    required CancelToken cancelToken,
    required Future<T> Function(AiRunExecution execution) body,
    AiRunCheckpointWriter? checkpointWriter,
  }) async {
    return _aiWorkspace.executeWorkflow(
      descriptor: descriptor,
      budget: budget,
      cancelToken: cancelToken,
      checkpointWriter: checkpointWriter,
      body: body,
    );
  }

  late final AiBookCorpusCache _aiCorpus = AiBookCorpusCache(
    loadBookBody: bridge.loadBookPlainText,
    loadChapter: bridge.loadChapterText,
  );
  late final BookAiReaderGateway _aiReaderGateway = BookAiReaderGateway(
    _aiWorkspace,
    _aiCorpus,
  );
  late final AiBookStructureSession _aiStructure = AiBookStructureSession(
    corpus: _aiCorpus,
    publicationTitle: item.title,
    loadIndex: bridge.loadBookStructureIndex,
    isSupplementTitle: (title) =>
        _isOutlineMetadataTitle(title) || _isGraphAppendixLabel(title),
  );
  late final BookTtsController _tts = BookTtsController(
    isReaderDisposed: () => _disposed,
    isReaderReady: () => _ready,
    beforeStart: _annotationState.clearSelectionMenu,
    onPlaybackStarted: showChrome,
    onChanged: notifyListeners,
  );

  /// Optional one-shot message for UI snackbars (cleared by screen).
  String? get ttsUserMessage => _tts.userMessage;
  set ttsUserMessage(String? value) => _tts.userMessage = value;
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
  BookAnnotationsController get annotations => _annotationState;
  BookReaderPreferencesController get preferences => _preferences;
  BookSearchController get search => _search;

  bool get hasPageMode =>
      _preferences.readingMode == BookReadingMode.page && bridge.canGoNextPage;
  List<ReaderBookmark> get bookmarks => _bookmarks;

  BookTtsStatus get ttsStatus => _tts.status;
  bool get ttsActive => _tts.active;
  bool get ttsPlaying => _tts.playing;
  bool get ttsPaused => _tts.paused;
  double get ttsRate => _tts.rate;

  static const ttsRatePresets = BookTtsController.ratePresets;

  bool get canGoPreviousPage => bridge.canGoPreviousPage;
  bool get canGoNextPage => bridge.canGoNextPage;

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
    _annotationState.watchAnnotations();
    _ready = true;
    _openError = null;
    notifyListeners();
    unawaited(database.touchLastOpened(item.id, DateTime.now()));
  }

  /// Optional chat history store (per contentHash). Null → memory-only session.
  void attachChatHistoryStore(AiChatHistoryStore? store) {
    _chatHistoryStore = store;
  }

  /// Optional graph cache store (per contentHash under `ai_graph/`).
  void attachAiGraphStore(AiGraphStore? store) {
    _aiGraphStore = store;
  }

  void attachAiActionJournalStore(AiActionJournalStore store) {
    _aiWorkspace.replaceActionJournal(store);
  }

  void attachAiWorkflowStores({
    required AiWorkflowCheckpointStore checkpoints,
    required AiArtifactRepository artifacts,
  }) {
    _aiWorkspace.replaceWorkflowStores(
      checkpoints: checkpoints,
      artifacts: artifacts,
    );
  }

  void attachTtsBridge({
    required Future<String?> Function() here,
    required Future<String?> Function() next,
    required Future<String?> Function() prev,
    required Future<void> Function() stop,
  }) {
    _tts.attachBridge(here: here, next: next, previous: prev, stop: stop);
  }

  void detachTtsBridge() => _tts.detachBridge();

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
      // Outline generation/deletion has its own writer. A chat-sheet snapshot
      // may have been loaded before either operation, so it must never write
      // outline fields back — including resurrecting an outline deleted while
      // the sheet remained open. Persisted outline state is authoritative.
      final merged = AiChatSession(
        contentHash: session.contentHash,
        itemId: session.itemId,
        messages: session.messages,
        outline: current?.outline,
        workOutlines: current?.workOutlines ?? const {},
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
  AiOutlineProgress? get bookOutlineProgress => null;
  String? get bookOutlineError => _bookOutlineError;
  bool get isGeneratingBookOutline => false;

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

  /// Retired production surface. Structured batch outline is no longer a
  /// product path — use the book chat shortcut "生成本书大纲" instead.
  @Deprecated('Use chat outline shortcut via normal conversation send')
  Future<void> generateBookOutline({Set<int>? excludedSectionIndices}) async {
    _bookOutlineError = '大纲请使用本书对话中的「生成本书大纲」快捷操作';
    if (!_disposed) notifyListeners();
  }

  String _titleForOutlineSection(int sectionIndex1Based) {
    final toc = _tocTitles;
    final index = sectionIndex1Based - 1;
    if (index >= 0 && index < toc.length && toc[index].trim().isNotEmpty) {
      return toc[index].trim();
    }
    return '第 $sectionIndex1Based 节';
  }

  AiContentRuleWords get _contentRuleWords => _aiWorkspace.contentRuleWords;

  /// Never-matches regex used when a word list is empty (rule disabled).
  static final RegExp _neverMatches = RegExp(r'$.^');

  bool _isGraphAppendixLabel(String raw) {
    final title = raw.trim().replaceAll(RegExp(r'\s+'), '');
    final words = _contentRuleWords;
    if (words.metadataUnits.any((word) => word.trim() == title)) return false;
    return matchesAiStructureSupplementTitle(
      raw,
      appendixUnits: words.appendixUnits,
      metadataUnits: words.metadataUnits,
    );
  }

  bool _isOutlineMetadataTitle(String value) {
    final title = value.trim().replaceAll(RegExp(r'\s+'), '');
    return _contentRuleWords.metadataUnits.any((word) => word.trim() == title);
  }



  Future<void> deleteBookOutline() async {
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
          final empty =
              cleared.messages.isEmpty &&
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

  void cancelBookOutlineGeneration() {}

  // ------------------------------------------------------------------
  // Book mind map — independent from chat Mermaid and the knowledge graph.
  // ------------------------------------------------------------------

  String? get bookMindMapProgress => _aiWorkspace.mindMapProgress;
  String? get bookMindMapError => _aiWorkspace.mindMapError;
  bool get isGeneratingBookMindMap => _aiWorkspace.isGeneratingMindMap;

  /// Deterministic substantive units for the frozen current work/publication.
  /// The conversation scope is already confirmed by the user's wording, so
  /// this never exposes graph-style section choices to presentation.
  Future<List<AiBookSectionSlice>> bookMindMapSections({
    AiBookWork? work,
    bool useFrozenWork = false,
  }) async {
    if (!useFrozenWork) await resolveBookStructure();
    final target = useFrozenWork ? work : work ?? currentReadingWork;
    return _mindMapSectionsForWork(target);
  }

  /// Freezes the renderer-backed current chapter before any asynchronous
  /// structure resolution can observe a later page turn. Reader section
  /// indices and the logical whole-book corpus are deliberately not joined:
  /// some EPUBs expose different spine spaces through those two bridges.
  Future<AiBookSectionSlice?> captureCurrentBookMindMapChapter() async {
    final sourceSectionIndex = _sectionIndex + 1;
    final title = currentChapterTitle.trim();
    final text = (await bridge.loadChapterText()).trim();
    if (text.isEmpty) return null;
    AiLog.d(
      'mind map chapter scope: source=$sourceSectionIndex '
      'title=${title.isEmpty ? '-' : title} chars=${text.length}',
    );
    return AiBookSectionSlice(
      index: sourceSectionIndex,
      sourceSectionIndex: sourceSectionIndex,
      label: title.isEmpty ? '当前章节' : title,
      text: text,
    );
  }

  /// Restores and freezes the exact source range of an existing artifact.
  /// Presentation must not duplicate this scope policy or fall back to the
  /// reader's current work when an old artifact can no longer be resolved.
  Future<BookMindMapRevisionInput> prepareBookMindMapRevision(
    AiBookMindMap map,
  ) async {
    if (bookStructureManifest == null) await resolveBookStructure();
    AiBookWork? targetWork;
    final mapWorkKey = map.workKey;
    if (mapWorkKey != null) {
      for (final work in bookStructureManifest?.works ?? const <AiBookWork>[]) {
        if (work.id == mapWorkKey) {
          targetWork = work;
          break;
        }
      }
      if (targetWork == null) {
        throw AiProviderException('这张导图对应的作品范围已经变化，请重新生成后再修改');
      }
    }
    final allSections = await bookMindMapSections(
      work: targetWork,
      useFrozenWork: true,
    );
    final wanted = map.scopeSectionIndices.toSet();
    final scoped = allSections
        .where((section) => wanted.contains(section.index))
        .toList(growable: false);
    if (scoped.isEmpty || scoped.length != wanted.length) {
      throw AiProviderException('这张导图对应的正文范围当前无法读取，请重新生成后再修改');
    }
    return (
      work: targetWork,
      label: map.root.title,
      frozenSections: scoped,
      estimatedSections: scoped.length,
    );
  }

  AiBookMindMapTurnSnapshot freezeBookMindMapTurn({
    required AiBookWork? workScope,
    required AiChatContextBundle context,
  }) {
    return AiBookMindMapActionGateway.freeze(
      conversationWorkKey: workScope == null ? null : workKeyFor(workScope),
      currentWork: workScope,
      manifest: bookStructureManifest,
      context: context,
    );
  }

  Future<AiBookMindMap?> generateBookMindMap({
    AiBookWork? work,
    AiBookSectionSlice? frozenCurrentChapter,
    List<AiBookSectionSlice>? frozenSections,
    AiBookMindMap? existingMindMap,
    bool useFrozenWork = false,
    required String userInstruction,
    String? scopeLabel,
    String? progressLabel,
  }) async {
    if (!useFrozenWork) await resolveBookStructure();
    final target = useFrozenWork ? work : work ?? currentReadingWork;
    final sections =
        frozenSections ??
        (frozenCurrentChapter == null
            ? await bookMindMapSections(work: target, useFrozenWork: true)
            : <AiBookSectionSlice>[frozenCurrentChapter]);
    // Content hook only — session intents use generateMindMapsInConversation.
    return _aiWorkspace.generateMindMapContent(
      contentHash: item.contentHash,
      workKey: target == null ? null : workKeyFor(target),
      publicationTitle: target?.title ?? item.title,
      publicationAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
      scopeLabel: scopeLabel ?? target?.title ?? item.title,
      userInstruction: userInstruction,
      sections: sections,
      existingMindMap: existingMindMap,
      progressLabel: progressLabel,
      emptyScopeMessage: frozenCurrentChapter == null
          ? '这本书没有可用于生成思维导图的正文'
          : '当前章节没有可用于生成思维导图的正文',
    );
  }

  void cancelBookMindMapGeneration() => _aiWorkspace.cancelMindMapGeneration();

  Future<BookAiMindMapBatchOutcome> generateMindMapsInConversation({
    required String turnId,
    required String? workKey,
    required String text,
    required List<BookAiMindMapGenerationUnit> units,
    required CancelToken cancelToken,
    AiBookMindMap? baseMap,
    String? retryTurnId,
    AiConversationCommand? command,
    void Function(AiBookMindMap artifact)? onArtifact,
  }) {
    return _aiWorkspace.runMindMapSession(
      turnId: turnId,
      workKey: workKey,
      text: text,
      publicationTitle: item.title,
      units: units,
      retryTurnId: retryTurnId,
      command: command,
      baseMap: baseMap,
      cancelToken: cancelToken,
      segmentedPublication:
          bookStructureManifest?.kind ==
          AiBookStructureKind.segmentedSingleWork,
      loadSections: (unit) =>
          bookMindMapSections(work: unit.work, useFrozenWork: true),
      generateMap: (unit, sections, progress) => generateBookMindMap(
        work: unit.work,
        useFrozenWork: true,
        frozenSections: sections,
        existingMindMap: baseMap,
        userInstruction: text,
        scopeLabel: unit.label,
        progressLabel: progress,
      ),
      onArtifact: onArtifact,
    );
  }

  // ------------------------------------------------------------------
  // Book knowledge graph (AI M5) — see docs/specs/ai-graph.md
  // ------------------------------------------------------------------

  AiBookGraph? get bookGraph => _bookGraph;

  static bool _hasDisplayGraphData(AiBookGraph? graph) {
    if (graph == null) return false;
    final display = graph.verifiedForDisplay();
    return display.entities.isNotEmpty || display.relations.isNotEmpty;
  }

  @visibleForTesting
  static bool graphCanResumeIncrementally(AiBookGraph? graph) =>
      _hasDisplayGraphData(graph);

  @visibleForTesting
  static int? graphReadThroughForGeneration({
    required bool userConfirmedScope,
    required bool resettingEmptySnapshot,
    required bool existingIncludesUnread,
    required bool allowUnread,
    required int readThrough,
  }) {
    final applyAutomaticReadGate =
        !userConfirmedScope &&
        !resettingEmptySnapshot &&
        !existingIncludesUnread &&
        !allowUnread;
    return applyAutomaticReadGate ? readThrough : null;
  }

  /// Whether the saved snapshot contains at least one grounded item that the
  /// reader can actually present. Coverage metadata alone does not make an
  /// empty snapshot a completed graph.
  bool get hasUsableBookGraph => _hasDisplayGraphData(_bookGraph);

  /// Display projection of the saved graph.
  ///
  /// [includesUnread] records the scope that was explicitly used when the
  /// graph was generated. Do not re-filter that persisted result with this
  /// device's current setting or renderer position: preferences are local and
  /// mobile relocation can arrive after the graph tab opens, which previously
  /// turned a valid cross-device graph into an all-zero view.
  AiBookGraph? get visibleBookGraph {
    final graph = _bookGraph;
    if (graph == null) return null;
    final display = graph.verifiedForDisplay();
    if (display.entities.isEmpty && display.relations.isEmpty) return null;
    return display;
  }

  /// Collection work currently shown in the graph tab, or null for a
  /// whole-book graph / plain book.
  AiGraphWorkCandidate? get activeGraphWork => _activeGraphWork;

  bool get hasActiveWorkGraph => _activeGraphWork != null;

  static String workKeyFor(AiBookWork work) => work.id;

  /// The internal work the reader is currently inside (current spine →
  /// work range), or null when the current section belongs to no work (plain
  /// book / front matter / whole-book view). Drives the「读到哪本跟哪本」
  /// behavior for a multi-work file.
  AiBookWork? get currentReadingWork {
    return _aiStructure.workAtSection(_sectionIndex + 1);
  }

  /// Current deterministic part/volume as well as an omnibus work. Logical
  /// ranges that share one physical spine cannot be inferred from the reader
  /// locator and deliberately return null.
  AiBookWork? get currentMindMapStructureUnit {
    final manifest = bookStructureManifest;
    if (manifest == null) return null;
    final matches = manifest.works
        .where((work) => work.contains(_sectionIndex + 1))
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  /// Public view of the cached structural-recognition result (null = not
  /// resolved yet or no works); the sheet uses it to decide the loading
  /// state without holding a duplicate cache.
  List<AiBookWork>? get resolvedBookWorks => _aiStructure.scopedWorks;

  /// Compatibility projection retained for the knowledge-graph UI.
  List<AiGraphWorkCandidate>? get resolvedGraphWorks => resolvedBookWorks;

  AiBookStructureManifest? get bookStructureManifest => _aiStructure.manifest;

  List<AiBookWork>? get _resolvedBookWorks => _aiStructure.scopedWorks;

  /// Whether this single file is a recognized multi-work omnibus.
  bool get hasCollectionWorks => _aiStructure.hasCollectionWorks;

  bool get hasAmbiguousInternalWorks => _aiStructure.hasAmbiguousInternalWorks;

  String get aiStructureUnavailableMessage =>
      '当前无法可靠判断这些内容是章节还是多部作品。对话将按整本书处理；大纲和知识图谱可手动选择范围。';

  /// Chat is always available. A resolved work narrows the corpus; an
  /// uncertain structure or front-matter position falls back to the whole
  /// publication instead of disabling the composer.
  bool get canChatAtCurrentPosition => true;

  /// True when a graph was already generated for [work] of this collection.
  bool hasWorkGraph(AiGraphWorkCandidate work) =>
      _hasDisplayGraphData(_workGraphs[workKeyFor(work)]);

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

  /// Returns from a generated work to the publication's work list. Reader
  /// pagination never selects a graph on the user's behalf.
  void closeActiveWorkGraph() {
    if (_activeGraphWork == null && _bookGraph == null) return;
    _activeGraphWork = null;
    _bookGraph = null;
    if (!_disposed) notifyListeners();
  }

  AiGraphProgress? get bookGraphProgress => _bookGraphProgress;
  String? get bookGraphError => _bookGraphError;
  bool get isGeneratingBookGraph => _bookGraphGeneration != null;
  AiGraphWorkCandidate? get generatingGraphWork => _generatingGraphWork;

  AiGraphWorkCandidate? _generatingGraphWork;

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
      final works = _resolvedBookWorks;
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
    AiNarrationPlanMode narrationMode = AiNarrationPlanMode.autoAnalyze,
    Set<int>? excludedGraphSectionIndices,
  }) {
    final active = _bookGraphGeneration;
    if (active != null) return active;
    _generatingGraphWork = only ?? _activeGraphWork;
    final done = Completer<void>();
    _bookGraphGeneration = done.future;
    unawaited(() async {
      try {
        await _generateBookGraph(
          only: only,
          force: force,
          narrationOverride: narrationOverride,
          narrationMode: narrationMode,
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
        _generatingGraphWork = null;
        if (!_disposed) notifyListeners();
      }),
    );
    return done.future;
  }

  /// Resolves deterministic file structure once per reader. Compatibility
  /// return: independent work scopes for an omnibus, otherwise null.
  Future<List<AiBookWork>?> resolveBookStructure({CancelToken? cancel}) async {
    if (_aiStructure.isResolved) return _resolvedBookWorks;
    cancel?.throwIfCancelled();
    try {
      return await _resolveWorks(cancel);
    } catch (error) {
      // A corpus-extraction failure (WebView reload mid-read, JS callback
      // error) must not wedge callers waiting for deterministic structure.
      AiLog.d('resolveBookStructure failed: $error');
      return null;
    }
  }

  /// Compatibility name retained for the knowledge-graph presentation.
  Future<List<AiGraphWorkCandidate>?> resolveGraphWorkCandidates({
    CancelToken? cancel,
  }) => resolveBookStructure(cancel: cancel);

  Future<List<AiBookWork>?> _resolveWorks(CancelToken? cancel) async {
    final works = await _aiStructure.resolve(
      maxChars: AiBookOutlineService.maxBookBodyChars,
      cancel: cancel,
    );
    if (!_disposed) notifyListeners();
    return works;
  }

  Future<void> _generateBookGraph({
    AiGraphWorkCandidate? only,
    bool force = false,
    AiNarrationPlan? narrationOverride,
    AiNarrationPlanMode narrationMode = AiNarrationPlanMode.autoAnalyze,
    Set<int>? excludedGraphSectionIndices,
  }) async {
    // Carry the manual slice so a failed partial save doesn't silently drop
    // it for the next incremental run (catch block is out of try scope).
    var carryExcluded = const <int>[];
    final service = _aiWorkspace.graph;
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
    final previous = workKey == null ? _bookGraph : _workGraphs[workKey];
    // An old/partial cache can have every section marked covered while still
    // containing zero grounded display data. Resuming from it would skip the
    // entire corpus forever and immediately produce another all-zero graph.
    // Treat it as a fresh run while preserving the user's hidden-ID list.
    final resettingEmptySnapshot =
        previous != null && !graphCanResumeIncrementally(previous);
    final existing = force || resettingEmptySnapshot ? null : previous;
    final hiddenEntityIds = previous?.hiddenEntityIds ?? const <String>[];
    _bookGraphError = null;
    final cancel = CancelToken();
    _bookGraphCancel = cancel;
    if (!_disposed) notifyListeners();
    try {
      await resolveGraphWorkCandidates(cancel: cancel);
      final allowUnread = allowUnreadGraphContext;
      final deduped = await _graphSectionsForWork(work);
      // Manual slice persists on the graph: a fresh regeneration carries the
      // previous exclusions unless the user changed them in the dialog;
      // incremental runs keep excluding the same sections too.
      final effectiveExcluded =
          excludedGraphSectionIndices ??
          existing?.excludedGraphSections.toSet() ??
          const <int>{};
      final sections = excludeGraphSections(deduped, effectiveExcluded)
          // Structural container markers have no body; the flat range picker
          // and extraction pipeline both operate only on non-empty leaves.
          .where((s) => s.text.trim().isNotEmpty)
          .toList(growable: false);
      if (sections.isEmpty) {
        throw AiProviderException('所选章节都被排除了，请至少保留一节正文');
      }
      final readThrough = sectionIndex + 1;
      final userConfirmedScope = excludedGraphSectionIndices != null;
      final selectedIncludesUnread = sections.any(
        (section) => section.originSectionIndex > readThrough,
      );
      final includesUnread =
          allowUnread ||
          selectedIncludesUnread ||
          (existing?.includesUnread ?? false);
      // The range chooser is the user's final decision. In particular, a
      // mobile renderer may still report the cover/first spine while the
      // chooser already contains 248 valid sections; applying the position
      // gate again here used to collapse that explicit selection to zero.
      final effectiveReadThrough = graphReadThroughForGeneration(
        userConfirmedScope: userConfirmedScope,
        resettingEmptySnapshot: resettingEmptySnapshot,
        existingIncludesUnread: existing?.includesUnread ?? false,
        allowUnread: allowUnread,
        readThrough: readThrough,
      );
      carryExcluded = (effectiveExcluded.toList()..sort()).toList(
        growable: false,
      );
      final graph = await _executeAiWorkflow<AiBookGraph>(
        descriptor: AiRunDescriptor(
          runId: AiRunIds.next(),
          task: AiRunTask.bookGraph,
          scope: AiRunScope(
            contentHash: item.contentHash,
            workKey: workKey,
            label: work?.title,
          ),
        ),
        budget: AiRunBudget(
          maxModelCalls: (sections.length * 12 + 64).clamp(128, 4096),
        ),
        cancelToken: cancel,
        checkpointWriter: (checkpoint) async {
          final partial = checkpoint.payload;
          if (partial is! AiBookGraph) return;
          _bookGraph = partial;
          if (work != null) _activeGraphWork = work;
          await _saveBookGraph(partial, workKey: workKey);
        },
        body: (execution) => service.generate(
          bookTitle: work?.title ?? item.title,
          bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
          sections: sections,
          sectionScheme: 'spine',
          includesUnread: includesUnread,
          readThroughSection: effectiveReadThrough,
          existing: existing,
          plannedNarration: narrationOverride,
          narrationMode: narrationMode,
          cancelToken: execution.cancelToken,
          onModelStarted: execution.modelStarted,
          onUsage: ({inputTokens, outputTokens}) => execution.reportTokens(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          ),
          onProgress: (progress) {
            execution.progress(progress.label);
            _bookGraphProgress = progress;
            if (!_disposed) notifyListeners();
          },
          onCheckpoint: (partial) => execution.checkpoint(
            partial.copyWith(
              contentHash: item.contentHash,
              excludedGraphSections: carryExcluded,
              hiddenEntityIds: hiddenEntityIds,
            ),
          ),
        ),
      );
      final saved = graph.copyWith(
        excludedGraphSections: carryExcluded,
        hiddenEntityIds: hiddenEntityIds,
      );
      _bookGraph = saved;
      if (work != null) _activeGraphWork = work;
      _bookGraphProgress = null;
      await _saveBookGraph(saved, workKey: workKey);
      if (!_disposed) notifyListeners();
    } on AiGraphGenerationException catch (error) {
      _bookGraphProgress = null;
      if (!cancel.isCancelled) {
        AiLog.d('graph failed: ${error.message}');
        final partial = error.partial;
        if (partial != null && !identical(partial, _bookGraph)) {
          // contentHash is re-stamped by _saveBookGraph; on a first
          // generation the partial carries an empty hash. Keep the manual
          // slice on the partial so incremental runs keep excluding.
          final savedPartial = partial.copyWith(
            excludedGraphSections: carryExcluded,
            hiddenEntityIds: hiddenEntityIds,
          );
          _bookGraph = savedPartial;
          await _saveBookGraph(savedPartial, workKey: workKey);
        }
        _bookGraphError = aiUserErrorMessage(
          error,
          operation: AiUserOperation.graph,
        );
      }
      if (!_disposed) notifyListeners();
    } catch (error, stack) {
      _bookGraphProgress = null;
      if (!cancel.isCancelled) {
        AiLog.d('graph failed: $error\n$stack');
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
    String Function(AiBookSectionSlice section)? fallback,
  }) => [
    for (final section in sections)
      AiBookSectionSlice(
        index: section.index,
        label: section.label.trim().isNotEmpty
            ? section.label.trim()
            : (fallback?.call(section) ?? section.label),
        text: section.text,
        sourceSectionIndex: section.sourceSectionIndex,
        isNavigationUnit: section.isNavigationUnit,
        navigationChildCount: section.navigationChildCount,
        level: section.level,
      ),
  ];

  /// Spine-mode extraction used by a file-internal work can receive the EPUB
  /// resource href as its fallback label (`OEBPS/Text/ch01.xhtml`). That is a
  /// useful engine identifier but not a chapter name. Replace only those
  /// resource-shaped labels with the authoritative per-spine TOC title; keep
  /// real document headings such as “第一章” or “狂人日记” untouched.
  List<AiBookSectionSlice> _withAiDisplayTitles(
    List<AiBookSectionSlice> sections,
  ) => [
    for (final section in sections)
      AiBookSectionSlice(
        index: section.index,
        label: _looksLikeBookResourcePath(section.label)
            ? _titleForOutlineSection(section.originSectionIndex)
            : section.label,
        text: section.text,
        sourceSectionIndex: section.sourceSectionIndex,
        isNavigationUnit: section.isNavigationUnit,
        navigationChildCount: section.navigationChildCount,
        level: section.level,
      ),
  ];

  static bool _looksLikeBookResourcePath(String raw) {
    final label = raw.trim();
    if (label.isEmpty) return false;
    return RegExp(
      r'\.(?:xhtml?|html?|xml|opf|ncx|txt)(?:[?#].*)?$',
      caseSensitive: false,
    ).hasMatch(label);
  }

  Future<List<AiBookSectionSlice>> _mindMapSectionsForWork(
    AiBookWork? work,
  ) async {
    final body = await _aiCorpus.loadSpine(AiBookMindMapService.maxBodyChars);
    if (body.length >= AiBookMindMapService.maxBodyChars - 64) {
      throw AiProviderException('本书正文超过当前可完整读取的范围，未生成删减版思维导图');
    }
    final sections = AiChatRetrieve.splitSections(body);
    if (sections.isEmpty) throw AiProviderException('无法读取本书正文');
    final titled = _withAiDisplayTitles(
      _withTitles(
        sections,
        fallback: (section) =>
            _titleForOutlineSection(section.originSectionIndex),
      ),
    );
    final workScoped = work == null
        ? titled
        : titled
              .where((section) {
                if (work.needsLogicalLocator) {
                  final physical = section.sourceSectionIndex ?? section.index;
                  final logicalEnd = work.endLogicalIndexExclusive;
                  return physical == work.startSection &&
                      section.index >= work.startLogicalIndex! &&
                      (logicalEnd == null || section.index < logicalEnd);
                }
                return work.contains(
                  section.sourceSectionIndex ?? section.index,
                );
              })
              .toList(growable: false);
    final substantive = workScoped
        .where((section) => !_isMindMapAutomaticSupplement(section))
        .where((section) => !_isMindMapTitleOnlySection(section))
        .toList(growable: false);
    if (substantive.isEmpty) {
      throw AiProviderException('这本书没有可用于生成思维导图的正文');
    }
    AiLog.d(
      'mind map scope: work=${work?.title ?? 'whole-book'} '
      'units=${titled.length} scoped=${workScoped.length} '
      'substantive=${substantive.length}',
    );
    return substantive;
  }

  String? _mindMapExcludedPatternsKey;
  RegExp? _mindMapExcludedPatternsRegExp;

  /// Mind-map input uses its own configurable title globs. It must not inherit
  /// knowledge-graph supplement settings or a graph scope plan.
  bool _isMindMapAutomaticSupplement(AiBookSectionSlice section) {
    final label = section.label.trim().replaceAll(RegExp(r'\s+'), '');
    final patterns = _contentRuleWords.mindMapExcludedTitlePatterns;
    final key = patterns.join('\u0001');
    if (key != _mindMapExcludedPatternsKey) {
      _mindMapExcludedPatternsKey = key;
      _mindMapExcludedPatternsRegExp = _titleGlobsRegExp(patterns);
    }
    if (_mindMapExcludedPatternsRegExp!.hasMatch(label)) return true;
    final text = section.text.trim();
    if (text.isEmpty) return false;
    final prefix = text.length > 640 ? text.substring(0, 640) : text;
    final compact = prefix.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^(目录|目次)(?:[：:]|$)').hasMatch(compact)) return true;
    final hasCopyrightSignal = RegExp(
      r'ISBN|图书在版编目|版权所有|版权归属|版权信息',
    ).hasMatch(prefix);
    return hasCopyrightSignal && RegExp(r'出版|出版社|版权|编目').hasMatch(prefix);
  }

  static RegExp _titleGlobsRegExp(List<String> patterns) {
    final expressions = <String>[];
    for (final raw in patterns) {
      final pattern = raw.trim().replaceAll(RegExp(r'\s+'), '');
      if (pattern.isEmpty) continue;
      final parts = pattern.split('*').map(RegExp.escape).join('.*');
      expressions.add('(?:$parts)');
    }
    if (expressions.isEmpty) return _neverMatches;
    return RegExp('^(?:${expressions.join('|')})\$');
  }

  static bool _isMindMapTitleOnlySection(AiBookSectionSlice section) {
    final text = _mindMapComparable(section.text);
    final title = _mindMapComparable(section.label);
    return text.isEmpty || (title.isNotEmpty && text == title);
  }

  static String _mindMapComparable(String value) => value
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '')
      .toLowerCase();

  /// Loads the fine-grained graph corpus for [work] (null = the publication).
  /// Nothing is removed here: supplement rules only become recommendations in
  /// [graphScopePlan], and the user's confirmed selection is the final scope.
  Future<List<AiBookSectionSlice>> _graphSectionsForWork(
    AiGraphWorkCandidate? work,
  ) async {
    final body = await _aiCorpus.loadSpine(AiBookGraphService.maxBookBodyChars);
    final sections = AiChatRetrieve.splitSections(body);
    if (sections.isEmpty) throw AiProviderException('无法读取本书正文');
    final titled = _withAiDisplayTitles(
      _withTitles(
        sections,
        fallback: (section) =>
            _titleForOutlineSection(section.originSectionIndex),
      ),
    );
    final scoped = work == null
        ? titled
        : titled
              .where(
                (section) =>
                    work.contains(section.sourceSectionIndex ?? section.index),
              )
              .toList(growable: false);
    if (scoped.isEmpty) {
      throw AiProviderException('所选著作没有可用正文');
    }
    AiLog.d(
      'graph scope: work=${work?.title ?? 'whole-book'} '
      'range=${work == null ? '-' : '${work.startSection}..${work.endSectionExclusive}'} '
      'sections=${titled.length} scoped=${scoped.length}',
    );
    return scoped;
  }

  /// Complete user-visible scope plan. Rules are recommendations and never
  /// erase a readable unit before the user sees it.
  Future<AiGraphScopePlan> graphScopePlan(AiGraphWorkCandidate? work) async {
    final sections = await _graphSectionsForWork(work);
    return AiGraphScopePlanner.build(
      sections: sections,
      work: work,
      isSuggestedSupplement: (title) =>
          _isOutlineMetadataTitle(title) || _isGraphAppendixLabel(title),
    );
  }

  /// Compatibility accessor for tests and non-UI callers. New UI should use
  /// [graphScopePlan] so recommendation reasons are not lost.
  Future<List<AiBookSectionSlice>> graphSectionChoices(
    AiGraphWorkCandidate? work,
  ) async => (await graphScopePlan(
    work,
  )).choices.map((choice) => choice.section).toList(growable: false);

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
  Future<AiNarrationPlan?> analyzeActiveGraphNarration({
    AiGraphWorkCandidate? work,
  }) async {
    final service = _aiWorkspace.graph;
    if (service == null || !canUseAiChat) return null;
    try {
      await resolveGraphWorkCandidates();
      final sections = await _graphSectionsForWork(work);
      return await service.analyzeNarration(
        bookTitle: work?.title ?? item.title,
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

  Future<void> hideBookGraphEntity(String entityId) async {
    if (isGeneratingBookGraph) return;
    final graph = _bookGraph;
    if (graph == null || graph.hiddenEntityIds.contains(entityId)) return;
    final hidden = [...graph.hiddenEntityIds, entityId];
    final updated = graph.copyWith(hiddenEntityIds: hidden);
    _bookGraph = updated;
    final work = _activeGraphWork;
    await _saveBookGraph(
      updated,
      workKey: work == null ? null : workKeyFor(work),
    );
    if (!_disposed) notifyListeners();
  }

  void cancelBookGraphGeneration() {
    _bookGraphCancel?.cancel();
  }

  /// Lean chat seed: current chapter + selection + TOC titles (no whole-book dump).
  Future<AiChatContextBundle> loadAiChatContext({
    String? selectionOverride,
    required AiBookWork? workScope,
  }) => _aiReaderGateway.loadContext(
    chapterSectionIndex: _sectionIndex + 1,
    chapterTitle: currentChapterTitle,
    tocTitles: _tocTitles,
    workScope: workScope,
    selectionOverride: selectionOverride,
    currentSelection: _annotationState.selectionMenu?.text,
    loadSelectedText: _annotationState.peekSelectedText,
    loadChapterText: bridge.loadChapterText,
  );

  /// Stream an assistant reply for book chat. Null when AI is unavailable.
  Stream<AiRunEvent>? streamBookChat({
    required String userText,
    required List<AiChatMessage> history,
    required AiChatContextBundle context,
    required AiBookWork? workScope,
    List<AiWebSearchHit>? webHits,
    AiChatProductContext productContext = const AiChatProductContext(),
    bool? reasoningEnabled,
    CancelToken? cancelToken,
    String? runId,
  }) => _aiReaderGateway.streamChat(
    contentHash: item.contentHash,
    bookTitle: item.title,
    bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
    userText: userText,
    history: history,
    context: context,
    workScope: workScope,
    webHits: webHits,
    productContext: productContext,
    reasoningEnabled: reasoningEnabled,
    cancelToken: cancelToken,
    runId: runId,
  );

  /// A short, answer-specific follow-up prompt. Failure is intentionally an
  /// empty result so the chat sheet can keep its stable fallback suggestions.
  Future<List<String>> suggestBookChatFollowUps({
    required String userText,
    required String answer,
    required AiChatContextBundle context,
    CancelToken? cancelToken,
  }) => _aiReaderGateway.suggestFollowUps(
    bookTitle: item.title,
    bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
    userText: userText,
    answer: answer,
    context: context,
    cancelToken: cancelToken,
  );

  /// BYOK web search for chat 联网. Empty list if not configured.
  Future<List<AiWebSearchHit>> searchWebForChat(
    String query, {
    required AiBookWork? workScope,
    CancelToken? cancelToken,
  }) => _aiReaderGateway.searchWeb(
    query: query,
    bookTitle: workScope?.title ?? item.title,
    bookAuthor: bookAuthorsLabel.isEmpty ? null : bookAuthorsLabel,
    cancelToken: cancelToken,
  );

  /// Optimistic scrub to a whole-book fraction; Foliate relocate confirms CFI.
  void seekToFraction(double fraction) {
    if (_disposed || !_ready) return;
    final next = fraction.clamp(0.0, 1.0);
    _renditionProgress = next;
    notifyListeners();
    bridge.seek(next);
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
    debugPrint('[BookReader] failed to open book: $error');
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

  void goNextPage() => bridge.nextPage();

  void goPreviousPage() => bridge.previousPage();

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

  /// AI stream for in-app dictionary / translation. Null when AI is unavailable.
  Stream<String>? streamLanguageAssist({
    required BookLanguageOperation operation,
    required String text,
    CancelToken? cancelToken,
    AiTranslationRequestOptions? translationOptions,
  }) {
    final service = _aiWorkspace.language;
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
    return _streamLanguageAssistRun(
      service: service,
      operation: operation,
      text: text,
      cancelToken: cancelToken,
      translationOptions: merged,
    );
  }

  Stream<String> _streamLanguageAssistRun({
    required AiLanguageService service,
    required BookLanguageOperation operation,
    required String text,
    CancelToken? cancelToken,
    AiTranslationRequestOptions? translationOptions,
  }) async* {
    final effectiveCancel = cancelToken ?? CancelToken();
    await for (final event in const AiRunOrchestrator().run(
      descriptor: AiRunDescriptor(
        runId: AiRunIds.next(),
        task: AiRunTask.language,
        scope: AiRunScope(
          contentHash: item.contentHash,
          label: currentChapterTitle,
        ),
      ),
      budget: const AiRunBudget(maxModelCalls: 2),
      cancelToken: effectiveCancel,
      body: (execution) async {
        await for (final snapshot in service.streamAssist(
          operation: operation,
          text: text,
          cancelToken: execution.cancelToken,
          translationOptions: translationOptions,
          onModelStarted: execution.modelStarted,
          onUsage: ({inputTokens, outputTokens}) => execution.reportTokens(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          ),
        )) {
          execution.textSnapshot(snapshot);
        }
      },
    )) {
      _aiWorkspace.recordRunEvent(event);
      switch (event) {
        case AiRunTextSnapshot():
          yield event.text;
        case AiRunFailed():
          Error.throwWithStackTrace(event.error, event.stackTrace);
        case AiRunCancelled():
          throw AiProviderException('已取消');
        default:
          break;
      }
    }
  }

  void _goToAnnotationCfi(String cfi) {
    final key = cfi.trim();
    if (key.isEmpty) return;
    final fromCfi = BookLocator.sectionIndexFromCfi(key);
    final sectionIndex =
        (fromCfi != null && (sectionCount <= 0 || fromCfi < sectionCount))
        ? fromCfi
        : _sectionIndex;
    _sectionIndex = sectionIndex;
    _pendingJumpLocator = BookLocator(
      sectionIndex: sectionIndex,
      progressInSection: _progressInSection,
      cfi: key,
    );
    notifyListeners();
  }

  void _goToSearchHit(FoliateSearchHit hit) {
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
    notifyListeners();
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
    _aiWorkspace.dispose();

    _bookGraphCancel?.cancel();
    _attachGeneration++;
    _preferences.removeListener(_notifyPreferencesChanged);
    _preferences.dispose();
    _annotationState.removeListener(_notifyAnnotationsChanged);
    _annotationState.dispose();
    _search.removeListener(_notifySearchChanged);
    _search.dispose();
    _saveDebounce?.cancel();
    unawaited(_tts.dispose());
    bridge.detachAll();
    detachTtsBridge();
    unawaited(_bookmarksSubscription?.cancel());
    unawaited(_persist());
    super.dispose();
  }

  // System TTS compatibility facade. Engine state and playback loops live in
  // [BookTtsController]; Foliate navigation remains attached through the
  // reader bridge above.

  Future<void> startTts() => _tts.start();

  Future<void> pauseTts() => _tts.pause();

  Future<void> resumeTts() => _tts.resume();

  Future<void> toggleTtsPlayPause() => _tts.togglePlayPause();

  Future<void> stopTts() => _tts.stop();

  Future<void> setTtsRate(double rate) => _tts.setRate(rate);

  Future<void> ttsSkipNext() => _tts.skipNext();

  Future<void> ttsSkipPrevious() => _tts.skipPrevious();
}

/// Test seam for verifying the controller-backed tool contract without
/// exposing the private host implementation to production callers.
@visibleForTesting
AiChatToolHost createBookChatToolHostForTesting({
  required BookReaderController controller,
  required AiChatContextBundle context,
  AiBookWork? work,
}) => controller._aiReaderGateway.createToolHost(context: context, work: work);

/// Restricts a getBookPlainText body to [work]'s unit (「读到哪本跟哪本」
/// chat scope). A null work passes the body through unchanged.
///
/// The current chat corpus is chapter-granular spine mode, so the physical
/// work range is authoritative and retains every chapter/logical piece in the
/// work. Exact work-title matching remains only as compatibility fallback for
/// older/navigation-mode bodies that contain one slice per work.
@visibleForTesting
String scopeChatBodyToWork(String body, AiBookWork? work) {
  return scopeAiChatBodyToWork(body, work);
}

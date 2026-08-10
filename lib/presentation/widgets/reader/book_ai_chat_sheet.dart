import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../ai/ai_cancel.dart';
import '../../../ai/ai_chat.dart';
import '../../../ai/ai_chat_session_ops.dart';
import '../../../ai/ai_graph.dart';
import '../../../ai/ai_graph_family_tree.dart';
import '../../../ai/ai_graph_service.dart';
import '../../../ai/ai_models.dart';
import '../../../ai/ai_mind_map.dart';
import '../../../ai/ai_provider_kind.dart';
import '../../../ai/ai_run.dart';
import '../../../ai/ai_search.dart';
import '../../../ai/ai_user_error.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/text_editing_focus.dart';
import '../../../core/theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../../screens/ai_settings_screen.dart';
import '../ai_typography.dart';
import '../app_components.dart';
import '../app_overlays.dart';
import 'ai_result_body.dart';
import 'book_ai_entity_sheet.dart';
import 'book_ai_graph_family_tree_fullscreen.dart';
import 'book_ai_graph_family_tree_view.dart';
import 'book_ai_graph_sort.dart';
import 'book_ai_graph_tiles.dart';
import 'book_ai_graph_fullscreen.dart';
import 'book_ai_graph_view.dart';
import 'book_ai_mind_map_fullscreen.dart';
import 'book_ai_mind_map_view.dart';
import 'book_ai_narration_dialog.dart';

/// Book-scoped AI chat (M2). Session is isolated by contentHash.
///
/// Presentation is adaptive: side panel on medium/wide windows, bottom sheet
/// on compact phones.
Future<void> showBookAiChatSheet(
  BuildContext context, {
  required BookReaderController controller,
  String? initialSelection,
}) async {
  if (!context.mounted) return;
  final anchorPoint = appTrailingBottomOverlayAnchor(context);
  // Phone: bottom sheet. Tablet / desktop: trailing side panel that tracks
  // window width (see [showAppAdaptivePanel] / [resolveAppSideSheetWidth]).
  return showAppAdaptivePanel<void>(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.16),
    // This is a reading workspace, not a floating peek surface. Keep the
    // rendered book from competing with long outline text underneath.
    surfaceColor: Theme.of(context).colorScheme.surface,
    // Avoid recompositing the live WebView through a full-height blur during
    // the side-sheet entrance animation.
    sideSheetBlur: false,
    anchorPoint: anchorPoint,
    builder: (sheetContext) => _BookAiChatSheet(
      controller: controller,
      initialSelection: initialSelection,
    ),
  );
}

class _BookAiChatSheet extends StatefulWidget {
  const _BookAiChatSheet({required this.controller, this.initialSelection});

  final BookReaderController controller;
  final String? initialSelection;

  @override
  State<_BookAiChatSheet> createState() => _BookAiChatSheetState();
}

enum _BookAiWorkspaceTab { chat, graph }

/// Kept only while old structured-outline caches remain readable by older
/// app versions. The current UI generates outlines through normal chat.
enum _OutlineAction { delete }

typedef _NarrationConfirmation = ({
  AiNarrationPlan? plan,
  AiNarrationPlanMode mode,
  Set<int> excludedSections,
});

/// Default view is the person card list (Kindle X-Ray style); the force
/// layout stays available as a secondary「关系图」view. Each entity type gets
/// its own chapter-ordered list so「谁是谁 / 在哪里 / 发生了哪些事」are
/// readable without the graph.
enum _GraphViewMode {
  persons,
  locations,
  events,
  organizations,
  things,
  graph,
  familyTree,
}

class _BookAiChatSheetState extends State<_BookAiChatSheet>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _graphQueryController = TextEditingController();
  final _graphScrollController = ScrollController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final TabController _tabs;
  _BookAiWorkspaceTab _activeTab = _BookAiWorkspaceTab.chat;

  AiChatSession _session = const AiChatSession(contentHash: '', itemId: '');
  _GraphViewMode _graphViewMode = _GraphViewMode.persons;

  /// Plan whose default view has been applied; applying again is skipped so
  /// the user's manual view choice survives unrelated controller updates.
  AiBookGraph? _appliedNarrationGraph;
  bool _familyTreeDetailExpanded = false;

  /// Per-view selection: changing 人物 never changes 地点/事件/组织.
  final _graphSortOrders = <_GraphViewMode, GraphEntitySortOrder>{};

  GraphEntitySortOrder get _graphSortOrder =>
      _graphSortOrders[_graphViewMode] ?? defaultGraphSortOrder(_graphListKind);

  /// Isolated entities (0 relations) collapse into a single row until opened.
  bool _graphIsolatedExpanded = false;

  /// Collection works (null = plain book or not resolved yet). Resolved
  /// lazily via a one-shot structure recognition; gates the collection UI.
  bool _graphWorksLoading = false;
  bool _graphPreparing = false;
  String? _graphPreparingWorkId;
  String _graphQuery = '';
  String? _graphHighlighted;
  Timer? _graphHighlightTimer;
  Timer? _streamCheckpointTimer;
  DateTime? _lastStreamCheckpointAt;
  final _graphEntityKeys = <String, GlobalKey>{};
  int _graphListEpoch = 0;

  /// Attached highlight; null when cleared by user.
  String? _selection;
  bool _loadingSession = true;
  String? _loadError;
  bool _sending = false;

  /// Draft cleared for the active send. Restored only when the user has not
  /// entered a newer draft while the request was in flight.
  String? _pendingDraft;

  /// In-panel toggle: when on, fetch web hits before each reply.
  bool _webSearchOn = false;
  late bool _deepThinkingOn;
  bool _searchingWeb = false;

  /// Last completed search hit count (null = no search this turn yet).
  int? _lastWebHitCount;

  /// Human-readable tool activity ("正在检索「张居正」…"); null = none.
  String? _toolStatus;
  String? _error;
  String? _retryText;
  bool _clearingHistory = false;
  bool _generatingFollowUp = false;
  CancelToken _cancel = CancelToken();
  CancelToken? _suggestionCancel;
  StreamSubscription<AiRunEvent>? _sub;
  AiRunState? _runState;
  String _streaming = '';
  String _streamingReasoning = '';
  AiReasoningContentKind _streamingReasoningKind =
      AiReasoningContentKind.process;

  /// Work key of the in-flight turn, captured at send time so a mid-stream
  /// page flip doesn't reroute a stop/partial commit into the new work.
  String? _activeTurnWorkKey;
  String? _activeTurnId;
  String? _retryTurnId;
  int _turnSerial = 0;
  String? _mindMapTurnId;

  BookReaderController get _c => widget.controller;

  /// Keep the in-memory + stored session bounded: every write re-serializes
  /// the whole JSON, so an unbounded list would grow each write (O(n²)) and
  /// the ai_chat/ file without limit. 100 messages ≈ 50 turns is generous.
  static const int _maxStoredMessages = 100;

  /// Current collection work's key (null for plain books / no work under the
  /// reading position). Collections isolate chat per work — same 读哪本跟哪本
  /// model as graph scopes.
  String? get _chatWorkKey {
    final work = _c.currentReadingWork;
    return work == null ? null : BookReaderController.workKeyFor(work);
  }

  /// Messages of the current conversation: per-work for collections, the
  /// shared whole-book list for plain books.
  List<AiChatMessage> get _messages => _session.messagesFor(_chatWorkKey);

  bool get _ready => _c.canUseAiChat;

  bool get _graphBusy => _graphPreparing || _c.isGeneratingBookGraph;

  bool get _canWebSearch => _c.canUseWebSearch;

  String get _attachedSelection => (_selection ?? '').trim();

  bool get _showThinkingIndicator =>
      _activeTurnVisible &&
      _sending &&
      _streaming.isEmpty &&
      _streamingReasoning.isEmpty &&
      !_searchingWeb &&
      _toolStatus == null;

  bool get _showStatusIndicator =>
      _activeTurnVisible &&
      (_searchingWeb || _toolStatus != null || _showThinkingIndicator);

  bool get _activeTurnVisible =>
      _activeTurnId == null || _activeTurnWorkKey == _chatWorkKey;

  OrbState get _statusOrbState {
    if (_searchingWeb) return OrbState.searching;
    if (_toolStatus != null) return OrbState.working;
    return OrbState.solving;
  }

  String get _statusIndicatorLabel {
    if (_searchingWeb) return '正在联网搜索…';
    if (_toolStatus != null) return _toolStatus!;
    if (_lastWebHitCount != null) {
      return _lastWebHitCount == 0
          ? '联网完成 · 无结果，思考中…'
          : '联网完成 · $_lastWebHitCount 条，思考中…';
    }
    return '思考中…';
  }

  String get _liveStatus {
    if (!_activeTurnVisible) return '';
    if (_searchingWeb) return '正在联网搜索…';
    if (_toolStatus != null) return _toolStatus!;
    if (_showThinkingIndicator) return '思考中…';
    if (_error != null) return '错误：$_error';
    return '';
  }

  bool get _canRetry =>
      _retryText != null && _retryText!.trim().isNotEmpty && !_sending;

  double _panelTitleSize(BuildContext context) => context.aiTitleSize;

  double _panelBodySize(BuildContext context) => context.aiBodySize;

  double _panelDetailSize(BuildContext context) => context.aiDetailSize;

  double _panelTabSize(BuildContext context) => context.aiLabelSize;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _BookAiWorkspaceTab.values.length,
      vsync: this,
    )..addListener(_onTabChanged);
    _c.addListener(_onReaderControllerChanged);
    _deepThinkingOn = _c.defaultDeepThinkingEnabled;
    final sel = widget.initialSelection?.trim() ?? '';
    _selection = sel.isEmpty ? null : sel;
    unawaited(_bootstrap());
  }

  void _onTabChanged() {
    // TabController updates its index at the start of the indicator animation.
    // Waiting for indexIsChanging=false inserts a visible 300ms pause before
    // the workspace changes, which feels like a stalled tab switch.
    if (_activeTab.index == _tabs.index) return;
    setState(() => _activeTab = _BookAiWorkspaceTab.values[_tabs.index]);
    // TabBarView keeps visited pages alive; bump the graph list epoch so the
    // ListView is rebuilt fresh (landing at the top) instead of restoring its
    // previous scroll position.
    if (_activeTab == _BookAiWorkspaceTab.graph) {
      _graphListEpoch++;
      unawaited(_ensureGraphWorks());
    }
  }

  void _onReaderControllerChanged() {
    if (!mounted) return;
    // Apply the narration plan's recommended default view once per graph
    // instance (new generation or re-analysis); afterwards the user's own
    // view choice wins.
    final storedGraph = _c.bookGraph;
    final visibleGraph = _c.visibleBookGraph;
    if (storedGraph != null &&
        !identical(storedGraph, _appliedNarrationGraph)) {
      _appliedNarrationGraph = storedGraph;
      final wanted = _viewModeFor(
        resolveGraphInitialView(
          visibleGraph ?? storedGraph,
          storedGraph.narration?.defaultView,
        ),
      );
      if (wanted != null && _graphViewMode != wanted) {
        _graphViewMode = wanted;
      }
      _graphQueryController.clear();
      _graphQuery = '';
    }
    if (_mindMapTurnId != null) {
      _toolStatus =
          _c.bookMindMapProgress?.label ??
          (_c.isGeneratingBookMindMap ? '正在生成思维导图' : _toolStatus);
    }
    // The graph scope is user-selected and must not follow pagination.
    setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      final loadedSession = await _c.loadChatSession();
      final session = AiChatSessionOps.recoverInterruptedTurns(loadedSession);
      if (!identical(session, loadedSession)) {
        await _c.saveChatSession(session);
      }
      // Resolve the work structure ONCE at panel open (collection or not —
      // plain books resolve to null with no side effect). Doing it here means
      // the graph tab and every 翻页 follow read a ready cache
      // instead of each kicking off their own async resolve and flickering.
      await _c.resolveGraphWorkCandidates();
      if (!mounted) return;
      await _c.loadBookGraph();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loadingSession = false;
      });
      // Open on the latest turn (history starts at top of the list).
      if (_messages.isNotEmpty) {
        _scrollToEnd(animated: false);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_focusComposer());
      });
    } catch (error) {
      // A read/decode failure must not leave the sheet on an eternal
      // spinner: show the error with a retry instead.
      if (!mounted) return;
      setState(() {
        _loadingSession = false;
        _loadError = aiUserErrorMessage(
          error,
          operation: AiUserOperation.history,
        );
      });
    }
  }

  /// Focus the composer. Order matters on macOS: request Flutter focus first
  /// (the engine makes its TextInputPlugin first responder while the field is
  /// active), then ask the WebView to drop native focus. The engine-side
  /// clearFocus only moves first responder away from the WebView itself, so it
  /// can never steal text input back from a focused field.
  Future<void> _focusComposer() async {
    _focus.requestFocus();
    await _c.clearPlatformFocus();
  }

  Future<void> _persist() => _c.saveChatSession(_session);

  void _scheduleStreamingCheckpoint() {
    if (!_sending ||
        _activeTurnId == null ||
        (_streaming.trim().isEmpty && _streamingReasoning.trim().isEmpty)) {
      return;
    }
    if (_streamCheckpointTimer?.isActive ?? false) return;
    final now = DateTime.now();
    final elapsed = _lastStreamCheckpointAt == null
        ? const Duration(days: 1)
        : now.difference(_lastStreamCheckpointAt!);
    const interval = Duration(seconds: 2);
    if (elapsed >= interval) {
      _writeStreamingCheckpoint();
      return;
    }
    _streamCheckpointTimer = Timer(
      interval - elapsed,
      _writeStreamingCheckpoint,
    );
  }

  void _writeStreamingCheckpoint() {
    _streamCheckpointTimer = null;
    final turnId = _activeTurnId;
    final body = _streaming.trim();
    final reasoning = _streamingReasoning.trim();
    if (!_sending || turnId == null || (body.isEmpty && reasoning.isEmpty)) {
      return;
    }
    _lastStreamCheckpointAt = DateTime.now();
    final snapshot = AiChatSessionOps.appendBounded(
      _session,
      AiChatMessage(
        role: AiMessageRole.assistant,
        content: body,
        reasoningContent: reasoning,
        reasoningKind: _streamingReasoningKind,
        createdAt: DateTime.now(),
        turnId: turnId,
        status: AiChatTurnStatus.pending,
      ),
      workKey: _activeTurnWorkKey,
      maxMessages: _maxStoredMessages,
    );
    unawaited(_c.saveChatSession(snapshot));
  }

  void _cancelStreamingCheckpoint() {
    _streamCheckpointTimer?.cancel();
    _streamCheckpointTimer = null;
    _lastStreamCheckpointAt = null;
  }

  /// Append [message], keeping only the newest [_maxStoredMessages] so both the
  /// in-memory list and the JSON file stay bounded.
  ///
  /// [workKey] is the key captured when the turn STARTED (may be null for a
  /// whole-book turn). It is used verbatim — never re-read [_chatWorkKey]
  /// here, or a mid-stream page flip would reroute this message into the new
  /// work's list and split the Q&A across two scopes.
  AiChatSession _withMessage(AiChatMessage message, {String? workKey}) {
    return AiChatSessionOps.appendBounded(
      _session,
      message,
      workKey: workKey,
      maxMessages: _maxStoredMessages,
    );
  }

  String _newTurnId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_turnSerial++}';

  void _setTurnStatus(
    String turnId,
    AiChatTurnStatus status, {
    String? workKey,
  }) {
    _session = AiChatSessionOps.setTurnStatus(
      _session,
      turnId,
      status,
      workKey: workKey,
    );
  }

  Future<void> _onWebSearchChanged(bool value) async {
    if (!value) {
      setState(() => _webSearchOn = false);
      return;
    }
    if (_canWebSearch) {
      setState(() => _webSearchOn = true);
      return;
    }
    // No search key yet — keep switch off and offer settings.
    setState(() => _webSearchOn = false);
    if (!mounted) return;
    showAppSnackBar(context, '请先在设置中填写联网搜索 Key');
    await _openSettings();
    if (!mounted) return;
    if (_canWebSearch) {
      setState(() => _webSearchOn = true);
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (!_ready) return;
    final mindMapScope = resolveAiMindMapRequestScope(text);
    if (mindMapScope != null) {
      if (preset == null && _input.text.trim() == text) _input.clear();
      await _generateMindMapInChat(text, mindMapScope);
      return;
    }

    // Prefer the resolved work. Null deliberately means the whole
    // publication: uncertain structure/front matter must not disable chat.
    final turnWork = _c.currentReadingWork;

    _suggestionCancel?.cancel();
    _suggestionCancel = null;

    final wantWeb = _webSearchOn;
    final wantDeepThinking = _c.supportsDeepThinking ? _deepThinkingOn : null;
    final retrying = preset != null && preset == _retryText;
    if (wantWeb && !_canWebSearch) {
      showAppSnackBar(context, '请先在设置中填写联网搜索 Key');
      await _openSettings();
      if (!mounted || !_canWebSearch) return;
    }

    // Freeze collection scope before any asynchronous context/search/tool
    // work. A page flip during the request must not move this turn.
    final chatContext = await _c.loadAiChatContext(
      selectionOverride: _attachedSelection.isEmpty ? null : _attachedSelection,
      workScope: turnWork,
    );
    if (!mounted) return;

    // Capture the work key ONCE for the whole turn: the user may flip to
    // another work while the answer streams, and both the user message and
    // the assistant reply must land in the work the question was asked in —
    // never re-read _chatWorkKey at commit time.
    final turnWorkKey = turnWork == null
        ? null
        : BookReaderController.workKeyFor(turnWork);
    final retryTurnId = retrying ? _retryTurnId : null;
    final turnId = _newTurnId();
    _activeTurnWorkKey = turnWorkKey;
    _activeTurnId = turnId;

    // Clear a composer send as soon as the request is committed. Preset and
    // retry actions leave any separately typed draft untouched.
    if ((preset == null || retrying) && _input.text.trim() == text) {
      _input.clear();
      _pendingDraft = text;
    }

    // Placeholder user bubble; webHitCount filled after search (if any).
    var userMsg = AiChatMessage(
      role: AiMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
      webHitCount: wantWeb ? 0 : null,
      turnId: turnId,
      status: AiChatTurnStatus.pending,
    );
    final historyBefore = List<AiChatMessage>.from(
      _session.messagesFor(turnWorkKey),
    );
    if (retrying && historyBefore.isNotEmpty) {
      final msgs = List<AiChatMessage>.from(_session.messagesFor(turnWorkKey));
      if (retryTurnId != null) {
        msgs.removeWhere((message) => message.turnId == retryTurnId);
      } else {
        // Legacy sessions have no turn id; retain the old tail-pair fallback.
        if (msgs.isNotEmpty && msgs.last.role == AiMessageRole.assistant) {
          msgs.removeLast();
        }
        if (msgs.isNotEmpty &&
            msgs.last.role == AiMessageRole.user &&
            msgs.last.content.trim() == text) {
          msgs.removeLast();
        }
      }
      historyBefore
        ..clear()
        ..addAll(msgs);
      if (msgs.length != _session.messagesFor(turnWorkKey).length) {
        setState(() => _session = _session.withMessagesFor(turnWorkKey, msgs));
      }
    }
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _cancelStreamingCheckpoint();
    final turnCancel = CancelToken();
    _cancel = turnCancel;
    setState(() {
      _session = _withMessage(userMsg, workKey: turnWorkKey);
      _sending = true;
      _generatingFollowUp = false;
      _searchingWeb = wantWeb;
      _lastWebHitCount = null;
      _error = null;
      _retryText = null;
      _retryTurnId = null;
      _streaming = '';
      _streamingReasoning = '';
      _streamingReasoningKind = AiReasoningContentKind.process;
      _toolStatus = null;
      _runState = null;
    });
    unawaited(_persist());
    _scrollToEnd();

    // null = 联网 off; non-null (even []) = search ran this turn.
    List<AiWebSearchHit>? webHits;
    if (wantWeb) {
      try {
        webHits = await _c.searchWebForChat(
          text,
          workScope: turnWork,
          cancelToken: turnCancel,
        );
      } on AiProviderException catch (error) {
        if (turnCancel.isCancelled) return;
        if (!mounted) return;
        setState(() {
          _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: turnWorkKey);
          _sending = false;
          _searchingWeb = false;
          _lastWebHitCount = null;
          _retryText = text;
          _retryTurnId = turnId;
          _error = aiUserErrorMessage(error, operation: AiUserOperation.search);
          _activeTurnId = null;
          _activeTurnWorkKey = null;
        });
        _restorePendingDraft();
        unawaited(_persist());
        return;
      } catch (_) {
        if (turnCancel.isCancelled) return;
        if (!mounted) return;
        setState(() {
          _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: turnWorkKey);
          _sending = false;
          _searchingWeb = false;
          _lastWebHitCount = null;
          _retryText = text;
          _retryTurnId = turnId;
          _error = '联网搜索失败，请稍后重试';
          _activeTurnId = null;
          _activeTurnWorkKey = null;
        });
        _restorePendingDraft();
        unawaited(_persist());
        return;
      }
      turnCancel.throwIfCancelled();
      if (!mounted) return;
      final hitCount = webHits.length;
      userMsg = userMsg.copyWith(webHitCount: hitCount);
      setState(() {
        _searchingWeb = false;
        _lastWebHitCount = hitCount;
        // Refresh last user bubble with real hit count.
        final msgs = List<AiChatMessage>.from(
          _session.messagesFor(turnWorkKey),
        );
        if (msgs.isNotEmpty && msgs.last.role == AiMessageRole.user) {
          msgs[msgs.length - 1] = userMsg;
          _session = _session.withMessagesFor(turnWorkKey, msgs);
        }
      });
      unawaited(_persist());
    } else {
      _lastWebHitCount = null;
    }

    final stream = _c.streamBookChat(
      userText: text,
      history: historyBefore,
      context: chatContext,
      workScope: turnWork,
      webHits: webHits,
      reasoningEnabled: wantDeepThinking,
      cancelToken: turnCancel,
      runId: turnId,
    );
    if (stream == null) {
      setState(() {
        _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: turnWorkKey);
        _sending = false;
        _searchingWeb = false;
        _toolStatus = null;
        _error = 'AI 未启用或未配置';
        _retryText = text;
        _retryTurnId = turnId;
        _activeTurnId = null;
        _activeTurnWorkKey = null;
        _runState = null;
      });
      _restorePendingDraft();
      unawaited(_persist());
      return;
    }

    var endedWithFailure = false;
    void handleFailure(Object error) {
      if (!mounted || endedWithFailure) return;
      endedWithFailure = true;
      _cancelStreamingCheckpoint();
      setState(() {
        _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: turnWorkKey);
        _sending = false;
        _searchingWeb = false;
        _toolStatus = null;
        _error = aiUserErrorMessage(error, operation: AiUserOperation.chat);
        _retryText = text;
        _retryTurnId = turnId;
        if (_streaming.trim().isNotEmpty ||
            _streamingReasoning.trim().isNotEmpty) {
          _commitAssistant(
            _streaming,
            reasoningContent: _streamingReasoning,
            reasoningKind: _streamingReasoningKind,
            workKey: turnWorkKey,
            turnId: turnId,
            status: AiChatTurnStatus.failed,
          );
        }
        _streaming = '';
        _streamingReasoning = '';
        _streamingReasoningKind = AiReasoningContentKind.process;
        _activeTurnId = null;
        _activeTurnWorkKey = null;
        _runState = null;
      });
      _restorePendingDraft();
      unawaited(_persist());
    }

    _sub = stream.listen(
      (event) {
        if (!mounted) return;
        final current = switch (event) {
          AiRunStarted(:final descriptor) => AiRunState.initial(descriptor),
          _ => _runState,
        };
        if (current == null) return;
        final next = current.apply(event);
        setState(() {
          _runState = next;
          _streaming = next.text;
          _streamingReasoning = next.reasoningText;
          _streamingReasoningKind = next.reasoningKind;
          _toolStatus = next.status;
        });
        if (event is AiRunTextSnapshot || event is AiRunReasoningSnapshot) {
          _scheduleStreamingCheckpoint();
          _scrollToEnd();
        } else if (event case AiRunFailed(:final error)) {
          handleFailure(error);
        } else if (event is AiRunCancelled) {
          handleFailure(AiProviderException('已取消'));
        }
      },
      onError: handleFailure,
      onDone: () {
        if (!mounted || endedWithFailure) return;
        _cancelStreamingCheckpoint();
        final body = _streaming.trim();
        final reasoning = _streamingReasoning.trim();
        int? assistantIndex;
        setState(() {
          _sending = false;
          _searchingWeb = false;
          _toolStatus = null;
          if (body.isNotEmpty) {
            _setTurnStatus(
              turnId,
              AiChatTurnStatus.completed,
              workKey: turnWorkKey,
            );
            _commitAssistant(
              body,
              reasoningContent: reasoning,
              reasoningKind: _streamingReasoningKind,
              workKey: turnWorkKey,
              turnId: turnId,
            );
            assistantIndex = _session.messagesFor(turnWorkKey).length - 1;
          } else {
            _setTurnStatus(
              turnId,
              AiChatTurnStatus.failed,
              workKey: turnWorkKey,
            );
            _error = '没有生成内容，请重试';
            _retryText = text;
            _retryTurnId = turnId;
          }
          if (body.isNotEmpty) {
            _retryText = null;
            _retryTurnId = null;
          }
          _streaming = '';
          _streamingReasoning = '';
          _streamingReasoningKind = AiReasoningContentKind.process;
          _activeTurnId = null;
          _activeTurnWorkKey = null;
          _runState = null;
        });
        _pendingDraft = null;
        unawaited(_persist());
        if (assistantIndex != null) {
          setState(() => _generatingFollowUp = true);
          unawaited(
            _generateFollowUpQuestion(
              messageIndex: assistantIndex!,
              userText: text,
              answer: body,
              context: chatContext,
              workKey: turnWorkKey,
            ),
          );
        }
      },
      cancelOnError: true,
    );
  }

  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }

    // IMEs use Enter to commit the currently composed candidate. Let the
    // platform text input handle that before considering the chat shortcut.
    final composing = _input.value.composing;
    if ((composing.isValid && !composing.isCollapsed) ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }

    if (!_sending) unawaited(_send());
    return KeyEventResult.handled;
  }

  void _commitAssistant(
    String body, {
    String reasoningContent = '',
    AiReasoningContentKind reasoningKind = AiReasoningContentKind.process,
    String? workKey,
    required String turnId,
    AiChatTurnStatus status = AiChatTurnStatus.completed,
    AiBookMindMap? mindMap,
  }) {
    _session = _withMessage(
      AiChatMessage(
        role: AiMessageRole.assistant,
        content: body,
        reasoningContent: reasoningContent,
        reasoningKind: reasoningKind,
        createdAt: DateTime.now(),
        turnId: turnId,
        status: status,
        mindMap: mindMap,
      ),
      workKey: workKey,
    );
  }

  Future<void> _generateFollowUpQuestion({
    required int messageIndex,
    required String userText,
    required String answer,
    required AiChatContextBundle context,
    String? workKey,
  }) async {
    final token = CancelToken();
    _suggestionCancel = token;
    var published = false;
    try {
      final suggestions = await _c.suggestBookChatFollowUps(
        userText: userText,
        answer: answer,
        context: context,
        cancelToken: token,
      );
      if (!mounted ||
          token.isCancelled ||
          !identical(_suggestionCancel, token)) {
        return;
      }
      final msgs = _session.messagesFor(workKey);
      if (suggestions.isEmpty ||
          messageIndex >= msgs.length ||
          msgs[messageIndex].role != AiMessageRole.assistant ||
          msgs[messageIndex].content != answer) {
        return;
      }
      final messages = List<AiChatMessage>.from(msgs);
      messages[messageIndex] = messages[messageIndex].copyWith(
        suggestedQuestions: suggestions,
      );
      setState(() {
        _session = _session.withMessagesFor(workKey, messages);
        _generatingFollowUp = false;
      });
      published = true;
      unawaited(_persist());
      _scrollToEnd();
    } finally {
      if (identical(_suggestionCancel, token)) {
        _suggestionCancel = null;
        if (!published && mounted) {
          setState(() => _generatingFollowUp = false);
          // Empty/failed model suggestions reveal the stable fallback list.
          // Keep that newly inserted UI in view just like generated follow-ups.
          _scrollToEnd();
        }
      }
    }
  }

  void _restorePendingDraft() {
    final draft = _pendingDraft;
    if (draft == null) return;
    if (_input.text.trim().isEmpty) {
      _input.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    _pendingDraft = null;
  }

  Future<void> _stop({bool commitPartial = true, bool persist = true}) async {
    final turnId = _activeTurnId;
    final turnWorkKey = _activeTurnWorkKey;
    if (_mindMapTurnId == turnId) {
      _c.cancelBookMindMapGeneration();
      _mindMapTurnId = null;
    }
    _cancel.cancel();
    _cancelStreamingCheckpoint();
    final sub = _sub;
    _sub = null;
    final cancellation = sub?.cancel();
    if (!mounted) return;
    final body = _streaming.trim();
    final reasoning = _streamingReasoning.trim();
    setState(() {
      _sending = false;
      _searchingWeb = false;
      _toolStatus = null;
      _runState = null;
      if (turnId != null) {
        _setTurnStatus(
          turnId,
          AiChatTurnStatus.cancelled,
          workKey: turnWorkKey,
        );
      }
      if (commitPartial &&
          (body.isNotEmpty || reasoning.isNotEmpty) &&
          turnId != null) {
        _commitAssistant(
          body,
          reasoningContent: reasoning,
          reasoningKind: _streamingReasoningKind,
          workKey: turnWorkKey,
          turnId: turnId,
          status: AiChatTurnStatus.cancelled,
        );
      }
      _streaming = '';
      _streamingReasoning = '';
      _streamingReasoningKind = AiReasoningContentKind.process;
      _cancel = CancelToken();
      _activeTurnId = null;
      _activeTurnWorkKey = null;
    });
    _restorePendingDraft();
    if (persist) unawaited(_persist());
    try {
      await cancellation;
    } catch (_) {
      // The visible run is already stopped. Transport cleanup errors must not
      // resurrect the turn or require a second tap.
    }
  }

  Future<void> _closePanel() async {
    if (_sending) unawaited(_stop());
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  void _finalizeActiveTurnForDisposal() {
    _cancelStreamingCheckpoint();
    final turnId = _activeTurnId;
    if (turnId == null) return;
    if (_mindMapTurnId == turnId) {
      _c.cancelBookMindMapGeneration();
      _mindMapTurnId = null;
    }
    final workKey = _activeTurnWorkKey;
    _setTurnStatus(turnId, AiChatTurnStatus.cancelled, workKey: workKey);
    final body = _streaming.trim();
    final reasoning = _streamingReasoning.trim();
    if (body.isNotEmpty || reasoning.isNotEmpty) {
      _commitAssistant(
        body,
        reasoningContent: reasoning,
        reasoningKind: _streamingReasoningKind,
        workKey: workKey,
        turnId: turnId,
        status: AiChatTurnStatus.cancelled,
      );
    }
    _activeTurnId = null;
    _activeTurnWorkKey = null;
    unawaited(_c.saveChatSession(_session));
  }

  Future<void> _clearHistory() async {
    if (_clearingHistory) return;
    final clearWork = _c.currentReadingWork;
    final workKey = clearWork == null
        ? null
        : BookReaderController.workKeyFor(clearWork);
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清空对话？',
      message: clearWork == null
          ? '将删除这本书保存的全部对话。清空后无法恢复。'
          : '将删除《${clearWork.title}》保存的全部对话，不影响合集中的其他作品。清空后无法恢复。',
      confirmLabel: '清空对话',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    _clearingHistory = true;
    try {
      _suggestionCancel?.cancel();
      _suggestionCancel = null;
      // Cancel first without committing an in-flight partial answer.
      await _stop(commitPartial: false, persist: false);
      _input.clear();
      _pendingDraft = null;
      await _c.clearChatSession(workKey: workKey);
      if (!mounted) return;
      setState(() {
        // 合集：只清当前作品的消息，保留其他作品的对话/大纲；单本整体会话清空。
        _session = workKey == null
            ? AiChatSession(
                contentHash: _c.item.contentHash,
                itemId: _c.item.id,
              )
            : _session.withMessagesFor(workKey, const []);
        _error = null;
        _retryText = null;
        _streaming = '';
        _streamingReasoning = '';
        _streamingReasoningKind = AiReasoningContentKind.process;
        _toolStatus = null;
        _generatingFollowUp = false;
      });
    } finally {
      _clearingHistory = false;
    }
  }

  /// Scroll message list to the bottom.
  ///
  /// [animated] is for new tokens / send. Opening the sheet uses a jump so
  /// the user does not briefly see the first message then animate down.
  /// Retries a few frames: ListView may not have clients yet right after
  /// bootstrap, and markdown bubbles can grow after the first layout.
  void _scrollToEnd({bool animated = true}) {
    void attempt(int remaining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scroll.hasClients) {
          if (remaining > 0) attempt(remaining - 1);
          return;
        }
        final max = _scroll.position.maxScrollExtent;
        if (animated && remaining == 8) {
          _scroll.animateTo(
            max,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        } else {
          _scroll.jumpTo(max);
        }
        // Content may still grow (markdown) — pin again if not at end.
        if (remaining > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final next = _scroll.position.maxScrollExtent;
            if (_scroll.offset < next - 1) {
              _scroll.jumpTo(next);
              attempt(remaining - 1);
            }
          });
        }
      });
    }

    attempt(8);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnackBar(context, '已复制');
  }

  void _updateMindMapLayout(AiChatMessage message, AiMindMapLayout layout) {
    final map = message.mindMap;
    if (map == null || map.layout == layout) return;
    final workKey = _chatWorkKey;
    final messages = List<AiChatMessage>.from(_session.messagesFor(workKey));
    final index = messages.indexWhere(
      (candidate) =>
          identical(candidate, message) ||
          (message.turnId != null && candidate.turnId == message.turnId),
    );
    if (index < 0) return;
    messages[index] = messages[index].copyWith(
      mindMap: map.copyWith(layout: layout),
    );
    setState(() {
      _session = _session.withMessagesFor(workKey, messages);
    });
    unawaited(_persist());
  }

  void _openMindMapFullscreen(AiChatMessage message) {
    final map = message.mindMap;
    if (map == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiMindMapFullscreen(
          title: map.root.title.isEmpty ? '思维导图' : map.root.title,
          map: map,
          onLayoutChanged: (layout) => _updateMindMapLayout(message, layout),
          onOpenEvidence: _goToMindMapEvidence,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final ai = _c.aiSettingsController;
    if (ai == null) {
      showAppSnackBar(context, '无法打开 AI 设置');
      return;
    }
    await AiSettingsScreen.open(context, controller: ai);
    // Re-read secure storage in case dispose race left memory empty.
    if (!ai.isSearchReady) {
      await ai.load();
    }
    if (mounted) setState(() {});
  }

  Future<void> _generateOutline({bool force = false}) async {
    if (!_ready || _c.isGeneratingBookOutline) return;
    if (force && _c.bookOutline != null) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: '重新生成大纲？',
        message: '将重新请求 AI，并替换当前保存的大纲。',
        confirmLabel: '重新生成',
      );
      if (confirmed != true || !mounted) return;
    }
    Set<int>? excludedSections;
    if (_c.hasAmbiguousInternalWorks) {
      final existing = _c.bookOutline;
      final confirmed = await _showNarrationChooser(
        initialExcluded: existing?.excludedSectionIndices.toSet() ?? const {},
        useRecommendedSelection: existing == null,
        scopeOnly: true,
        dialogTitle: '选择大纲范围',
        confirmLabel: '生成大纲',
      );
      if (confirmed == null || !mounted) return;
      excludedSections = confirmed.excludedSections;
    }
    await _c.generateBookOutline(excludedSectionIndices: excludedSections);
  }

  Future<void> _deleteOutline() async {
    if (_c.bookOutline == null || _c.isGeneratingBookOutline) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除大纲？',
      message: '只删除这本书保存的 AI 大纲，不影响对话记录。',
      confirmLabel: '删除大纲',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _c.deleteBookOutline();
  }

  Future<void> _handleOpeningShortcut(AiChatShortcut shortcut) async {
    await _send(shortcut.prompt);
  }

  Future<void> _generateMindMapInChat(
    String text,
    AiMindMapRequestScope scope,
  ) async {
    final work = _c.currentReadingWork;
    final workKey = work == null ? null : BookReaderController.workKeyFor(work);
    final turnId = _newTurnId();
    _activeTurnId = turnId;
    _activeTurnWorkKey = workKey;
    _mindMapTurnId = turnId;
    _cancel = CancelToken();
    setState(() {
      _session = _withMessage(
        AiChatMessage(
          role: AiMessageRole.user,
          content: text,
          createdAt: DateTime.now(),
          turnId: turnId,
          status: AiChatTurnStatus.pending,
        ),
        workKey: workKey,
      );
      _sending = true;
      _error = null;
      _retryText = null;
      _retryTurnId = null;
      _toolStatus = scope == AiMindMapRequestScope.currentChapter
          ? '正在读取当前章'
          : '正在读取全书范围';
    });
    unawaited(_persist());
    _scrollToEnd();

    AiBookMindMap? result;
    String? localError;
    try {
      final frozenChapter = scope == AiMindMapRequestScope.currentChapter
          ? await _c.captureCurrentBookMindMapChapter()
          : null;
      if (!mounted || _activeTurnId != turnId || _mindMapTurnId != turnId) {
        return;
      }
      if (scope == AiMindMapRequestScope.currentChapter &&
          frozenChapter == null) {
        localError = '当前章节正文尚未就绪，请稍后重试';
      } else {
        result = await _c.generateBookMindMap(
          work: work,
          useFrozenWork: true,
          frozenCurrentChapter: frozenChapter,
        );
      }
    } catch (_) {
      result = null;
      if (scope == AiMindMapRequestScope.currentChapter) {
        localError = '读取当前章节失败，请稍后重试';
      }
    }
    if (!mounted || _activeTurnId != turnId || _mindMapTurnId != turnId) {
      return;
    }
    final failed = result == null;
    final cancelled = localError == null && _c.bookMindMapError == '已停止';
    setState(() {
      _setTurnStatus(
        turnId,
        cancelled
            ? AiChatTurnStatus.cancelled
            : failed
            ? AiChatTurnStatus.failed
            : AiChatTurnStatus.completed,
        workKey: workKey,
      );
      if (result != null) {
        _commitAssistant(
          scope == AiMindMapRequestScope.currentChapter
              ? '已根据当前章生成思维导图。'
              : '已根据这本书生成思维导图。',
          workKey: workKey,
          turnId: turnId,
          mindMap: result,
        );
      } else if (!cancelled) {
        _error = localError ?? _c.bookMindMapError ?? '暂时无法生成思维导图，请稍后重试';
        _retryText = text;
        _retryTurnId = turnId;
      }
      _sending = false;
      _toolStatus = null;
      _activeTurnId = null;
      _activeTurnWorkKey = null;
      _mindMapTurnId = null;
    });
    unawaited(_persist());
    _scrollToEnd();
  }

  void _goToMindMapEvidence(AiMindMapEvidence evidence) {
    final index = evidence.sectionIndex - 1;
    if (index < 0 || index >= _c.sectionCount) return;
    _c.goToSection(index, progressInSection: evidence.progressInSection);
    // The node detail has just started closing. Wait for it to leave before
    // closing the AI workspace, otherwise the immediate pop can hit the same
    // modal twice and leave the workspace covering the target passage.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });
  }

  // Legacy renderer kept during the structured-outline cache compatibility
  // window. It has no navigation entry; new outlines use normal chat.
  // ignore: unused_element
  Widget _buildOutlineTab(BuildContext context) {
    final colors = context.appColors;
    final outline = _c.bookOutline;
    final progress = _c.bookOutlineProgress;
    final generating = _c.isGeneratingBookOutline;
    final error = _c.bookOutlineError;
    if (!_ready) {
      return _AiUnavailable(
        message: '添加 API Key 后，就可以生成本书大纲。',
        onOpenSettings: () => unawaited(_openSettings()),
        icon: KaijuanIcons.toc,
      );
    }
    if (outline == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(KaijuanIcons.toc, size: 34, color: context.appSecondaryText),
              const SizedBox(height: 14),
              // While generating, the title is redundant next to the live
              // progress label below; keep it only for the idle state.
              if (!generating)
                Text(
                  _c.hasAmbiguousInternalWorks
                      ? '选择范围生成大纲'
                      : _c.currentReadingWork != null
                      ? '《${_c.currentReadingWork!.title}》大纲'
                      : '本书大纲',
                  style: TextStyle(
                    fontSize: _panelTitleSize(context),
                    fontWeight: FontWeight.w600,
                    color: context.appPrimaryText,
                  ),
                ),
              if (!generating) ...[
                const SizedBox(height: 6),
                Text(
                  _c.hasAmbiguousInternalWorks
                      ? '目录结构无法可靠区分章节和多部作品。生成前请确认参与分析的内容。'
                      : '生成一次后会保存在这本书中。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _panelBodySize(context),
                    height: 1.45,
                    color: context.appSecondaryText,
                  ),
                ),
              ],
              if (generating) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _thinkingOrb(context),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        progress?.label ?? '正在生成…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: _panelBodySize(context),
                          height: 1.45,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _c.cancelBookOutlineGeneration,
                  icon: const Icon(KaijuanIcons.stop, size: 18),
                  label: const Text('停止'),
                ),
              ] else ...[
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => unawaited(_generateOutline()),
                  icon: const Icon(KaijuanIcons.aiChat, size: 18),
                  label: Text(
                    _c.hasAmbiguousInternalWorks ? '选择范围并生成' : '生成大纲',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _c.currentReadingWork != null
                    ? '《${_c.currentReadingWork!.title}》'
                    : '本书',
                style: TextStyle(
                  fontSize: _panelTitleSize(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: '重新生成大纲',
              onPressed: generating
                  ? null
                  : () => unawaited(_generateOutline(force: true)),
              icon: const Icon(KaijuanIcons.refresh, size: 20),
            ),
            PopupMenuButton<_OutlineAction>(
              tooltip: '更多大纲操作',
              enabled: !generating,
              onSelected: (action) {
                if (action == _OutlineAction.delete) {
                  unawaited(_deleteOutline());
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _OutlineAction.delete,
                  child: Text('删除大纲'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 综述（一段话讲清全书脉络）
        Text(
          outline.overview,
          style: TextStyle(
            fontSize: _panelBodySize(context),
            height: 1.6,
            color: context.appPrimaryText,
          ),
        ),
        if (generating) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              _thinkingOrb(context),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  progress?.label ?? '正在生成…',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: context.appSecondaryText,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _c.cancelBookOutlineGeneration,
                icon: const Icon(KaijuanIcons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: colors.error,
            ),
          ),
        ],
        SizedBox(height: context.appIsCompact ? 20 : 28),
        // 大纲（结构单元，按书中顺序）
        Text(
          '大纲',
          style: TextStyle(
            fontSize: _panelTitleSize(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < outline.units.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 序号
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      fontWeight: FontWeight.w600,
                      color: context.appSecondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        outline.units[i].title,
                        style: TextStyle(
                          fontSize: _panelBodySize(context),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: context.appPrimaryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        outline.units[i].blurb,
                        style: TextStyle(
                          fontSize: _panelDetailSize(context),
                          height: 1.55,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Which entity types the current list view shows; empty on the graph
  /// view (no list rendered there). The persons view also folds in
  /// `organization` has its own index; it must not inflate the person list.
  Set<AiGraphEntityType> get _graphListEntityTypes => switch (_graphViewMode) {
    _GraphViewMode.persons => {AiGraphEntityType.person},
    _GraphViewMode.locations => {AiGraphEntityType.location},
    _GraphViewMode.events => {AiGraphEntityType.event},
    _GraphViewMode.organizations => {AiGraphEntityType.organization},
    _GraphViewMode.things => {
      AiGraphEntityType.item,
      AiGraphEntityType.concept,
      AiGraphEntityType.creature,
    },
    _GraphViewMode.graph => const {},
    _GraphViewMode.familyTree => const {},
  };

  GraphEntityListKind get _graphListKind => switch (_graphViewMode) {
    _GraphViewMode.persons => GraphEntityListKind.persons,
    _GraphViewMode.locations => GraphEntityListKind.locations,
    _GraphViewMode.events => GraphEntityListKind.events,
    _GraphViewMode.organizations => GraphEntityListKind.organizations,
    _GraphViewMode.things => GraphEntityListKind.things,
    // Sorting controls are not rendered for exploration views. This fallback
    // only keeps the shared build path total while those views are active.
    _GraphViewMode.graph ||
    _GraphViewMode.familyTree => GraphEntityListKind.persons,
  };

  /// Stable information architecture. AI may choose the initial view, but it
  /// never rearranges navigation between books.
  List<_GraphViewMode> _orderedGraphViewModes(AiNarrationPlan? plan) {
    final essayHigh = (plan?.feature('essay') ?? 0) >= 0.5;
    return [
      _GraphViewMode.persons,
      _GraphViewMode.locations,
      _GraphViewMode.events,
      _GraphViewMode.organizations,
      _GraphViewMode.things,
      _GraphViewMode.graph,
      if (!essayHigh) _GraphViewMode.familyTree,
    ];
  }

  _GraphViewMode? _viewModeFor(String view) => switch (view) {
    'persons' => _GraphViewMode.persons,
    'locations' => _GraphViewMode.locations,
    'events' => _GraphViewMode.events,
    'organizations' || 'org_tree' => _GraphViewMode.organizations,
    'things' => _GraphViewMode.things,
    'graph' => _GraphViewMode.graph,
    'family_tree' => _GraphViewMode.familyTree,
    _ => null,
  };

  static const _graphViewLabels = <_GraphViewMode, String>{
    _GraphViewMode.persons: '人物',
    _GraphViewMode.locations: '地点',
    _GraphViewMode.events: '事件',
    _GraphViewMode.organizations: '组织',
    _GraphViewMode.things: '事物',
    _GraphViewMode.graph: '关系图',
    _GraphViewMode.familyTree: '家族树',
  };

  Widget _buildGraphViewNavigation(
    BuildContext context,
    AiBookGraph graph,
    AiNarrationPlan? plan,
  ) {
    final modes = _orderedGraphViewModes(plan);
    final primary = modes
        .where(
          (mode) =>
              mode != _GraphViewMode.graph && mode != _GraphViewMode.familyTree,
        )
        .toList(growable: false);
    final explore = modes
        .where(
          (mode) =>
              mode == _GraphViewMode.graph || mode == _GraphViewMode.familyTree,
        )
        .toList(growable: false);

    Widget selector(List<_GraphViewMode> choices) {
      int? countFor(_GraphViewMode mode) => switch (mode) {
        _GraphViewMode.persons =>
          graph.entities
              .where((entity) => entity.type == AiGraphEntityType.person)
              .length,
        _GraphViewMode.locations =>
          graph.entities
              .where((entity) => entity.type == AiGraphEntityType.location)
              .length,
        _GraphViewMode.events =>
          graph.entities
              .where((entity) => entity.type == AiGraphEntityType.event)
              .length,
        _GraphViewMode.organizations =>
          graph.entities
              .where((entity) => entity.type == AiGraphEntityType.organization)
              .length,
        _GraphViewMode.things =>
          graph.entities
              .where(
                (entity) =>
                    entity.type == AiGraphEntityType.item ||
                    entity.type == AiGraphEntityType.concept ||
                    entity.type == AiGraphEntityType.creature,
              )
              .length,
        _GraphViewMode.graph => graph.relations.length,
        // A family tree is one derived view, not a countable entity kind.
        _GraphViewMode.familyTree => null,
      };

      Widget labelFor(_GraphViewMode mode) {
        final count = countFor(mode);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: _graphViewLabels[mode]!),
              if (count != null)
                TextSpan(
                  text: ' $count',
                  style: TextStyle(
                    fontSize: context.appCaptionSmallSize,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          softWrap: false,
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_GraphViewMode>(
          segments: [
            for (final mode in choices)
              ButtonSegment(value: mode, label: labelFor(mode)),
          ],
          selected: choices.contains(_graphViewMode)
              ? {_graphViewMode}
              : const <_GraphViewMode>{},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              setState(() => _graphViewMode = selection.first);
            }
          },
          showSelectedIcon: false,
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: context.appCaptionSize),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '索引',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
        const SizedBox(height: 4),
        selector(primary),
        if (explore.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '探索',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
            ),
          ),
          const SizedBox(height: 4),
          selector(explore),
        ],
      ],
    );
  }

  Widget _buildGraphTab(BuildContext context) {
    if (_c.hasCollectionWorks && !_c.hasActiveWorkGraph) {
      return _buildGraphWorkList(context);
    }
    return _buildGraphContent(context);
  }

  Widget _buildGraphWorkList(BuildContext context) {
    if (!_ready) {
      return _AiUnavailable(
        message: '添加 API Key 后，就可以生成本书的人物、地点与事件图谱。',
        onOpenSettings: () => unawaited(_openSettings()),
        icon: KaijuanIcons.graph,
      );
    }
    final works = _c.resolvedGraphWorks ?? const <AiGraphWorkCandidate>[];
    final reading = _c.currentReadingWork;
    final generatingWork = _c.generatingGraphWork;
    final progress = _c.bookGraphProgress;
    final error = _c.bookGraphError;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemCount: works.length + 1,
      separatorBuilder: (_, index) =>
          index == 0 ? const SizedBox(height: 10) : const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择作品',
                style: TextStyle(
                  fontSize: _panelTitleSize(context),
                  fontWeight: FontWeight.w600,
                  color: context.appPrimaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '这份文件包含 ${works.length} 部作品。选择一部后，再确认参与生成的具体内容。',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
              if (_graphPreparing) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '正在准备图谱…',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ],
                ),
              ] else if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        }
        final work = works[index - 1];
        final ready = _c.hasWorkGraph(work);
        final isGenerating = identical(generatingWork, work);
        final isPreparing = _graphPreparing && _graphPreparingWorkId == work.id;
        final isReading = identical(reading, work);
        final status = isPreparing
            ? '正在准备…'
            : isGenerating
            ? (progress?.label ?? '正在生成…')
            : ready
            ? '已生成'
            : '未生成';
        return ListTile(
          key: ValueKey('graph-work-${work.id}'),
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(isReading ? '$status · 正在阅读' : status),
          trailing: isPreparing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : isGenerating
              ? TextButton.icon(
                  onPressed: _c.cancelBookGraphGeneration,
                  icon: const Icon(KaijuanIcons.stop, size: 16),
                  label: const Text('停止'),
                )
              : Icon(
                  ready ? Icons.chevron_right : KaijuanIcons.graph,
                  size: 20,
                  color: context.appSecondaryText,
                ),
          onTap: _graphBusy
              ? null
              : () {
                  if (ready) {
                    _c.openWorkGraph(work);
                  } else {
                    unawaited(_generateGraph(work: work));
                  }
                },
        );
      },
    );
  }

  Widget _buildGraphContent(BuildContext context) {
    final colors = context.appColors;
    final graph = _c.visibleBookGraph;
    final hadEmptySnapshot = graph == null && _c.bookGraph != null;
    final generating = _c.isGeneratingBookGraph;
    final preparing = _graphPreparing && !generating;
    final busy = preparing || generating;
    final error = _c.bookGraphError;
    if (!_ready) {
      return _AiUnavailable(
        message: '添加 API Key 后，就可以生成本书的人物、地点与事件图谱。',
        onOpenSettings: () => unawaited(_openSettings()),
        icon: KaijuanIcons.graph,
      );
    }
    if (graph == null) {
      // Collection detection is async (outline → work candidates). Until the
      // works are known, there is no valid range to generate — show a
      // loading state instead of the actionable empty-state button, or a
      // tap would start a whole-book dialog against a half-loaded book.
      // Only a recognition IN PROGRESS shows the loading state; once it
      // fails (or this is a plain book that will never have works), fall
      // through to the actionable empty state — otherwise the tab would be
      // stuck on「正在识别著作范围…」forever.
      final works = _c.resolvedGraphWorks;
      if (works == null && _graphWorksLoading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 12),
                Text(
                  '正在识别著作范围…',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: context.appSecondaryText,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                KaijuanIcons.graph,
                size: 34,
                color: context.appSecondaryText,
              ),
              const SizedBox(height: 14),
              if (!busy)
                Text(
                  hadEmptySnapshot ? '尚无有效图谱数据' : '知识图谱',
                  style: TextStyle(
                    fontSize: _panelTitleSize(context),
                    fontWeight: FontWeight.w600,
                    color: context.appPrimaryText,
                  ),
                ),
              if (busy) ...[
                const SizedBox(height: 10),
                Text(
                  '生成完成后，实体、关系与索引会显示在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: context.appSecondaryText,
                  ),
                ),
              ] else ...[
                if (hadEmptySnapshot) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上一次没有得到可展示的实体或关系。再次生成会重新读取正文，不会沿用空的完成记录。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      height: 1.4,
                      color: context.appSecondaryText,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => unawaited(
                    _generateGraph(
                      // Retry the range being retried: after a cancelled /
                      // failed generation the active work is still set, and
                      // the dialog must open scoped to it (not the whole
                      // collection).
                      work: _c.activeGraphWork,
                    ),
                  ),
                  icon: const Icon(KaijuanIcons.graph, size: 18),
                  label: Text(hadEmptySnapshot ? '重新生成图谱' : '生成图谱'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final readThrough = _c.sectionIndex + 1;
    // [visibleBookGraph] has already removed ungrounded evidence. Its saved
    // generation scope is authoritative, so child widgets must not invent a
    // device-local progress projection.
    const gateByProgress = false;
    // Entities with at least one relation form the readable core; zero-edge
    // entities (mere mentions) collapse into one foldable row and are left
    // off the force-directed view where they would float as orphan dots.
    final connectedIds = <String>{
      for (final r in graph.relations) ...[
        if (r.sourceId.isNotEmpty) r.sourceId,
        if (r.targetId.isNotEmpty) r.targetId,
      ],
    };
    // Structural gates below (view-mode switcher, graph/family-tree blocks)
    // must NOT depend on the search query: when a query matches nothing,
    // hiding a block above the search box shifts the ListView's children,
    // recreates the field's element and breaks IME composition (the next
    // keystroke garbles). baseEntities = progress/type gated, no query.
    // The model/store layers enforce unique stable IDs, but keep the render
    // boundary defensive: a legacy or in-memory graph must never mount one
    // GlobalKey twice and take down the whole AI panel.
    final renderedEntityIds = <String>{};
    final baseEntities = graph.entities
        .where((entity) {
          if (!renderedEntityIds.add(entity.id)) return false;
          final listTypes = _graphListEntityTypes;
          if (listTypes.isNotEmpty && !listTypes.contains(entity.type)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final visibleEntities = _graphQuery.trim().isEmpty
        ? baseEntities
        : baseEntities
              .where((entity) {
                final query = _graphQuery.trim();
                final hit =
                    entity.name.contains(query) ||
                    entity.aliases.any((alias) => alias.contains(query));
                return hit;
              })
              .toList(growable: false);
    // Main list = everything the book itself is about (setting), connected
    // or not. Only referenced outsiders (罗素 etc.) fold away — in essay
    // collections relations are sparse, so "connected only" would empty the
    // list.
    final isolatedEntities = <AiGraphEntity>[
      for (final entity in visibleEntities)
        if (entity.scope != AiGraphEntityScope.setting) entity,
    ];
    final mainEntities = <AiGraphEntity>[
      for (final entity in visibleEntities)
        if (entity.scope == AiGraphEntityScope.setting) entity,
    ];
    // Search is allowed to surface mere mentions without the fold.
    final foldIsolated =
        isolatedEntities.isNotEmpty && _graphQuery.trim().isEmpty;
    final relationCounts = graphEntityRelationCounts(
      graph.entities,
      graph.relations,
    );
    // Sort the visible snapshot explicitly. Cached graphs, repaired graphs
    // and newly generated graphs may all arrive in different array orders;
    // presentation order must never depend on that incidental storage order.
    List<AiGraphEntity> ordered(List<AiGraphEntity> source) {
      return sortGraphEntities(
        source,
        order: _graphSortOrder,
        relationCounts: relationCounts,
      );
    }

    final orderedMain = ordered(mainEntities);
    final orderedIsolated = ordered(isolatedEntities);

    return ListView(
      key: ValueKey<int>(_graphListEpoch),
      controller: _graphScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          children: [
            if (_c.activeGraphWork != null)
              IconButton(
                tooltip: '全部作品',
                onPressed: busy ? null : _c.closeActiveWorkGraph,
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
            Expanded(
              child: Text(
                _c.activeGraphWork != null
                    ? '《${_c.activeGraphWork!.title}》图谱'
                    : (graph.includesUnread ? '全书图谱' : '已读章节图谱'),
                style: TextStyle(
                  fontSize: _panelTitleSize(context),
                  fontWeight: FontWeight.w600,
                  color: context.appPrimaryText,
                ),
              ),
            ),
            IconButton(
              tooltip: '重新生成图谱',
              onPressed: busy
                  ? null
                  : () => unawaited(
                      _generateGraph(
                        force: true,
                        // Regenerate the range being viewed: the detail
                        // header is shared by whole-book and per-work graphs,
                        // and a per-work regeneration must reopen the dialog
                        // scoped to that work (not the whole collection).
                        work: _c.activeGraphWork,
                      ),
                    ),
              icon: const Icon(KaijuanIcons.refresh, size: 20),
            ),
            PopupMenuButton<_OutlineAction>(
              tooltip: '更多',
              enabled: !busy,
              onSelected: (action) {
                if (action == _OutlineAction.delete) {
                  unawaited(_deleteGraph());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _OutlineAction.delete,
                  child: Text('删除图谱'),
                ),
              ],
            ),
          ],
        ),
        if (shouldShowGraphViewNavigation(graph: graph, generating: busy)) ...[
          const SizedBox(height: 10),
          _buildGraphViewNavigation(context, graph, graph.narration),
        ],
        if (!busy && error != null) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: colors.error,
            ),
          ),
        ],
        if (!busy && _graphViewMode == _GraphViewMode.graph) ...[
          const SizedBox(height: 12),
          if (graph.relations.isEmpty)
            Text(
              '本书暂无可展示的实体关系。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _panelBodySize(context),
                color: context.appSecondaryText,
              ),
            )
          else ...[
            Semantics(
              label: '关系图说明：连线文字是关系类型，单箭头表示关系方向，双向符号表示对等关系。点击节点查看关系和出处。',
              child: Text(
                '连线文字为关系类型 · 箭头为方向 · 点击节点查看出处',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                BookAiGraphView(
                  entities: graph.entities
                      .where((entity) => connectedIds.contains(entity.id))
                      .toList(growable: false),
                  // Same spoiler gate as the family tree: hide edges whose
                  // evidence is entirely in unread chapters.
                  relations: graph.relations,
                  onVertexTap: _onGraphVertexTap,
                  height: 300,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: context.appColors.surfaceContainerHighest.withValues(
                      alpha: 0.9,
                    ),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: '全屏查看',
                      iconSize: 18,
                      icon: const Icon(KaijuanIcons.maximize),
                      onPressed: _openGraphFullscreen,
                    ),
                  ),
                ),
              ],
            ),
            BookAiGraphEntityNavigator(
              entities: graph.entities
                  .where((entity) => connectedIds.contains(entity.id))
                  .toList(growable: false),
              onEntityTap: _onGraphVertexTap,
            ),
          ],
          const SizedBox(height: 10),
        ],
        if (!busy && _graphViewMode == _GraphViewMode.familyTree) ...[
          const SizedBox(height: 12),
          _buildFamilyTreeView(context, graph, gateByProgress, readThrough),
          const SizedBox(height: 10),
        ],
        if (_graphViewMode != _GraphViewMode.graph &&
            _graphViewMode != _GraphViewMode.familyTree) ...[
          const SizedBox(height: 12),
          Row(
            // Stable key: the filtered results below churn on every
            // keystroke — this row must never be re-matched mid-composition.
            key: const ValueKey<String>('graphEntitySearch'),
            children: [
              Expanded(
                child: TextField(
                  controller: _graphQueryController,
                  onChanged: (value) => setState(() => _graphQuery = value),
                  style: context.appInputTextStyle.copyWith(
                    color: context.appPrimaryText,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索',
                    hintStyle: context.appInputTextStyle.copyWith(
                      color: context.appMutedText,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: context.appColors.surfaceContainerHighest
                        .withValues(alpha: 0.42),
                    constraints: BoxConstraints(
                      minHeight: context.appIsCompact ? 44 : 40,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    prefixIcon: const Icon(KaijuanIcons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<GraphEntitySortOrder>(
                tooltip: '排序',
                initialValue: _graphSortOrder,
                onSelected: (order) =>
                    setState(() => _graphSortOrders[_graphViewMode] = order),
                itemBuilder: (_) => [
                  for (final order in graphSortOrdersFor(_graphListKind))
                    PopupMenuItem(
                      value: order,
                      child: Text(graphSortOrderLabel(order, _graphListKind)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        KaijuanIcons.sort,
                        size: 18,
                        color: context.appSecondaryText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        graphSortOrderLabel(_graphSortOrder, _graphListKind),
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: context.appSecondaryText,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        KaijuanIcons.chevronDown,
                        size: 16,
                        color: context.appMutedText,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_graphViewMode == _GraphViewMode.locations &&
              (graph.narration?.feature('geography') ?? 0) >= 0.5)
            _buildLocationChain(context, graph, gateByProgress, readThrough),
          if (visibleEntities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    _graphQuery.trim().isEmpty
                        ? '本书暂无${_graphViewLabels[_graphViewMode]}实体。'
                        : '没有匹配“${_graphQuery.trim()}”的实体。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _panelBodySize(context),
                      color: context.appSecondaryText,
                    ),
                  ),
                  if (_graphQuery.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () {
                        _graphQueryController.clear();
                        setState(() => _graphQuery = '');
                      },
                      child: const Text('清除搜索'),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            if (_graphViewMode == _GraphViewMode.events)
              _buildGraphEventTimeline(
                context,
                orderedMain,
                gateByProgress,
                readThrough,
              )
            else
              for (final entity in orderedMain)
                KeyedSubtree(
                  key: _graphEntityKeys.putIfAbsent(
                    entity.id,
                    () => GlobalKey(),
                  ),
                  child: _buildGraphEntityTile(
                    context,
                    entity,
                    gateByProgress,
                    readThrough,
                  ),
                ),
            if (foldIsolated)
              _buildIsolatedRow(
                context,
                orderedIsolated,
                gateByProgress,
                readThrough,
              )
            else
              for (final entity in orderedIsolated)
                KeyedSubtree(
                  key: _graphEntityKeys.putIfAbsent(
                    entity.id,
                    () => GlobalKey(),
                  ),
                  child: _buildGraphEntityTile(
                    context,
                    entity,
                    gateByProgress,
                    readThrough,
                  ),
                ),
          ],
        ],
      ],
    );
  }

  /// Events view: chapter-ordered flat list of event cards. Chapter headers
  /// were dropped — section labels from the graph pipeline are too unreliable
  /// to show as headers, and the chapter order is already implied by the
  /// sort (出场顺序).
  Widget _buildGraphEventTimeline(
    BuildContext context,
    List<AiGraphEntity> events,
    bool gateByProgress,
    int readThrough,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in events)
          KeyedSubtree(
            key: _graphEntityKeys.putIfAbsent(event.id, () => GlobalKey()),
            child: _buildGraphEventTile(
              context,
              event,
              gateByProgress,
              readThrough,
            ),
          ),
      ],
    );
  }

  Widget _buildGraphEventTile(
    BuildContext context,
    AiGraphEntity entity,
    bool gateByProgress,
    int readThrough,
  ) {
    return GraphEventTile(
      entity: entity,
      bodySize: _panelBodySize(context),
      trailingLabel: switch (_graphSortOrder) {
        GraphEntitySortOrder.importance => '重要度 ${entity.importance}',
        GraphEntitySortOrder.chapters => '${graphEntityChapterCount(entity)} 章',
        _ => '第 ${entity.firstSection} 节',
      },
      highlighted: _graphHighlighted == entity.id,
      onTap: () => _showEntityDetails(entity),
    );
  }

  /// Family-tree view: the line-connected chart plus the foldable
  /// 「未入树 N 人 · 关系复杂 N 人」rows (each name opens the entity card).
  /// Degrades to a hint when the book has no kin data at all.
  Widget _buildFamilyTreeView(
    BuildContext context,
    AiBookGraph graph,
    bool gateByProgress,
    int readThrough,
  ) {
    final treeEntities = graph.entities
        .where((e) => !gateByProgress || e.firstSection <= readThrough)
        .toList(growable: false);
    // Spoiler gate (mirrors _buildGraphEntityTile's relation count): a 亲属
    // edge whose evidence is entirely in unread chapters reveals a late-plot
    // kinship between two already-introduced characters, so it must not
    // enter the tree (or the isolated/complex counts).
    final treeRelations = graph.relations
        .where(
          (r) =>
              !gateByProgress ||
              r.evidence.any((e) => e.sectionIndex <= readThrough),
        )
        .toList(growable: false);
    final familyTree = buildFamilyTree(
      entities: treeEntities,
      relations: treeRelations,
    );
    if (familyTree.roots.isEmpty && familyTree.isolatedCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '本书暂无血缘关系数据',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
      );
    }
    final detailEntities = <({String id, String name})>[
      for (var i = 0; i < familyTree.complexEntityIds.length; i++)
        (id: familyTree.complexEntityIds[i], name: familyTree.complexNames[i]),
      for (var i = 0; i < familyTree.isolatedEntityIds.length; i++)
        (
          id: familyTree.isolatedEntityIds[i],
          name: familyTree.isolatedNames[i],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '家族树图例：从上到下表示长辈到晚辈，虚线表示额外母系关系，标记为复杂表示关系存在冲突或成环。',
          child: Text(
            '上→下：长辈到晚辈 · 虚线：额外母系 · 复杂：关系冲突',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            BookAiGraphFamilyTreeView(
              tree: familyTree,
              onVertexTap: _onGraphVertexTap,
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: Material(
                color: context.appColors.surfaceContainerHighest.withValues(
                  alpha: 0.9,
                ),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: '全屏查看',
                  iconSize: 18,
                  icon: const Icon(KaijuanIcons.maximize),
                  onPressed: () => _openFamilyTreeFullscreen(
                    familyTree,
                    graph,
                    gateByProgress,
                    readThrough,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (familyTree.isolatedCount > 0 ||
            familyTree.complexNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(
              () => _familyTreeDetailExpanded = !_familyTreeDetailExpanded,
            ),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Icon(
                  _familyTreeDetailExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: context.appSecondaryText,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '未入树 ${familyTree.isolatedCount} 人'
                    ' · 关系复杂 ${familyTree.complexNames.length} 人',
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: context.appSecondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_familyTreeDetailExpanded) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entity in detailEntities)
                  ActionChip(
                    label: Text(entity.name),
                    visualDensity: VisualDensity.compact,
                    // Tree mode renders no entity list rows, so the
                    // scroll-and-highlight path in _onGraphVertexTap has
                    // nothing to scroll to — go straight to the detail card
                    // (same as tapping a tree node).
                    onPressed: () => _onGraphVertexTap(entity.id),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildLocationChain(
    BuildContext context,
    AiBookGraph graph,
    bool gateByProgress,
    int readThrough,
  ) {
    return GraphLocationChain(
      locations: graph.entities
          .where(
            (e) =>
                e.type == AiGraphEntityType.location &&
                e.scope == AiGraphEntityScope.setting,
          )
          .toList(growable: false),
      gateByProgress: gateByProgress,
      readThrough: readThrough,
      onPillTap: _onGraphVertexTap,
    );
  }

  Widget _buildIsolatedRow(
    BuildContext context,
    List<AiGraphEntity> isolated,
    bool gateByProgress,
    int readThrough,
  ) {
    final expanded = _graphIsolatedExpanded;
    return GraphIsolatedRow(
      count: isolated.length,
      expanded: expanded,
      onToggle: () => setState(() => _graphIsolatedExpanded = !expanded),
      expandedChildren: [
        for (final entity in isolated)
          KeyedSubtree(
            key: _graphEntityKeys.putIfAbsent(entity.id, () => GlobalKey()),
            child: _buildGraphEntityTile(
              context,
              entity,
              gateByProgress,
              readThrough,
            ),
          ),
      ],
    );
  }

  void _onGraphVertexTap(String entityId) {
    final graph = _c.visibleBookGraph;
    final entity = graph?.entityById(entityId);
    if (entity == null) return;
    if (_graphViewMode == _GraphViewMode.graph ||
        _graphViewMode == _GraphViewMode.familyTree) {
      _showEntityDetails(entity);
      return;
    }
    setState(() => _graphHighlighted = entityId);
    _graphHighlightTimer?.cancel();
    _streamCheckpointTimer?.cancel();
    _graphHighlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _graphHighlighted = null);
    });
    final ctx = _graphEntityKeys[entityId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.2,
      );
    }
  }

  void _openFamilyTreeFullscreen(
    AiFamilyTree familyTree,
    AiBookGraph graph,
    bool gateByProgress,
    int readThrough,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiGraphFamilyTreeFullscreen(
          title: _c.activeGraphWork != null
              ? '《${_c.activeGraphWork!.title}》家族树'
              : '家族树',
          tree: familyTree,
          graph: graph,
          gateByProgress: gateByProgress,
          readThrough: readThrough,
          onJumpToEvidence: _goToGraphEvidence,
        ),
      ),
    );
  }

  void _openGraphFullscreen() {
    final graph = _c.visibleBookGraph;
    if (graph == null) return;
    final readThrough = _c.sectionIndex + 1;
    const gateByProgress = false;
    final connectedIds = <String>{
      for (final r in graph.relations) ...[
        if (r.sourceId.isNotEmpty) r.sourceId,
        if (r.targetId.isNotEmpty) r.targetId,
      ],
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiGraphFullscreen(
          title: _c.activeGraphWork != null
              ? '《${_c.activeGraphWork!.title}》图谱'
              : '知识图谱',
          graph: graph,
          gateByProgress: gateByProgress,
          readThrough: readThrough,
          entities: graph.entities
              .where((entity) => connectedIds.contains(entity.id))
              .toList(growable: false),
          relations: graph.relations,
          onJumpToEvidence: _goToGraphEvidence,
        ),
      ),
    );
  }

  Widget _buildGraphEntityTile(
    BuildContext context,
    AiGraphEntity entity,
    bool gateByProgress,
    int readThrough,
  ) {
    final graph = _c.visibleBookGraph;
    final relationCount = graph == null
        ? 0
        : graph.relations
              .where(
                (r) =>
                    ((r.sourceId.isNotEmpty &&
                            (r.sourceId == entity.id ||
                                r.targetId == entity.id)) ||
                        (r.sourceId.isEmpty &&
                            (r.source == entity.name ||
                                r.target == entity.name))) &&
                    (!gateByProgress ||
                        r.evidence.any((e) => e.sectionIndex <= readThrough)),
              )
              .length;
    return GraphEntityTile(
      entity: entity,
      metadata: switch (_graphSortOrder) {
        GraphEntitySortOrder.appearance =>
          '首次：第 ${entity.firstSection} 节 · '
              '${graphEntityChapterCount(entity)} 章',
        GraphEntitySortOrder.evidence =>
          '${graphEntityEvidenceCount(entity)} 条出处 · '
              '${graphEntityChapterCount(entity)} 章',
        GraphEntitySortOrder.relations =>
          '$relationCount 关系 · ${graphEntityChapterCount(entity)} 章',
        GraphEntitySortOrder.type =>
          '${_graphEntityTypeLabel(entity.type)} · '
              '${graphEntityChapterCount(entity)} 章',
        _ => '${graphEntityChapterCount(entity)} 章 · $relationCount 关系',
      },
      typeColor: graphEntityTypeColor(context, entity.type),
      highlighted: _graphHighlighted == entity.id,
      bodySize: _panelBodySize(context),
      onTap: () => _showEntityDetails(entity),
    );
  }

  String _graphEntityTypeLabel(AiGraphEntityType type) => switch (type) {
    AiGraphEntityType.person => '人物',
    AiGraphEntityType.location => '地点',
    AiGraphEntityType.event => '事件',
    AiGraphEntityType.organization => '组织',
    AiGraphEntityType.item => '物件',
    AiGraphEntityType.concept => '概念',
    AiGraphEntityType.creature => '非人角色',
  };

  void _showEntityDetails(AiGraphEntity entity) {
    final graph = _c.visibleBookGraph;
    if (graph == null) return;
    final readThrough = _c.sectionIndex + 1;
    const gateByProgress = false;
    showAppBottomSheet<void>(
      context,
      useRootNavigator: true,
      anchorPoint: appTrailingBottomOverlayAnchor(context),
      builder: (_) => BookAiEntitySheet(
        entity: entity,
        graph: graph,
        gateByProgress: gateByProgress,
        readThrough: readThrough,
        titleSize: _panelTitleSize(context),
        bodySize: _panelBodySize(context),
        onOpenEvidence: _goToGraphEvidence,
        onHideEntity: () => unawaited(_c.hideBookGraphEntity(entity.id)),
      ),
    );
  }

  void _goToGraphEvidence(AiGraphEvidence evidence) {
    final index = evidence.sectionIndex - 1;
    if (index < 0 || index >= _c.sectionCount) return;
    _c.goToSection(index, progressInSection: evidence.progressInSection ?? 0);
    // The evidence row already popped its modal; wait for that route's exit
    // animation to finish, then close the side panel itself so the reader
    // sees the quoted section. Popping immediately would hit the modal
    // (still animating out) and leave the panel open.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });
  }

  Future<void> _ensureGraphWorks() async {
    if (_c.bookStructureManifest != null) return;
    if (_graphWorksLoading || !mounted) return;
    _graphWorksLoading = true;
    await _c.resolveGraphWorkCandidates();
    if (!mounted) return;
    _graphWorksLoading = false;
    setState(() {});
  }

  Future<void> _generateGraph({
    bool force = false,
    AiGraphWorkCandidate? work,
  }) async {
    if (!_ready || _graphBusy) return;
    setState(() {
      _graphPreparing = true;
      _graphPreparingWorkId = work?.id;
    });
    try {
      if (force && _c.bookGraph != null) {
        final confirmed = await showAppConfirmDialog(
          context,
          title: '重新生成图谱？',
          message: '将重新请求 AI，并替换当前保存的图谱。',
          confirmLabel: '重新生成',
        );
        if (confirmed != true || !mounted) return;
      }
      // Step-0 display plan, confirmed before extraction: a fresh generation
      // (no narration yet) and every regeneration get the confirm dialog;
      // incremental runs keep their existing plan untouched. Judged against
      // the TARGET work's graph — the picker page shows the whole-book legacy
      // graph, whose plan must not suppress a fresh per-work dialog.
      final hasPlan = work == null
          ? _c.bookGraph?.narration != null
          : _c.workGraphHasNarration(work);
      if (force || !hasPlan) {
        final confirmed = await _confirmNarrationPlan(work);
        if (confirmed == null || !mounted) return;
        final generation = _c.generateBookGraph(
          only: work,
          force: force,
          narrationOverride: confirmed.plan,
          narrationMode: confirmed.mode,
          excludedGraphSectionIndices: confirmed.excludedSections,
        );
        _clearGraphPreparing();
        await generation;
        return;
      }
      final generation = _c.generateBookGraph(only: work, force: force);
      _clearGraphPreparing();
      await generation;
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          aiUserErrorMessage(error, operation: AiUserOperation.graph),
        );
      }
    } finally {
      _clearGraphPreparing();
    }
  }

  void _clearGraphPreparing() {
    if (!mounted || !_graphPreparing) return;
    setState(() {
      _graphPreparing = false;
      _graphPreparingWorkId = null;
    });
  }

  /// Pre-generation confirm dialog: runs the step-0 display plan (features +
  /// recommended view, user may pick another default view) **and** the
  /// auto-filtered graph corpus with a manual section chooser (uncheck to
  /// exclude a chapter). Returns the confirmed plan (null = keep the default
  /// view) + excluded section indices. Null = cancelled.
  Future<_NarrationConfirmation?> _confirmNarrationPlan(
    AiGraphWorkCandidate? work,
  ) async {
    final existing = work == null ? _c.bookGraph : _c.workGraphFor(work);
    return _showNarrationChooser(
      work: work,
      initialExcluded: existing?.excludedGraphSections.toSet() ?? const {},
      useRecommendedSelection: existing == null,
    );
  }

  Future<_NarrationConfirmation?> _showNarrationChooser({
    AiGraphWorkCandidate? work,
    Set<int> initialExcluded = const {},
    bool useRecommendedSelection = true,
    bool scopeOnly = false,
    String? dialogTitle,
    String? confirmLabel,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    final anchorPoint = appTrailingBottomOverlayAnchor(context);
    Widget chooser(BuildContext _) => NarrationPlanDialog(
      controller: _c,
      work: work,
      initialExcluded: initialExcluded,
      useRecommendedSelection: useRecommendedSelection,
      scopeOnly: scopeOnly,
      dialogTitle: dialogTitle,
      confirmLabel: confirmLabel,
      sheetLayout: context.appIsCompact,
    );
    if (context.appIsCompact) {
      return showAppBottomSheet<_NarrationConfirmation>(
        context,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
        showHandle: false,
        maxWidth: 640,
        anchorPoint: anchorPoint,
        builder: chooser,
      );
    }
    return showDialog<_NarrationConfirmation>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      anchorPoint: anchorPoint,
      builder: chooser,
    );
  }

  Future<void> _deleteGraph() async {
    if (_c.bookGraph == null || _c.isGeneratingBookGraph) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除图谱？',
      message: '只删除这本书保存的 AI 图谱，不影响对话与大纲。',
      confirmLabel: '删除图谱',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _c.deleteBookGraph();
  }

  /// Inline thinking indicator, same animation family as the chat bubbles.
  Widget _thinkingOrb(BuildContext context) => ThinkingOrb(
    state: OrbState.working,
    size: OrbSize.size20,
    theme: Theme.of(context).brightness == Brightness.dark
        ? OrbTheme.dark
        : OrbTheme.light,
  );

  Widget _buildGraphOperationStatus(BuildContext context) {
    final progress = _c.bookGraphProgress;
    final generating = _c.isGeneratingBookGraph;
    final label = _graphPreparing
        ? '正在准备知识图谱…'
        : progress?.label ?? '正在生成知识图谱…';
    final total = progress?.total ?? 0;
    final completed = progress?.completed ?? 0;
    final value = total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
    final compact = context.appIsCompact;

    return Semantics(
      container: true,
      liveRegion: true,
      label: total > 0 ? '$label，$completed / $total' : label,
      child: Container(
        key: const ValueKey<String>('graph-operation-status'),
        margin: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
        decoration: BoxDecoration(
          color: context.appColors.surfaceContainerHighest.withValues(
            alpha: 0.48,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _thinkingOrb(context),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    total > 0 ? '$label  $completed / $total' : label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      fontWeight: FontWeight.w500,
                      color: context.appPrimaryText,
                    ),
                  ),
                ),
                if (generating)
                  TextButton.icon(
                    onPressed: _c.cancelBookGraphGeneration,
                    icon: const Icon(KaijuanIcons.stop, size: 16),
                    label: const Text('停止'),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: value, minHeight: 3),
          ],
        ),
      ),
    );
  }

  Widget _withLiveStatus({
    required Widget child,
    required String label,
    bool announce = true,
  }) {
    if (!announce) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Semantics(
          container: true,
          liveRegion: true,
          label: label,
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _c.removeListener(_onReaderControllerChanged);
    _cancel.cancel();
    _suggestionCancel?.cancel();
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _finalizeActiveTurnForDisposal();
    _input.dispose();
    _graphQueryController.dispose();
    _graphScrollController.dispose();
    _graphHighlightTimer?.cancel();
    _scroll.dispose();
    _focus.dispose();
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    final colors = context.appColors;
    final compact = context.appIsCompact;
    final bottomInset = compact
        ? math.max(keyboardInset, MediaQuery.viewPaddingOf(context).bottom)
        : keyboardInset;
    final hasSelection = _attachedSelection.isNotEmpty;
    final openingShortcuts = aiChatOpeningShortcuts(hasSelection: hasSelection);
    final showFollowUpShortcuts =
        !_sending &&
        !_generatingFollowUp &&
        !_searchingWeb &&
        _streaming.isEmpty &&
        _streamingReasoning.isEmpty &&
        _error == null &&
        _messages.isNotEmpty &&
        _messages.last.role == AiMessageRole.assistant &&
        _messages.last.status == AiChatTurnStatus.completed;
    final followUpShortcuts = aiChatFollowUpShortcuts(
      hasSelection: hasSelection,
      generatedQuestions: showFollowUpShortcuts
          ? _messages.last.suggestedQuestions
          : const [],
    );
    final graphLiveStatus = _graphPreparing
        ? '正在准备知识图谱'
        : _c.isGeneratingBookGraph
        ? _c.bookGraphProgress?.label ?? '正在生成知识图谱'
        : _c.bookGraphError ??
              (_c.visibleBookGraph != null
                  ? '知识图谱已生成'
                  : _c.bookGraph != null
                  ? '知识图谱没有有效数据'
                  : '尚未生成知识图谱');
    final composerControlSize = compact ? 44.0 : 40.0;

    // Side panel already has a fixed height; bottom sheet needs an explicit
    // height so Expanded children layout correctly.
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 20,
            compact ? 8 : 12,
            4,
            0,
          ),
          child: Row(
            children: [
              Text(
                '本书 AI',
                style: TextStyle(
                  fontSize: _panelTitleSize(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_activeTab == _BookAiWorkspaceTab.chat &&
                  _messages.isNotEmpty)
                IconButton(
                  tooltip: '清空对话',
                  onPressed: _sending || _clearingHistory
                      ? null
                      : () => unawaited(_clearHistory()),
                  icon: const Icon(KaijuanIcons.delete, size: 20),
                ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => unawaited(_closePanel()),
                icon: const Icon(KaijuanIcons.close, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, compact ? 8 : 12),
          child: TabBar(
            controller: _tabs,
            labelStyle: TextStyle(
              fontSize: _panelTabSize(context),
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: TextStyle(
              fontSize: _panelTabSize(context),
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: '对话'),
              Tab(text: '知识图谱'),
            ],
          ),
        ),
        if (_activeTab == _BookAiWorkspaceTab.graph && _graphBusy)
          _buildGraphOperationStatus(context),
        if (_activeTab == _BookAiWorkspaceTab.graph)
          Expanded(
            child: _withLiveStatus(
              child: _buildGraphTab(context),
              label: graphLiveStatus,
              announce: !_graphBusy,
            ),
          )
        else if (!_ready)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '添加 API Key 后，就可以围绕这本书提问了。',
                    style: TextStyle(
                      fontSize: _panelBodySize(context),
                      height: 1.45,
                      color: context.appPrimaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => unawaited(_openSettings()),
                    child: const Text('去设置'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Expanded(
            child: _loadingSession
                ? Center(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: ThinkingOrb(
                        state: OrbState.working,
                        size: OrbSize.size64,
                        theme: Theme.of(context).brightness == Brightness.dark
                            ? OrbTheme.dark
                            : OrbTheme.light,
                      ),
                    ),
                  )
                : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '会话加载失败',
                            style: TextStyle(
                              fontSize: context.aiBodySize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _loadError!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: context.appCaptionSize,
                              color: context.appSecondaryText,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                _loadError = null;
                                _loadingSession = true;
                              });
                              unawaited(_bootstrap());
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    key: const ValueKey<String>('ai-chat-message-list'),
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      compact ? 0 : 4,
                      16,
                      compact ? 8 : 12,
                    ),
                    children: [
                      Semantics(
                        container: true,
                        liveRegion: true,
                        label: _liveStatus,
                        child: const SizedBox.shrink(),
                      ),
                      if (_messages.isEmpty &&
                          _streaming.isEmpty &&
                          _streamingReasoning.isEmpty &&
                          !_searchingWeb)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            compact ? 12 : 20,
                            4,
                            compact ? 16 : 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '围绕这本书聊聊：总结、人物，或你想到的问题。',
                                style: TextStyle(
                                  fontSize: _panelBodySize(context),
                                  height: 1.6,
                                  color: context.appSecondaryText,
                                ),
                              ),
                              if (openingShortcuts.isNotEmpty) ...[
                                SizedBox(height: compact ? 12 : 16),
                                _SuggestedQuestionList(
                                  shortcuts: openingShortcuts,
                                  onSelected: (shortcut) => unawaited(
                                    _handleOpeningShortcut(shortcut),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      for (final msg in _messages)
                        _Bubble(
                          key: ValueKey<String>(
                            '${msg.turnId ?? msg.createdAt?.microsecondsSinceEpoch ?? msg.hashCode}:'
                            '${msg.mindMap?.scopeFingerprint ?? ''}',
                          ),
                          message: msg,
                          onCopy: () => unawaited(_copy(msg.content)),
                          onMindMapLayoutChanged: msg.mindMap == null
                              ? null
                              : (layout) => _updateMindMapLayout(msg, layout),
                          onOpenMindMapEvidence: msg.mindMap == null
                              ? null
                              : _goToMindMapEvidence,
                          onOpenMindMapFullscreen: msg.mindMap == null
                              ? null
                              : () => _openMindMapFullscreen(msg),
                        ),
                      if (showFollowUpShortcuts)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 12),
                          child: _SuggestedQuestionList(
                            shortcuts: followUpShortcuts,
                            onSelected: (shortcut) =>
                                unawaited(_send(shortcut.prompt)),
                          ),
                        ),
                      if (_showStatusIndicator)
                        ExcludeSemantics(
                          child: _ThinkingIndicator(
                            label: _statusIndicatorLabel,
                            state: _statusOrbState,
                          ),
                        ),
                      if (_activeTurnVisible &&
                          (_streaming.isNotEmpty ||
                              _streamingReasoning.isNotEmpty))
                        _Bubble(
                          message: AiChatMessage(
                            role: AiMessageRole.assistant,
                            content: _streaming,
                            reasoningContent: _streamingReasoning,
                            reasoningKind: _streamingReasoningKind,
                          ),
                          streaming: true,
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: colors.error,
                                    fontSize: _panelBodySize(context),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              if (_canRetry) ...[
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => unawaited(_send(_retryText)),
                                  child: const Text('重试'),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _WebSearchToggle(
                      enabled: !_sending,
                      selected: _webSearchOn,
                      onPressed: () =>
                          unawaited(_onWebSearchChanged(!_webSearchOn)),
                    ),
                    if (_c.supportsDeepThinking) ...[
                      const SizedBox(width: 8),
                      _DeepThinkingToggle(
                        enabled: !_sending,
                        selected: _deepThinkingOn,
                        onPressed: () =>
                            setState(() => _deepThinkingOn = !_deepThinkingOn),
                      ),
                    ],
                    if (hasSelection) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: InputChip(
                          avatar: const Icon(KaijuanIcons.quote, size: 16),
                          label: Text(
                            _attachedSelection.length > 28
                                ? '${_attachedSelection.substring(0, 28)}…'
                                : _attachedSelection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: _panelDetailSize(context),
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          onDeleted: _sending
                              ? null
                              : () => setState(() => _selection = null),
                          deleteIcon: const Icon(KaijuanIcons.close, size: 16),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  key: const ValueKey<String>('ai-chat-composer'),
                  constraints: BoxConstraints(minHeight: composerControlSize),
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    // Center send/stop against the multiline field (not bottom-stuck).
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        // Keep IME candidate confirmation ahead of desktop
                        // shortcuts; see [_handleComposerKey].
                        child: Focus(
                          onKeyEvent: _handleComposerKey,
                          child: withDesktopTextEditingShortcuts(
                            controller: _input,
                            TextField(
                              controller: _input,
                              focusNode: _focus,
                              autofocus: true,
                              minLines: 1,
                              maxLines: 6,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.send,
                              textCapitalization: TextCapitalization.sentences,
                              enableInteractiveSelection: true,
                              onTap: () => unawaited(_focusComposer()),
                              onSubmitted: (_) {
                                if (!_sending) unawaited(_send());
                              },
                              style: context.appInputTextStyle.copyWith(
                                color: context.appPrimaryText,
                              ),
                              decoration: InputDecoration(
                                hintText: '问这本书…',
                                hintStyle: context.appInputTextStyle.copyWith(
                                  color: context.appSecondaryText,
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_sending)
                        IconButton.filledTonal(
                          tooltip: '停止',
                          onPressed: _stop,
                          style: IconButton.styleFrom(
                            fixedSize: Size.square(composerControlSize),
                            padding: const EdgeInsets.all(10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            KaijuanIcons.stopFilled,
                            size: 18,
                            color: colors.error,
                          ),
                        )
                      else
                        IconButton.filled(
                          tooltip: '发送',
                          onPressed: () => unawaited(_send()),
                          style: IconButton.styleFrom(
                            fixedSize: Size.square(composerControlSize),
                            padding: const EdgeInsets.all(10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(KaijuanIcons.sendFilled, size: 18),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: compact
          ? ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    ((size.height - keyboardInset).clamp(0.0, size.height) *
                            0.92)
                        .clamp(0.0, size.height),
              ),
              child: SizedBox(
                height:
                    ((size.height - keyboardInset).clamp(0.0, size.height) *
                            0.92)
                        .clamp(0.0, size.height),
                child: body,
              ),
            )
          : body,
    );
  }
}

class _AiUnavailable extends StatelessWidget {
  const _AiUnavailable({
    required this.message,
    required this.onOpenSettings,
    this.icon,
  });

  final String message;
  final VoidCallback onOpenSettings;

  /// Optional leading icon (e.g. toc for the outline tab, graph for the
  /// graph tab) matching the empty-state language of each tab.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 34, color: context.appSecondaryText),
            const SizedBox(height: 14),
          ],
          Text(
            message,
            style: TextStyle(
              fontSize: context.aiBodySize,
              height: 1.45,
              color: context.appPrimaryText,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onOpenSettings, child: const Text('去设置')),
        ],
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator({required this.label, required this.state});

  final String label;
  final OrbState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: ThinkingOrb(
              state: state,
              size: OrbSize.size20,
              theme: Theme.of(context).brightness == Brightness.dark
                  ? OrbTheme.dark
                  : OrbTheme.light,
              semanticLabel: label,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSearchToggle extends StatelessWidget {
  const _WebSearchToggle({
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.primary : context.appSecondaryText;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '联网搜索',
      value: selected ? '已开启' : '已关闭',
      toggled: selected,
      child: Tooltip(
        message: selected ? '联网搜索已开启' : '开启联网搜索',
        child: ExcludeSemantics(
          child: IconButton(
            onPressed: enabled ? onPressed : null,
            icon: Icon(KaijuanIcons.globe, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              backgroundColor: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.42),
              disabledForegroundColor: context.appSecondaryText.withValues(
                alpha: 0.5,
              ),
              minimumSize: Size.square(context.appIsCompact ? 44 : 40),
              padding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeepThinkingToggle extends StatelessWidget {
  const _DeepThinkingToggle({
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.primary : context.appSecondaryText;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '深度思考',
      value: selected ? '已开启' : '已关闭',
      toggled: selected,
      child: Tooltip(
        message: selected ? '深度思考已开启' : '开启深度思考',
        child: ExcludeSemantics(
          child: IconButton(
            key: const ValueKey<String>('ai-chat-deep-thinking-toggle'),
            onPressed: enabled ? onPressed : null,
            icon: const Icon(KaijuanIcons.aiChat, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              backgroundColor: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.42),
              disabledForegroundColor: context.appSecondaryText.withValues(
                alpha: 0.5,
              ),
              minimumSize: Size.square(context.appIsCompact ? 44 : 40),
              padding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestedQuestionList extends StatelessWidget {
  const _SuggestedQuestionList({
    required this.shortcuts,
    required this.onSelected,
  });

  final List<AiChatShortcut> shortcuts;
  final ValueChanged<AiChatShortcut> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final compact = context.appIsCompact;
    final maxWidth = MediaQuery.sizeOf(context).width * (compact ? 0.88 : 0.74);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < shortcuts.length; index++) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSelected(shortcuts[index]),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 14,
                      compact ? 8 : 9,
                      compact ? 10 : 12,
                      compact ? 8 : 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            shortcuts[index].label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact
                                  ? context.aiLabelSize
                                  : context.aiDetailSize,
                              height: 1.4,
                              color: context.appPrimaryText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          KaijuanIcons.chevronRight,
                          size: compact ? 15 : 17,
                          color: context.appSecondaryText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (index < shortcuts.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    this.onCopy,
    this.streaming = false,
    this.onMindMapLayoutChanged,
    this.onOpenMindMapEvidence,
    this.onOpenMindMapFullscreen,
  });

  final AiChatMessage message;
  final VoidCallback? onCopy;
  final bool streaming;
  final ValueChanged<AiMindMapLayout>? onMindMapLayoutChanged;
  final ValueChanged<AiMindMapEvidence>? onOpenMindMapEvidence;
  final VoidCallback? onOpenMindMapFullscreen;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiMessageRole.user;
    final bg = isUser
        ? context.appColors.primary.withValues(alpha: 0.12)
        : Colors.transparent;
    final webHits = message.webHitCount;
    final compact = context.appIsCompact;
    final maxWidth = MediaQuery.sizeOf(context).width * (isUser ? 0.76 : 0.92);

    final bubble = Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 14),
      padding: isUser
          ? EdgeInsets.symmetric(
              horizontal: compact ? 13 : 15,
              vertical: compact ? 9 : 10,
            )
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(isUser ? 16 : 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUser)
            SelectionArea(
              child: Text(
                message.content,
                style: TextStyle(
                  fontSize: context.aiBodySize,
                  height: compact ? 1.5 : 1.55,
                  color: context.appPrimaryText,
                ),
              ),
            )
          else ...[
            if (message.reasoningContent.trim().isNotEmpty)
              _ReasoningDisclosure(
                text: message.reasoningContent,
                streaming: streaming,
                kind: message.reasoningKind,
              ),
            if (message.reasoningContent.trim().isNotEmpty &&
                message.content.trim().isNotEmpty)
              const SizedBox(height: 8),
            if (message.content.trim().isNotEmpty)
              AiResultBody(
                text: message.content,
                compact: compact,
                streaming: streaming,
              ),
            if (message.mindMap case final map?) ...[
              if (message.content.trim().isNotEmpty) const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: context.appDivider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox(
                  height: compact ? 420 : 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BookAiMindMapView(
                      map: map,
                      onLayoutChanged: onMindMapLayoutChanged ?? (_) {},
                      onOpenEvidence: onOpenMindMapEvidence ?? (_) {},
                      onOpenFullscreen: onOpenMindMapFullscreen,
                    ),
                  ),
                ),
              ),
            ],
          ],
          if (isUser && webHits != null) ...[
            const SizedBox(height: 6),
            Text(
              webHits == 0 ? '联网 · 无结果' : '联网 · $webHits 条',
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: context.appSecondaryText,
                height: 1.2,
              ),
            ),
          ],
          if (message.status != AiChatTurnStatus.completed &&
              message.status != AiChatTurnStatus.pending) ...[
            const SizedBox(height: 6),
            Text(
              switch (message.status) {
                AiChatTurnStatus.failed => isUser ? '发送失败' : '回答未完成',
                AiChatTurnStatus.cancelled => isUser ? '已停止' : '回答已停止',
                _ => '',
              },
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: message.status == AiChatTurnStatus.failed
                    ? context.appColors.error
                    : context.appSecondaryText,
                height: 1.2,
              ),
            ),
          ],
          if (!isUser && !streaming && onCopy != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '复制本条回答',
                onPressed: onCopy,
                icon: const Icon(KaijuanIcons.copy, size: 15),
                style: IconButton.styleFrom(
                  foregroundColor: context.appSecondaryText,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.square(compact ? 30 : 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: isUser
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: IntrinsicWidth(child: bubble),
            )
          : SizedBox(width: maxWidth, child: bubble),
    );
  }
}

class _ReasoningDisclosure extends StatefulWidget {
  const _ReasoningDisclosure({
    required this.text,
    required this.streaming,
    required this.kind,
  });

  final String text;
  final bool streaming;
  final AiReasoningContentKind kind;

  @override
  State<_ReasoningDisclosure> createState() => _ReasoningDisclosureState();
}

class _ReasoningDisclosureState extends State<_ReasoningDisclosure> {
  late bool _expanded = widget.streaming;

  @override
  void didUpdateWidget(covariant _ReasoningDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming != oldWidget.streaming) {
      _expanded = widget.streaming;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = widget.streaming
        ? '正在思考'
        : widget.kind == AiReasoningContentKind.summary
        ? '思考摘要'
        : '思考过程';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: label,
            value: _expanded ? '已展开' : '已折叠',
            onTap: () => setState(() => _expanded = !_expanded),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      KaijuanIcons.aiChat,
                      size: 15,
                      color: context.appSecondaryText,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          fontWeight: FontWeight.w600,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        KaijuanIcons.chevronRight,
                        size: 15,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectionArea(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    height: 1.55,
                    color: context.appSecondaryText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

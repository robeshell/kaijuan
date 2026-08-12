import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../ai/ai_cancel.dart';
import '../../../ai/ai_book_mind_map_action_gateway.dart';
import '../../../ai/ai_book_structure.dart';
import '../../../ai/ai_chat.dart';
import '../../../ai/ai_chat_retrieve.dart';
import '../../../ai/ai_chat_session_ops.dart';
import '../../../ai/ai_conversation_intent.dart';
import '../../../ai/ai_models.dart';
import '../../../ai/ai_mind_map.dart';
import '../../../ai/ai_provider_kind.dart';
import '../../../ai/ai_product_action.dart';
import '../../../ai/ai_product_action_protocol.dart';

import '../../../ai/ai_rich_content_inspector.dart';
import '../../../ai/ai_user_error.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../../controllers/book_ai_conversation_controller.dart';
import '../../controllers/book_ai_mind_map_coordinator.dart';
import '../../controllers/book_ai_mind_map_controller.dart';
import '../../controllers/book_ai_product_action_host.dart';
import '../../screens/ai_settings_screen.dart';
import '../ai_typography.dart';
import '../app_components.dart';
import '../app_overlays.dart';
import 'book_ai_chat_components.dart';
import 'book_ai_graph_workspace.dart';
import 'book_ai_mind_map_routes.dart';

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

class _BookAiChatSheetState extends State<_BookAiChatSheet>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final TabController _tabs;
  _BookAiWorkspaceTab _activeTab = _BookAiWorkspaceTab.chat;

  int _scrollRequestEpoch = 0;
  int _streamTailFollowEpoch = 0;
  bool _committingComposer = false;

  /// Attached highlight; null when cleared by user.
  String? _selection;
  bool _loadingSession = true;
  String? _loadError;
  bool _sending = false;
  bool _resolvingChatScope = false;

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
  bool _chatRunActive = false;
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
  String? _activeActionProposalId;
  late final BookAiMindMapCoordinator _mindMapCoordinator;
  late final BookAiProductActionHost _productHost;
  BookReaderController get _c => widget.controller;

  BookAiConversationController get _conversation => _c.aiWorkspace.conversation;

  BookAiMindMapController get _mindMapConversation =>
      _c.aiWorkspace.mindMapConversation;

  String? get _activeMindMapArtifactId => _mindMapCoordinator.activeArtifactId;

  AiChatSession get _session => _conversation.session;

  set _session(AiChatSession value) => _conversation.hydrate(value);

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

  AiBookMindMap? _mindMapForArtifact(String artifactId) =>
      _mindMapCoordinator.mapForArtifact(artifactId);

  AiConversationCommand? _commandForTurn(String? turnId) {
    if (turnId == null) return null;
    for (final message in _messages.reversed) {
      if (message.turnId == turnId && message.role == AiMessageRole.user) {
        return message.command;
      }
    }
    return null;
  }

  AiBookMindMap? get _activeMindMap => _mindMapCoordinator.activeMindMap;

  bool get _ready => _c.canUseAiChat;


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

  double _panelTabSize(BuildContext context) => context.aiLabelSize;

  @override
  void initState() {
    super.initState();
    _mindMapCoordinator = BookAiMindMapCoordinator(
      conversation: _conversation,
      mindMapConversation: _mindMapConversation,
      currentWorkKey: () => _chatWorkKey,
      persist: _persist,
    )..addListener(_onMindMapCoordinatorChanged);
    _productHost = BookAiProductActionHost(
      workspace: _c.aiWorkspace,
      ui: BookAiProductActionUi(
        isMounted: () => mounted,
        contentHash: () => _c.item.contentHash,
        publicationTitle: () => _c.item.title,
        chatWorkKey: () => _chatWorkKey,
        sessionMessagesFor: (workKey) => _session.messagesFor(workKey),
        newTurnId: _newTurnId,
        requestConfirmation:
            ({
              required proposalId,
              required title,
              required summary,
              scopeLabel,
              targetLabel,
              revisionLabel,
            }) => _mindMapCoordinator.requestActionConfirmation(
              proposalId: proposalId,
              title: title,
              summary: summary,
              scopeLabel: scopeLabel,
              targetLabel: targetLabel,
              revisionLabel: revisionLabel,
              onOpened: _scrollToEnd,
            ),
        appendClarification: (original, body, {workKey}) =>
            _appendMindMapClarification(original, body, workKey: workKey),
        onArtifactRevealed: _mindMapCoordinator.reveal,
        runCreateMindMap:
            ({
              required text,
              required scope,
              frozenTurn,
              resolvedWork,
              frozenCurrentChapter,
              retryTurnId,
              required clearComposer,
            }) => _routeMindMapRequest(
              text,
              scope,
              frozenTurn: frozenTurn,
              resolvedWork: resolvedWork,
              frozenCurrentChapter: frozenCurrentChapter,
              retryTurnId: retryTurnId,
              clearComposer: clearComposer,
            ),
        runReviseMindMap:
            ({
              required text,
              required target,
              conversationWorkKey,
              retryTurnId,
              required clearComposer,
            }) => _runMindMapRevision(
              text,
              target,
              conversationWorkKey: conversationWorkKey,
              retryTurnId: retryTurnId,
              clearComposer: clearComposer,
            ),
        runGenerateUnits:
            ({
              required text,
              required units,
              baseMap,
              retryTurnId,
              required conversationWorkKey,
              command,
              keepEditing = false,
            }) => _generateMindMapsInChat(
              text,
              units,
              baseMap: baseMap,
              retryTurnId: retryTurnId,
              conversationWorkKey: conversationWorkKey,
              command: command,
              keepEditing: keepEditing,
            ),
        mindMapEditUnit:
            (target, {required requestText, conversationWorkKey}) =>
                _mindMapEditUnit(
                  target,
                  requestText: requestText,
                  conversationWorkKey: conversationWorkKey,
                ),
        bookMindMapSections: ({work, required useFrozenWork}) =>
            _c.bookMindMapSections(work: work, useFrozenWork: useFrozenWork),
        workForKey: _workForKey,
        resolveGraphWorkCandidates: () async {
          await _c.resolveGraphWorkCandidates();
        },
        loadAiChatContext: ({selectionOverride, required workScope}) =>
            _c.loadAiChatContext(
              selectionOverride: selectionOverride,
              workScope: workScope,
            ),
        freezeBookMindMapTurn: ({required workScope, required context}) =>
            _c.freezeBookMindMapTurn(workScope: workScope, context: context),
        currentReadingWork: () => _c.currentReadingWork,
        bookStructureManifest: () => _c.bookStructureManifest,
        itemTitle: () => _c.item.title,
      ),
    );
    _tabs = TabController(
      length: _BookAiWorkspaceTab.values.length,
      vsync: this,
    )..addListener(_onTabChanged);
    _c.addListener(_onReaderControllerChanged);
    _conversation.addListener(_onConversationChanged);
    _mindMapConversation.addListener(_onMindMapConversationChanged);
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
  }

  void _onReaderControllerChanged() {
    if (!mounted) return;
    if (_mindMapTurnId != null) {
      _toolStatus =
          _c.bookMindMapProgress ??
          (_c.isGeneratingBookMindMap ? '正在生成思维导图' : _toolStatus);
    }
    setState(() {});
  }

  void _onConversationChanged() {
    if (!mounted || !_chatRunActive) return;
    final previousText = _streaming;
    final shouldFollowTail = _isNearMessageTail;
    final previousOffset = _scroll.hasClients ? _scroll.offset : null;
    setState(() {
      _sending = _conversation.sending;
      _searchingWeb = _conversation.searchingWeb;
      _lastWebHitCount = _conversation.lastWebHitCount;
      _streaming = _conversation.streaming;
      _streamingReasoning = _conversation.streamingReasoning;
      _streamingReasoningKind = _conversation.streamingReasoningKind;
      _toolStatus = _conversation.toolStatus;
    });
    if (shouldFollowTail && previousText != _streaming) {
      _followStreamingTail(previousOffset: previousOffset);
    }
  }

  void _onMindMapConversationChanged() {
    if (!mounted) return;
    setState(() {
      _mindMapTurnId = _mindMapConversation.activeTurnId;
      _toolStatus = _mindMapConversation.progress;
      _sending = _conversation.sending;
    });
  }

  void _onMindMapCoordinatorChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      // Must not load until chat/history stores attach; otherwise an empty
      // session can later overwrite durable history on first save.
      await _c.aiWorkspace.whenStoresSettled;
      if (!mounted) return;
      if (_c.aiWorkspace.aiStoresError != null &&
          !_c.aiWorkspace.aiStoresReady) {
        // Chat history may still be usable if only journal failed; continue.
      }
      final loadedSession = await _c.loadChatSession();
      final session = AiChatSessionOps.recoverInterruptedTurns(loadedSession);
      if (!identical(session, loadedSession)) {
        await _c.saveChatSession(session);
      }
      await _c.loadBookGraph();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loadingSession = false;
      });
      unawaited(_restorePendingProductAction());
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

  Future<void> _restorePendingProductAction() async {
    await _productHost.resumeAfterOpen();
    if (mounted) setState(() {});
  }

  String scopeNameFromProposal(AiActionProposal proposal) =>
      '${proposal.requestedArguments['scope'] ?? 'wholePublication'}';

  AiBookWork? _workForKey(String workKey) {
    final works = _c.bookStructureManifest?.works ?? const <AiBookWork>[];
    for (final work in works) {
      if (BookReaderController.workKeyFor(work) == workKey) return work;
    }
    return null;
  }

  Future<void> _focusComposer() async {
    _focus.requestFocus();
    await _c.clearPlatformFocus();
  }

  Future<void> _persist() => _conversation.persist();

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
    if (_committingComposer) return;
    _committingComposer = true;
    try {
      await _sendLocked(preset);
    } finally {
      _committingComposer = false;
    }
  }

  Future<void> _sendLocked(String? preset) async {
    // Freeze the submitted value before yielding. macOS can deliver a late
    // IME editing update after the keyboard action, and rereading the
    // controller after an await could otherwise submit that transient value.
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty ||
        _sending ||
        _resolvingChatScope ||
        _mindMapCoordinator.scopePrompt != null ||
        _mindMapCoordinator.actionPrompt != null) {
      return;
    }
    if (!_ready) return;
    if (preset == null) {
      // End the platform editing connection before any async scope/model work
      // can rebuild the panel. This keeps delayed IME updates out of Flutter's
      // layout/semantics phase. The outer submission lock also deduplicates a
      // platform action that reaches both keyboard and submit callbacks.
      _focus.unfocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final retrying = preset != null && preset == _retryText;
    final retryTurnId = retrying ? _retryTurnId : null;
    final retryCommand = _commandForTurn(retryTurnId);
    final frozenTargetId = retryCommand?.targetArtifactId;
    final retryTarget = frozenTargetId == null
        ? null
        : _mindMapForArtifact(frozenTargetId);
    if (retrying && retryCommand?.object == AiIntentObject.mindMap) {
      await _retryMindMapProductAction(
        text: text,
        retryTurnId: retryTurnId,
        retryCommand: retryCommand!,
        retryTarget: retryTarget,
      );
      return;
    }

    // Attachment only binds preferred target context for this free-input turn.
    // The model may propose a revision; it cannot authorize one. Direct
    // revision shortcuts would bypass Proposal/Policy/Command.

    // Ordinary chat also preserves the resolved work of an omnibus. Mind-map
    // product actions are requested by this same model run and dispatched
    // only after the run emits its terminal action event.
    _resolvingChatScope = true;
    try {
      await _c.resolveGraphWorkCandidates();
    } finally {
      _resolvingChatScope = false;
    }
    if (!mounted) return;

    // Prefer the resolved work. Null deliberately means the whole publication:
    // uncertain structure/front matter must not disable chat.
    final turnWork = _c.currentReadingWork;

    _suggestionCancel?.cancel();
    _suggestionCancel = null;

    final wantWeb = _webSearchOn;
    final wantDeepThinking = _c.supportsDeepThinking ? _deepThinkingOn : null;
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
    final scopeSnapshot = _c.freezeBookMindMapTurn(
      workScope: turnWork,
      context: chatContext,
    );
    final turnId = _newTurnId();
    _activeTurnWorkKey = turnWorkKey;
    _activeTurnId = turnId;

    // Clear a composer send as soon as the request is committed. Preset and
    // retry actions leave any separately typed draft untouched.
    if ((preset == null || retrying) && _input.text.trim() == text) {
      _clearComposerAfterFrame(text);
      _pendingDraft = text;
    }

    final turnCancel = CancelToken();
    _cancel = turnCancel;
    setState(() {
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
    });
    _scrollToEnd();
    late AiBookMindMapProductTurn productTurn;
    _chatRunActive = true;
    late final BookAiRunOutcome outcome;
    try {
      outcome = await _conversation.runTurn(
        turnId: turnId,
        workKey: turnWorkKey,
        text: text,
        wantsWebSearch: wantWeb,
        retrying: retrying,
        retryTurnId: retryTurnId,
        cancelToken: turnCancel,
        searchWeb: wantWeb
            ? () => _c.searchWebForChat(
                text,
                workScope: turnWork,
                cancelToken: turnCancel,
              )
            : null,
        startRuntime: (turn, webHits) {
          productTurn = AiBookMindMapActionGateway.prepareProductTurn(
            history: turn.history,
            scopeSnapshot: scopeSnapshot,
            preferredArtifactId: _activeMindMapArtifactId,
            capabilities: _c.aiWorkspace.resolveCapabilities(),
          );
          return _c.streamBookChat(
            userText: text,
            history: turn.history,
            context: chatContext,
            workScope: turnWork,
            webHits: webHits,
            productContext: productTurn.modelContext,
            reasoningEnabled: wantDeepThinking,
            cancelToken: turnCancel,
            runId: turnId,
          );
        },
      );
    } catch (error) {
      _conversation.failActiveTurn(error);
      outcome = BookAiRunFailedOutcome(error);
    }
    _chatRunActive = false;
    if (!mounted) return;
    setState(() {
      _sending = false;
      _searchingWeb = false;
      _toolStatus = null;
      _streaming = '';
      _streamingReasoning = '';
      _streamingReasoningKind = AiReasoningContentKind.process;
      _activeTurnId = null;
      _activeTurnWorkKey = null;
    });

    switch (outcome) {
      case BookAiRunProductActionOutcome(:final request):
        _pendingDraft = null;
        unawaited(
          _dispatchProductAction(
            text,
            request,
            productTurn: productTurn,
            retryTurnId: retryTurnId,
          ),
        );
      case BookAiRunCompletedOutcome(:final completion):
        final body = completion.body;
        final assistantIndex = completion.assistantIndex;
        setState(() {
          if (body.isEmpty) {
            _error = '没有生成内容，请重试';
            _retryText = text;
            _retryTurnId = turnId;
          } else {
            _retryText = null;
            _retryTurnId = null;
          }
        });
        _pendingDraft = null;
        if (assistantIndex != null) {
          setState(() => _generatingFollowUp = true);
          unawaited(
            _generateFollowUpQuestion(
              messageIndex: assistantIndex,
              userText: text,
              answer: body,
              context: chatContext,
              workKey: turnWorkKey,
            ),
          );
        }
      case BookAiRunFailedOutcome(:final error, :final phase):
        setState(() {
          _error = aiUserErrorMessage(
            error,
            operation: phase == BookAiRunFailurePhase.webSearch
                ? AiUserOperation.search
                : AiUserOperation.chat,
          );
          _retryText = text;
          _retryTurnId = turnId;
        });
        _restorePendingDraft();
      case BookAiRunCancelledOutcome():
        _restorePendingDraft();
    }
  }

  void _appendMindMapClarification(
    String text,
    String answer, {
    String? workKey,
  }) {
    final targetWorkKey = workKey ?? _chatWorkKey;
    final turnId = _newTurnId();
    setState(() {
      _session = _withMessage(
        AiChatMessage(
          role: AiMessageRole.user,
          content: text,
          createdAt: DateTime.now(),
          turnId: turnId,
          status: AiChatTurnStatus.completed,
        ),
        workKey: targetWorkKey,
      );
      _session = _withMessage(
        AiChatMessage(
          role: AiMessageRole.assistant,
          content: answer,
          createdAt: DateTime.now(),
          turnId: turnId,
          status: AiChatTurnStatus.completed,
        ),
        workKey: targetWorkKey,
      );
    });
    if (_input.text.trim() == text) {
      _clearComposerAfterFrame(text);
    }
    unawaited(_persist());
    _scrollToEnd();
  }

  Future<BookAiMindMapGenerationUnit?> _mindMapEditUnit(
    AiBookMindMap map, {
    required String requestText,
    String? conversationWorkKey,
  }) async {
    try {
      return await _c.prepareBookMindMapRevision(map);
    } catch (error) {
      if (mounted) {
        _appendMindMapClarification(
          requestText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
          workKey: conversationWorkKey,
        );
      }
      return null;
    }
  }

  Future<bool> _runMindMapRevision(
    String text,
    AiBookMindMap target, {
    String? conversationWorkKey,
    String? retryTurnId,
    required bool clearComposer,
  }) async {
    final frozenConversationWorkKey = conversationWorkKey ?? _chatWorkKey;
    final targetId = target.artifactId ?? 'mind-map:${target.scopeFingerprint}';
    final keepEditing = _activeMindMapArtifactId == targetId;
    setState(() => _resolvingChatScope = true);
    BookAiMindMapGenerationUnit? unit;
    try {
      unit = await _mindMapEditUnit(
        target,
        requestText: text,
        conversationWorkKey: frozenConversationWorkKey,
      );
    } finally {
      if (mounted) setState(() => _resolvingChatScope = false);
    }
    if (!mounted) return false;
    if (unit == null) {
      if (_activeMindMapArtifactId == targetId) {
        _mindMapConversation.detachArtifact();
      }
      return false;
    }
    if (clearComposer) _clearComposerAfterFrame(text);
    await _generateMindMapsInChat(
      text,
      [unit],
      baseMap: target,
      retryTurnId: retryTurnId,
      conversationWorkKey: frozenConversationWorkKey,
      command: AiConversationCommand(
        object: AiIntentObject.mindMap,
        action: AiIntentAction.edit,
        originalText: text,
        targetArtifactId: targetId,
      ),
      keepEditing: keepEditing,
    );
    return true;
  }

  void _clearComposerAfterFrame(String submittedText) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _input.text.trim() != submittedText) return;
      _input.clear();
    });
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
        richArtifactKind: mindMap == null ? inspectAiRichArtifact(body) : null,
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
    _mindMapCoordinator.cancelScope();
    _mindMapCoordinator.cancelActionPrompt();
    final turnId = _activeTurnId;
    final turnWorkKey = _activeTurnWorkKey;
    final actionProposalId = _activeActionProposalId;
    if (actionProposalId != null) {
      try {
        final entry = await _c.aiWorkspace.actionController.journal.read(
          actionProposalId,
        );
        if (entry != null &&
            (entry.status == AiActionJournalStatus.authorized ||
                entry.status == AiActionJournalStatus.queued ||
                entry.status == AiActionJournalStatus.executing)) {
          await _c.aiWorkspace.actionController.requestCancel(actionProposalId);
        }
      } catch (_) {
        // The workflow completion path remains authoritative if the stop
        // races a terminal journal write.
      }
    }
    if (_mindMapTurnId == turnId) {
      _c.cancelBookMindMapGeneration();
      _mindMapTurnId = null;
    }
    _cancel.cancel();
    if (!mounted) return;
    final conversationOwnsTurn = _conversation.activeTurnId == turnId;
    if (conversationOwnsTurn) {
      await _conversation.cancelRun(
        commitPartial: commitPartial,
        persistAfter: persist,
      );
    }
    if (!mounted) return;
    final body = _streaming.trim();
    final reasoning = _streamingReasoning.trim();
    setState(() {
      _sending = false;
      _searchingWeb = false;
      _toolStatus = null;
      if (turnId != null && !conversationOwnsTurn) {
        _setTurnStatus(
          turnId,
          AiChatTurnStatus.cancelled,
          workKey: turnWorkKey,
        );
      }
      if (!conversationOwnsTurn &&
          commitPartial &&
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
    if (persist && !conversationOwnsTurn) unawaited(_persist());
  }

  Future<void> _closePanel() async {
    if (_sending) unawaited(_stop());
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  void _finalizeActiveTurnForDisposal() {
    final turnId = _activeTurnId;
    if (turnId == null) return;
    if (_mindMapTurnId == turnId) {
      _c.cancelBookMindMapGeneration();
      _mindMapTurnId = null;
    }
    final workKey = _activeTurnWorkKey;
    if (_conversation.activeTurnId == turnId) {
      unawaited(_conversation.cancelRun());
      _activeTurnId = null;
      _activeTurnWorkKey = null;
      return;
    }
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
      _mindMapConversation.detachArtifact();
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
  /// [animated] is for an explicit send or newly inserted follow-ups. Opening
  /// the sheet uses a jump so the user does not briefly see the first message
  /// then animate down. Streaming snapshots use [_followStreamingTail].
  /// Retries a few frames: ListView may not have clients yet right after
  /// bootstrap, and markdown bubbles can grow after the first layout.
  void _scrollToEnd({bool animated = true}) {
    _streamTailFollowEpoch++;
    final epoch = ++_scrollRequestEpoch;
    void attempt(int remaining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _scrollRequestEpoch) return;
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
            if (!mounted ||
                epoch != _scrollRequestEpoch ||
                !_scroll.hasClients) {
              return;
            }
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

  bool get _isNearMessageTail {
    if (!_scroll.hasClients) return true;
    return _scroll.position.extentAfter <= 48;
  }

  /// Keeps a growing streaming bubble pinned without starting a new scroll
  /// animation for every model snapshot. The captured offset protects a user
  /// gesture that begins between the event and the next layout frame.
  void _followStreamingTail({required double? previousOffset}) {
    final epoch = ++_streamTailFollowEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _streamTailFollowEpoch || !_scroll.hasClients) {
        return;
      }
      if (_scroll.position.isScrollingNotifier.value) return;
      if (previousOffset != null &&
          (_scroll.offset - previousOffset).abs() > 1) {
        return;
      }
      final max = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - max).abs() > 0.5) {
        _scroll.jumpTo(max);
      }
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnackBar(context, '已复制');
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

  Future<void> _handleOpeningShortcut(AiChatShortcut shortcut) async {
    final scope = shortcut.mindMapScope;
    if (scope != null) {
      await _productHost.dispatchExplicitCreate(
        originalText: shortcut.prompt,
        requestScope: scope,
        parentTurnId: _activeTurnId,
        conversationWorkKey: _chatWorkKey,
      );
      if (mounted) setState(() {});
      return;
    }
    await _send(shortcut.prompt);
  }

  Future<void> _dispatchProductAction(
    String originalText,
    AiProductActionRequest action, {
    required AiBookMindMapProductTurn productTurn,
    String? retryTurnId,
  }) async {
    await _productHost.dispatch(
      originalText: originalText,
      action: action,
      productTurn: productTurn,
      retryTurnId: retryTurnId,
      parentTurnId: _activeTurnId,
    );
    if (mounted) setState(() {});
  }

  List<BookAiMindMapGenerationUnit>? _lastFailedUnits;
  AiBookMindMap? _lastFailedBaseMap;
  String? _lastFailedWorkKey;

  Future<void> _retryMindMapProductAction({
    required String text,
    required String? retryTurnId,
    required AiConversationCommand retryCommand,
    AiBookMindMap? retryTarget,
  }) async {
    final units = _lastFailedUnits;
    if (units == null || units.isEmpty) {
      if (retryCommand.action == AiIntentAction.edit && retryTarget != null) {
        await _runMindMapRevision(
          text,
          retryTarget,
          conversationWorkKey: _lastFailedWorkKey ?? _chatWorkKey,
          retryTurnId: retryTurnId,
          clearComposer: false,
        );
        return;
      }
      if (mounted) {
        _appendMindMapClarification(text, '无法重试：缺少上次范围，请重新发起。');
      }
      return;
    }
    await _productHost.retrySession(
      text: text,
      units: units,
      conversationWorkKey: _lastFailedWorkKey ?? _chatWorkKey,
      retryTurnId: retryTurnId,
      baseMap: _lastFailedBaseMap ?? retryTarget,
      command: retryCommand,
    );
    if (mounted) setState(() {});
  }

  Future<bool> _routeMindMapRequest(
    String text,
    AiMindMapRequestScope scope, {
    AiBookMindMapTurnSnapshot? frozenTurn,
    AiBookWork? resolvedWork,
    AiBookSectionSlice? frozenCurrentChapter,
    String? retryTurnId,
    bool clearComposer = false,
  }) async {
    final conversationWorkKey = frozenTurn?.conversationWorkKey ?? _chatWorkKey;
    List<BookAiMindMapGenerationUnit>? units;
    var composerClearedForChoice = false;
    setState(() => _resolvingChatScope = true);
    try {
      if (scope == AiMindMapRequestScope.currentChapter) {
        units = frozenCurrentChapter == null
            ? await _captureCurrentChapterUnit()
            : [
                (
                  work: resolvedWork,
                  label: frozenCurrentChapter.label.trim().isEmpty
                      ? '当前章'
                      : frozenCurrentChapter.label.trim(),
                  frozenSections: [frozenCurrentChapter],
                  estimatedSections: 1,
                ),
              ];
      } else {
        if (frozenTurn == null && _c.bookStructureManifest == null) {
          await _c.resolveBookStructure();
        }
        if (!mounted) return false;
        final manifest = frozenTurn?.manifest ?? _c.bookStructureManifest;
        if (scope == AiMindMapRequestScope.unspecified &&
            resolvedWork == null) {
          units = await _captureCurrentChapterUnit();
        } else {
          units = await _resolveMindMapUnits(
            scope: scope,
            manifest: manifest,
            resolvedWork: resolvedWork,
            currentWork: frozenTurn?.currentWork,
            onChoicePresented: () {
              if (!clearComposer || composerClearedForChoice) return;
              _clearComposerAfterFrame(text);
              composerClearedForChoice = true;
            },
          );
        }
      }
    } finally {
      if (mounted) setState(() => _resolvingChatScope = false);
    }
    if (!mounted || units == null || units.isEmpty) {
      if (composerClearedForChoice && mounted && _input.text.isEmpty) {
        _restoreComposerText(text);
      }
      return false;
    }
    if (clearComposer && !composerClearedForChoice) {
      _clearComposerAfterFrame(text);
    }
    units = await _freezeMindMapUnits(units);
    await _generateMindMapsInChat(
      text,
      units,
      retryTurnId: retryTurnId,
      conversationWorkKey: conversationWorkKey,
    );
    return true;
  }

  Future<List<BookAiMindMapGenerationUnit>> _freezeMindMapUnits(
    List<BookAiMindMapGenerationUnit> units,
  ) async {
    final frozen = <BookAiMindMapGenerationUnit>[];
    for (final unit in units) {
      final sections =
          unit.frozenSections ??
          await _c.bookMindMapSections(work: unit.work, useFrozenWork: true);
      frozen.add((
        work: unit.work,
        label: unit.label,
        frozenSections: List.unmodifiable(sections),
        estimatedSections: sections.length,
      ));
    }
    return List.unmodifiable(frozen);
  }

  void _restoreComposerText(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<List<BookAiMindMapGenerationUnit>?>
  _captureCurrentChapterUnit() async {
    try {
      final chapter = await _c.captureCurrentBookMindMapChapter();
      if (chapter == null) {
        if (mounted) showAppSnackBar(context, '当前章节正文尚未就绪，请稍后重试');
        return null;
      }
      return [
        (
          work: null,
          label: chapter.label.trim().isEmpty ? '当前章' : chapter.label.trim(),
          frozenSections: [chapter],
          estimatedSections: 1,
        ),
      ];
    } catch (_) {
      if (mounted) showAppSnackBar(context, '读取当前章节失败，请稍后重试');
      return null;
    }
  }

  Future<List<BookAiMindMapGenerationUnit>?> _resolveMindMapUnits({
    required AiMindMapRequestScope scope,
    required AiBookStructureManifest? manifest,
    required AiBookWork? resolvedWork,
    AiBookWork? currentWork,
    VoidCallback? onChoicePresented,
  }) async {
    if (resolvedWork != null) return _mindMapUnitsForWorks([resolvedWork]);
    if (scope == AiMindMapRequestScope.currentWork) {
      final current = currentWork ?? _c.currentMindMapStructureUnit;
      if (current != null) return _mindMapUnitsForWorks([current]);
    }
    final works = manifest?.works ?? const <AiBookWork>[];
    final structureRoute = resolveAiMindMapStructureRoute(manifest);
    if (structureRoute == AiMindMapStructureRoute.sequentialUnits) {
      return _mindMapUnitsForWorks(works);
    }
    if (structureRoute == AiMindMapStructureRoute.chooseUnits) {
      final chapterCounts = [for (final work in works) _workChapterCount(work)];
      final totalChapters = chapterCounts.fold<int>(
        0,
        (total, count) => total + count,
      );
      onChoicePresented?.call();
      final choice = await _showMindMapScopePrompt(
        title: '本书包含 ${works.length} 部作品，共 $totalChapters 章',
        choices: [
          (value: -1, label: '全部作品', subtitle: '按作品依次生成 ${works.length} 张思维导图'),
          for (var index = 0; index < works.length; index++)
            (
              value: index,
              label: works[index].title,
              subtitle: '共 ${chapterCounts[index]} 章',
            ),
        ],
      );
      if (choice == null) return null;
      return _mindMapUnitsForWorks(choice == -1 ? works : [works[choice]]);
    }
    return [
      (
        work: null,
        label: _c.item.title,
        frozenSections: null,
        estimatedSections: math.max(1, _c.sectionCount),
      ),
    ];
  }

  Future<int?> _showMindMapScopePrompt({
    required String title,
    required List<BookAiMindMapScopeChoice> choices,
  }) => _mindMapCoordinator.requestScope(
    title: title,
    choices: choices,
    onOpened: _scrollToEnd,
  );

  int _workChapterCount(AiBookWork work) {
    final logicalStart = work.startLogicalIndex;
    final logicalEnd = work.endLogicalIndexExclusive;
    if (logicalStart != null && logicalEnd != null) {
      return math.max(1, logicalEnd - logicalStart);
    }
    final end = work.endSectionExclusive;
    return end == null ? 1 : math.max(1, end - work.startSection);
  }

  List<BookAiMindMapGenerationUnit> _mindMapUnitsForWorks(
    List<AiBookWork> works,
  ) => [
    for (final work in works)
      (
        work: work,
        label: work.title,
        frozenSections: null,
        estimatedSections: _workChapterCount(work),
      ),
  ];

  Future<void> _generateMindMapsInChat(
    String text,
    List<BookAiMindMapGenerationUnit> units, {
    AiBookMindMap? baseMap,
    String? retryTurnId,
    required String? conversationWorkKey,
    AiConversationCommand? command,
    bool keepEditing = false,
  }) async {
    final workKey = conversationWorkKey;
    final turnId = _newTurnId();
    _activeTurnId = turnId;
    _activeTurnWorkKey = workKey;
    _cancel = CancelToken();
    setState(() {
      _sending = true;
      _error = null;
      _retryText = null;
      _retryTurnId = null;
    });
    _scrollToEnd();
    final outcome = await _c.generateMindMapsInConversation(
      turnId: turnId,
      workKey: workKey,
      text: text,
      units: units,
      cancelToken: _cancel,
      retryTurnId: retryTurnId,
      command: command ??
          AiConversationCommand(
            object: AiIntentObject.mindMap,
            action: baseMap == null
                ? AiIntentAction.create
                : AiIntentAction.edit,
            originalText: text,
            targetArtifactId: baseMap?.artifactId,
          ),
      baseMap: baseMap,
      onArtifact: (artifact) {
        final artifactId = artifact.artifactId;
        if (!mounted) return;
        if (keepEditing && artifactId != null) {
          _mindMapConversation.attachArtifact(artifactId);
        }
        if (artifactId != null) _mindMapCoordinator.reveal(artifactId);
      },
    );
    if (!mounted) return;
    final failed = !outcome.succeeded && !outcome.cancelled;
    _mindMapCoordinator.cancelScope();
    setState(() {
      if (failed) {
        _error = outcome.completed == 0
            ? outcome.userMessage ??
                  (outcome.error == null
                      ? _c.bookMindMapError ?? '暂时无法生成思维导图，请稍后重试'
                      : aiUserErrorMessage(
                          outcome.error!,
                          operation: AiUserOperation.mindMap,
                        ))
            : '已保留前 ${outcome.completed} 张思维导图，生成《${outcome.failedUnit?.label ?? '下一范围'}》时失败，可单独请求该部或卷。';
        if (outcome.completed == 0) {
          _retryText = text;
          _retryTurnId = turnId;
          _lastFailedUnits = units;
          _lastFailedBaseMap = baseMap;
          _lastFailedWorkKey = workKey;
        }
      } else {
        _lastFailedUnits = null;
        _lastFailedBaseMap = null;
        _lastFailedWorkKey = null;
      }
      _sending = false;
      _toolStatus = null;
      _activeTurnId = null;
      _activeTurnWorkKey = null;
      _activeActionProposalId = null;
      _mindMapTurnId = null;
    });
    if (!failed) {
      _scrollRequestEpoch++;
    } else {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onReaderControllerChanged);
    _conversation.removeListener(_onConversationChanged);
    _mindMapConversation.removeListener(_onMindMapConversationChanged);
    _cancel.cancel();
    _mindMapCoordinator.removeListener(_onMindMapCoordinatorChanged);
    _mindMapCoordinator.dispose();
    _suggestionCancel?.cancel();
    _finalizeActiveTurnForDisposal();
    _input.dispose();
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
    final compact = context.appIsCompact;
    final bottomInset = compact
        ? math.max(keyboardInset, MediaQuery.viewPaddingOf(context).bottom)
        : keyboardInset;
    final hasSelection = _attachedSelection.isNotEmpty;
    final openingShortcuts = aiChatOpeningShortcuts(hasSelection: hasSelection);
    final showFollowUpShortcuts =
        !_sending &&
        _mindMapCoordinator.scopePrompt == null &&
        _mindMapCoordinator.actionPrompt == null &&
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
    final composerControlSize = compact ? 44.0 : 40.0;
    final conversationInputLocked =
        _sending ||
        _resolvingChatScope ||
        _mindMapCoordinator.scopePrompt != null ||
        _mindMapCoordinator.actionPrompt != null;

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
                  onPressed:
                      _sending ||
                          _resolvingChatScope ||
                          _clearingHistory ||
                          _mindMapCoordinator.scopePrompt != null ||
                          _mindMapCoordinator.actionPrompt != null
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
        if (_activeTab == _BookAiWorkspaceTab.graph)
          Expanded(
            child: BookAiGraphWorkspace(
              controller: _c,
              onOpenSettings: _openSettings,
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
                : BookAiChatTimeline(
                    scrollController: _scroll,
                    compact: compact,
                    pointerActive: _mindMapCoordinator.pointerActive,
                    liveStatus: _liveStatus,
                    messages: _messages,
                    openingShortcuts: openingShortcuts,
                    followUpShortcuts: followUpShortcuts,
                    showFollowUpShortcuts: showFollowUpShortcuts,
                    showStatusIndicator: _showStatusIndicator,
                    statusIndicatorLabel: _statusIndicatorLabel,
                    statusOrbState: _statusOrbState,
                    activeTurnVisible: _activeTurnVisible,
                    streamingText: _streaming,
                    streamingReasoning: _streamingReasoning,
                    streamingReasoningKind: _streamingReasoningKind,
                    searchingWeb: _searchingWeb,
                    error: _error,
                    canRetry: _canRetry,
                    mindMapRevealTurnId: _mindMapCoordinator.revealArtifactId,
                    scopePrompt: _mindMapCoordinator.scopePrompt,
                    onScopeSelected: _mindMapCoordinator.selectScope,
                    onScopeCancelled: _mindMapCoordinator.cancelScope,
                    actionPrompt: _mindMapCoordinator.actionPrompt,
                    onActionApproved: () =>
                        _mindMapCoordinator.selectActionConfirmation(true),
                    onActionRejected: () =>
                        _mindMapCoordinator.selectActionConfirmation(false),
                    onUserDrag: () {
                      _scrollRequestEpoch++;
                      _streamTailFollowEpoch++;
                    },
                    onShortcutSelected: (shortcut) =>
                        unawaited(_handleOpeningShortcut(shortcut)),
                    onCopy: (message) => unawaited(_copy(message.content)),
                    onMindMapLayoutChanged: _mindMapCoordinator.updateLayout,
                    onOpenMindMapEvidence: (evidence) =>
                        BookAiMindMapRoutes.openEvidence(
                          context,
                          reader: _c,
                          evidence: evidence,
                        ),
                    onOpenMindMapFullscreen: (message) =>
                        BookAiMindMapRoutes.openFullscreen(
                          context,
                          message: message,
                          coordinator: _mindMapCoordinator,
                          onOpenEvidence: (evidence) =>
                              BookAiMindMapRoutes.openEvidence(
                                context,
                                reader: _c,
                                evidence: evidence,
                              ),
                        ),
                    onMindMapRevealed: _mindMapCoordinator.consumeReveal,
                    onMindMapPointerChanged:
                        _mindMapCoordinator.setPointerActive,
                    onRetry: () => unawaited(_send(_retryText)),
                  ),
          ),
          BookAiComposer(
            controller: _input,
            focusNode: _focus,
            locked: conversationInputLocked,
            sending: _sending,
            webSearchSelected: _webSearchOn,
            deepThinkingSupported: _c.supportsDeepThinking,
            deepThinkingSelected: _deepThinkingOn,
            selection: _attachedSelection,
            controlSize: composerControlSize,
            activeMindMapTitle: _activeMindMap == null
                ? null
                : '正在修改：${_activeMindMap!.root.title}',
            activeMindMapRevision: _activeMindMap?.revision,
            onMindMapDetached: _mindMapCoordinator.detachArtifact,
            onFocusRequested: () => unawaited(_focusComposer()),
            onSend: () => unawaited(_send()),
            onStop: () => unawaited(_stop()),
            onWebSearchChanged: (value) =>
                unawaited(_onWebSearchChanged(value)),
            onDeepThinkingChanged: (value) =>
                setState(() => _deepThinkingOn = value),
            onSelectionRemoved: () => setState(() => _selection = null),
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

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../ai/ai_chat.dart';
import '../../../ai/ai_graph.dart';
import '../../../ai/ai_graph_family_tree.dart';
import '../../../ai/ai_log.dart';
import '../../../ai/ai_models.dart';
import '../../../ai/ai_outline.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_search.dart';
import '../../../brand/brand_config.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/text_editing_focus.dart';
import '../../../core/theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../../screens/ai_settings_screen.dart';
import '../app_components.dart';
import '../app_overlays.dart';
import 'ai_result_body.dart';
import 'book_ai_entity_sheet.dart';
import 'book_ai_graph_family_tree_view.dart';
import 'book_ai_graph_tiles.dart';
import 'book_ai_graph_fullscreen.dart';
import 'book_ai_graph_view.dart';
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
  if (controller.aiSettingsController != null) {
    try {
      final root = await getApplicationSupportDirectory();
      final brand = BrandConfig.app;
      final support = brand.storageNamespace.isEmpty
          ? root
          : Directory(p.join(root.path, brand.storageNamespace));
      final dir = Directory(p.join(support.path, 'ai_chat'));
      controller.attachChatHistoryStore(JsonAiChatHistoryStore(dir));
      final graphDir = Directory(p.join(support.path, 'ai_graph'));
      controller.attachAiGraphStore(AiGraphStore(graphDir));
    } catch (_) {}
  }

  if (!context.mounted) return;
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

enum _BookAiWorkspaceTab { chat, outline, graph }

enum _OutlineAction { delete }

/// Default view is the person card list (Kindle X-Ray style); the force
/// layout stays available as a secondary「关系图」view. Each entity type gets
/// its own chapter-ordered list so「谁是谁 / 在哪里 / 发生了哪些事」are
/// readable without the graph.
enum _GraphViewMode { persons, locations, events, graph, familyTree }

/// Sort order for the entity list views.
enum _GraphSortOrder {
  /// First appearance in the book (firstSection ascending).
  byAppearance,

  /// Total mentions (chapterFreq sum) descending — the service's default.
  byFrequency,
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
  final _expandedOutlineSections = <String>{};
  final _expandedOutlineDetails = <String>{};
  final _outlineChildrenKeys = <String, GlobalKey>{};
  bool _outlineOverviewExpanded = false;
  _GraphViewMode _graphViewMode = _GraphViewMode.persons;

  /// Plan whose default view has been applied; applying again is skipped so
  /// the user's manual view choice survives unrelated controller updates.
  AiBookGraph? _appliedNarrationGraph;
  bool _familyTreeDetailExpanded = false;

  /// Per-view sort order, so 人物/地点/事件 keep their own choice. Defaults
  /// to frequency (most-mentioned first).
  final _graphSortOrders = <_GraphViewMode, _GraphSortOrder>{};

  _GraphSortOrder get _graphSortOrder =>
      _graphSortOrders[_graphViewMode] ?? _GraphSortOrder.byFrequency;

  /// Isolated entities (0 relations) collapse into a single row until opened.
  bool _graphIsolatedExpanded = false;

  /// Collection works shown as the graph-tab picker (null = plain book or
  /// not resolved yet). Resolved lazily: sync from the outline, else via a
  /// one-shot structure recognition.
  List<AiGraphWorkCandidate>? _graphWorks;
  bool _graphWorksLoading = false;
  String _graphQuery = '';
  String? _graphHighlighted;
  Timer? _graphHighlightTimer;
  final _graphEntityKeys = <String, GlobalKey>{};
  int _graphListEpoch = 0;

  /// Attached highlight; null when cleared by user.
  String? _selection;
  bool _loadingSession = true;
  bool _sending = false;

  /// Draft cleared for the active send. Restored only when the user has not
  /// entered a newer draft while the request was in flight.
  String? _pendingDraft;

  /// In-panel toggle: when on, fetch web hits before each reply.
  bool _webSearchOn = false;
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
  StreamSubscription<String>? _sub;
  String _streaming = '';

  BookReaderController get _c => widget.controller;

  /// Keep the in-memory + stored session bounded: every write re-serializes
  /// the whole JSON, so an unbounded list would grow each write (O(n²)) and
  /// the ai_chat/ file without limit. 100 messages ≈ 50 turns is generous.
  static const int _maxStoredMessages = 100;

  bool get _ready => _c.canUseAiChat;

  bool get _canWebSearch => _c.canUseWebSearch;

  String get _attachedSelection => (_selection ?? '').trim();

  bool get _showThinkingIndicator =>
      _sending && _streaming.isEmpty && !_searchingWeb && _toolStatus == null;

  bool get _showStatusIndicator =>
      _searchingWeb || _toolStatus != null || _showThinkingIndicator;

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
    if (_searchingWeb) return '正在联网搜索…';
    if (_toolStatus != null) return _toolStatus!;
    if (_showThinkingIndicator) return '思考中…';
    if (_error != null) return '错误：$_error';
    return '';
  }

  bool get _canRetry =>
      _retryText != null && _retryText!.trim().isNotEmpty && !_sending;

  double _panelTitleSize(BuildContext context) =>
      context.appIsCompact ? 16 : context.appTitleSize;

  double _panelBodySize(BuildContext context) =>
      context.appIsCompact ? 15 : context.appBodySize;

  double _panelDetailSize(BuildContext context) =>
      context.appIsCompact ? 14 : context.appBodySecondarySize;

  double _panelTabSize(BuildContext context) =>
      context.appIsCompact ? 14 : context.appListTitleSize;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _BookAiWorkspaceTab.values.length,
      vsync: this,
    )..addListener(_onTabChanged);
    _c.addListener(_onReaderControllerChanged);
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
    } else if (_activeTab == _BookAiWorkspaceTab.outline) {
      // 「读到哪本跟哪本」: landing on the outline tab expands the chain
      // down to the work currently under the reading position.
      _revealOutlineForReadingWork();
    }
  }

  /// Expands the outline nodes leading to the work the reader is currently
  /// inside (match by the work's start spine). No-op for plain books or when
  /// the outline is not loaded yet; scrolling to the row is skipped — the
  /// expanded chain makes the anchor visible without fighting the scroll
  /// controller.
  void _revealOutlineForReadingWork() {
    final work = _c.currentReadingWork;
    if (work == null) return;
    final outline = _c.bookOutline;
    if (outline == null) return;
    final chain = <AiBookOutlineChapter>[];
    final ancestors = <AiBookOutlineChapter>[];
    void walk(AiBookOutlineChapter node) {
      if (chain.isNotEmpty) return;
      if (node.sectionIndex == work.startSection ||
          node.sourceSectionIndex == work.startSection) {
        chain.add(node);
        return;
      }
      for (final child in node.children ?? const <AiBookOutlineChapter>[]) {
        if (chain.isNotEmpty) return;
        ancestors.add(node);
        walk(child);
        if (chain.isNotEmpty) return;
        ancestors.removeLast();
      }
    }

    for (final root in outline.chapters) {
      walk(root);
      if (chain.isNotEmpty) break;
    }
    if (chain.isEmpty) return;
    for (final ancestor in ancestors) {
      _expandedOutlineSections.add(ancestor.stableNodeId);
    }
    _expandedOutlineSections.add(chain.first.stableNodeId);
    setState(() {});
  }

  void _onReaderControllerChanged() {
    if (!mounted) return;
    // Apply the narration plan's recommended default view once per graph
    // instance (new generation or re-analysis); afterwards the user's own
    // view choice wins.
    final graph = _c.bookGraph;
    final plan = graph?.narration;
    if (plan != null && !identical(graph, _appliedNarrationGraph)) {
      _appliedNarrationGraph = graph;
      final wanted = _viewModeFor(plan.defaultView);
      if (wanted != null && _graphViewMode != wanted) {
        _graphViewMode = wanted;
      }
    }
    setState(() {});
  }

  Future<void> _bootstrap() async {
    final session = await _c.loadChatSession();
    // The outline shares the same session JSON; avoid decoding it twice while
    // the side sheet is animating in.
    await _c.loadBookOutline(session: session);
    await _c.loadBookGraph();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loadingSession = false;
    });
    // Open on the latest turn (history starts at top of the list).
    if (session.messages.isNotEmpty) {
      _scrollToEnd(animated: false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_focusComposer());
    });
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

  /// Append [message], keeping only the newest [_maxStoredMessages] so both the
  /// in-memory list and the JSON file stay bounded.
  AiChatSession _withMessage(AiChatMessage message) {
    final messages = <AiChatMessage>[..._session.messages, message];
    final kept = messages.length > _maxStoredMessages
        ? messages.sublist(messages.length - _maxStoredMessages)
        : messages;
    return _session.copyWith(messages: kept);
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

    _suggestionCancel?.cancel();
    _suggestionCancel = null;

    final wantWeb = _webSearchOn;
    final retrying = preset != null && preset == _retryText;
    if (wantWeb && !_canWebSearch) {
      showAppSnackBar(context, '请先在设置中填写联网搜索 Key');
      await _openSettings();
      if (!mounted || !_canWebSearch) return;
    }

    final chatContext = await _c.loadAiChatContext(
      selectionOverride: _attachedSelection.isEmpty ? null : _attachedSelection,
    );
    if (!mounted) return;

    // Clear a composer send as soon as the request is committed. Preset and
    // retry actions leave any separately typed draft untouched.
    if (preset == null && _input.text.trim() == text) {
      _input.clear();
      _pendingDraft = text;
    }

    // Placeholder user bubble; webHitCount filled after search (if any).
    var userMsg = AiChatMessage(
      role: AiMessageRole.user,
      content: text,
      createdAt: DateTime.now(),
      webHitCount: wantWeb ? 0 : null,
    );
    final historyBefore = List<AiChatMessage>.from(_session.messages);
    if (retrying && historyBefore.isNotEmpty) {
      final msgs = List<AiChatMessage>.from(_session.messages);
      if (msgs.isNotEmpty && msgs.last.role == AiMessageRole.assistant) {
        msgs.removeLast();
      }
      if (msgs.isNotEmpty &&
          msgs.last.role == AiMessageRole.user &&
          msgs.last.content.trim() == text) {
        msgs.removeLast();
      }
      historyBefore
        ..clear()
        ..addAll(msgs);
      if (msgs.length != _session.messages.length) {
        setState(() => _session = _session.copyWith(messages: msgs));
      }
    }
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _cancel = CancelToken();
    setState(() {
      _session = _withMessage(userMsg);
      _sending = true;
      _generatingFollowUp = false;
      _searchingWeb = wantWeb;
      _lastWebHitCount = null;
      _error = null;
      _retryText = null;
      _streaming = '';
      _toolStatus = null;
    });
    unawaited(_persist());
    _scrollToEnd();

    // null = 联网 off; non-null (even []) = search ran this turn.
    List<AiWebSearchHit>? webHits;
    if (wantWeb) {
      try {
        webHits = await _c.searchWebForChat(text);
      } on AiProviderException catch (error) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _searchingWeb = false;
          _lastWebHitCount = null;
          _retryText = text;
          _error = error.message;
        });
        _restorePendingDraft();
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _searchingWeb = false;
          _lastWebHitCount = null;
          _retryText = text;
          _error = '联网搜索失败，请稍后重试';
        });
        _restorePendingDraft();
        return;
      }
      if (!mounted) return;
      final hitCount = webHits.length;
      userMsg = userMsg.copyWith(webHitCount: hitCount);
      setState(() {
        _searchingWeb = false;
        _lastWebHitCount = hitCount;
        // Refresh last user bubble with real hit count.
        final msgs = List<AiChatMessage>.from(_session.messages);
        if (msgs.isNotEmpty && msgs.last.role == AiMessageRole.user) {
          msgs[msgs.length - 1] = userMsg;
          _session = _session.copyWith(messages: msgs);
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
      webHits: webHits,
      cancelToken: _cancel,
      onToolStatus: (status) {
        if (!mounted) return;
        setState(() => _toolStatus = status);
      },
    );
    if (stream == null) {
      setState(() {
        _sending = false;
        _searchingWeb = false;
        _toolStatus = null;
        _error = 'AI 未启用或未配置';
        _retryText = null;
      });
      _restorePendingDraft();
      return;
    }

    _sub = stream.listen(
      (value) {
        if (!mounted) return;
        setState(() => _streaming = value);
        _scrollToEnd();
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _searchingWeb = false;
          _toolStatus = null;
          _error = error is AiProviderException ? error.message : '生成失败，请稍后重试';
          _retryText = text;
          if (_streaming.trim().isNotEmpty) {
            _commitAssistant(_streaming);
          }
          _streaming = '';
        });
        _restorePendingDraft();
      },
      onDone: () {
        if (!mounted) return;
        final body = _streaming.trim();
        int? assistantIndex;
        setState(() {
          _sending = false;
          _searchingWeb = false;
          _toolStatus = null;
          if (body.isNotEmpty) {
            _commitAssistant(body);
            assistantIndex = _session.messages.length - 1;
          }
          _retryText = null;
          _streaming = '';
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

  void _commitAssistant(String body) {
    _session = _withMessage(
      AiChatMessage(
        role: AiMessageRole.assistant,
        content: body,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _generateFollowUpQuestion({
    required int messageIndex,
    required String userText,
    required String answer,
    required AiChatContextBundle context,
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
      if (suggestions.isEmpty ||
          messageIndex >= _session.messages.length ||
          _session.messages[messageIndex].role != AiMessageRole.assistant ||
          _session.messages[messageIndex].content != answer) {
        return;
      }
      final messages = List<AiChatMessage>.from(_session.messages);
      messages[messageIndex] = messages[messageIndex].copyWith(
        suggestedQuestions: suggestions,
      );
      setState(() {
        _session = _session.copyWith(messages: messages);
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
    _cancel.cancel();
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (!mounted) return;
    final body = _streaming.trim();
    setState(() {
      _sending = false;
      _searchingWeb = false;
      _toolStatus = null;
      if (commitPartial && body.isNotEmpty) {
        _commitAssistant(body);
      }
      _streaming = '';
      _cancel = CancelToken();
    });
    _restorePendingDraft();
    if (persist) unawaited(_persist());
  }

  Future<void> _clearHistory() async {
    if (_clearingHistory) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清空对话？',
      message: '将删除这本书保存的全部对话。清空后无法恢复。',
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
      await _c.clearChatSession();
      if (!mounted) return;
      setState(() {
        _session = AiChatSession(
          contentHash: _c.item.contentHash,
          itemId: _c.item.id,
        );
        _error = null;
        _retryText = null;
        _streaming = '';
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
    await _c.generateBookOutline();
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

  Widget _buildOutlineTab(BuildContext context) {
    final colors = context.appColors;
    final outline = _c.bookOutline;
    final progress = _c.bookOutlineProgress;
    final generating = _c.isGeneratingBookOutline;
    final error = _c.bookOutlineError;
    final canExpandOverview = outline != null && outline.overview.length > 180;
    if (!_ready) {
      return _AiUnavailable(
        message: '添加 API Key 后，就可以生成本书大纲。',
        onOpenSettings: () => unawaited(_openSettings()),
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
              Text(
                generating ? '正在生成大纲' : '本书大纲',
                style: TextStyle(
                  fontSize: _panelTitleSize(context),
                  fontWeight: FontWeight.w600,
                  color: context.appPrimaryText,
                ),
              ),
              const SizedBox(height: 6),
              // While generating, the live progress label lives next to the
              // thinking orb below; showing it here too duplicates the text.
              if (!generating)
                Text(
                  progress?.label ?? '生成一次后会保存在这本书中。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _panelBodySize(context),
                    height: 1.45,
                    color: context.appSecondaryText,
                  ),
                ),
              if (generating) ...[
                const SizedBox(height: 14),
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
                  label: const Text('生成大纲'),
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
                '全书概览',
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
        RichText(
          maxLines: _outlineOverviewExpanded ? null : 3,
          overflow: _outlineOverviewExpanded
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          text: TextSpan(
            style: TextStyle(
              fontSize: _panelDetailSize(context),
              height: 1.55,
              color: context.appSecondaryText,
            ),
            children: [
              TextSpan(text: outline.overview),
              if (canExpandOverview)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _InlineOutlineOverviewToggle(
                    expanded: _outlineOverviewExpanded,
                    onPressed: () => setState(
                      () =>
                          _outlineOverviewExpanded = !_outlineOverviewExpanded,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (generating) ...[
          const SizedBox(height: 18),
          Text(
            progress?.label ?? '正在生成…',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _c.cancelBookOutlineGeneration,
              icon: const Icon(KaijuanIcons.stop, size: 18),
              label: const Text('停止'),
            ),
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
        Text(
          '章节大纲',
          style: TextStyle(
            fontSize: _panelTitleSize(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        for (final chapter in outline.chapters)
          _buildOutlineChapterTile(context, chapter),
      ],
    );
  }

  Widget _buildOutlineChapterTile(
    BuildContext context,
    AiBookOutlineChapter chapter, {
    int depth = 0,
  }) {
    final nodeId = chapter.stableNodeId;
    final expanded = _expandedOutlineSections.contains(nodeId);
    final detailsExpanded = _expandedOutlineDetails.contains(nodeId);
    final children = chapter.children;
    final loadingChildren = _c.isGeneratingBookOutlineChildren(chapter);
    final childProgress = _c.bookOutlineChildrenProgress(chapter);
    final childError = _c.bookOutlineChildrenError(chapter);
    final canGenerateChildren =
        _c.canGenerateBookOutlineChildren(chapter) || childError != null;
    final indent = 8.0 + depth * 18.0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: depth * 18.0),
          child: ListTile(
            contentPadding: EdgeInsetsDirectional.fromSTEB(
              8,
              context.appIsCompact ? 6 : 10,
              2,
              context.appIsCompact ? 6 : 10,
            ),
            minVerticalPadding: 0,
            title: Text(
              chapter.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _panelBodySize(context),
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: context.appPrimaryText,
              ),
            ),
            subtitle: expanded
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      chapter.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        height: 1.4,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ),
            trailing: IconButton(
              tooltip: expanded ? '收起' : '展开',
              onPressed: () => _toggleOutlineNode(chapter),
              icon: Icon(
                expanded ? KaijuanIcons.chevronDown : KaijuanIcons.chevronRight,
                size: 18,
                color: context.appSecondaryText,
              ),
            ),
            onTap: () => _toggleOutlineNode(chapter),
          ),
        ),
        if (expanded)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              indent,
              4,
              8,
              context.appIsCompact ? 12 : 16,
            ),
            child: _buildOutlineChapterDetails(
              context,
              chapter,
              detailsExpanded: detailsExpanded,
              loadingChildren: loadingChildren,
              childProgress: childProgress,
              childError: childError,
              canGenerateChildren: canGenerateChildren,
              hasChildren: children?.isNotEmpty ?? false,
            ),
          ),
        if (expanded && children != null)
          KeyedSubtree(
            key: _outlineChildrenKey(nodeId),
            child: Column(
              children: [
                for (final child in children)
                  _buildOutlineChapterTile(context, child, depth: depth + 1),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOutlineChapterDetails(
    BuildContext context,
    AiBookOutlineChapter chapter, {
    required bool detailsExpanded,
    required bool loadingChildren,
    required AiOutlineProgress? childProgress,
    required String? childError,
    required bool canGenerateChildren,
    required bool hasChildren,
  }) {
    final showAllPoints = detailsExpanded || chapter.keyPoints.length <= 2;
    final canExpandDetails =
        chapter.summary.length > 260 || chapter.keyPoints.length > 2;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loadingChildren)
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: _thinkingOrb(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    childProgress?.label ?? '正在生成下级大纲…',
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: context.appSecondaryText,
                    ),
                  ),
                ),
              ],
            ),
          Text(
            chapter.summary,
            maxLines: detailsExpanded ? null : 5,
            overflow: detailsExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _panelDetailSize(context),
              height: 1.5,
              color: context.appSecondaryText,
            ),
          ),
          if (chapter.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '要点',
              style: TextStyle(
                fontSize: context.appCaptionSize,
                fontWeight: FontWeight.w600,
                color: context.appPrimaryText,
              ),
            ),
            const SizedBox(height: 5),
            for (final point
                in showAllPoints
                    ? chapter.keyPoints
                    : chapter.keyPoints.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 7),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.appSecondaryText,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          fontSize: _panelDetailSize(context),
                          height: 1.45,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          Row(
            children: [
              if (!loadingChildren && canGenerateChildren && !hasChildren)
                TextButton.icon(
                  onPressed: () => unawaited(
                    _generateOutlineChildren(chapter, force: false),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  icon: const Icon(KaijuanIcons.aiChat, size: 17),
                  label: const Text('生成下级大纲'),
                ),
              const Spacer(),
              if (canExpandDetails)
                IconButton(
                  tooltip: detailsExpanded ? '收起完整内容' : '展开完整内容',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleOutlineDetails(chapter),
                  icon: Icon(
                    detailsExpanded ? KaijuanIcons.minimize : KaijuanIcons.more,
                    size: 18,
                  ),
                ),
              if (!loadingChildren && hasChildren)
                IconButton(
                  tooltip: '重新生成下级大纲',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      unawaited(_generateOutlineChildren(chapter, force: true)),
                  icon: const Icon(KaijuanIcons.refresh, size: 18),
                ),
              IconButton(
                tooltip: '前往原文',
                visualDensity: VisualDensity.compact,
                onPressed: () => _goToOutlineChapter(context, chapter),
                icon: const Icon(KaijuanIcons.open, size: 18),
              ),
            ],
          ),
          if (childError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                childError,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleOutlineNode(AiBookOutlineChapter chapter) {
    final nodeId = chapter.stableNodeId;
    final expanding = !_expandedOutlineSections.contains(nodeId);
    setState(() {
      if (expanding) {
        _expandedOutlineSections.add(nodeId);
      } else {
        _expandedOutlineSections.remove(nodeId);
      }
    });
  }

  void _toggleOutlineDetails(AiBookOutlineChapter chapter) {
    final nodeId = chapter.stableNodeId;
    setState(() {
      if (_expandedOutlineDetails.contains(nodeId)) {
        _expandedOutlineDetails.remove(nodeId);
      } else {
        _expandedOutlineDetails.add(nodeId);
      }
    });
  }

  void _goToOutlineChapter(BuildContext context, AiBookOutlineChapter chapter) {
    _c.goToSection((chapter.sourceSectionIndex ?? chapter.sectionIndex) - 1);
    Navigator.of(context).maybePop();
  }

  Future<void> _generateOutlineChildren(
    AiBookOutlineChapter chapter, {
    required bool force,
  }) async {
    await _c.generateBookOutlineChildren(chapter, force: force);
    if (!mounted) return;
    // Keep the just-generated branch visible even if a parent rebuild raced
    // with the final controller notification.
    final childCount = _outlineChildrenCount(
      _c.bookOutline?.chapters ?? const [],
      chapter.stableNodeId,
    );
    AiLog.d(
      'outline sheet children parent=${chapter.stableNodeId} '
      'visible=$childCount',
    );
    setState(() => _expandedOutlineSections.add(chapter.stableNodeId));
    if (childCount != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final target = _outlineChildrenKeys[chapter.stableNodeId]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.16,
        );
      }
    }
  }

  GlobalKey _outlineChildrenKey(String nodeId) =>
      _outlineChildrenKeys.putIfAbsent(nodeId, GlobalKey.new);

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

  bool get _allowUnread =>
      _c.aiSettingsController?.settings.allowUnreadContext ?? false;

  /// Which entity types the current list view shows; empty on the graph
  /// view (no list rendered there). The persons view also folds in
  /// `organization` entities (家族/势力 read as part of the cast).
  Set<AiGraphEntityType> get _graphListEntityTypes => switch (_graphViewMode) {
    _GraphViewMode.persons => {
        AiGraphEntityType.person,
        AiGraphEntityType.organization,
      },
    _GraphViewMode.locations => {AiGraphEntityType.location},
    _GraphViewMode.events => {AiGraphEntityType.event},
    _GraphViewMode.graph => const {},
    _GraphViewMode.familyTree => const {},
  };

  /// View entry order: the plan's `viewOrder` when present (unknown views
  /// like family_tree are skipped until the tree lands), then the base
  /// order for anything not mentioned. Essays (散文) never get a family
  /// tree entry — no lineage structure exists there — matching the plan
  /// filtering; other books keep every view reachable.
  List<_GraphViewMode> _orderedGraphViewModes(AiNarrationPlan? plan) {
    final essayHigh = (plan?.feature('essay') ?? 0) >= 0.5;
    final base = [
      _GraphViewMode.persons,
      _GraphViewMode.locations,
      _GraphViewMode.events,
      _GraphViewMode.graph,
      if (!essayHigh) _GraphViewMode.familyTree,
    ];
    if (plan == null) {
      return [
        _GraphViewMode.persons,
        _GraphViewMode.locations,
        _GraphViewMode.events,
        _GraphViewMode.graph,
      ];
    }
    final ordered = <_GraphViewMode>[];
    for (final view in plan.viewOrder) {
      final mode = _viewModeFor(view);
      if (mode != null && !ordered.contains(mode)) ordered.add(mode);
    }
    for (final mode in base) {
      if (!ordered.contains(mode)) ordered.add(mode);
    }
    return ordered;
  }

  _GraphViewMode? _viewModeFor(String view) => switch (view) {
    'persons' => _GraphViewMode.persons,
    'locations' => _GraphViewMode.locations,
    'events' => _GraphViewMode.events,
    'graph' => _GraphViewMode.graph,
    'family_tree' => _GraphViewMode.familyTree,
    _ => null, // org_tree: not rendered until the organization tree lands.
  };

  static const _graphViewLabels = <_GraphViewMode, String>{
    _GraphViewMode.persons: '人物',
    _GraphViewMode.locations: '地点',
    _GraphViewMode.events: '事件',
    _GraphViewMode.graph: '关系图',
    _GraphViewMode.familyTree: '家族树',
  };

  Widget _buildGraphTab(BuildContext context) {
    final colors = context.appColors;
    final graph = _c.bookGraph;
    final progress = _c.bookGraphProgress;
    final generating = _c.isGeneratingBookGraph;
    final error = _c.bookGraphError;
    // Collection books: the picker lists every work; entering one shows its
    // graph (whole-book / plain-book graphs keep the single view below).
    final works = _graphWorks ?? _c.graphWorkCandidates;
    if (works != null &&
        works.isNotEmpty &&
        !_c.hasActiveWorkGraph &&
        !_c.viewingWholeBookGraph) {
      return _buildGraphWorksList(context, works);
    }
    if (!_ready) {
      return _AiUnavailable(
        message: '添加 API Key 后，就可以生成本书的人物、地点与事件图谱。',
        onOpenSettings: () => unawaited(_openSettings()),
      );
    }
    if (graph == null) {
      // Collection detection is async (outline → work candidates). Until the
      // works are known, there is no valid range to generate — show a
      // loading state instead of the actionable empty-state button, or a
      // tap would start a whole-book dialog against a half-loaded book.
      final outlinePending = _c.bookOutline == null;
      if (works == null && (_graphWorksLoading || outlinePending)) {
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
              if (_c.activeGraphWork != null || _c.viewingWholeBookGraph) ...[
                _graphBackRow(),
                const SizedBox(height: 8),
              ],
              Icon(
                KaijuanIcons.collections,
                size: 34,
                color: context.appSecondaryText,
              ),
              const SizedBox(height: 14),
              // While generating, the title row is redundant next to the
              // live progress label; keep it only for the idle state.
              if (!generating)
                Text(
                  '知识图谱',
                  style: TextStyle(
                    fontSize: _panelTitleSize(context),
                    fontWeight: FontWeight.w600,
                    color: context.appPrimaryText,
                  ),
                ),
              if (generating) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _thinkingOrb(context),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        progress?.label ?? '正在生成图谱…',
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
                  onPressed: _c.cancelBookGraphGeneration,
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
                  onPressed: () => unawaited(_generateGraph(
                        // Retry the range being retried: after a cancelled /
                        // failed generation the active work is still set, and
                        // the dialog must open scoped to it (not the whole
                        // collection).
                        work: _c.activeGraphWork,
                      )),
                  icon: const Icon(KaijuanIcons.collections, size: 18),
                  label: const Text('生成图谱'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final readThrough = _c.sectionIndex + 1;
    final gateByProgress = !_allowUnread && graph.includesUnread;
    // Entities with at least one relation form the readable core; zero-edge
    // entities (mere mentions) collapse into one foldable row and are left
    // off the force-directed view where they would float as orphan dots.
    final connectedNames = <String>{
      for (final r in graph.relations) ...[r.source, r.target],
    };
    final visibleEntities = graph.entities.where((entity) {
      if (gateByProgress && entity.firstSection > readThrough) return false;
      final listTypes = _graphListEntityTypes;
      if (listTypes.isNotEmpty && !listTypes.contains(entity.type)) {
        return false;
      }
      if (_graphQuery.trim().isNotEmpty) {
        final query = _graphQuery.trim();
        final hit = entity.name.contains(query) ||
            entity.aliases.any((alias) => alias.contains(query));
        if (!hit) return false;
      }
      return true;
    }).toList(growable: false);
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
    // Every list view can be read by 出场顺序 (first appearance) or by
    // total mentions. The service already emits frequency-descending order,
    // so byFrequency just keeps the source list.
    List<AiGraphEntity> ordered(List<AiGraphEntity> source) {
      switch (_graphSortOrder) {
        case _GraphSortOrder.byFrequency:
          return source;
        case _GraphSortOrder.byAppearance:
          return [...source]
            ..sort(
              (a, b) => a.firstSection.compareTo(b.firstSection),
            );
      }
    }

    final orderedMain = ordered(mainEntities);
    final orderedIsolated = ordered(isolatedEntities);

    final personCount = graph.entities
        .where(
          (entity) =>
              entity.type == AiGraphEntityType.person &&
              (!gateByProgress || entity.firstSection <= readThrough),
        )
        .length;

    return ListView(
      key: ValueKey<int>(_graphListEpoch),
      controller: _graphScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (_c.activeGraphWork != null || _c.viewingWholeBookGraph) ...[
          _graphBackRow(),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                _c.activeGraphWork != null
                    ? '《${_c.activeGraphWork!.title}》图谱'
                    : (graph.excludedGraphSections.isNotEmpty
                        ? '部分章节图谱'
                        : (_c.viewingWholeBookGraph
                            ? '整本图谱'
                            : (graph.includesUnread ? '全书图谱' : '已读章节图谱'))),
                style: TextStyle(
                  fontSize: _panelTitleSize(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!_allowUnread && graph.includesUnread)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '按进度展示',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: colors.primary,
                  ),
                ),
              ),
            IconButton(
              tooltip: '重新生成图谱',
              onPressed: generating
                  ? null
                  : () => unawaited(_generateGraph(
                        force: true,
                        // Regenerate the range being viewed: the detail
                        // header is shared by whole-book and per-work graphs,
                        // and a per-work regeneration must reopen the dialog
                        // scoped to that work (not the whole collection).
                        work: _c.activeGraphWork,
                      )),
              icon: const Icon(KaijuanIcons.refresh, size: 20),
            ),
            PopupMenuButton<_OutlineAction>(
              tooltip: '更多',
              enabled: !generating,
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
        Text(
          '人物 $personCount · 实体 ${visibleEntities.length} · '
          '关系 ${graph.relations.length}',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
        if (graph.generatedAt != null || graph.generationSeconds != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _graphGenerationSummary(graph),
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: context.appSecondaryText,
              ),
            ),
          ),
        if (!generating && mainEntities.isNotEmpty) ...[
          const SizedBox(height: 10),
          SegmentedButton<_GraphViewMode>(
            segments: [
              for (final mode in _orderedGraphViewModes(graph.narration))
                ButtonSegment(
                  value: mode,
                  label: Text(_graphViewLabels[mode]!),
                ),
            ],
            selected: {_graphViewMode},
            onSelectionChanged: (selection) =>
                setState(() => _graphViewMode = selection.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: context.appCaptionSize),
              ),
            ),
          ),
        ],
        if (generating) ...[
          const SizedBox(height: 10),
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
                onPressed: _c.cancelBookGraphGeneration,
                icon: const Icon(KaijuanIcons.stop, size: 16),
                label: const Text('停止'),
              ),
            ],
          ),
        ] else if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: colors.error,
            ),
          ),
        ],
        if (!generating &&
            mainEntities.isNotEmpty &&
            _graphViewMode == _GraphViewMode.graph) ...[
          const SizedBox(height: 12),
          Stack(
            children: [
              BookAiGraphView(
                entities: graph.entities
                    .where(
                      (entity) =>
                          !gateByProgress || entity.firstSection <= readThrough,
                    )
                    .where(
                      (entity) => connectedNames.contains(entity.name),
                    )
                    .toList(growable: false),
                // Same spoiler gate as the family tree: hide edges whose
                // evidence is entirely in unread chapters.
                relations: graph.relations
                    .where(
                      (r) =>
                          !gateByProgress ||
                          r.evidence
                              .any((e) => e.sectionIndex <= readThrough),
                    )
                    .toList(growable: false),
                onVertexTap: _onGraphVertexTap,
                height: 300,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: context.appColors.surfaceContainerHighest
                      .withValues(alpha: 0.9),
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
          const SizedBox(height: 10),
        ],
        if (!generating &&
            mainEntities.isNotEmpty &&
            _graphViewMode == _GraphViewMode.familyTree) ...[
          const SizedBox(height: 12),
          _buildFamilyTreeView(context, graph, gateByProgress, readThrough),
          const SizedBox(height: 10),
        ],
        if (_graphViewMode != _GraphViewMode.graph &&
            _graphViewMode != _GraphViewMode.familyTree) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _graphQueryController,
                  onChanged: (value) =>
                      setState(() => _graphQuery = value),
                  decoration: InputDecoration(
                    hintText: '搜索',
                    isDense: true,
                    prefixIcon: const Icon(KaijuanIcons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_GraphSortOrder>(
                tooltip: '排序',
                initialValue: _graphSortOrder,
                onSelected: (order) => setState(
                  () => _graphSortOrders[_graphViewMode] = order,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _GraphSortOrder.byAppearance,
                    child: Text('出场顺序'),
                  ),
                  PopupMenuItem(
                    value: _GraphSortOrder.byFrequency,
                    child: Text('出现次数'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(KaijuanIcons.sort, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _graphSortLabel(_graphSortOrder),
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: context.appSecondaryText,
                        ),
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
                        ? '没有匹配的实体。'
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
                    entity.name,
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
                    entity.name,
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
            key: _graphEntityKeys.putIfAbsent(
              event.name,
              () => GlobalKey(),
            ),
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
    final detailNames = [
      ...familyTree.complexNames,
      ...familyTree.isolatedNames,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookAiGraphFamilyTreeView(
          tree: familyTree,
          onVertexTap: _showEntityDetailsByName,
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
                for (final name in detailNames)
                  ActionChip(
                    label: Text(name),
                    visualDensity: VisualDensity.compact,
                    // Tree mode renders no entity list rows, so the
                    // scroll-and-highlight path in _onGraphVertexTap has
                    // nothing to scroll to — go straight to the detail card
                    // (same as tapping a tree node).
                    onPressed: () => _showEntityDetailsByName(name),
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
      onToggle: () =>
          setState(() => _graphIsolatedExpanded = !expanded),
      expandedChildren: [
        for (final entity in isolated)
          KeyedSubtree(
            key: _graphEntityKeys.putIfAbsent(
              entity.name,
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
    );
  }

  /// Family-tree node tap: open the entity detail card directly (same as a
  /// list row tap). The tree canvas has no scroll target for the highlight-
  /// and-scroll path used by the list views, so we skip that and go straight
  /// to the detail sheet the user expects.
  void _showEntityDetailsByName(String name) {
    final graph = _c.bookGraph;
    if (graph == null) return;
    final match = graph.entities.where((e) => e.name == name);
    if (match.isNotEmpty) _showEntityDetails(match.first);
  }

  void _onGraphVertexTap(String name) {
    setState(() => _graphHighlighted = name);
    _graphHighlightTimer?.cancel();
    _graphHighlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _graphHighlighted = null);
    });
    final ctx = _graphEntityKeys[name]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.2,
      );
    }
  }

  void _openGraphFullscreen() {
    final graph = _c.bookGraph;
    if (graph == null) return;
    final readThrough = _c.sectionIndex + 1;
    final gateByProgress = !_allowUnread && graph.includesUnread;
    final connectedNames = <String>{
      for (final r in graph.relations) ...[r.source, r.target],
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiGraphFullscreen(
          title: _c.activeGraphWork != null
              ? '《${_c.activeGraphWork!.title}》图谱'
              : (graph.excludedGraphSections.isNotEmpty
                  ? '部分章节图谱'
                  : (_c.viewingWholeBookGraph ? '整本图谱' : '知识图谱')),
          entities: graph.entities
              .where(
                (entity) =>
                    !gateByProgress || entity.firstSection <= readThrough,
              )
              .where((entity) => connectedNames.contains(entity.name))
              .toList(growable: false),
          // Spoiler gate: hide edges whose evidence is unread-only.
          relations: graph.relations
              .where(
                (r) =>
                    !gateByProgress ||
                    r.evidence.any((e) => e.sectionIndex <= readThrough),
              )
              .toList(growable: false),
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
    final graph = _c.bookGraph;
    final relationCount = graph == null
        ? 0
        : graph.relations
            .where(
              (r) =>
                  (r.source == entity.name || r.target == entity.name) &&
                  (!gateByProgress ||
                      r.evidence.any((e) => e.sectionIndex <= readThrough)),
            )
            .length;
    return GraphEntityTile(
      entity: entity,
      relationCount: relationCount,
      typeColor: graphEntityTypeColor(context, entity.type),
      highlighted: _graphHighlighted == entity.name,
      bodySize: _panelBodySize(context),
      onTap: () => _showEntityDetails(entity),
    );
  }

  void _showEntityDetails(AiGraphEntity entity) {
    final graph = _c.bookGraph;
    if (graph == null) return;
    final readThrough = _c.sectionIndex + 1;
    final gateByProgress = !_allowUnread && graph.includesUnread;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => BookAiEntitySheet(
        entity: entity,
        graph: graph,
        gateByProgress: gateByProgress,
        readThrough: readThrough,
        titleSize: _panelTitleSize(context),
        bodySize: _panelBodySize(context),
        onOpenEvidence: _goToGraphEvidence,
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
    if (_graphWorks != null || _graphWorksLoading || !mounted) return;
    final sync = _c.graphWorkCandidates;
    if (sync != null) {
      setState(() => _graphWorks = sync);
      unawaited(_c.loadGraphActualSectionCounts());
      return;
    }
    if (_c.bookOutline != null) return; // has outline, not a collection
    _graphWorksLoading = true;
    final resolved = await _c.resolveGraphWorkCandidates();
    if (!mounted) return;
    _graphWorksLoading = false;
    if (resolved != null && resolved.isNotEmpty) {
      setState(() => _graphWorks = resolved);
      unawaited(_c.loadGraphActualSectionCounts());
    }
  }

  Future<void> _generateGraph({
    bool force = false,
    AiGraphWorkCandidate? work,
  }) async {
    if (!_ready || _c.isGeneratingBookGraph) return;
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
      await _c.generateBookGraph(
        only: work,
        force: force,
        // The dialog's plan was judged over the whole corpus; when the user
        // excluded any section, re-judge over the actual generation range so
        // the default view matches the content (a 散文 slice must not inherit
        // the collection's family_tree plan).
        narrationOverride:
            confirmed.excludedSections.isEmpty ? confirmed.plan : null,
        excludedGraphSectionIndices: confirmed.excludedSections.isEmpty
            ? null
            : confirmed.excludedSections,
      );
      return;
    }
    await _c.generateBookGraph(only: work, force: force);
  }

  /// Pre-generation confirm dialog: runs the step-0 display plan (features +
  /// recommended view, user may pick another default view) **and** the
  /// auto-filtered graph corpus with a manual section chooser (uncheck to
  /// exclude a chapter). Returns the confirmed plan (null = keep the default
  /// view) + excluded section indices. Null = cancelled.
  Future<({AiNarrationPlan? plan, Set<int> excludedSections})?>
      _confirmNarrationPlan(
    AiGraphWorkCandidate? work,
  ) {
    return showDialog<({AiNarrationPlan? plan, Set<int> excludedSections})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NarrationPlanDialog(
        controller: _c,
        work: work,
        // Reopen with the previous manual slice of the TARGET range (per-work
        // graphs keep their own exclusions; the picker's whole-book legacy
        // graph must not leak its exclusions into a fresh per-work dialog).
        initialExcluded:
            (work == null ? _c.bookGraph : _c.workGraphFor(work))
                    ?.excludedGraphSections.toSet() ??
                const {},
      ),
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

  String _graphGenerationSummary(AiBookGraph graph) {
    final time = graph.generatedAt?.toLocal();
    final timeText = time == null
        ? ''
        : '生成于 ${time.hour.toString().padLeft(2, '0')}:'
              '${time.minute.toString().padLeft(2, '0')}';
    final seconds = graph.generationSeconds;
    final durationText = seconds == null
        ? ''
        : '用时 ${seconds >= 60 ? '${seconds ~/ 60} 分 ${seconds % 60} 秒' : '$seconds 秒'}';
    final parts = [if (timeText.isNotEmpty) timeText, if (durationText.isNotEmpty) durationText];
    return parts.join(' · ');
  }

  /// Anchored entry for the work under the reading position: one tap opens
  /// that work's graph (or starts it). Only shown on the collection picker.
  Widget _buildCurrentReadingGraphCard(
    BuildContext context,
    AiGraphWorkCandidate reading,
  ) {
    final colors = context.appColors;
    final ready = _c.hasWorkGraph(reading);
    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.menu_book_outlined,
          size: 18,
          color: colors.primary,
        ),
        title: Text(
          '当前阅读：《${reading.title}》',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: context.appBodySize,
            fontWeight: FontWeight.w600,
            color: context.appPrimaryText,
          ),
        ),
        subtitle: Text(
          ready ? '这本的图谱已生成' : '生成本书的图谱',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
        trailing: Text(
          ready ? '查看' : '生成',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
        onTap: ready
            ? () => _c.openWorkGraph(reading)
            : () => unawaited(_generateGraph(work: reading)),
      ),
    );
  }

  /// Collection picker: one native ListTile per work (same visual language
  /// as the outline tab). Tapping opens the work's graph or starts it.
  Widget _buildGraphWorksList(
    BuildContext context,
    List<AiGraphWorkCandidate> works,
  ) {
    final generating = _c.isGeneratingBookGraph;
    final progress = _c.bookGraphProgress;
    return ListView(
      key: ValueKey<int>(_graphListEpoch),
      controller: _graphScrollController,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
          child: Text(
            '知识图谱',
            style: TextStyle(
              fontSize: _panelTitleSize(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 「读到哪本跟哪本」: the picker opens anchored to the work the
        // reader is currently inside — one tap enters that work's graph.
        if (_c.currentReadingWork case final AiGraphWorkCandidate? reading
            when reading != null) ...[
          _buildCurrentReadingGraphCard(context, reading),
          const SizedBox(height: 4),
        ],
        if (generating) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
            child: Row(
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
                  onPressed: _c.cancelBookGraphGeneration,
                  icon: const Icon(KaijuanIcons.stop, size: 16),
                  label: const Text('停止'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        // Core: one native ListTile per work, no separators — spacing and
        // the shared leading edge carry the structure (outline-tab language).
        for (final work in works) _buildGraphWorkRow(context, work),
        // Legacy whole-book graph ($hash.json, pre-per-work files) is a
        // fallback row, kept last per importance ordering.
        if (_c.bookGraph != null) ...[
          const SizedBox(height: 8),
          _buildWholeBookGraphRow(context),
        ],
      ],
    );
  }

  Widget _buildWholeBookGraphRow(BuildContext context) {
    final colors = context.appColors;
    final graph = _c.bookGraph!;
    final range = graph.excludedGraphSections.isNotEmpty
        ? '已排除 ${graph.excludedGraphSections.length} 节'
        : (graph.includesUnread ? '全书' : '已读');
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 2, 4, 2),
      leading: Icon(
        KaijuanIcons.collections,
        size: 18,
        color: context.appSecondaryText,
      ),
      title: Text(
        graph.excludedGraphSections.isNotEmpty ? '部分章节图谱' : '整本图谱',
        style: TextStyle(
          fontSize: _panelBodySize(context),
          fontWeight: FontWeight.w600,
          color: context.appPrimaryText,
        ),
      ),
      subtitle: Text(
        range,
        style: TextStyle(
          fontSize: context.appCaptionSize,
          color: context.appSecondaryText,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '已生成',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            KaijuanIcons.chevronRight,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _c.openWholeBookGraph(),
    );
  }

  Widget _buildGraphWorkRow(BuildContext context, AiGraphWorkCandidate work) {
    final colors = context.appColors;
    final key = BookReaderController.workKeyFor(work);
    final ready = _c.hasWorkGraph(work);
    final generatingWork = _c.generatingGraphWork;
    final generatingThis = generatingWork != null &&
        BookReaderController.workKeyFor(generatingWork) == key;
    final busy = generatingThis || _c.isGeneratingBookGraph;
    final dimmed = busy && !generatingThis;
    final actual = _c.graphActualSectionCounts?[key];
    final String range;
    if (actual != null) {
      range = '$actual 节';
    } else if (work.isOpenEnded) {
      range = '至书末';
    } else if (_c.graphActualSectionCounts != null) {
      // Count pass finished but this row has no data (fallback path):
      // show the spine-range estimate rather than a stale placeholder.
      range = '${work.sectionCount} 节';
    } else {
      range = '计算中';
    }
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 2, 4, 2),
        leading: Icon(
          KaijuanIcons.collections,
          size: 18,
          color: context.appSecondaryText,
        ),
        title: Text(
          work.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _panelBodySize(context),
            fontWeight: FontWeight.w600,
            color: context.appPrimaryText,
          ),
        ),
        subtitle: Text(
          range,
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (generatingThis)
              SizedBox(
                width: 20,
                height: 20,
                child: _thinkingOrb(context),
              )
            else
              Text(
                ready ? '已生成' : '生成',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              KaijuanIcons.chevronRight,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
        onTap: generatingThis
            ? () => _c.enterGraphWork(work)
            : busy
                ? null
                : () {
                    if (ready) {
                      _c.openWorkGraph(work);
                    } else {
                      unawaited(_generateGraph(work: work));
                    }
                  },
      ),
    );
  }

  Widget _graphBackRow() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _c.closeWorkGraph,
      icon: const Icon(KaijuanIcons.back, size: 16),
      label: const Text('全部著作'),
    ),
  );

  /// Inline thinking indicator, same animation family as the chat bubbles.
  Widget _thinkingOrb(BuildContext context) => ThinkingOrb(
    state: OrbState.working,
    size: OrbSize.size20,
    theme: Theme.of(context).brightness == Brightness.dark
        ? OrbTheme.dark
        : OrbTheme.light,
  );

  String _graphSortLabel(_GraphSortOrder order) => switch (order) {
    _GraphSortOrder.byAppearance => '出场顺序',
    _GraphSortOrder.byFrequency => '出现次数',
  };

  @override
  void dispose() {
    _c.removeListener(_onReaderControllerChanged);
    _cancel.cancel();
    _suggestionCancel?.cancel();
    unawaited(_sub?.cancel() ?? Future<void>.value());
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
        _error == null &&
        _session.messages.isNotEmpty &&
        _session.messages.last.role == AiMessageRole.assistant;
    final followUpShortcuts = aiChatFollowUpShortcuts(
      hasSelection: hasSelection,
      generatedQuestions: showFollowUpShortcuts
          ? _session.messages.last.suggestedQuestions
          : const [],
    );

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
                  _session.messages.isNotEmpty)
                IconButton(
                  tooltip: '清空对话',
                  onPressed: _sending || _clearingHistory
                      ? null
                      : () => unawaited(_clearHistory()),
                  icon: const Icon(KaijuanIcons.delete, size: 20),
                ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).maybePop(),
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
              Tab(text: '大纲'),
              Tab(text: '知识图谱'),
            ],
          ),
        ),
        if (_activeTab == _BookAiWorkspaceTab.outline)
          Expanded(child: _buildOutlineTab(context))
        else if (_activeTab == _BookAiWorkspaceTab.graph)
          Expanded(child: _buildGraphTab(context))
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
                : ListView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      compact ? 0 : 4,
                      16,
                      compact ? 8 : 12,
                    ),
                    children: [
                      if (_c.hasCollectionWorks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                '对话范围',
                                style: TextStyle(
                                  fontSize: context.appCaptionSize,
                                  color: context.appSecondaryText,
                                ),
                              ),
                              const Spacer(),
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('当前作品'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('全书'),
                                  ),
                                ],
                                selected: {_c.chatScopeWholeBook},
                                onSelectionChanged: (selection) => setState(
                                  () => _c.chatScopeWholeBook =
                                      selection.first,
                                ),
                                showSelectedIcon: false,
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: WidgetStatePropertyAll(
                                    TextStyle(
                                      fontSize: context.appCaptionSize,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Semantics(
                        container: true,
                        liveRegion: true,
                        label: _liveStatus,
                        child: const SizedBox.shrink(),
                      ),
                      if (_session.messages.isEmpty &&
                          _streaming.isEmpty &&
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
                                  height: 1.5,
                                  color: context.appSecondaryText,
                                ),
                              ),
                              if (openingShortcuts.isNotEmpty) ...[
                                SizedBox(height: compact ? 12 : 16),
                                _SuggestedQuestionList(
                                  shortcuts: openingShortcuts,
                                  onSelected: (shortcut) =>
                                      unawaited(_send(shortcut.prompt)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      for (final msg in _session.messages)
                        _Bubble(
                          message: msg,
                          onCopy: () => unawaited(_copy(msg.content)),
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
                      if (_streaming.isNotEmpty)
                        _Bubble(
                          message: AiChatMessage(
                            role: AiMessageRole.assistant,
                            content: _streaming,
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
                          onDeleted: _sending
                              ? null
                              : () => setState(() => _selection = null),
                          deleteIcon: const Icon(KaijuanIcons.close, size: 16),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_sending)
                      IconButton.filledTonal(
                        tooltip: '停止',
                        onPressed: _stop,
                        icon: Icon(
                          KaijuanIcons.stopFilled,
                          color: colors.error,
                        ),
                      )
                    else
                      IconButton.filled(
                        tooltip: '发送',
                        onPressed: () => unawaited(_send()),
                        icon: const Icon(KaijuanIcons.sendFilled, size: 20),
                      ),
                  ],
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
  const _AiUnavailable({required this.message, required this.onOpenSettings});

  final String message;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: context.appBodySize,
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

class _InlineOutlineOverviewToggle extends StatelessWidget {
  const _InlineOutlineOverviewToggle({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = expanded ? '收起完整概览' : '展开完整概览';
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 2, 4),
              child: Icon(
                expanded ? KaijuanIcons.chevronUp : KaijuanIcons.chevronDown,
                size: 16,
                color: context.appSecondaryText,
              ),
            ),
          ),
        ),
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
              minimumSize: const Size(40, 40),
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
                color: colors.surfaceContainerHighest.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
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
                                  ? 14
                                  : context.appBodySecondarySize,
                              color: context.appPrimaryText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          KaijuanIcons.chevronRight,
                          size: compact ? 16 : 18,
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
  const _Bubble({required this.message, this.onCopy, this.streaming = false});

  final AiChatMessage message;
  final VoidCallback? onCopy;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiMessageRole.user;
    final bg = isUser
        ? context.appColors.primary.withValues(alpha: 0.14)
        : Colors.transparent;
    final webHits = message.webHitCount;
    final compact = context.appIsCompact;
    final maxWidth = MediaQuery.sizeOf(context).width * (isUser ? 0.76 : 0.92);

    final bubble = Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 14),
      padding: EdgeInsets.fromLTRB(
        isUser ? (compact ? 12 : 14) : 4,
        isUser ? (compact ? 8 : 10) : 4,
        isUser ? (compact ? 12 : 14) : 4,
        isUser ? (compact ? 8 : 10) : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiResultBody(text: message.content, compact: compact),
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
          if (!isUser && !streaming && onCopy != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '复制本条回答',
                onPressed: onCopy,
                icon: const Icon(KaijuanIcons.copy, size: 16),
                style: IconButton.styleFrom(
                  foregroundColor: context.appSecondaryText,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.square(compact ? 32 : 36),
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

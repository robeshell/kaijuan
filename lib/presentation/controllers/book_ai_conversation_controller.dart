import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_session_ops.dart';
import '../../ai/ai_chat_tools.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_conversation_intent.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_provider_kind.dart';
import '../../ai/ai_product_action.dart';
import '../../ai/ai_rich_content_inspector.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_search.dart';

typedef AiChatSessionWriter = Future<void> Function(AiChatSession session);

class BookAiTurnStart {
  const BookAiTurnStart({
    required this.turnId,
    required this.workKey,
    required this.history,
  });

  final String turnId;
  final String? workKey;
  final List<AiChatMessage> history;
}

class BookAiTurnCompletion {
  const BookAiTurnCompletion({
    required this.body,
    required this.reasoning,
    required this.reasoningKind,
    this.assistantIndex,
  });

  final String body;
  final String reasoning;
  final AiReasoningContentKind reasoningKind;
  final int? assistantIndex;
}

sealed class BookAiRunOutcome {
  const BookAiRunOutcome();
}

final class BookAiRunCompletedOutcome extends BookAiRunOutcome {
  const BookAiRunCompletedOutcome(this.completion);

  final BookAiTurnCompletion completion;
}

final class BookAiRunProductActionOutcome extends BookAiRunOutcome {
  const BookAiRunProductActionOutcome(this.request);

  final AiProductActionRequest request;
}

final class BookAiRunFailedOutcome extends BookAiRunOutcome {
  const BookAiRunFailedOutcome(
    this.error, {
    this.phase = BookAiRunFailurePhase.model,
  });

  final Object error;
  final BookAiRunFailurePhase phase;
}

final class BookAiRunCancelledOutcome extends BookAiRunOutcome {
  const BookAiRunCancelledOutcome();
}

enum BookAiRunFailurePhase { webSearch, model }

typedef BookAiWebSearch = Future<List<AiWebSearchHit>> Function();
typedef BookAiRuntimeStarter =
    Stream<AiRunEvent>? Function(
      BookAiTurnStart turn,
      List<AiWebSearchHit>? webHits,
    );

/// Owns the durable conversation projection for one open book workspace.
///
/// Model/provider calls stay behind [AiAgentRuntime]. This controller owns the
/// App-facing turn lifecycle: bounded messages, run snapshots, retry identity,
/// partial-answer checkpoints, completion/failure/cancellation and persistence.
/// It deliberately knows nothing about widgets, reader WebViews or product
/// workflow implementations.
class BookAiConversationController extends ChangeNotifier {
  BookAiConversationController(
    this._saveSession, {
    DateTime Function()? now,
    this.maxStoredMessages = 100,
  }) : _now = now ?? DateTime.now;

  final AiChatSessionWriter _saveSession;
  final DateTime Function() _now;
  final int maxStoredMessages;

  AiChatSession _session = const AiChatSession(contentHash: '', itemId: '');
  AiChatSession get session => _session;

  bool _sending = false;
  bool get sending => _sending;

  bool _searchingWeb = false;
  bool get searchingWeb => _searchingWeb;

  int? _lastWebHitCount;
  int? get lastWebHitCount => _lastWebHitCount;

  AiRunState? _runState;
  AiRunState? get runState => _runState;

  String _streaming = '';
  String get streaming => _streaming;

  String _streamingReasoning = '';
  String get streamingReasoning => _streamingReasoning;

  AiReasoningContentKind _streamingReasoningKind =
      AiReasoningContentKind.process;
  AiReasoningContentKind get streamingReasoningKind => _streamingReasoningKind;

  String? _toolStatus;
  String? get toolStatus => _toolStatus;

  /// Completed / in-flight tool steps for the active turn (timeline UI).
  final List<AiChatToolStep> _toolSteps = [];
  List<AiChatToolStep> get toolSteps => List.unmodifiable(_toolSteps);

  Object? _failure;
  Object? get failure => _failure;

  String? _retryText;
  String? get retryText => _retryText;

  String? _retryTurnId;
  String? get retryTurnId => _retryTurnId;

  String? _activeTurnId;
  String? get activeTurnId => _activeTurnId;

  String? _activeTurnWorkKey;
  String? get activeTurnWorkKey => _activeTurnWorkKey;

  Timer? _checkpointTimer;
  StreamSubscription<AiRunEvent>? _runSubscription;
  Completer<BookAiRunOutcome>? _runCompleter;
  DateTime? _lastCheckpointAt;
  /// Bumped on every durable session write start so a late checkpoint cannot
  /// overwrite a product-action wipe or map projection.
  int _sessionWriteEpoch = 0;
  bool _disposed = false;

  List<AiChatMessage> messagesFor(String? workKey) =>
      _session.messagesFor(workKey);

  void hydrate(AiChatSession session) {
    _session = session;
    notifyListeners();
  }

  Future<void> persist() {
    // Invalidate in-flight checkpoints before writing the live session.
    _sessionWriteEpoch++;
    return _saveSession(_session);
  }

  BookAiTurnStart beginTurn({
    required String turnId,
    required String? workKey,
    required String text,
    required bool wantsWebSearch,
    bool retrying = false,
    String? retryTurnId,
    AiConversationCommand? command,
  }) {
    final history = List<AiChatMessage>.from(_session.messagesFor(workKey));
    if (retryTurnId != null) {
      // User/assistant turn plus session mind-map projections
      // (`$turnId-mind-map-N`) from the failed run.
      history.removeWhere((message) {
        final id = message.turnId;
        if (id == null) return false;
        return id == retryTurnId || id.startsWith('$retryTurnId-mind-map-');
      });
      _session = _session.withMessagesFor(workKey, history);
    } else if (retrying) {
      if (history.isNotEmpty && history.last.role == AiMessageRole.assistant) {
        history.removeLast();
      }
      if (history.isNotEmpty &&
          history.last.role == AiMessageRole.user &&
          history.last.content.trim() == text) {
        history.removeLast();
      }
      _session = _session.withMessagesFor(workKey, history);
    }
    _activeTurnId = turnId;
    _activeTurnWorkKey = workKey;
    _session = _append(
      AiChatMessage(
        role: AiMessageRole.user,
        content: text,
        createdAt: _now(),
        webHitCount: wantsWebSearch ? 0 : null,
        turnId: turnId,
        status: AiChatTurnStatus.pending,
        command: command,
      ),
      workKey: workKey,
    );
    _sending = true;
    _searchingWeb = wantsWebSearch;
    _lastWebHitCount = null;
    _failure = null;
    _retryText = null;
    _retryTurnId = null;
    _streaming = '';
    _streamingReasoning = '';
    _streamingReasoningKind = AiReasoningContentKind.process;
    _toolStatus = null;
    _toolSteps.clear();
    _runState = null;
    notifyListeners();
    unawaited(persist());
    return BookAiTurnStart(
      turnId: turnId,
      workKey: workKey,
      history: List.unmodifiable(history),
    );
  }

  void completeWebSearch(int hitCount) {
    final turnId = _activeTurnId;
    final workKey = _activeTurnWorkKey;
    if (turnId == null) return;
    final messages = List<AiChatMessage>.from(_session.messagesFor(workKey));
    final index = messages.lastIndexWhere(
      (message) =>
          message.role == AiMessageRole.user && message.turnId == turnId,
    );
    if (index >= 0) {
      messages[index] = messages[index].copyWith(webHitCount: hitCount);
      _session = _session.withMessagesFor(workKey, messages);
    }
    _searchingWeb = false;
    _lastWebHitCount = hitCount;
    notifyListeners();
    unawaited(persist());
  }

  /// Applies one App-owned run event. Returns true for visible text/reasoning
  /// snapshots so the view can decide whether to follow the message tail.
  bool applyRunEvent(AiRunEvent event) {
    final current = switch (event) {
      AiRunStarted(:final descriptor) => AiRunState.initial(descriptor),
      _ => _runState,
    };
    if (current == null) return false;
    if (event is AiRunToolStarted) {
      // One timeline row per tool call (same name may run many times).
      if (_toolSteps.isNotEmpty && !_toolSteps.last.done) {
        _toolSteps[_toolSteps.length - 1] = _toolSteps.last.copyWith(
          done: true,
        );
      }
      for (final name in event.toolNames) {
        _toolSteps.add(
          AiChatToolStep(label: AiChatTools.displayNameFor(name), done: false),
        );
      }
    } else if (event is AiRunToolCompleted) {
      for (var i = 0; i < _toolSteps.length; i++) {
        if (!_toolSteps[i].done) {
          _toolSteps[i] = _toolSteps[i].copyWith(done: true);
        }
      }
    }
    final next = current.apply(event);
    _runState = next;
    _streaming = next.text;
    _streamingReasoning = next.reasoningText;
    _streamingReasoningKind = next.reasoningKind;
    _toolStatus = next.status;
    final isSnapshot =
        event is AiRunTextSnapshot || event is AiRunReasoningSnapshot;
    if (isSnapshot) _scheduleCheckpoint();
    notifyListeners();
    return isSnapshot;
  }

  Future<BookAiRunOutcome> consumeRun(
    Stream<AiRunEvent> stream, {
    void Function()? onSnapshot,
  }) {
    if (_runSubscription != null || _runCompleter != null) {
      throw StateError('A conversation run is already active');
    }
    final completer = Completer<BookAiRunOutcome>();
    _runCompleter = completer;
    AiProductActionRequest? productAction;
    var terminal = false;

    void finish(BookAiRunOutcome outcome) {
      if (terminal) return;
      terminal = true;
      _runSubscription = null;
      _runCompleter = null;
      if (!completer.isCompleted) completer.complete(outcome);
    }

    void fail(Object error) {
      if (terminal) return;
      failActiveTurn(error);
      finish(BookAiRunFailedOutcome(error));
    }

    _runSubscription = stream.listen(
      (event) {
        if (terminal) return;
        final isSnapshot = applyRunEvent(event);
        if (isSnapshot) onSnapshot?.call();
        switch (event) {
          case AiRunProductActionRequested(:final request):
            productAction = request;
          case AiRunFailed(:final error):
            fail(error);
          case AiRunCancelled():
            cancelActiveTurn();
            finish(const BookAiRunCancelledOutcome());
          default:
            break;
        }
      },
      onError: fail,
      onDone: () {
        if (terminal) return;
        final action = productAction;
        if (action != null) {
          finishWithProductAction();
          finish(BookAiRunProductActionOutcome(action));
          return;
        }
        finish(BookAiRunCompletedOutcome(completeActiveTurn()));
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  /// Runs one complete conversational transaction after the caller has
  /// frozen its reader/product context.
  ///
  /// Search and runtime callbacks are capability adapters only. Their
  /// lifecycle, failure terminal, retry identity and persistence remain owned
  /// here so the Widget cannot accidentally create a second run state machine.
  Future<BookAiRunOutcome> runTurn({
    required String turnId,
    required String? workKey,
    required String text,
    required bool wantsWebSearch,
    required BookAiRuntimeStarter startRuntime,
    BookAiWebSearch? searchWeb,
    CancelToken? cancelToken,
    bool retrying = false,
    String? retryTurnId,
  }) async {
    final turn = beginTurn(
      turnId: turnId,
      workKey: workKey,
      text: text,
      wantsWebSearch: wantsWebSearch,
      retrying: retrying,
      retryTurnId: retryTurnId,
    );
    List<AiWebSearchHit>? webHits;
    if (wantsWebSearch) {
      try {
        final search = searchWeb;
        if (search == null) {
          throw StateError('Web search capability is unavailable');
        }
        webHits = await search();
        completeWebSearch(webHits.length);
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) {
          cancelActiveTurn();
          return const BookAiRunCancelledOutcome();
        }
        failActiveTurn(error);
        return BookAiRunFailedOutcome(
          error,
          phase: BookAiRunFailurePhase.webSearch,
        );
      }
    }
    if (cancelToken?.isCancelled ?? false) {
      cancelActiveTurn();
      return const BookAiRunCancelledOutcome();
    }
    try {
      final stream = startRuntime(turn, webHits);
      if (stream == null) {
        throw StateError('AI 未启用或未配置');
      }
      return await consumeRun(stream);
    } catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        cancelActiveTurn();
        return const BookAiRunCancelledOutcome();
      }
      failActiveTurn(error);
      return BookAiRunFailedOutcome(error);
    }
  }

  Future<void> cancelRun({
    bool commitPartial = true,
    bool persistAfter = true,
  }) async {
    final subscription = _runSubscription;
    _runSubscription = null;
    final completer = _runCompleter;
    _runCompleter = null;
    cancelActiveTurn(commitPartial: commitPartial, persistAfter: persistAfter);
    if (completer != null && !completer.isCompleted) {
      completer.complete(const BookAiRunCancelledOutcome());
    }
    try {
      await subscription?.cancel();
    } catch (_) {
      // State and persistence are already terminal; transport cleanup cannot
      // resurrect the run.
    }
  }

  void failActiveTurn(Object error) {
    final turnId = _activeTurnId;
    final workKey = _activeTurnWorkKey;
    if (turnId == null) return;
    _cancelCheckpoint();
    _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: workKey);
    final hasProse =
        _streaming.trim().isNotEmpty || _streamingReasoning.trim().isNotEmpty;
    if (hasProse || _toolSteps.isNotEmpty) {
      _commitAssistant(
        hasProse ? _streaming : '（未生成文字回答）',
        reasoningContent: _streamingReasoning,
        reasoningKind: _streamingReasoningKind,
        workKey: workKey,
        turnId: turnId,
        status: AiChatTurnStatus.failed,
      );
    }
    _failure = error;
    _retryText = _userTextForTurn(turnId, workKey: workKey);
    _retryTurnId = turnId;
    _resetActiveTurn();
    notifyListeners();
    unawaited(persist());
  }

  BookAiTurnCompletion completeActiveTurn() {
    final turnId = _activeTurnId;
    final workKey = _activeTurnWorkKey;
    if (turnId == null) {
      return const BookAiTurnCompletion(
        body: '',
        reasoning: '',
        reasoningKind: AiReasoningContentKind.process,
      );
    }
    _cancelCheckpoint();
    final body = _streaming.trim();
    final reasoning = _streamingReasoning.trim();
    final reasoningKind = _streamingReasoningKind;
    int? assistantIndex;
    if (body.isNotEmpty) {
      _setTurnStatus(turnId, AiChatTurnStatus.completed, workKey: workKey);
      _commitAssistant(
        body,
        reasoningContent: reasoning,
        reasoningKind: reasoningKind,
        workKey: workKey,
        turnId: turnId,
      );
      assistantIndex = _session.messagesFor(workKey).length - 1;
      _retryText = null;
      _retryTurnId = null;
      _failure = null;
    } else if (_toolSteps.isNotEmpty) {
      // Tools ran but no prose — still persist the timeline for S7 visibility.
      _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: workKey);
      _commitAssistant(
        '（未生成文字回答）',
        workKey: workKey,
        turnId: turnId,
        status: AiChatTurnStatus.failed,
      );
      _failure = StateError('没有生成内容，请重试');
      _retryText = _userTextForTurn(turnId, workKey: workKey);
      _retryTurnId = turnId;
    } else {
      _setTurnStatus(turnId, AiChatTurnStatus.failed, workKey: workKey);
      _failure = StateError('没有生成内容，请重试');
      _retryText = _userTextForTurn(turnId, workKey: workKey);
      _retryTurnId = turnId;
    }
    _resetActiveTurn();
    notifyListeners();
    unawaited(persist());
    return BookAiTurnCompletion(
      body: body,
      reasoning: reasoning,
      reasoningKind: reasoningKind,
      assistantIndex: assistantIndex,
    );
  }

  void finishWithProductAction() {
    final turnId = _activeTurnId;
    final workKey = _activeTurnWorkKey;
    if (turnId == null) return;
    // Drop any in-flight prose checkpoint for this chat turn so a later
    // checkpoint write cannot resurrect a free-chat imitation beside the map.
    _cancelCheckpoint();
    final messages = List<AiChatMessage>.from(_session.messagesFor(workKey))
      ..removeWhere((message) => message.turnId == turnId);
    _session = _session.withMessagesFor(workKey, messages);
    _failure = null;
    _retryText = null;
    _retryTurnId = null;
    _resetActiveTurn();
    notifyListeners();
    unawaited(persist());
  }

  void cancelActiveTurn({bool commitPartial = true, bool persistAfter = true}) {
    final turnId = _activeTurnId;
    final workKey = _activeTurnWorkKey;
    if (turnId == null) return;
    _cancelCheckpoint();
    _setTurnStatus(turnId, AiChatTurnStatus.cancelled, workKey: workKey);
    final hasProse =
        _streaming.trim().isNotEmpty || _streamingReasoning.trim().isNotEmpty;
    if (commitPartial && (hasProse || _toolSteps.isNotEmpty)) {
      _commitAssistant(
        hasProse ? _streaming : '（已停止）',
        reasoningContent: _streamingReasoning,
        reasoningKind: _streamingReasoningKind,
        workKey: workKey,
        turnId: turnId,
        status: AiChatTurnStatus.cancelled,
      );
    }
    _resetActiveTurn();
    notifyListeners();
    if (persistAfter) unawaited(persist());
  }

  void replaceMessages(String? workKey, List<AiChatMessage> messages) {
    _session = _session.withMessagesFor(workKey, messages);
    notifyListeners();
  }

  void appendMessage(AiChatMessage message, {String? workKey}) {
    _session = _append(message, workKey: workKey);
    notifyListeners();
  }

  /// Removes messages with [turnId] from the given work scope only.
  ///
  /// Used to unstage a failed mind-map projection without wiping concurrent
  /// session edits (cancel, layout, other turns) that landed during persist.
  void removeMessagesWithTurnId(String turnId, {String? workKey}) {
    final history = _session.messagesFor(workKey);
    final next = history
        .where((message) => message.turnId != turnId)
        .toList(growable: false);
    if (next.length == history.length) return;
    _session = _session.withMessagesFor(workKey, next);
    notifyListeners();
  }

  /// True when a durable mind-map message already projects [artifactId].
  bool hasMindMapArtifact(String artifactId, {String? workKey}) {
    for (final message in _session.messagesFor(workKey)) {
      final map = message.mindMap;
      if (map == null) continue;
      final id = map.artifactId ?? message.turnId;
      if (id == artifactId) return true;
    }
    return false;
  }

  void finishProductTurn({
    required String turnId,
    required String? workKey,
    required AiChatTurnStatus status,
    Object? error,
    bool allowRetry = false,
  }) {
    if (_activeTurnId != turnId || _activeTurnWorkKey != workKey) return;
    _cancelCheckpoint();
    _setTurnStatus(turnId, status, workKey: workKey);
    _failure = error;
    if (allowRetry && status == AiChatTurnStatus.failed) {
      _retryText = _userTextForTurn(turnId, workKey: workKey);
      _retryTurnId = turnId;
    } else {
      _retryText = null;
      _retryTurnId = null;
    }
    _resetActiveTurn();
    notifyListeners();
    unawaited(persist());
  }

  void clearMessages({required String? workKey, AiChatSession? emptySession}) {
    _cancelCheckpoint();
    _session = workKey == null
        ? (emptySession ?? const AiChatSession(contentHash: '', itemId: ''))
        : _session.withMessagesFor(workKey, const []);
    _failure = null;
    _retryText = null;
    _retryTurnId = null;
    _resetActiveTurn();
    notifyListeners();
  }

  void _scheduleCheckpoint() {
    if (!_sending ||
        _activeTurnId == null ||
        (_streaming.trim().isEmpty && _streamingReasoning.trim().isEmpty) ||
        (_checkpointTimer?.isActive ?? false)) {
      return;
    }
    final elapsed = _lastCheckpointAt == null
        ? const Duration(days: 1)
        : _now().difference(_lastCheckpointAt!);
    const interval = Duration(seconds: 2);
    if (elapsed >= interval) {
      _writeCheckpoint();
      return;
    }
    _checkpointTimer = Timer(interval - elapsed, _writeCheckpoint);
  }

  void _writeCheckpoint() {
    _checkpointTimer = null;
    final turnId = _activeTurnId;
    if (!_sending ||
        turnId == null ||
        (_streaming.trim().isEmpty && _streamingReasoning.trim().isEmpty)) {
      return;
    }
    _lastCheckpointAt = _now();
    final snapshot = AiChatSessionOps.appendBounded(
      _session,
      AiChatMessage(
        role: AiMessageRole.assistant,
        content: _streaming.trim(),
        reasoningContent: _streamingReasoning.trim(),
        reasoningKind: _streamingReasoningKind,
        createdAt: _now(),
        turnId: turnId,
        status: AiChatTurnStatus.pending,
        toolSteps: [
          for (final step in _toolSteps) step.copyWith(done: true),
        ],
      ),
      workKey: _activeTurnWorkKey,
      maxMessages: maxStoredMessages,
    );
    final epoch = _sessionWriteEpoch;
    unawaited(() async {
      // Product-action wipe / map projection may have advanced the epoch.
      if (epoch != _sessionWriteEpoch) return;
      await _saveSession(snapshot);
    }());
  }

  void _cancelCheckpoint() {
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _lastCheckpointAt = null;
  }

  AiChatSession _append(AiChatMessage message, {String? workKey}) =>
      AiChatSessionOps.appendBounded(
        _session,
        message,
        workKey: workKey,
        maxMessages: maxStoredMessages,
      );

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

  void _commitAssistant(
    String body, {
    required String turnId,
    String? workKey,
    String reasoningContent = '',
    AiReasoningContentKind reasoningKind = AiReasoningContentKind.process,
    AiChatTurnStatus status = AiChatTurnStatus.completed,
  }) {
    final steps = [
      for (final step in _toolSteps) step.copyWith(done: true),
    ];
    _session = _append(
      AiChatMessage(
        role: AiMessageRole.assistant,
        content: body.trim(),
        reasoningContent: reasoningContent.trim(),
        reasoningKind: reasoningKind,
        createdAt: _now(),
        turnId: turnId,
        status: status,
        richArtifactKind: inspectAiRichArtifact(body),
        toolSteps: steps,
      ),
      workKey: workKey,
    );
  }

  String? _userTextForTurn(String turnId, {String? workKey}) {
    for (final message in _session.messagesFor(workKey).reversed) {
      if (message.turnId == turnId && message.role == AiMessageRole.user) {
        return message.content;
      }
    }
    return null;
  }

  void _resetActiveTurn() {
    _sending = false;
    _searchingWeb = false;
    _toolStatus = null;
    // Live steps are snapshotted onto the assistant message in [_commitAssistant].
    _toolSteps.clear();
    _runState = null;
    _streaming = '';
    _streamingReasoning = '';
    _streamingReasoningKind = AiReasoningContentKind.process;
    _activeTurnId = null;
    _activeTurnWorkKey = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelCheckpoint();
    unawaited(cancelRun());
    super.dispose();
  }
}

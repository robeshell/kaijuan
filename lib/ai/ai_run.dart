import 'ai_provider_kind.dart';

/// App-owned task categories. Provider/framework-specific concepts must not
/// leak into this contract.
enum AiRunTask {
  bookChat,
  bookOutline,
  bookMindMap,
  bookGraph,
  bookTranslation,
  language,
}

/// Frozen book/work boundary for one run.
///
/// [contentHash] is optional only for lower-level/transient callers. Product
/// entry points should always provide it so persistence and recovery can bind
/// the run to the same book identity.
class AiRunScope {
  const AiRunScope({this.contentHash, this.workKey, this.label});

  final String? contentHash;
  final String? workKey;
  final String? label;
}

class AiRunDescriptor {
  const AiRunDescriptor({
    required this.runId,
    required this.task,
    required this.scope,
  });

  final String runId;
  final AiRunTask task;
  final AiRunScope scope;
}

/// Current deterministic projection of an [AiRunEvent] stream.
enum AiRunPhase {
  preparing,
  requestingModel,
  runningTool,
  generating,
  continuing,
  completed,
  failed,
  cancelled,
}

enum AiRunModelPurpose { toolDecision, answer, continuation, workflowStep }

/// Provider-neutral counters owned by the app runtime.
///
/// Token counts remain optional until an adapter can report them reliably;
/// deterministic call/round/character budgets never depend on provider
/// accounting.
class AiRunUsage {
  const AiRunUsage({
    this.modelCalls = 0,
    this.toolRounds = 0,
    this.continuationRounds = 0,
    this.toolResultChars = 0,
    this.inputTokens,
    this.outputTokens,
  });

  final int modelCalls;
  final int toolRounds;
  final int continuationRounds;
  final int toolResultChars;
  final int? inputTokens;
  final int? outputTokens;

  AiRunUsage copyWith({
    int? modelCalls,
    int? toolRounds,
    int? continuationRounds,
    int? toolResultChars,
    int? inputTokens,
    int? outputTokens,
  }) => AiRunUsage(
    modelCalls: modelCalls ?? this.modelCalls,
    toolRounds: toolRounds ?? this.toolRounds,
    continuationRounds: continuationRounds ?? this.continuationRounds,
    toolResultChars: toolResultChars ?? this.toolResultChars,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
  );
}

sealed class AiRunEvent {
  const AiRunEvent({
    required this.runId,
    required this.sequence,
    required this.occurredAt,
  });

  final String runId;
  final int sequence;
  final DateTime occurredAt;
}

final class AiRunStarted extends AiRunEvent {
  AiRunStarted({
    required this.descriptor,
    required super.sequence,
    required super.occurredAt,
  }) : super(runId: descriptor.runId);

  final AiRunDescriptor descriptor;
}

final class AiRunScopeResolved extends AiRunEvent {
  const AiRunScopeResolved({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.scope,
  });

  final AiRunScope scope;
}

final class AiRunModelStarted extends AiRunEvent {
  const AiRunModelStarted({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.purpose,
    required this.callIndex,
  });

  final AiRunModelPurpose purpose;
  final int callIndex;
}

final class AiRunToolStarted extends AiRunEvent {
  const AiRunToolStarted({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.round,
    required this.toolNames,
    required this.status,
  });

  final int round;
  final List<String> toolNames;
  final String status;
}

final class AiRunToolCompleted extends AiRunEvent {
  const AiRunToolCompleted({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.round,
    required this.toolNames,
    required this.observationChars,
  });

  final int round;
  final List<String> toolNames;
  final int observationChars;
}

final class AiRunContinuationStarted extends AiRunEvent {
  const AiRunContinuationStarted({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.round,
    required this.maxRounds,
  });

  final int round;
  final int maxRounds;
}

/// Auxiliary human-readable progress. A null value clears the current label.
final class AiRunProgressUpdated extends AiRunEvent {
  const AiRunProgressUpdated({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.status,
  });

  final String? status;
}

final class AiRunUsageUpdated extends AiRunEvent {
  const AiRunUsageUpdated({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.usage,
  });

  final AiRunUsage usage;
}

/// The complete answer visible at this point, not a token delta.
///
/// Consumers replace their current text with [text]. This permits a native
/// tool preface to be retracted and continuation stitching to remove overlap.
final class AiRunTextSnapshot extends AiRunEvent {
  const AiRunTextSnapshot({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.text,
  });

  final String text;
}

/// The complete provider-visible reasoning available at this point.
///
/// This is deliberately independent from [AiRunTextSnapshot], so UI and
/// persistence cannot accidentally treat reasoning as answer Markdown.
final class AiRunReasoningSnapshot extends AiRunEvent {
  const AiRunReasoningSnapshot({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.text,
    required this.kind,
  });

  final String text;
  final AiReasoningContentKind kind;
}

final class AiRunCompleted extends AiRunEvent {
  const AiRunCompleted({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.text,
  });

  final String text;
}

final class AiRunFailed extends AiRunEvent {
  const AiRunFailed({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.error,
    required this.stackTrace,
    required this.text,
  });

  final Object error;
  final StackTrace stackTrace;
  final String text;
}

final class AiRunCancelled extends AiRunEvent {
  const AiRunCancelled({
    required super.runId,
    required super.sequence,
    required super.occurredAt,
    required this.text,
  });

  final String text;
}

/// Pure reducer used by controllers, UI projections, checkpoints and tests.
///
/// Replayed/duplicate events are idempotently ignored. Events from another run
/// are rejected, and a terminal state never accepts later mutations.
class AiRunState {
  const AiRunState._({
    required this.descriptor,
    required this.phase,
    required this.scope,
    required this.text,
    required this.reasoningText,
    required this.reasoningKind,
    required this.status,
    required this.modelCallCount,
    required this.toolRound,
    required this.continuationRound,
    required this.usage,
    required this.lastSequence,
    required this.startedAt,
    required this.updatedAt,
    this.finishedAt,
    this.error,
  });

  factory AiRunState.initial(AiRunDescriptor descriptor) => AiRunState._(
    descriptor: descriptor,
    phase: AiRunPhase.preparing,
    scope: descriptor.scope,
    text: '',
    reasoningText: '',
    reasoningKind: AiReasoningContentKind.process,
    status: null,
    modelCallCount: 0,
    toolRound: 0,
    continuationRound: 0,
    usage: const AiRunUsage(),
    lastSequence: -1,
    startedAt: null,
    updatedAt: null,
  );

  final AiRunDescriptor descriptor;
  final AiRunPhase phase;
  final AiRunScope scope;
  final String text;
  final String reasoningText;
  final AiReasoningContentKind reasoningKind;
  final String? status;
  final int modelCallCount;
  final int toolRound;
  final int continuationRound;
  final AiRunUsage usage;
  final int lastSequence;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;
  final Object? error;

  bool get isTerminal => switch (phase) {
    AiRunPhase.completed || AiRunPhase.failed || AiRunPhase.cancelled => true,
    _ => false,
  };

  AiRunState apply(AiRunEvent event) {
    if (event.runId != descriptor.runId) {
      throw StateError(
        'Cannot apply event for ${event.runId} to ${descriptor.runId}',
      );
    }
    if (isTerminal || event.sequence <= lastSequence) return this;

    var nextPhase = phase;
    var nextScope = scope;
    var nextText = text;
    var nextReasoningText = reasoningText;
    var nextReasoningKind = reasoningKind;
    String? nextStatus = status;
    var nextModelCallCount = modelCallCount;
    var nextToolRound = toolRound;
    var nextContinuationRound = continuationRound;
    var nextUsage = usage;
    var nextStartedAt = startedAt;
    DateTime? nextFinishedAt = finishedAt;
    Object? nextError = error;

    switch (event) {
      case AiRunStarted():
        nextPhase = AiRunPhase.preparing;
        nextStartedAt = event.occurredAt;
      case AiRunScopeResolved():
        nextScope = event.scope;
      case AiRunModelStarted():
        nextPhase = AiRunPhase.requestingModel;
        nextStatus = '正在请求模型…';
        nextModelCallCount = event.callIndex;
      case AiRunToolStarted():
        nextPhase = AiRunPhase.runningTool;
        nextStatus = event.status;
        nextToolRound = event.round;
      case AiRunToolCompleted():
        nextPhase = AiRunPhase.requestingModel;
        nextToolRound = event.round;
      case AiRunContinuationStarted():
        nextPhase = AiRunPhase.continuing;
        nextStatus = '正在续写…';
        nextContinuationRound = event.round;
      case AiRunProgressUpdated():
        nextStatus = event.status;
      case AiRunUsageUpdated():
        nextUsage = event.usage;
      case AiRunTextSnapshot():
        nextPhase = AiRunPhase.generating;
        nextText = event.text;
        nextStatus = null;
      case AiRunReasoningSnapshot():
        nextReasoningText = event.text;
        nextReasoningKind = event.kind;
        if (nextText.isEmpty) nextStatus = '正在思考…';
      case AiRunCompleted():
        nextPhase = AiRunPhase.completed;
        nextText = event.text;
        nextStatus = null;
        nextFinishedAt = event.occurredAt;
      case AiRunFailed():
        nextPhase = AiRunPhase.failed;
        nextText = event.text;
        nextStatus = null;
        nextError = event.error;
        nextFinishedAt = event.occurredAt;
      case AiRunCancelled():
        nextPhase = AiRunPhase.cancelled;
        nextText = event.text;
        nextStatus = null;
        nextFinishedAt = event.occurredAt;
    }

    return AiRunState._(
      descriptor: descriptor,
      phase: nextPhase,
      scope: nextScope,
      text: nextText,
      reasoningText: nextReasoningText,
      reasoningKind: nextReasoningKind,
      status: nextStatus,
      modelCallCount: nextModelCallCount,
      toolRound: nextToolRound,
      continuationRound: nextContinuationRound,
      usage: nextUsage,
      lastSequence: event.sequence,
      startedAt: nextStartedAt,
      updatedAt: event.occurredAt,
      finishedAt: nextFinishedAt,
      error: nextError,
    );
  }
}

abstract final class AiRunIds {
  static int _counter = 0;

  static String next() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'ai-$now-${_counter++}';
  }
}

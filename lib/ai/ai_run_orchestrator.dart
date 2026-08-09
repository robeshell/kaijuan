import 'dart:async';

import 'ai_cancel.dart';
import 'ai_run.dart';

/// Deterministic limits enforced independently of the selected model SDK.
class AiRunBudget {
  const AiRunBudget({
    this.maxModelCalls = 1,
    this.maxToolRounds = 0,
    this.maxContinuationRounds = 0,
    this.maxToolResultChars = 0,
    this.maxElapsed,
  }) : assert(maxModelCalls >= 0),
       assert(maxToolRounds >= 0),
       assert(maxContinuationRounds >= 0),
       assert(maxToolResultChars >= 0);

  final int maxModelCalls;
  final int maxToolRounds;
  final int maxContinuationRounds;
  final int maxToolResultChars;
  final Duration? maxElapsed;
}

class AiRunBudgetExceeded implements Exception {
  const AiRunBudgetExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Versioned recovery seam. Payload ownership stays with the workflow; the
/// orchestrator only freezes identity, state and ordering around it.
class AiRunCheckpoint {
  const AiRunCheckpoint({
    required this.version,
    required this.descriptor,
    required this.state,
    required this.payload,
    required this.createdAt,
  });

  final int version;
  final AiRunDescriptor descriptor;
  final AiRunState state;
  final Object? payload;
  final DateTime createdAt;
}

typedef AiRunCheckpointWriter =
    Future<void> Function(AiRunCheckpoint checkpoint);
typedef AiRunBody = Future<void> Function(AiRunExecution execution);

/// Kaijuan-owned execution boundary. Model frameworks are adapters below this
/// type and must not decide task routing, scope, budgets, cancellation or
/// terminal state.
class AiRunOrchestrator {
  const AiRunOrchestrator({this.clock = DateTime.now});

  final DateTime Function() clock;

  Stream<AiRunEvent> run({
    required AiRunDescriptor descriptor,
    required AiRunBudget budget,
    required AiRunBody body,
    CancelToken? cancelToken,
    AiRunCheckpointWriter? checkpointWriter,
  }) {
    final effectiveCancel = cancelToken ?? CancelToken();
    late final StreamController<AiRunEvent> controller;
    late final AiRunExecution execution;
    var consumerCancelled = false;
    var timedOut = false;
    Timer? timer;
    Completer<void>? deadline;
    Completer<void>? cancellation;

    void cancelExecution() {
      final gate = cancellation;
      if (gate != null && !gate.isCompleted) {
        gate.completeError(const _AiRunCancelledSignal(), StackTrace.current);
      }
    }

    void add(AiRunEvent event) {
      if (!consumerCancelled && !controller.isClosed) controller.add(event);
    }

    Future<void> execute() async {
      execution = AiRunExecution._(
        descriptor: descriptor,
        budget: budget,
        cancelToken: effectiveCancel,
        checkpointWriter: checkpointWriter,
        clock: clock,
        add: add,
      );
      execution._start();
      final maxElapsed = budget.maxElapsed;
      if (maxElapsed != null) {
        deadline = Completer<void>();
        timer = Timer(maxElapsed, () {
          timedOut = true;
          effectiveCancel.cancel();
          if (!deadline!.isCompleted) {
            deadline!.completeError(
              const AiRunBudgetExceeded('AI 任务超过最长运行时间'),
              StackTrace.current,
            );
          }
        });
      }
      try {
        execution.ensureActive();
        cancellation = Completer<void>();
        effectiveCancel.addCancelListener(cancelExecution);
        final bodyFuture = body(execution);
        final deadlineFuture = deadline?.future;
        await Future.any<void>([
          bodyFuture,
          cancellation!.future,
          ?deadlineFuture,
        ]);
        execution.ensureActive();
        execution._complete();
      } catch (error, stackTrace) {
        if (timedOut) {
          execution._fail(AiRunBudgetExceeded('AI 任务超过最长运行时间'), stackTrace);
        } else if (effectiveCancel.isCancelled) {
          execution._cancel();
        } else {
          execution._fail(error, stackTrace);
        }
      } finally {
        timer?.cancel();
        effectiveCancel.removeCancelListener(cancelExecution);
        await controller.close();
      }
    }

    controller = StreamController<AiRunEvent>(
      onListen: () => unawaited(execute()),
      onCancel: () {
        consumerCancelled = true;
        effectiveCancel.cancel();
      },
    );
    return controller.stream;
  }
}

class _AiRunCancelledSignal implements Exception {
  const _AiRunCancelledSignal();
}

class AiRunExecution {
  AiRunExecution._({
    required this.descriptor,
    required this.budget,
    required this.cancelToken,
    required this._checkpointWriter,
    required this._clock,
    required this._add,
  }) : _state = AiRunState.initial(descriptor);

  final AiRunDescriptor descriptor;
  final AiRunBudget budget;
  final CancelToken cancelToken;
  final AiRunCheckpointWriter? _checkpointWriter;
  final DateTime Function() _clock;
  final void Function(AiRunEvent event) _add;

  late AiRunState _state;
  var _sequence = 0;
  var _usage = const AiRunUsage();
  var _latestText = '';

  AiRunState get state => _state;
  AiRunUsage get usage => _usage;

  void ensureActive() => cancelToken.throwIfCancelled();

  void _start() {
    _emit(
      AiRunStarted(
        descriptor: descriptor,
        sequence: _nextSequence(),
        occurredAt: _clock(),
      ),
    );
    _emit(
      AiRunScopeResolved(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        scope: descriptor.scope,
      ),
    );
  }

  void modelStarted(AiRunModelPurpose purpose) {
    ensureActive();
    final next = _usage.modelCalls + 1;
    if (next > budget.maxModelCalls) {
      throw AiRunBudgetExceeded('模型调用超过 ${budget.maxModelCalls} 次上限');
    }
    _usage = _usage.copyWith(modelCalls: next);
    _emit(
      AiRunModelStarted(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        purpose: purpose,
        callIndex: next,
      ),
    );
    _emitUsage();
  }

  void toolStarted({
    required int round,
    required List<String> toolNames,
    required String status,
  }) {
    ensureActive();
    if (round <= 0 || round > budget.maxToolRounds) {
      throw AiRunBudgetExceeded('工具轮数超过 ${budget.maxToolRounds} 轮上限');
    }
    if (round < _usage.toolRounds) {
      throw StateError('Tool rounds must be monotonic');
    }
    _usage = _usage.copyWith(toolRounds: round);
    _emit(
      AiRunToolStarted(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        round: round,
        toolNames: List.unmodifiable(toolNames),
        status: status,
      ),
    );
    _emitUsage();
  }

  void toolCompleted({
    required int round,
    required List<String> toolNames,
    required int observationChars,
  }) {
    ensureActive();
    if (round != _usage.toolRounds || observationChars < 0) {
      throw StateError('Tool completion does not match the active round');
    }
    final chars = _usage.toolResultChars + observationChars;
    if (chars > budget.maxToolResultChars) {
      throw AiRunBudgetExceeded('工具结果超过 ${budget.maxToolResultChars} 字符上限');
    }
    _usage = _usage.copyWith(toolResultChars: chars);
    _emit(
      AiRunToolCompleted(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        round: round,
        toolNames: List.unmodifiable(toolNames),
        observationChars: observationChars,
      ),
    );
    _emitUsage();
  }

  void continuationStarted({required int round}) {
    ensureActive();
    if (round <= 0 || round > budget.maxContinuationRounds) {
      throw AiRunBudgetExceeded('自动续写超过 ${budget.maxContinuationRounds} 轮上限');
    }
    _usage = _usage.copyWith(continuationRounds: round);
    _emit(
      AiRunContinuationStarted(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        round: round,
        maxRounds: budget.maxContinuationRounds,
      ),
    );
    _emitUsage();
  }

  void progress(String? status) {
    ensureActive();
    _emit(
      AiRunProgressUpdated(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        status: status,
      ),
    );
  }

  void textSnapshot(String text) {
    ensureActive();
    _latestText = text;
    _emit(
      AiRunTextSnapshot(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        text: text,
      ),
    );
  }

  void reportTokens({int? inputTokens, int? outputTokens}) {
    ensureActive();
    _usage = _usage.copyWith(
      inputTokens: inputTokens == null
          ? _usage.inputTokens
          : (_usage.inputTokens ?? 0) + inputTokens,
      outputTokens: outputTokens == null
          ? _usage.outputTokens
          : (_usage.outputTokens ?? 0) + outputTokens,
    );
    _emitUsage();
  }

  Future<void> checkpoint(Object? payload, {int version = 1}) async {
    ensureActive();
    final writer = _checkpointWriter;
    if (writer == null) return;
    await writer(
      AiRunCheckpoint(
        version: version,
        descriptor: descriptor,
        state: _state,
        payload: payload,
        createdAt: _clock(),
      ),
    );
    ensureActive();
  }

  void _emitUsage() {
    _emit(
      AiRunUsageUpdated(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        usage: _usage,
      ),
    );
  }

  void _complete() {
    _emit(
      AiRunCompleted(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        text: _latestText,
      ),
    );
  }

  void _fail(Object error, StackTrace stackTrace) {
    _emit(
      AiRunFailed(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        error: error,
        stackTrace: stackTrace,
        text: _latestText,
      ),
    );
  }

  void _cancel() {
    _emit(
      AiRunCancelled(
        runId: descriptor.runId,
        sequence: _nextSequence(),
        occurredAt: _clock(),
        text: _latestText,
      ),
    );
  }

  int _nextSequence() => _sequence++;

  void _emit(AiRunEvent event) {
    _state = _state.apply(event);
    _add(event);
  }
}

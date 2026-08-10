import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';

void main() {
  const scope = AiRunScope(
    contentHash: 'hash-1',
    workKey: 'work-1',
    label: '第一部',
  );
  const descriptor = AiRunDescriptor(
    runId: 'run-1',
    task: AiRunTask.bookChat,
    scope: scope,
  );
  final time = DateTime.utc(2026, 8, 9);

  test('AiRunState deterministically reduces a complete lifecycle', () {
    final events = <AiRunEvent>[
      AiRunStarted(descriptor: descriptor, sequence: 0, occurredAt: time),
      AiRunScopeResolved(
        runId: descriptor.runId,
        sequence: 1,
        occurredAt: time,
        scope: scope,
      ),
      AiRunModelStarted(
        runId: descriptor.runId,
        sequence: 2,
        occurredAt: time,
        purpose: AiRunModelPurpose.toolDecision,
        callIndex: 1,
      ),
      AiRunToolStarted(
        runId: descriptor.runId,
        sequence: 3,
        occurredAt: time,
        round: 1,
        toolNames: const ['search_book'],
        status: '正在检索…',
      ),
      AiRunToolCompleted(
        runId: descriptor.runId,
        sequence: 4,
        occurredAt: time,
        round: 1,
        toolNames: const ['search_book'],
        observationChars: 200,
      ),
      AiRunUsageUpdated(
        runId: descriptor.runId,
        sequence: 5,
        occurredAt: time,
        usage: const AiRunUsage(
          modelCalls: 1,
          toolRounds: 1,
          toolResultChars: 200,
        ),
      ),
      AiRunContinuationStarted(
        runId: descriptor.runId,
        sequence: 6,
        occurredAt: time,
        round: 1,
        maxRounds: 8,
      ),
      AiRunTextSnapshot(
        runId: descriptor.runId,
        sequence: 7,
        occurredAt: time,
        text: '完整回答',
      ),
      AiRunReasoningSnapshot(
        runId: descriptor.runId,
        sequence: 8,
        occurredAt: time,
        text: '先核对章节，再组织回答。',
        kind: AiReasoningContentKind.process,
      ),
      AiRunCompleted(
        runId: descriptor.runId,
        sequence: 9,
        occurredAt: time,
        text: '完整回答',
      ),
    ];

    var state = AiRunState.initial(descriptor);
    for (final event in events) {
      state = state.apply(event);
    }

    expect(state.phase, AiRunPhase.completed);
    expect(state.scope.contentHash, 'hash-1');
    expect(state.text, '完整回答');
    expect(state.reasoningText, '先核对章节，再组织回答。');
    expect(state.modelCallCount, 1);
    expect(state.toolRound, 1);
    expect(state.continuationRound, 1);
    expect(state.usage.toolResultChars, 200);
    expect(state.lastSequence, 9);
    expect(state.isTerminal, isTrue);
  });

  test('replay is idempotent and terminal state ignores later events', () {
    var state = AiRunState.initial(descriptor);
    final started = AiRunStarted(
      descriptor: descriptor,
      sequence: 0,
      occurredAt: time,
    );
    state = state.apply(started);
    expect(identical(state.apply(started), state), isTrue);

    state = state.apply(
      AiRunCancelled(
        runId: descriptor.runId,
        sequence: 1,
        occurredAt: time,
        text: '部分回答',
      ),
    );
    final terminal = state;
    state = state.apply(
      AiRunTextSnapshot(
        runId: descriptor.runId,
        sequence: 2,
        occurredAt: time,
        text: '不应写入',
      ),
    );

    expect(identical(state, terminal), isTrue);
    expect(state.text, '部分回答');
  });

  test('rejects events belonging to another run', () {
    final state = AiRunState.initial(descriptor);
    expect(
      () => state.apply(
        AiRunProgressUpdated(
          runId: 'other-run',
          sequence: 0,
          occurredAt: time,
          status: null,
        ),
      ),
      throwsStateError,
    );
  });
}

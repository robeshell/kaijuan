import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_run_orchestrator.dart';

void main() {
  const descriptor = AiRunDescriptor(
    runId: 'run-orchestrator',
    task: AiRunTask.bookChat,
    scope: AiRunScope(contentHash: 'hash', workKey: 'work'),
  );

  test('owns ordered lifecycle, usage, text and checkpoint state', () async {
    final checkpoints = <AiRunCheckpoint>[];
    final events = await const AiRunOrchestrator()
        .run(
          descriptor: descriptor,
          budget: const AiRunBudget(
            maxModelCalls: 2,
            maxToolRounds: 1,
            maxContinuationRounds: 1,
            maxToolResultChars: 20,
          ),
          checkpointWriter: (checkpoint) async {
            checkpoints.add(checkpoint);
          },
          body: (run) async {
            run.modelStarted(AiRunModelPurpose.toolDecision);
            run.toolStarted(
              round: 1,
              toolNames: const ['search_book'],
              status: '正在检索…',
            );
            run.toolCompleted(
              round: 1,
              toolNames: const ['search_book'],
              observationChars: 8,
            );
            await run.checkpoint({'covered': 1});
            run.modelStarted(AiRunModelPurpose.answer);
            run.reasoningSnapshot('先判断证据。');
            run.textSnapshot('回答');
          },
        )
        .toList();

    expect(events.first, isA<AiRunStarted>());
    expect(events[1], isA<AiRunScopeResolved>());
    expect(events.last, isA<AiRunCompleted>());
    expect(
      events.map((event) => event.sequence),
      orderedEquals(List<int>.generate(events.length, (index) => index)),
    );
    final completed = events.last as AiRunCompleted;
    expect(completed.text, '回答');
    expect(events.whereType<AiRunReasoningSnapshot>().single.text, '先判断证据。');
    final usage = events.whereType<AiRunUsageUpdated>().last.usage;
    expect(usage.modelCalls, 2);
    expect(usage.toolRounds, 1);
    expect(usage.toolResultChars, 8);
    expect(checkpoints.single.payload, {'covered': 1});
    expect(checkpoints.single.state.toolRound, 1);
    expect(checkpoints.single.state.isTerminal, isFalse);
  });

  test('turns budget violations into one failed terminal event', () async {
    final events = await const AiRunOrchestrator()
        .run(
          descriptor: descriptor,
          budget: const AiRunBudget(maxModelCalls: 1),
          body: (run) async {
            run.modelStarted(AiRunModelPurpose.answer);
            run.modelStarted(AiRunModelPurpose.continuation);
          },
        )
        .toList();

    final failure = events.last as AiRunFailed;
    expect(failure.error, isA<AiRunBudgetExceeded>());
    expect(events.whereType<AiRunFailed>(), hasLength(1));
    expect(events.whereType<AiRunCompleted>(), isEmpty);
  });

  test('consumer cancellation propagates to the run token', () async {
    final entered = Completer<void>();
    final stopped = Completer<void>();
    final token = CancelToken();
    final stream = const AiRunOrchestrator().run(
      descriptor: descriptor,
      budget: const AiRunBudget(maxModelCalls: 1),
      cancelToken: token,
      body: (run) async {
        entered.complete();
        while (!run.cancelToken.isCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        stopped.complete();
        run.ensureActive();
      },
    );
    final subscription = stream.listen((_) {});
    await entered.future;
    await subscription.cancel();
    await stopped.future.timeout(const Duration(seconds: 1));
    expect(token.isCancelled, isTrue);
  });

  test(
    'elapsed budget cancels transport but reports a timeout failure',
    () async {
      final events = await const AiRunOrchestrator()
          .run(
            descriptor: descriptor,
            budget: const AiRunBudget(
              maxModelCalls: 1,
              maxElapsed: Duration(milliseconds: 5),
            ),
            body: (run) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              run.ensureActive();
            },
          )
          .toList();

      final failure = events.last as AiRunFailed;
      expect(failure.error, isA<AiRunBudgetExceeded>());
      expect(
        (failure.error as AiRunBudgetExceeded).message,
        contains('最长运行时间'),
      );
    },
  );

  test(
    'elapsed budget completes even when the body never cooperates',
    () async {
      final never = Completer<void>();
      final events = await const AiRunOrchestrator()
          .run(
            descriptor: descriptor,
            budget: const AiRunBudget(
              maxModelCalls: 1,
              maxElapsed: Duration(milliseconds: 5),
            ),
            body: (_) => never.future,
          )
          .toList()
          .timeout(const Duration(seconds: 1));

      expect(events.last, isA<AiRunFailed>());
      expect((events.last as AiRunFailed).error, isA<AiRunBudgetExceeded>());
    },
  );

  test(
    'explicit cancellation completes even when the body never cooperates',
    () async {
      final entered = Completer<void>();
      final never = Completer<void>();
      final token = CancelToken();
      final eventsFuture = const AiRunOrchestrator()
          .run(
            descriptor: descriptor,
            budget: const AiRunBudget(maxModelCalls: 1),
            cancelToken: token,
            body: (_) {
              entered.complete();
              return never.future;
            },
          )
          .toList();

      await entered.future;
      token.cancel();
      final events = await eventsFuture.timeout(const Duration(seconds: 1));

      expect(events.last, isA<AiRunCancelled>());
    },
  );
}

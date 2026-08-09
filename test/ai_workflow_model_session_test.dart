import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_workflow_model_session.dart';

void main() {
  test('reports calls and token usage for text and structured turns', () async {
    final adapter = _SessionAdapter();
    final purposes = <AiRunModelPurpose>[];
    final usages = <({int? input, int? output})>[];
    final session = AiWorkflowModelSession(adapter, purposes.add, ({
      inputTokens,
      outputTokens,
    }) {
      usages.add((input: inputTokens, output: outputTokens));
    });

    final events = await session
        .streamTurn(const AiModelTurnRequest(messages: []))
        .toList();
    final structured = await session.completeJson(
      const AiModelJsonRequest(messages: [], schema: {'type': 'object'}),
    );
    await session.close();
    await session.close();

    expect(events.whereType<AiModelTurnCompleted>().single.text, 'ok');
    expect(structured.value, {'ok': true});
    expect(purposes, [
      AiRunModelPurpose.workflowStep,
      AiRunModelPurpose.workflowStep,
    ]);
    expect(usages, [(input: 3, output: 2), (input: 5, output: 1)]);
    expect(adapter.closeCalls, 1);
  });

  test('close cleanup errors do not replace workflow results', () async {
    final adapter = _SessionAdapter(throwOnClose: true);
    final session = AiWorkflowModelSession(adapter, (_) {}, null);

    final result = await session.completeJson(
      const AiModelJsonRequest(messages: [], schema: {'type': 'object'}),
    );
    await expectLater(session.close(), completes);

    expect(result.value, {'ok': true});
    await expectLater(
      session.completeJson(
        const AiModelJsonRequest(messages: [], schema: {'type': 'object'}),
      ),
      throwsA(isA<AiProviderException>()),
    );
  });
}

final class _SessionAdapter
    implements AiModelAdapter, AiStructuredOutputAdapter {
  _SessionAdapter({this.throwOnClose = false});

  final bool throwOnClose;
  int closeCalls = 0;

  @override
  String get runtimeName => 'session-test';

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) async* {
    yield const AiModelTurnCompleted(
      text: 'ok',
      toolCalls: [],
      truncated: false,
      inputTokens: 3,
      outputTokens: 2,
    );
  }

  @override
  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async => const AiModelJsonResult(
    value: {'ok': true},
    inputTokens: 5,
    outputTokens: 1,
  );

  @override
  Future<void> close() async {
    closeCalls++;
    if (throwOnClose) throw StateError('close failed');
  }
}

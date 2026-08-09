import 'ai_cancel.dart';
import 'ai_model_adapter.dart';
import 'ai_models.dart';
import 'ai_run.dart';

typedef AiModelUsageReporter =
    void Function({int? inputTokens, int? outputTokens});

/// Owns one adapter for one deterministic workflow run.
///
/// The wrapper keeps model-call accounting, token reporting and lifecycle out
/// of individual language/outline/graph algorithms. Genkit types remain below
/// [AiModelAdapter].
final class AiWorkflowModelSession {
  AiWorkflowModelSession(
    this._adapter,
    this._onModelStarted,
    this._onUsage,
  );

  final AiModelAdapter _adapter;
  final void Function(AiRunModelPurpose purpose) _onModelStarted;
  final AiModelUsageReporter? _onUsage;
  var _closed = false;

  String get runtimeName => _adapter.runtimeName;

  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
    AiRunModelPurpose purpose = AiRunModelPurpose.workflowStep,
  }) async* {
    _ensureOpen();
    _onModelStarted(purpose);
    await for (final event in _adapter.streamTurn(
      request,
      cancelToken: cancelToken,
    )) {
      if (event case AiModelTurnCompleted(
        :final inputTokens,
        :final outputTokens,
      )) {
        _onUsage?.call(inputTokens: inputTokens, outputTokens: outputTokens);
      }
      yield event;
    }
  }

  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
    AiRunModelPurpose purpose = AiRunModelPurpose.workflowStep,
  }) async {
    _ensureOpen();
    if (_adapter is! AiStructuredOutputAdapter) {
      throw AiProviderException('当前模型运行时不支持结构化输出');
    }
    _onModelStarted(purpose);
    final result = await (_adapter as AiStructuredOutputAdapter).completeJson(
      request,
      cancelToken: cancelToken,
    );
    _onUsage?.call(
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
    );
    return result;
  }

  void _ensureOpen() {
    if (_closed) throw AiProviderException('AI 工作流模型会话已关闭');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _adapter.close();
  }
}

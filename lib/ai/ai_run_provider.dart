import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_run.dart';

/// Counts provider calls for deterministic workflows without making their
/// extraction/translation algorithms depend on the orchestrator itself.
class AiRunTrackingProvider implements AiProvider {
  const AiRunTrackingProvider({
    required this.delegate,
    required this.onModelStarted,
    this.purpose = AiRunModelPurpose.workflowStep,
  });

  final AiProvider delegate;
  final void Function(AiRunModelPurpose purpose) onModelStarted;
  final AiRunModelPurpose purpose;

  @override
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) {
    onModelStarted(purpose);
    return delegate.complete(request, cancelToken: cancelToken);
  }

  @override
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {
    onModelStarted(purpose);
    yield* delegate.stream(request, cancelToken: cancelToken);
  }

  @override
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken}) =>
      delegate.listModels(cancelToken: cancelToken);
}

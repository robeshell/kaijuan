import 'ai_agent_runtime.dart';
import 'ai_chat_service.dart';
import 'ai_model_adapter.dart';
import 'ai_run.dart';

AiAgentRuntime createLegacyAiAgentRuntime({
  required bool Function() isAvailable,
  required AiModelAdapterOpener openModelAdapter,
}) => LegacyAiAgentRuntime(
  isAvailable: isAvailable,
  openModelAdapter: openModelAdapter,
);

/// Compatibility implementation used while Genkit Agent is validated.
///
/// Keeping the legacy loop behind the App contract allows the controller
/// extraction to land without changing prompts, budgets, or provider behavior.
class LegacyAiAgentRuntime implements AiAgentRuntime {
  LegacyAiAgentRuntime({
    required bool Function() isAvailable,
    required AiModelAdapterOpener openModelAdapter,
  }) : _service = AiChatService(
         isAvailable: isAvailable,
         openModelAdapter: openModelAdapter,
       );

  LegacyAiAgentRuntime.fromService(AiChatService service) : _service = service;

  final AiChatService _service;

  @override
  bool get isAvailable => _service.isAvailable;

  @override
  Stream<AiRunEvent> stream(AiAgentTurn turn) => _service.streamRun(
    run: turn.run,
    userText: turn.userText,
    history: turn.history,
    context: turn.context,
    bookTitle: turn.bookTitle,
    bookAuthor: turn.bookAuthor,
    webHits: turn.webHits,
    tools: turn.tools,
    productContext: turn.productContext,
    reasoningEnabled: turn.reasoningEnabled,
    cancelToken: turn.cancelToken,
  );

  @override
  Future<List<String>> suggestFollowUpQuestions(
    AiAgentSuggestionRequest request,
  ) => _service.suggestFollowUpQuestions(
    userText: request.userText,
    answer: request.answer,
    context: request.context,
    bookTitle: request.bookTitle,
    bookAuthor: request.bookAuthor,
    cancelToken: request.cancelToken,
  );
}

import 'ai_chat.dart';
import 'ai_chat_tools.dart';
import 'ai_cancel.dart';
import 'ai_model_adapter.dart';
import 'ai_product_action.dart';
import 'ai_run.dart';
import 'ai_search.dart';

/// Frozen input for one conversational Agent turn.
///
/// This is an App-owned boundary: Genkit session, message, tool, and artifact
/// types must not cross it. Product scope and aliases are captured before the
/// runtime starts so a page turn cannot retarget an in-flight request.
class AiAgentTurn {
  const AiAgentTurn({
    required this.run,
    required this.userText,
    required this.history,
    required this.context,
    required this.bookTitle,
    required this.tools,
    this.bookAuthor,
    this.webHits,
    this.productContext = const AiChatProductContext(),
    this.reasoningEnabled,
    this.cancelToken,
  });

  final AiRunDescriptor run;
  final String userText;
  final List<AiChatMessage> history;
  final AiChatContextBundle context;
  final String bookTitle;
  final String? bookAuthor;
  final List<AiWebSearchHit>? webHits;
  final AiChatToolHost tools;
  final AiChatProductContext productContext;
  final bool? reasoningEnabled;
  final CancelToken? cancelToken;
}

class AiAgentSuggestionRequest {
  const AiAgentSuggestionRequest({
    required this.userText,
    required this.answer,
    required this.context,
    required this.bookTitle,
    this.bookAuthor,
    this.cancelToken,
  });

  final String userText;
  final String answer;
  final AiChatContextBundle context;
  final String bookTitle;
  final String? bookAuthor;
  final CancelToken? cancelToken;
}

/// Replaceable runtime for ordinary book conversation.
///
/// Deterministic product workflows remain outside this interface. A runtime
/// may request a product action through [AiRunProductActionRequested], but the
/// App validates and executes that request after the turn terminates.
abstract interface class AiAgentRuntime {
  bool get isAvailable;

  Stream<AiRunEvent> stream(AiAgentTurn turn);

  Future<List<String>> suggestFollowUpQuestions(
    AiAgentSuggestionRequest request,
  );
}

typedef AiAgentRuntimeFactory =
    AiAgentRuntime Function({
      required bool Function() isAvailable,
      required AiModelAdapterOpener openModelAdapter,
    });

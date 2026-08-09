import 'ai_cancel.dart';
import 'ai_provider_kind.dart';

enum AiModelRole { system, user, assistant, tool }

class AiModelToolDefinition {
  const AiModelToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
}

class AiModelToolCall {
  const AiModelToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class AiModelToolResult {
  const AiModelToolResult({
    required this.callId,
    required this.name,
    required this.output,
  });

  final String callId;
  final String name;
  final Object? output;
}

class AiModelMessage {
  const AiModelMessage({
    required this.role,
    this.text = '',
    this.toolCalls = const [],
    this.toolResults = const [],
  });

  final AiModelRole role;
  final String text;
  final List<AiModelToolCall> toolCalls;
  final List<AiModelToolResult> toolResults;
}

class AiModelTurnRequest {
  const AiModelTurnRequest({
    required this.messages,
    this.tools = const [],
    this.maxTokens = 1024,
    this.temperature = 0.3,
    this.timeout,
  });

  final List<AiModelMessage> messages;
  final List<AiModelToolDefinition> tools;
  final int maxTokens;
  final double temperature;
  final Duration? timeout;
}

class AiModelJsonRequest {
  const AiModelJsonRequest({
    required this.messages,
    required this.schema,
    this.maxTokens = 1024,
    this.temperature = 0.1,
    this.timeout,
  });

  final List<AiModelMessage> messages;
  final Map<String, Object?> schema;
  final int maxTokens;
  final double temperature;
  final Duration? timeout;
}

class AiModelJsonResult {
  const AiModelJsonResult({
    required this.value,
    this.inputTokens,
    this.outputTokens,
  });

  final Map<String, dynamic> value;
  final int? inputTokens;
  final int? outputTokens;
}

sealed class AiModelTurnEvent {
  const AiModelTurnEvent();
}

final class AiModelTextDelta extends AiModelTurnEvent {
  const AiModelTextDelta(this.text);

  final String text;
}

final class AiModelTurnCompleted extends AiModelTurnEvent {
  const AiModelTurnCompleted({
    required this.text,
    required this.toolCalls,
    required this.truncated,
    this.inputTokens,
    this.outputTokens,
  });

  final String text;
  final List<AiModelToolCall> toolCalls;
  final bool truncated;
  final int? inputTokens;
  final int? outputTokens;
}

/// Provider/framework-neutral model seam. Implementations perform one model
/// turn only; Kaijuan always owns the surrounding loop and tool execution.
abstract interface class AiModelAdapter {
  String get runtimeName;

  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  });

  Future<void> close();
}

abstract interface class AiStructuredOutputAdapter {
  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  });
}

abstract interface class AiModelAdapterFactory {
  AiModelAdapter? create({
    required AiProviderKind providerKind,
    required String baseUrl,
    required String apiKey,
    required String model,
  });
}

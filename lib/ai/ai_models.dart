/// Role for chat-style LLM messages.
enum AiMessageRole { system, user, assistant }

class AiMessage {
  const AiMessage({required this.role, required this.content});

  final AiMessageRole role;
  final String content;
}

/// One streamed text delta from the model.
class AiStreamChunk {
  const AiStreamChunk({
    required this.text,
    this.isFinal = false,
    this.truncated = false,
  }) : assert(!truncated || isFinal);

  final String text;
  final bool isFinal;

  /// The provider stopped because the output reached its token limit. A
  /// truncated terminal chunk is not a successful completion: callers should
  /// retain any visible partial text but surface a retry/continue state.
  final bool truncated;
}

class AiCompletionRequest {
  const AiCompletionRequest({
    required this.messages,
    this.maxTokens = 1024,
    this.temperature = 0.3,
    this.timeout,
  });

  final List<AiMessage> messages;
  final int maxTokens;
  final double temperature;

  /// Per-call network timeout; null uses the provider default (45s). Graph
  /// extraction passes a longer budget (long prompts + big JSON output).
  final Duration? timeout;
}

/// Result of a non-streaming completion (used by test connection and short tools).
class AiCompletionResult {
  const AiCompletionResult({required this.text, this.truncated = false});

  final String text;

  /// True when the provider stopped because the output hit the token budget
  /// (`finish_reason == length` / `stop_reason == max_tokens`). A truncated
  /// reply cannot contain a complete JSON object; retrying the same request
  /// is pointless, so callers should shrink the input instead.
  final bool truncated;
}

/// Outcome of "测试连接".
class AiConnectionTestResult {
  const AiConnectionTestResult.success({this.detail})
    : ok = true,
      message = '连接正常';

  const AiConnectionTestResult.failure(this.message)
    : ok = false,
      detail = null;

  final bool ok;
  final String message;
  final String? detail;
}

/// User-facing failure from an AI backend call.
class AiProviderException implements Exception {
  AiProviderException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// The model reached its output budget before a complete structured result.
/// Deterministic workflows may shrink their input, but must never accept the
/// partial value as valid JSON.
class AiModelOutputTruncatedException extends AiProviderException {
  AiModelOutputTruncatedException([String? message])
    : super(message ?? '模型输出达到长度上限');
}

/// One model id returned by a provider's list-models API.
class AiModelInfo {
  const AiModelInfo({required this.id, this.displayName});

  final String id;
  final String? displayName;

  String get label {
    final name = displayName?.trim();
    if (name == null || name.isEmpty || name == id) return id;
    return name;
  }
}

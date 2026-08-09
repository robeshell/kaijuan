/// Role for chat-style LLM messages.
enum AiMessageRole { system, user, assistant }

class AiMessage {
  const AiMessage({required this.role, required this.content});

  final AiMessageRole role;
  final String content;
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

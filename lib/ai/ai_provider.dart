import 'dart:async';

import 'ai_log.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'anthropic_provider.dart';
import 'openai_compatible_provider.dart';

/// Transport for chat completions. UI never holds this type — controllers do.
abstract interface class AiProvider {
  /// One-shot completion (test connection, short tools).
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  });

  /// Streamed completion for long answers. Yields text deltas.
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  });

  /// Lists model ids available for this API key / endpoint.
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken});
}

/// Simple cancel flag shared by request methods.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw AiProviderException('已取消');
    }
  }
}

/// One retry for short, idempotent completions (ai.md §10): rate-limit (429)
/// and response timeout. Streaming answers are **not** retried — the UI
/// surfaces the error so the user can retry or stop.
Future<AiCompletionResult> completeWithRetry(
  AiProvider provider,
  AiCompletionRequest request, {
  CancelToken? cancelToken,
  int attempts = 2,
}) async {
  for (var attempt = 0; ; attempt++) {
    cancelToken?.throwIfCancelled();
    try {
      return await provider.complete(request, cancelToken: cancelToken);
    } on AiProviderException catch (error) {
      final retryable = error.statusCode == 429;
      if (!retryable || attempt + 1 >= attempts) rethrow;
      AiLog.d(
        'complete retry attempt=${attempt + 1} status=${error.statusCode}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } on TimeoutException {
      if (attempt + 1 >= attempts) rethrow;
      AiLog.d('complete retry attempt=${attempt + 1} reason=timeout');
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}

/// Builds a concrete [AiProvider] from the current settings + key.
abstract interface class AiProviderFactory {
  AiProvider? create({
    required AiSettings settings,
    required String apiKey,
  });
}

class DefaultAiProviderFactory implements AiProviderFactory {
  const DefaultAiProviderFactory();

  @override
  AiProvider? create({
    required AiSettings settings,
    required String apiKey,
  }) {
    final key = apiKey.trim();
    if (key.isEmpty) return null;
    final baseUrl = settings.resolvedBaseUrl;
    if (baseUrl.isEmpty) return null;
    // Model may be empty when only listing models; complete/stream still need
    // a non-empty model set by the caller beforehand.
    final model = settings.resolvedModel;

    if (settings.usesAnthropicProtocol) {
      return AnthropicAiProvider(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      );
    }
    return OpenAiCompatibleAiProvider(
      baseUrl: baseUrl,
      apiKey: key,
      model: model,
    );
  }
}

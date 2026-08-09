import 'dart:async';

import 'dart:io';

import 'ai_log.dart';
import 'ai_cancel.dart';
import 'ai_models.dart';
import 'ai_settings.dart';

export 'ai_cancel.dart';

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

bool _retryableProviderStatus(int? statusCode) =>
    statusCode == 408 ||
    statusCode == 409 ||
    statusCode == 425 ||
    statusCode == 429 ||
    (statusCode != null && statusCode >= 500);

/// One retry for short, idempotent completions (ai.md §10): transient HTTP,
/// timeout and network failures.
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
      final retryable = _retryableProviderStatus(error.statusCode);
      if (!retryable || attempt + 1 >= attempts) rethrow;
      AiLog.d(
        'complete retry attempt=${attempt + 1} status=${error.statusCode}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } on TimeoutException {
      if (attempt + 1 >= attempts) rethrow;
      AiLog.d('complete retry attempt=${attempt + 1} reason=timeout');
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } on IOException {
      // TLS handshake failures / socket resets (e.g. HandshakeException:
      // "Connection terminated during handshake") — transient network noise.
      // Without this catch a flaky connection silently kills one graph
      // section (each section is a separate completion call).
      if (attempt + 1 >= attempts) rethrow;
      AiLog.d('complete retry attempt=${attempt + 1} reason=network');
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}

/// Retries a streaming request only while it is still invisible to the user.
/// Once any text has been emitted, restarting would duplicate content and may
/// repeat tool calls, so the original error is surfaced with its partial text.
Stream<AiStreamChunk> streamWithRetryBeforeFirstText(
  AiProvider provider,
  AiCompletionRequest request, {
  CancelToken? cancelToken,
  int attempts = 2,
}) async* {
  for (var attempt = 0; ; attempt++) {
    cancelToken?.throwIfCancelled();
    var emittedText = false;
    try {
      await for (final chunk in provider.stream(
        request,
        cancelToken: cancelToken,
      )) {
        if (chunk.text.isNotEmpty) emittedText = true;
        yield chunk;
      }
      return;
    } on AiProviderException catch (error) {
      if (emittedText ||
          !_retryableProviderStatus(error.statusCode) ||
          attempt + 1 >= attempts) {
        rethrow;
      }
      AiLog.d(
        'stream retry before first text attempt=${attempt + 1} '
        'status=${error.statusCode}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } on TimeoutException {
      if (emittedText || attempt + 1 >= attempts) rethrow;
      AiLog.d(
        'stream retry before first text attempt=${attempt + 1} reason=timeout',
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } on IOException {
      if (emittedText || attempt + 1 >= attempts) rethrow;
      AiLog.d(
        'stream retry before first text attempt=${attempt + 1} reason=network',
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}

/// Builds a concrete [AiProvider] from the current settings + key.
abstract interface class AiProviderFactory {
  AiProvider? create({required AiSettings settings, required String apiKey});
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'adapters/genkit_anthropic_model_adapter.dart';
import 'ai_log.dart';
import 'ai_model_adapter.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_user_error.dart';

/// Anthropic Messages API transport for deterministic text workflows.
///
/// Native tool conversations use [GenkitAnthropicModelAdapter] directly; this
/// provider keeps the existing language/outline/graph workflow contract.
class AnthropicAiProvider implements AiProvider {
  AnthropicAiProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _providedClient = client;

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client? _providedClient;

  String get _root {
    final value = baseUrl.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  Uri get _modelsUrl {
    final root = _root;
    final endpoint = root.endsWith('/v1/models')
        ? Uri.parse(root)
        : root.endsWith('/v1')
        ? Uri.parse('$root/models')
        : Uri.parse('$root/v1/models');
    return endpoint.replace(queryParameters: {'limit': '1000'});
  }

  Map<String, String> get _headers => {
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    'accept': 'application/json',
  };

  @override
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken}) async {
    cancelToken?.throwIfCancelled();
    final client = _providedClient ?? http.Client();
    try {
      final response = await client
          .get(_modelsUrl, headers: _headers)
          .timeout(const Duration(seconds: 30));
      cancelToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiProviderException(
          _httpError(response.statusCode, response.body),
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['data'] is! List) {
        throw AiProviderException('模型列表格式无法识别');
      }
      final models = <AiModelInfo>[];
      for (final item in decoded['data'] as List) {
        if (item is! Map || item['id'] is! String) continue;
        final id = (item['id'] as String).trim();
        if (id.isEmpty) continue;
        final displayName = item['display_name'];
        models.add(
          AiModelInfo(
            id: id,
            displayName: displayName is String ? displayName.trim() : null,
          ),
        );
      }
      if (models.isEmpty) throw AiProviderException('未获取到可用模型');
      return models;
    } finally {
      if (_providedClient == null) client.close();
    }
  }

  @override
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    final buffer = StringBuffer();
    AiModelTurnCompleted? terminal;
    await for (final event in _streamAdapter(
      request,
      cancelToken: cancelToken,
    )) {
      if (event case AiModelTextDelta(text: final text)) buffer.write(text);
      if (event is AiModelTurnCompleted) terminal = event;
    }
    if (terminal == null) throw AiProviderException('模型响应缺少完成终态');
    final text = buffer.toString().trim();
    if (text.isEmpty) throw AiProviderException('接口返回了空内容');
    return AiCompletionResult(text: text, truncated: terminal.truncated);
  }

  @override
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {
    await for (final event in _streamAdapter(
      request,
      cancelToken: cancelToken,
    )) {
      switch (event) {
        case AiModelTextDelta(text: final text):
          if (text.isNotEmpty) yield AiStreamChunk(text: text);
        case AiModelTurnCompleted(:final truncated):
          yield AiStreamChunk(text: '', isFinal: true, truncated: truncated);
      }
    }
  }

  Stream<AiModelTurnEvent> _streamAdapter(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {
    if (model.trim().isEmpty) throw AiProviderException('请先选择或填写模型');
    final adapter = GenkitAnthropicModelAdapter(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      requestTimeout: request.timeout ?? const Duration(seconds: 45),
      maxAttempts: 1,
    );
    try {
      yield* adapter.streamTurn(
        AiModelTurnRequest(
          messages: [
            for (final message in request.messages)
              AiModelMessage(
                role: switch (message.role) {
                  AiMessageRole.system => AiModelRole.system,
                  AiMessageRole.user => AiModelRole.user,
                  AiMessageRole.assistant => AiModelRole.assistant,
                },
                text: message.content,
              ),
          ],
          maxTokens: request.maxTokens,
          temperature: request.temperature,
        ),
        cancelToken: cancelToken,
      );
    } finally {
      await adapter.close();
    }
  }

  static String _httpError(int statusCode, String body) {
    String? providerMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String && message.trim().isNotEmpty) {
          providerMessage = message.trim();
        }
      }
    } catch (error) {
      AiLog.d('anthropic error body parse failed: $error');
    }
    return aiProviderHttpErrorMessage(
      statusCode,
      providerMessage: providerMessage,
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_openai/genkit_openai.dart';
import 'package:http/http.dart' as http;
import 'package:schemantic/schemantic.dart';

import '../ai_cancel.dart';
import '../ai_model_adapter.dart';
import '../ai_models.dart';

/// Isolated Preview SDK integration. No Genkit type crosses this file.
class GenkitOpenAiModelAdapter
    implements AiModelAdapter, AiStructuredOutputAdapter {
  factory GenkitOpenAiModelAdapter({
    required String baseUrl,
    required String apiKey,
    required String model,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 45),
    Duration retryDelay = const Duration(milliseconds: 700),
    int maxAttempts = 2,
  }) {
    final client = httpClient ?? http.Client();
    return GenkitOpenAiModelAdapter._(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      client: client,
      ownsClient: httpClient == null,
      requestTimeout: requestTimeout,
      retryDelay: retryDelay,
      maxAttempts: maxAttempts,
    );
  }

  GenkitOpenAiModelAdapter._({
    required this._baseUrl,
    required this._apiKey,
    required String model,
    required http.Client client,
    required this._ownsClient,
    required this.requestTimeout,
    required this.retryDelay,
    required this.maxAttempts,
  }) : assert(maxAttempts > 0),
       _modelName = model,
       _client = client {
    _ai = _createGenkit(client);
  }

  static const _namespace = 'kaijuan_openai';

  final String _baseUrl;
  final String _apiKey;
  final String _modelName;
  late genkit.Genkit _ai;
  late http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Duration retryDelay;
  final int maxAttempts;
  final Map<String, genkit.Tool> _tools = {};
  var _closed = false;

  genkit.Genkit _createGenkit(http.Client client) => genkit.Genkit(
    plugins: [
      openAI(
        name: _namespace,
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        models: [CustomModelDefinition(name: _modelName)],
        httpClient: client,
      ),
    ],
  );

  void _resetOwnedTransport() {
    if (!_ownsClient || _closed) return;
    final oldAi = _ai;
    _client.close();
    unawaited(oldAi.shutdown());
    _client = http.Client();
    _ai = _createGenkit(_client);
    _tools.clear();
  }

  @override
  String get runtimeName => 'genkit-openai/0.3.7';

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) async* {
    if (_closed) throw AiProviderException('AI 运行时已关闭');
    cancelToken?.throwIfCancelled();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      var emittedText = false;
      try {
        await for (final event in _streamTurnOnce(
          request,
          cancelToken: cancelToken,
        )) {
          if (event case AiModelTextDelta(
            text: final text,
          ) when text.isNotEmpty) {
            emittedText = true;
          }
          yield event;
        }
        return;
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) {
          throw AiProviderException('已取消');
        }
        if (emittedText || attempt + 1 >= maxAttempts || !_isRetryable(error)) {
          throw _asProviderException(error, operation: '模型调用');
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Stream<AiModelTurnEvent> _streamTurnOnce(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) async* {
    final tools = [for (final tool in request.tools) _resolveTool(tool)];
    final messages = request.messages.map(_toGenkitMessage).toList();
    var timedOut = false;
    final timeout = request.timeout ?? requestTimeout;
    void cancelTransport() => _client.close();

    cancelToken?.addCancelListener(cancelTransport);
    try {
      final stream = _ai.generateStream(
        model: openAI.model(_modelName, namespace: _namespace),
        messages: messages,
        tools: tools,
        returnToolRequests: true,
        maxTurns: 1,
        config: OpenAIChatOptions(
          maxTokens: request.maxTokens < 1 ? 1 : request.maxTokens,
          temperature: request.temperature.clamp(0.0, 2.0),
        ),
      );
      final chunks = stream.timeout(
        timeout,
        onTimeout: (sink) {
          timedOut = true;
          if (_ownsClient) _resetOwnedTransport();
          sink.addError(TimeoutException('流式响应等待超时', timeout));
          sink.close();
        },
      );
      await for (final chunk in chunks) {
        cancelToken?.throwIfCancelled();
        if (chunk.text.isNotEmpty) yield AiModelTextDelta(chunk.text);
      }
      if (timedOut) return;
      cancelToken?.throwIfCancelled();
      final response = await stream.onResult.timeout(
        timeout,
        onTimeout: () {
          if (_ownsClient) _resetOwnedTransport();
          throw TimeoutException('流式响应终态等待超时', timeout);
        },
      );
      cancelToken?.throwIfCancelled();
      final finishReason = response.finishReason;
      final calls = <AiModelToolCall>[];
      final callIds = <String>{};
      for (var i = 0; i < response.toolRequests.length; i++) {
        final call = response.toolRequests[i];
        final raw = call.input;
        final callId = call.ref?.trim().isNotEmpty == true
            ? call.ref!
            : 'call-${i + 1}';
        if (!callIds.add(callId)) {
          throw AiProviderException('模型返回了重复的工具调用 ID');
        }
        if (call.name.trim().isEmpty || raw is! Map) {
          throw AiProviderException('模型返回了无效的工具调用');
        }
        calls.add(
          AiModelToolCall(
            id: callId,
            name: call.name,
            arguments: raw.map((key, value) => MapEntry('$key', value)),
          ),
        );
      }
      // genkit_openai 0.3.7 passes the OpenAI SDK enum name `toolCalls`
      // into a converter that only recognizes `tool_calls`, so a valid native
      // tool terminal currently surfaces as `unknown`. Isolate that pinned-SDK
      // bug here: unknown remains invalid unless structured calls are present.
      final hasVerifiedTerminal =
          finishReason == genkit.FinishReason.stop ||
          finishReason == genkit.FinishReason.length ||
          (finishReason == genkit.FinishReason.unknown && calls.isNotEmpty);
      if (!hasVerifiedTerminal) {
        throw AiProviderException('模型响应未以可验证的成功终态结束');
      }
      if (finishReason == genkit.FinishReason.length && calls.isNotEmpty) {
        throw AiProviderException('工具调用响应被截断，未执行任何工具');
      }
      final usage = response.usage;
      yield AiModelTurnCompleted(
        text: response.text,
        toolCalls: List.unmodifiable(calls),
        truncated: finishReason == genkit.FinishReason.length,
        inputTokens: usage?.inputTokens?.round(),
        outputTokens: usage?.outputTokens?.round(),
      );
    } finally {
      cancelToken?.removeCancelListener(cancelTransport);
    }
  }

  static bool _isRetryable(Object error) {
    if (error is TimeoutException ||
        error is IOException ||
        error is http.ClientException) {
      return true;
    }
    final status = error is AiProviderException ? error.statusCode : null;
    if (status == 408 ||
        status == 409 ||
        status == 422 ||
        status == 425 ||
        status == 429) {
      return true;
    }
    if (status != null && status >= 500) return true;
    final text = error.toString().toLowerCase();
    return RegExp(r'\b(408|409|422|425|429|5\d\d)\b').hasMatch(text) ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('unprocessableentityexception') ||
        text.contains('unprocessable entity') ||
        text.contains('socket') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable');
  }

  static AiProviderException _asProviderException(
    Object error, {
    required String operation,
  }) {
    if (error is AiProviderException) return error;
    final match = RegExp(r'\b([45]\d\d)\b').firstMatch(error.toString());
    return AiProviderException(
      'Genkit $operation失败：$error',
      statusCode: match == null ? null : int.tryParse(match.group(1)!),
    );
  }

  genkit.Tool _resolveTool(AiModelToolDefinition definition) {
    return _tools.putIfAbsent(definition.name, () {
      final schema = SchemanticType.from<Map<String, dynamic>>(
        jsonSchema: definition.inputSchema,
        parse: (value) => value is Map
            ? value.map((key, item) => MapEntry('$key', item))
            : <String, dynamic>{},
      );
      return _ai.defineTool<Map<String, dynamic>, Object?>(
        name: definition.name,
        description: definition.description,
        inputSchema: schema,
        fn: (_, _) => throw StateError(
          'Kaijuan executes tools; Genkit must return tool requests only.',
        ),
      );
    });
  }

  @override
  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async {
    if (_closed) throw AiProviderException('AI 运行时已关闭');
    cancelToken?.throwIfCancelled();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await _completeJsonOnce(request, cancelToken: cancelToken);
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) {
          throw AiProviderException('已取消');
        }
        if (attempt + 1 >= maxAttempts || !_isRetryable(error)) {
          throw _asProviderException(error, operation: '结构化输出');
        }
        await Future<void>.delayed(retryDelay);
      }
    }
    throw AiProviderException('Genkit 结构化输出失败');
  }

  Future<AiModelJsonResult> _completeJsonOnce(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async {
    final timeout = request.timeout ?? requestTimeout;
    void cancelTransport() => _client.close();

    cancelToken?.addCancelListener(cancelTransport);
    try {
      final schema = SchemanticType.from<Map<String, dynamic>>(
        jsonSchema: request.schema,
        parse: (value) {
          if (value is! Map) throw const FormatException('Expected object');
          return value.map((key, item) => MapEntry('$key', item));
        },
      );
      final response = await _ai
          .generate(
            model: openAI.model(_modelName, namespace: _namespace),
            messages: request.messages.map(_toGenkitMessage).toList(),
            outputFormat: 'json',
            outputSchema: schema,
            outputConstrained: true,
            config: OpenAIChatOptions(
              maxTokens: request.maxTokens < 1 ? 1 : request.maxTokens,
              temperature: request.temperature.clamp(0.0, 2.0),
            ),
          )
          .timeout(
            timeout,
            onTimeout: () {
              if (_ownsClient) _resetOwnedTransport();
              throw TimeoutException('Genkit 结构化输出等待超时', timeout);
            },
          );
      cancelToken?.throwIfCancelled();
      if (response.finishReason != genkit.FinishReason.stop) {
        if (response.finishReason == genkit.FinishReason.length) {
          throw AiModelOutputTruncatedException();
        }
        throw AiProviderException('结构化输出未以可验证的成功终态结束');
      }
      final value = response.output;
      if (value == null) throw AiProviderException('模型未返回结构化结果');
      return AiModelJsonResult(
        value: value,
        inputTokens: response.usage?.inputTokens?.round(),
        outputTokens: response.usage?.outputTokens?.round(),
      );
    } finally {
      cancelToken?.removeCancelListener(cancelTransport);
    }
  }

  static genkit.Message _toGenkitMessage(AiModelMessage message) {
    final parts = <genkit.Part>[
      if (message.text.isNotEmpty) genkit.TextPart(text: message.text),
      for (final call in message.toolCalls)
        genkit.ToolRequestPart(
          toolRequest: genkit.ToolRequest(
            ref: call.id,
            name: call.name,
            input: call.arguments,
          ),
        ),
      for (final result in message.toolResults)
        genkit.ToolResponsePart(
          toolResponse: genkit.ToolResponse(
            ref: result.callId,
            name: result.name,
            output:
                '<untrusted_tool_results>\n'
                '${_escapeUntrustedToolOutput(result.output)}\n'
                '</untrusted_tool_results>',
          ),
        ),
    ];
    return genkit.Message(
      role: switch (message.role) {
        AiModelRole.system => genkit.Role.system,
        AiModelRole.user => genkit.Role.user,
        AiModelRole.assistant => genkit.Role.model,
        AiModelRole.tool => genkit.Role.tool,
      },
      content: parts,
    );
  }

  static String _escapeUntrustedToolOutput(Object? output) {
    final text = '${output ?? '(empty)'}';
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
    await _ai.shutdown();
  }
}

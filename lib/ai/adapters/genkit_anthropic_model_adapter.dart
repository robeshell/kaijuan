import 'dart:async';
import 'dart:io';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_anthropic/genkit_anthropic.dart';
// The public plugin handle does not expose transport shutdown. This Preview
// implementation type is contained in this adapter so cancellation can abort
// the request instead of merely hiding its output.
// ignore: implementation_imports
import 'package:genkit_anthropic/src/plugin_impl.dart';
import 'package:http/http.dart' as http;
import 'package:schemantic/schemantic.dart';

import '../ai_cancel.dart';
import '../ai_model_adapter.dart';
import '../ai_models.dart';

/// Isolated official Genkit Anthropic plugin integration.
///
/// No Genkit, plugin, or Anthropic SDK type crosses this file. Kaijuan still
/// owns tool execution and the surrounding run loop.
class GenkitAnthropicModelAdapter
    implements AiModelAdapter, AiStructuredOutputAdapter {
  GenkitAnthropicModelAdapter({
    required String baseUrl,
    required this._apiKey,
    required String model,
    this.requestTimeout = const Duration(seconds: 45),
    this.retryDelay = const Duration(milliseconds: 700),
    this.maxAttempts = 2,
  }) : assert(maxAttempts > 0),
       _baseUrl = _normalizeBaseUrl(baseUrl),
       _modelName = model {
    _createRuntime();
  }

  final String _baseUrl;
  final String _apiKey;
  final String _modelName;
  final Duration requestTimeout;
  final Duration retryDelay;
  final int maxAttempts;
  late AnthropicPluginImpl _plugin;
  late genkit.Genkit _ai;
  final Map<String, genkit.Tool> _tools = {};
  var _closed = false;

  @override
  String get runtimeName => 'genkit-anthropic/0.2.11';

  void _createRuntime() {
    _plugin = AnthropicPluginImpl(apiKey: _apiKey, baseUrl: _baseUrl);
    _ai = genkit.Genkit(plugins: [_plugin], promptDir: null);
  }

  void _resetTransport() {
    if (_closed) return;
    final oldAi = _ai;
    _plugin.close();
    unawaited(oldAi.shutdown());
    _tools.clear();
    _createRuntime();
  }

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) async* {
    _ensureOpen();
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
        _resetTransport();
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
    final plugin = _plugin;
    void cancelTransport() => plugin.close();

    cancelToken?.addCancelListener(cancelTransport);
    try {
      final stream = _ai.generateStream(
        model: anthropic.model(_modelName),
        messages: messages,
        tools: tools,
        returnToolRequests: true,
        maxTurns: 1,
        config: AnthropicOptions(
          maxTokens: request.maxTokens < 1 ? 1 : request.maxTokens,
          temperature: request.temperature.clamp(0.0, 1.0),
        ),
      );
      final chunks = stream.timeout(
        timeout,
        onTimeout: (sink) {
          timedOut = true;
          _resetTransport();
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
          _resetTransport();
          throw TimeoutException('流式响应终态等待超时', timeout);
        },
      );
      cancelToken?.throwIfCancelled();

      final calls = <AiModelToolCall>[];
      final callIds = <String>{};
      for (var i = 0; i < response.toolRequests.length; i++) {
        final call = response.toolRequests[i];
        final callId = call.ref?.trim().isNotEmpty == true
            ? call.ref!
            : 'call-${i + 1}';
        if (!callIds.add(callId)) {
          throw AiProviderException('模型返回了重复的工具调用 ID');
        }
        if (call.name.trim().isEmpty || call.input is! Map) {
          throw AiProviderException('模型返回了无效的工具调用');
        }
        calls.add(
          AiModelToolCall(
            id: callId,
            name: call.name,
            arguments: (call.input as Map).map(
              (key, value) => MapEntry('$key', value),
            ),
          ),
        );
      }

      final finishReason = response.finishReason;
      final accepted =
          finishReason == genkit.FinishReason.stop ||
          finishReason == genkit.FinishReason.length;
      if (!accepted) {
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

  @override
  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async {
    _ensureOpen();
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
        _resetTransport();
        await Future<void>.delayed(retryDelay);
      }
    }
    throw AiProviderException('Genkit Anthropic 结构化输出失败');
  }

  Future<AiModelJsonResult> _completeJsonOnce(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async {
    final timeout = request.timeout ?? requestTimeout;
    final plugin = _plugin;
    void cancelTransport() => plugin.close();

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
            model: anthropic.model(_modelName),
            messages: request.messages.map(_toGenkitMessage).toList(),
            outputFormat: 'json',
            outputSchema: schema,
            outputConstrained: true,
            config: AnthropicOptions(
              maxTokens: request.maxTokens < 1 ? 1 : request.maxTokens,
              temperature: request.temperature.clamp(0.0, 1.0),
            ),
          )
          .timeout(
            timeout,
            onTimeout: () {
              _resetTransport();
              throw TimeoutException('Genkit Anthropic 结构化输出等待超时', timeout);
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
    if (parts.isEmpty) throw AiProviderException('模型消息内容为空');
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

  static bool _isRetryable(Object error) {
    if (error is TimeoutException ||
        error is IOException ||
        error is http.ClientException) {
      return true;
    }
    final status = error is AiProviderException ? error.statusCode : null;
    if (status == 408 ||
        status == 409 ||
        status == 425 ||
        status == 429 ||
        status == 529) {
      return true;
    }
    if (status != null && status >= 500) return true;
    final text = error.toString().toLowerCase();
    return RegExp(r'\b(408|409|425|429|529|5\d\d)\b').hasMatch(text) ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('overloaded') ||
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
    final match = RegExp(r'\b([45]\d\d|529)\b').firstMatch(error.toString());
    return AiProviderException(
      'Genkit Anthropic $operation失败：$error',
      statusCode: match == null ? null : int.tryParse(match.group(1)!),
    );
  }

  void _ensureOpen() {
    if (_closed) throw AiProviderException('AI 运行时已关闭');
    if (_baseUrl.isEmpty || _modelName.trim().isEmpty) {
      throw AiProviderException('Anthropic 接口地址或模型为空');
    }
  }

  static String _normalizeBaseUrl(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('/v1/messages')) {
      result = result.substring(0, result.length - '/v1/messages'.length);
    } else if (result.endsWith('/v1')) {
      result = result.substring(0, result.length - '/v1'.length);
    }
    return result;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _plugin.close();
    await _ai.shutdown();
  }
}

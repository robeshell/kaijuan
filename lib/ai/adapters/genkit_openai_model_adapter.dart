import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_openai/genkit_openai.dart';
import 'package:http/http.dart' as http;
import 'package:schemantic/schemantic.dart';

import '../ai_cancel.dart';
import '../ai_model_adapter.dart';
import '../ai_models.dart';
import '../ai_provider_kind.dart';

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
    required AiProviderKind providerKind,
    bool reasoningEnabled = false,
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
      providerKind: providerKind,
      reasoningEnabled: reasoningEnabled,
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
    required this.providerKind,
    required this.reasoningEnabled,
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
  final AiProviderKind providerKind;
  final bool reasoningEnabled;
  final Map<String, genkit.Tool> _tools = {};
  late _OpenAiRequestDecorator _requestDecorator;
  var _closed = false;

  genkit.Genkit _createGenkit(http.Client client) {
    _requestDecorator = _OpenAiRequestDecorator(
      client,
      policy: _OpenAiReasoningPolicy(
        providerKind: providerKind,
        model: _modelName,
        enabled: reasoningEnabled,
      ),
    );
    return genkit.Genkit(
      plugins: [
        openAI(
          name: _namespace,
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          models: [CustomModelDefinition(name: _modelName)],
          httpClient: _requestDecorator,
        ),
      ],
    );
  }

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
      var emittedVisibleOutput = false;
      try {
        await for (final event in _streamTurnOnce(
          request,
          cancelToken: cancelToken,
        )) {
          if (event case AiModelTextDelta(
            text: final text,
          ) when text.isNotEmpty) {
            emittedVisibleOutput = true;
          }
          if (event case AiModelReasoningDelta(
            text: final text,
          ) when text.isNotEmpty) {
            emittedVisibleOutput = true;
          }
          yield event;
        }
        return;
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) {
          throw AiProviderException('已取消');
        }
        if (emittedVisibleOutput ||
            attempt + 1 >= maxAttempts ||
            !_isRetryable(error)) {
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
    _requestDecorator.reasoningByAssistantMessage = [
      for (final message in request.messages)
        if (message.role == AiModelRole.assistant) message.reasoningText,
    ];
    final pendingReasoning = <String>[];
    _requestDecorator.onReasoningDelta = pendingReasoning.add;
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
        while (pendingReasoning.isNotEmpty) {
          yield AiModelReasoningDelta(
            pendingReasoning.removeAt(0),
            kind: _requestDecorator.policy.visibleKind,
          );
        }
        if (chunk.text.isNotEmpty) yield AiModelTextDelta(chunk.text);
      }
      while (pendingReasoning.isNotEmpty) {
        yield AiModelReasoningDelta(
          pendingReasoning.removeAt(0),
          kind: _requestDecorator.policy.visibleKind,
        );
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
        reasoningText: _extractReasoningText(response.raw),
        reasoningKind: _requestDecorator.policy.visibleKind,
        toolCalls: List.unmodifiable(calls),
        truncated: finishReason == genkit.FinishReason.length,
        inputTokens: usage?.inputTokens?.round(),
        outputTokens: usage?.outputTokens?.round(),
      );
    } finally {
      _requestDecorator.onReasoningDelta = null;
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
    if (operation == '结构化输出' && _isStructuredOutputFormatError(error)) {
      return AiModelStructuredOutputFormatException();
    }
    if (error is AiProviderException) return error;
    final match = RegExp(r'\b([45]\d\d)\b').firstMatch(error.toString());
    return AiProviderException(
      'Genkit $operation失败：$error',
      statusCode: match == null ? null : int.tryParse(match.group(1)!),
    );
  }

  static bool _isStructuredOutputFormatError(Object error) {
    if (error is FormatException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('failed to parse extracted json') ||
        text.contains('unexpected character') ||
        text.contains('unexpected end of input');
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
      _requestDecorator.reasoningByAssistantMessage = [
        for (final message in request.messages)
          if (message.role == AiModelRole.assistant) message.reasoningText,
      ];
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

  static String _extractReasoningText(Object? raw) {
    if (raw is! Map) return '';
    final choices = raw['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final message = (choices.first as Map)['message'];
    if (message is! Map) return '';
    return _reasoningString(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
    await _ai.shutdown();
  }
}

/// Adds vendor fields omitted by the pinned Genkit OpenAI plugin without
/// letting those fields cross the adapter boundary.
final class _OpenAiRequestDecorator extends http.BaseClient {
  _OpenAiRequestDecorator(this._inner, {required this.policy});

  final http.Client _inner;
  final _OpenAiReasoningPolicy policy;
  List<String> reasoningByAssistantMessage = const [];
  void Function(String text)? onReasoningDelta;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request &&
        request.method == 'POST' &&
        request.url.path.endsWith('/chat/completions')) {
      final decoded = jsonDecode(request.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('OpenAI request body must be an object');
      }
      policy.decorateRequest(decoded);
      _adaptStructuredOutput(decoded);
      final messages = decoded['messages'];
      if (policy.requiresReasoningContinuity &&
          messages is List &&
          reasoningByAssistantMessage.isNotEmpty) {
        var assistantIndex = 0;
        for (final item in messages) {
          if (item is! Map || item['role'] != 'assistant') continue;
          if (assistantIndex < reasoningByAssistantMessage.length) {
            final reasoning = reasoningByAssistantMessage[assistantIndex];
            if (reasoning.isNotEmpty) item['reasoning_content'] = reasoning;
          }
          assistantIndex++;
        }
      }
      request.body = jsonEncode(decoded);
    }
    final response = await _inner.send(request);
    final onReasoning = onReasoningDelta;
    if (!policy.canExposeReasoning || onReasoning == null) {
      return response;
    }
    return http.StreamedResponse(
      response.stream.transform(_ReasoningSseTap(onReasoning)),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  void _adaptStructuredOutput(Map<String, dynamic> body) {
    if (!policy.requiresJsonObjectStructuredOutput) return;
    final responseFormat = body['response_format'];
    if (responseFormat is! Map || responseFormat['type'] != 'json_schema') {
      return;
    }
    final jsonSchema = responseFormat['json_schema'];
    final schema = jsonSchema is Map ? jsonSchema['schema'] : null;
    if (schema is! Map) {
      throw const FormatException(
        'DeepSeek structured output requires an object JSON schema',
      );
    }

    // genkit_openai 0.3.7 maps every output schema to OpenAI's strict
    // json_schema response format. DeepSeek supports native JSON mode but its
    // protocol accepts only json_object. Keep the conversion isolated at the
    // wire boundary: Genkit still parses the response and the workflow still
    // validates the same schema and business invariants.
    body['response_format'] = const {'type': 'json_object'};
    final instruction =
        'Return exactly one JSON object. It must conform to the following '
        'JSON Schema. Do not include Markdown fences or any text outside the '
        'JSON object.\nJSON Schema:\n${jsonEncode(schema)}';
    final messages = body['messages'];
    if (messages is! List) {
      throw const FormatException(
        'DeepSeek structured output requires a messages array',
      );
    }
    final system = messages.whereType<Map>().firstWhere(
      (message) => message['role'] == 'system',
      orElse: () => <String, dynamic>{},
    );
    if (system.isEmpty) {
      messages.insert(0, <String, dynamic>{
        'role': 'system',
        'content': instruction,
      });
      return;
    }
    final content = system['content'];
    if (content is String) {
      system['content'] = '$content\n\n$instruction';
    } else if (content is List) {
      content.add(<String, dynamic>{'type': 'text', 'text': instruction});
    } else {
      throw const FormatException(
        'DeepSeek structured output requires text system content',
      );
    }
  }

  @override
  void close() {
    // The adapter owns and closes the underlying transport. The Genkit plugin
    // receives this decorator as an injected client and must not own it.
  }
}

/// Observes OpenAI-compatible reasoning extensions while forwarding the byte
/// stream to Genkit unchanged. The incremental UTF-8 decoder is required because a
/// reasoning character or JSON line may be split across HTTP chunks.
final class _ReasoningSseTap
    extends StreamTransformerBase<List<int>, List<int>> {
  const _ReasoningSseTap(this.onReasoning);

  final void Function(String text) onReasoning;

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) async* {
    final parser = _ReasoningSseParser(onReasoning);
    final decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_ReasoningTextSink(parser.addText));
    try {
      await for (final bytes in stream) {
        decoder.add(bytes);
        yield bytes;
      }
    } finally {
      decoder.close();
      parser.close();
    }
  }
}

final class _ReasoningTextSink extends StringConversionSinkBase {
  _ReasoningTextSink(this.onText);

  final void Function(String text) onText;

  @override
  void add(String str) => onText(str);

  @override
  void addSlice(String str, int start, int end, bool isLast) {
    onText(str.substring(start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}

final class _ReasoningSseParser {
  _ReasoningSseParser(this.onReasoning);

  final void Function(String text) onReasoning;
  var _pending = '';

  void addText(String text) {
    _pending += text;
    var newline = _pending.indexOf('\n');
    while (newline >= 0) {
      final line = _pending.substring(0, newline).trimRight();
      _pending = _pending.substring(newline + 1);
      _parseLine(line);
      newline = _pending.indexOf('\n');
    }
  }

  void close() {
    if (_pending.isNotEmpty) _parseLine(_pending.trimRight());
    _pending = '';
  }

  void _parseLine(String line) {
    if (!line.startsWith('data:')) return;
    final payload = line.substring(5).trimLeft();
    if (payload.isEmpty || payload == '[DONE]') return;
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final choices = decoded['choices'];
    if (choices is! List) return;
    for (final choice in choices) {
      if (choice is! Map) continue;
      final delta = choice['delta'];
      if (delta is! Map) continue;
      final reasoning = _reasoningString(delta);
      if (reasoning.isNotEmpty) onReasoning(reasoning);
    }
  }
}

String _reasoningString(Map<dynamic, dynamic> value) {
  final reasoning =
      value['reasoning_content'] ?? value['reasoning'] ?? value['thinking'];
  if (reasoning is String) return reasoning;
  if (reasoning is Map) {
    final text =
        reasoning['content'] ?? reasoning['text'] ?? reasoning['summary'];
    if (text is String) return text;
  }
  return '';
}

final class _OpenAiReasoningPolicy {
  const _OpenAiReasoningPolicy({
    required this.providerKind,
    required this.model,
    required this.enabled,
  });

  final AiProviderKind providerKind;
  final String model;
  final bool enabled;

  AiReasoningContentKind get visibleKind =>
      providerKind.reasoningCapabilities(model).visibleKind;

  bool get canExposeReasoning =>
      providerKind.reasoningCapabilities(model).supported;

  bool get requiresReasoningContinuity =>
      providerKind == AiProviderKind.deepseek;

  bool get requiresJsonObjectStructuredOutput =>
      providerKind == AiProviderKind.deepseek;

  void decorateRequest(Map<String, dynamic> body) {
    switch (providerKind) {
      case AiProviderKind.deepseek:
        body['thinking'] = {'type': enabled ? 'enabled' : 'disabled'};
      case AiProviderKind.openai:
        if (!canExposeReasoning) return;
        body['reasoning_effort'] = enabled
            ? 'high'
            : (_openAiCanDisable(model) ? 'none' : 'low');
      case AiProviderKind.xai:
        body['reasoning_effort'] = enabled ? 'high' : 'low';
      case AiProviderKind.ollama:
        body['reasoning_effort'] = enabled ? 'high' : 'none';
      case AiProviderKind.custom:
        if (enabled) body['reasoning_effort'] = 'high';
      case AiProviderKind.anthropic:
        throw StateError('Anthropic must not use the OpenAI adapter');
    }
  }

  static bool _openAiCanDisable(String value) {
    final model = value.trim().toLowerCase();
    final match = RegExp(r'^gpt-5[.-](\d+)').firstMatch(model);
    if (match == null) return false;
    return (int.tryParse(match.group(1)!) ?? 0) >= 1;
  }
}

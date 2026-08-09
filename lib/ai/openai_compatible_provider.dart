import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_log.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_user_error.dart';

/// OpenAI Chat Completions API (also DeepSeek, xAI, many local proxies).
class OpenAiCompatibleAiProvider implements AiProvider {
  OpenAiCompatibleAiProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _client;

  String get _root {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return root;
  }

  Uri get _chatUrl {
    final root = _root;
    // Accept both `…/v1` and bare hosts that already end with /v1.
    if (root.endsWith('/chat/completions')) {
      return Uri.parse(root);
    }
    return Uri.parse('$root/chat/completions');
  }

  Uri get _modelsUrl {
    final root = _root;
    if (root.endsWith('/models')) return Uri.parse(root);
    return Uri.parse('$root/models');
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  List<Map<String, String>> _encodeMessages(List<AiMessage> messages) {
    return [
      for (final message in messages)
        {
          'role': switch (message.role) {
            AiMessageRole.system => 'system',
            AiMessageRole.user => 'user',
            AiMessageRole.assistant => 'assistant',
          },
          'content': message.content,
        },
    ];
  }

  /// DeepSeek Chat Completions defaults thinking mode to **enabled**, which
  /// fills `reasoning_content` first; with a small [max_tokens] the final
  /// `content` can be empty. Other OpenAI-compatible hosts typically ignore
  /// this field.
  bool get _isDeepSeekHost {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    return host.contains('deepseek') ||
        model.toLowerCase().startsWith('deepseek');
  }

  Map<String, Object?> _body(
    AiCompletionRequest request, {
    required bool stream,
  }) {
    // Send both token caps: classic OpenAI + newer o-series / xAI aliases.
    return {
      'model': model,
      'messages': _encodeMessages(request.messages),
      'max_tokens': request.maxTokens,
      'max_completion_tokens': request.maxTokens,
      'temperature': request.temperature,
      'stream': stream,
      // DeepSeek defaults thinking **on**; final `content` can stay empty while
      // tokens go to reasoning_content. Disable for reading-assistant tasks.
      if (_isDeepSeekHost) 'thinking': {'type': 'disabled'},
    };
  }

  /// OpenAI / DeepSeek / xAI message text.
  ///
  /// Prefer visible `content`; fall back to `reasoning_content` (DeepSeek
  /// thinking, xAI reasoning traces) when content is null/empty.
  static String extractMessageText(Map message) {
    final fromContent = _coerceText(message['content']);
    if (fromContent.isNotEmpty) return fromContent;
    for (final key in const ['reasoning_content', 'reasoning', 'refusal']) {
      final text = _coerceText(message[key]);
      if (text.isNotEmpty && key != 'refusal') return text;
    }
    return '';
  }

  static String extractDeltaText(Map delta) {
    // Do not trim stream chunks — leading/trailing spaces are meaningful
    // across token boundaries ("noun" + " meaning").
    final content = _coerceText(delta['content'], trimEdges: false);
    if (content.isNotEmpty) return content;
    return _coerceText(delta['reasoning_content'], trimEdges: false);
  }

  static String _coerceText(Object? value, {bool trimEdges = true}) {
    if (value == null) return '';
    if (value is String) return trimEdges ? value.trim() : value;
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      final buffer = StringBuffer();
      for (final part in value) {
        if (part is String) {
          buffer.write(part);
        } else if (part is Map) {
          // OpenAI multi-part: {type: text, text: "..."}
          final type = part['type'];
          if (type == null ||
              type == 'text' ||
              type == 'output_text' ||
              type == 'input_text') {
            final text = part['text'];
            if (text is String) {
              buffer.write(text);
            } else if (text is Map) {
              final nested = text['value'];
              if (nested is String) buffer.write(nested);
            }
          }
          final content = part['content'];
          if (content is String) buffer.write(content);
        }
      }
      final joined = buffer.toString();
      return trimEdges ? joined.trim() : joined;
    }
    return '';
  }

  @override
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken}) async {
    cancelToken?.throwIfCancelled();
    final url = _modelsUrl;
    AiLog.d('openai GET $url');
    final sw = Stopwatch()..start();
    final response = await _client
        .get(url, headers: _headers)
        .timeout(const Duration(seconds: 30));
    cancelToken?.throwIfCancelled();
    AiLog.d(
      'openai GET models status=${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms bytes=${response.bodyBytes.length}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AiLog.d(
        'openai GET models error body=${AiLog.bodyPreview(response.body)}',
      );
      throw AiProviderException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw AiProviderException('模型列表格式无法识别');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw AiProviderException('模型列表为空');
    }
    final models = <AiModelInfo>[];
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.trim().isEmpty) continue;
      if (_isNonChatModel(id)) continue;
      models.add(AiModelInfo(id: id.trim()));
    }
    models.sort((a, b) => a.id.compareTo(b.id));
    if (models.isEmpty) {
      throw AiProviderException('未获取到可用聊天模型');
    }
    return models;
  }

  static bool _isNonChatModel(String id) {
    final lower = id.toLowerCase();
    const skip = [
      'embedding',
      'whisper',
      'tts',
      'dall-e',
      'davinci',
      'babbage',
      'moderation',
      'realtime',
      'audio',
      'transcribe',
      'image',
    ];
    for (final token in skip) {
      if (lower.contains(token)) return true;
    }
    return false;
  }

  @override
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    if (model.trim().isEmpty) {
      throw AiProviderException('请先选择或填写模型');
    }
    cancelToken?.throwIfCancelled();
    final url = _chatUrl;
    AiLog.d('openai POST $url model=$model stream=false');
    final sw = Stopwatch()..start();
    late final http.Response response;
    void abortRequest() => _client.close();
    cancelToken?.addCancelListener(abortRequest);
    try {
      response = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode(_body(request, stream: false)),
          )
          .timeout(request.timeout ?? const Duration(seconds: 45));
    } catch (error) {
      AiLog.d(
        'openai POST complete network error after ${sw.elapsedMilliseconds}ms: $error',
      );
      rethrow;
    } finally {
      cancelToken?.removeCancelListener(abortRequest);
    }
    cancelToken?.throwIfCancelled();
    AiLog.d(
      'openai POST complete status=${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms bytes=${response.bodyBytes.length}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AiLog.d(
        'openai POST complete error body=${AiLog.bodyPreview(response.body)}',
      );
      throw AiProviderException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    final rawBody = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw AiProviderException('接口返回格式无法识别');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      AiLog.d(
        'openai POST complete no choices body=${AiLog.bodyPreview(rawBody)}',
      );
      throw AiProviderException('接口未返回内容');
    }
    final first = choices.first;
    if (first is! Map) {
      throw AiProviderException('接口未返回内容');
    }
    final finish = first['finish_reason'];
    final message = first['message'];
    if (message is! Map) {
      AiLog.d(
        'openai POST complete missing message finish=$finish '
        'body=${AiLog.bodyPreview(rawBody)}',
      );
      throw AiProviderException('接口未返回内容');
    }
    final text = extractMessageText(message);
    if (text.isEmpty) {
      AiLog.d(
        'openai POST complete empty text finish=$finish '
        'messageKeys=${message.keys.join(",")} '
        'body=${AiLog.bodyPreview(rawBody)}',
      );
      throw AiProviderException('接口返回了空内容');
    }
    AiLog.d(
      'openai POST complete finish=$finish '
      'reply="${AiLog.bodyPreview(text, max: 80)}"',
    );
    return AiCompletionResult(text: text, truncated: finish == 'length');
  }

  @override
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {
    cancelToken?.throwIfCancelled();
    void abortRequest() => _client.close();
    cancelToken?.addCancelListener(abortRequest);
    try {
      final url = _chatUrl;
      AiLog.d('openai POST $url model=$model stream=true');
      final sw = Stopwatch()..start();
      final httpRequest = http.Request('POST', url)
        ..headers.addAll(_headers)
        ..body = jsonEncode(_body(request, stream: true));
      late final http.StreamedResponse streamed;
      try {
        streamed = await _client
            .send(httpRequest)
            .timeout(const Duration(seconds: 45));
      } catch (error) {
        AiLog.d(
          'openai POST stream network error after ${sw.elapsedMilliseconds}ms: $error',
        );
        rethrow;
      }
      cancelToken?.throwIfCancelled();
      AiLog.d(
        'openai POST stream status=${streamed.statusCode} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final body = await streamed.stream.bytesToString();
        AiLog.d('openai POST stream error body=${AiLog.bodyPreview(body)}');
        throw AiProviderException(
          _errorMessageFromBody(streamed.statusCode, body),
          statusCode: streamed.statusCode,
        );
      }

      final lines = streamed.stream
          .timeout(
            request.timeout ?? const Duration(seconds: 45),
            onTimeout: (sink) {
              sink.addError(AiProviderException('流式响应等待超时，请重试'));
              sink.close();
            },
          )
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        cancelToken?.throwIfCancelled();
        if (line.isEmpty || line.startsWith(':')) continue;
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') {
          yield const AiStreamChunk(text: '', isFinal: true);
          return;
        }
        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map) continue;
          final choices = decoded['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final first = choices.first;
          if (first is! Map) continue;
          final delta = first['delta'];
          if (delta is Map) {
            final piece = extractDeltaText(delta);
            if (piece.isNotEmpty) {
              yield AiStreamChunk(text: piece);
            }
          }
          final finish = first['finish_reason'];
          if (finish is String && finish.isNotEmpty && finish != 'null') {
            AiLog.d('openai POST stream finish=$finish');
            yield AiStreamChunk(
              text: '',
              isFinal: true,
              truncated: finish == 'length',
            );
            return;
          }
        } catch (_) {
          // Skip malformed SSE frames.
        }
      }
      throw AiProviderException('流式响应意外中断，请重试');
    } finally {
      cancelToken?.removeCancelListener(abortRequest);
    }
  }

  String _errorMessage(http.Response response) {
    return _errorMessageFromBody(response.statusCode, response.body);
  }

  String _errorMessageFromBody(int statusCode, String body) {
    final parsed = _tryParseError(body);
    return aiProviderHttpErrorMessage(statusCode, providerMessage: parsed);
  }

  String? _tryParseError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is Map) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    } catch (_) {}
    return null;
  }
}

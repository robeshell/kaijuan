import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_log.dart';
import 'ai_models.dart';
import 'ai_provider.dart';

/// Anthropic Messages API (`/v1/messages`).
class AnthropicAiProvider implements AiProvider {
  AnthropicAiProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const anthropicVersion = '2023-06-01';

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

  Uri get _messagesUrl {
    final root = _root;
    if (root.endsWith('/v1/messages')) return Uri.parse(root);
    if (root.endsWith('/v1')) return Uri.parse('$root/messages');
    return Uri.parse('$root/v1/messages');
  }

  Uri get _modelsUrl {
    final root = _root;
    if (root.endsWith('/v1/models')) return Uri.parse(root);
    if (root.endsWith('/models')) return Uri.parse(root);
    if (root.endsWith('/v1')) return Uri.parse('$root/models');
    return Uri.parse('$root/v1/models');
  }

  Map<String, String> get _headers => {
    'x-api-key': apiKey,
    'anthropic-version': anthropicVersion,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, Object?> _body(
    AiCompletionRequest request, {
    required bool stream,
  }) {
    String? system;
    final messages = <Map<String, Object?>>[];
    for (final message in request.messages) {
      if (message.role == AiMessageRole.system) {
        system = (system == null || system.isEmpty)
            ? message.content
            : '$system\n\n${message.content}';
        continue;
      }
      // Anthropic content may be a string or a list of content blocks.
      messages.add({
        'role': message.role == AiMessageRole.assistant ? 'assistant' : 'user',
        'content': message.content,
      });
    }
    if (messages.isEmpty) {
      messages.add({'role': 'user', 'content': 'ping'});
    }
    // Clamp temperature to Anthropic's documented 0–1 range.
    final temperature = request.temperature.clamp(0.0, 1.0);
    return {
      'model': model,
      // Required by Messages API.
      'max_tokens': request.maxTokens < 1 ? 1 : request.maxTokens,
      'temperature': temperature,
      'stream': stream,
      if (system != null && system.isNotEmpty) 'system': system,
      'messages': messages,
    };
  }

  /// Prefer `text` blocks; fall back to `thinking` only if no visible text
  /// (extended thinking can leave text empty while thinking is filled).
  static String extractContentText(Object? content) {
    if (content is String) return content.trim();
    if (content is! List) return '';
    final texts = StringBuffer();
    final thinking = StringBuffer();
    for (final block in content) {
      if (block is! Map) continue;
      final type = block['type'];
      if (type == 'text') {
        final text = block['text'];
        if (text is String) texts.write(text);
      } else if (type == 'thinking') {
        final text = block['thinking'] ?? block['text'];
        if (text is String) thinking.write(text);
      }
    }
    final visible = texts.toString().trim();
    if (visible.isNotEmpty) return visible;
    return thinking.toString().trim();
  }

  static String extractStreamDeltaText(Map delta) {
    final type = delta['type'];
    if (type == 'text_delta' || type == null) {
      final text = delta['text'];
      if (text is String && text.isNotEmpty) return text;
    }
    // Skip thinking_delta for normal reading UX (final answer only).
    return '';
  }

  @override
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken}) async {
    cancelToken?.throwIfCancelled();
    final url = _modelsUrl;
    AiLog.d('anthropic GET $url');
    final sw = Stopwatch()..start();
    final response = await _client
        .get(url, headers: _headers)
        .timeout(const Duration(seconds: 30));
    cancelToken?.throwIfCancelled();
    AiLog.d(
      'anthropic GET models status=${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms bytes=${response.bodyBytes.length}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AiLog.d(
        'anthropic GET models error body=${AiLog.bodyPreview(response.body)}',
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
      final display = item['display_name'];
      models.add(
        AiModelInfo(
          id: id.trim(),
          displayName: display is String ? display.trim() : null,
        ),
      );
    }
    // Anthropic returns newest first; keep that order.
    if (models.isEmpty) {
      throw AiProviderException('未获取到可用模型');
    }
    return models;
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
    final url = _messagesUrl;
    AiLog.d('anthropic POST $url model=$model stream=false');
    final sw = Stopwatch()..start();
    late final http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode(_body(request, stream: false)),
          )
          .timeout(const Duration(seconds: 45));
    } catch (error) {
      AiLog.d(
        'anthropic POST complete network error after ${sw.elapsedMilliseconds}ms: $error',
      );
      rethrow;
    }
    cancelToken?.throwIfCancelled();
    AiLog.d(
      'anthropic POST complete status=${response.statusCode} '
      'in ${sw.elapsedMilliseconds}ms bytes=${response.bodyBytes.length}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AiLog.d(
        'anthropic POST complete error body=${AiLog.bodyPreview(response.body)}',
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
    final stopReason = decoded['stop_reason'];
    final content = decoded['content'];
    final text = extractContentText(content);
    if (text.isEmpty) {
      AiLog.d(
        'anthropic POST complete empty text stop_reason=$stopReason '
        'body=${AiLog.bodyPreview(rawBody)}',
      );
      throw AiProviderException('接口返回了空内容');
    }
    AiLog.d(
      'anthropic POST complete stop_reason=$stopReason '
      'reply="${AiLog.bodyPreview(text, max: 80)}"',
    );
    return AiCompletionResult(text: text);
  }

  @override
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {
    cancelToken?.throwIfCancelled();
    final url = _messagesUrl;
    AiLog.d('anthropic POST $url model=$model stream=true');
    final sw = Stopwatch()..start();
    final httpRequest = http.Request('POST', url)
      ..headers.addAll({
        ..._headers,
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(_body(request, stream: true));
    late final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(httpRequest).timeout(
        const Duration(seconds: 45),
      );
    } catch (error) {
      AiLog.d(
        'anthropic POST stream network error after ${sw.elapsedMilliseconds}ms: $error',
      );
      rethrow;
    }
    cancelToken?.throwIfCancelled();
    AiLog.d(
      'anthropic POST stream status=${streamed.statusCode} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      AiLog.d('anthropic POST stream error body=${AiLog.bodyPreview(body)}');
      throw AiProviderException(
        _errorMessageFromBody(streamed.statusCode, body),
        statusCode: streamed.statusCode,
      );
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      cancelToken?.throwIfCancelled();
      if (line.isEmpty || line.startsWith(':')) continue;
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final type = decoded['type'];
        if (type == 'content_block_delta') {
          final delta = decoded['delta'];
          if (delta is Map) {
            final piece = extractStreamDeltaText(delta);
            if (piece.isNotEmpty) {
              yield AiStreamChunk(text: piece);
            }
          }
        } else if (type == 'message_delta') {
          // Optional: log stop_reason on final delta.
          final delta = decoded['delta'];
          if (delta is Map) {
            final stop = delta['stop_reason'];
            if (stop != null) {
              AiLog.d('anthropic stream message_delta stop_reason=$stop');
            }
          }
        } else if (type == 'message_stop' || type == 'error') {
          if (type == 'error') {
            AiLog.d(
              'anthropic stream error event body=${AiLog.bodyPreview(payload)}',
            );
          }
          yield const AiStreamChunk(text: '', isFinal: true);
          return;
        }
      } catch (_) {
        // Skip malformed SSE frames.
      }
    }
    yield const AiStreamChunk(text: '', isFinal: true);
  }

  String _errorMessage(http.Response response) {
    return _errorMessageFromBody(response.statusCode, response.body);
  }

  String _errorMessageFromBody(int statusCode, String body) {
    final parsed = _tryParseError(body);
    if (parsed != null) return parsed;
    return switch (statusCode) {
      401 || 403 => '密钥无效或没有权限，请检查 API Key',
      404 => '接口地址不正确，请检查 Base URL',
      429 => '请求过于频繁或额度不足，请稍后再试',
      >= 500 => '服务暂时不可用（$statusCode），请稍后再试',
      _ => '请求失败（$statusCode）',
    };
  }

  String? _tryParseError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is Map) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) {
          final type = error['type'];
          if (type is String && type.isNotEmpty) {
            return '$message ($type)';
          }
          return message.trim();
        }
      }
      // SSE error event: { "type": "error", "error": { ... } }
      if (decoded['type'] == 'error' && error is Map) {
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

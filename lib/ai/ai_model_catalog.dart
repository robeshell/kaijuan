import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel.dart';
import 'ai_models.dart';
import 'ai_provider_kind.dart';
import 'ai_user_error.dart';

/// Lists models without coupling the app runtime to a legacy completion API.
///
/// Genkit owns generation and tool calls. Model discovery remains a small,
/// read-only HTTP capability because compatible providers expose it outside
/// the generation protocol.
abstract interface class AiModelCatalog {
  Future<List<AiModelInfo>> listModels({
    required AiProviderKind providerKind,
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  });
}

final class DefaultAiModelCatalog implements AiModelCatalog {
  const DefaultAiModelCatalog();

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderKind providerKind,
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final client = http.Client();
    void abortRequest() => client.close();
    cancelToken?.addCancelListener(abortRequest);
    try {
      final anthropic = providerKind == AiProviderKind.anthropic;
      final url = _modelsUrl(baseUrl, anthropic: anthropic);
      late final http.Response response;
      try {
        response = await client
            .get(
              url,
              headers: anthropic
                  ? {
                      'x-api-key': apiKey,
                      'anthropic-version': '2023-06-01',
                      'accept': 'application/json',
                    }
                  : {
                      'Authorization': 'Bearer $apiKey',
                      'Accept': 'application/json',
                    },
            )
            .timeout(const Duration(seconds: 30));
      } catch (_) {
        cancelToken?.throwIfCancelled();
        rethrow;
      }
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
        if (item is! Map) continue;
        final id = '${item['id'] ?? ''}'.trim();
        if (id.isEmpty || (!anthropic && _isNonChatModel(id))) continue;
        final displayName = '${item['display_name'] ?? ''}'.trim();
        models.add(
          AiModelInfo(
            id: id,
            displayName: displayName.isEmpty ? null : displayName,
          ),
        );
      }
      models.sort((left, right) => left.id.compareTo(right.id));
      if (models.isEmpty) {
        throw AiProviderException(anthropic ? '未获取到可用模型' : '未获取到可用聊天模型');
      }
      return models;
    } finally {
      cancelToken?.removeCancelListener(abortRequest);
      client.close();
    }
  }

  static Uri _modelsUrl(String baseUrl, {required bool anthropic}) {
    final trimmed = baseUrl.trim();
    final root = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (!anthropic) {
      return Uri.parse(root.endsWith('/models') ? root : '$root/models');
    }
    final endpoint = root.endsWith('/v1/models')
        ? Uri.parse(root)
        : root.endsWith('/v1')
        ? Uri.parse('$root/models')
        : Uri.parse('$root/v1/models');
    return endpoint.replace(queryParameters: {'limit': '1000'});
  }

  static bool _isNonChatModel(String id) {
    final lower = id.toLowerCase();
    const skippedTokens = [
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
    return skippedTokens.any(lower.contains);
  }

  static String _httpError(int statusCode, String body) {
    String? providerMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          providerMessage = error['message'] as String;
        } else if (decoded['message'] is String) {
          providerMessage = decoded['message'] as String;
        }
      }
    } catch (_) {
      // Status-based user copy remains actionable when the body is not JSON.
    }
    return aiProviderHttpErrorMessage(
      statusCode,
      providerMessage: providerMessage,
    );
  }
}

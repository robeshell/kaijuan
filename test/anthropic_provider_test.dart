import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/anthropic_provider.dart';

import 'support/anthropic_test_server.dart';

void main() {
  test('lists Anthropic models using native headers', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 'claude-sonnet-4-6',
              'display_name': 'Claude Sonnet 4.6',
              'type': 'model',
            },
          ],
          'has_more': false,
        }),
        200,
      );
    });
    final provider = AnthropicAiProvider(
      baseUrl: 'https://api.anthropic.com',
      apiKey: 'test-key',
      model: 'claude-sonnet-4-6',
      client: client,
    );

    final models = await provider.listModels();

    expect(captured!.url.path, '/v1/models');
    expect(captured!.url.queryParameters['limit'], '1000');
    expect(captured!.headers['x-api-key'], 'test-key');
    expect(captured!.headers['anthropic-version'], '2023-06-01');
    expect(models.single.id, 'claude-sonnet-4-6');
    expect(models.single.label, 'Claude Sonnet 4.6');
  });

  test('maps deterministic completion through Genkit Anthropic', () async {
    Map<String, dynamic>? body;
    final server = await AnthropicTestServer.start((
      request,
      requestBody,
    ) async {
      body = requestBody;
      await sendAnthropicSse(request, anthropicTextSse('ok'));
    });
    final provider = AnthropicAiProvider(
      baseUrl: '${server.baseUrl}/v1',
      apiKey: 'test-key',
      model: 'claude-sonnet-5',
    );

    try {
      final result = await provider.complete(
        const AiCompletionRequest(
          messages: [
            AiMessage(role: AiMessageRole.system, content: '只回答 ok'),
            AiMessage(role: AiMessageRole.user, content: '测试'),
          ],
        ),
      );

      expect(result.text, 'ok');
      expect(body!['system'], isNotNull);
      expect(jsonEncode(body!['system']), contains('只回答 ok'));
      expect(body!['messages'], hasLength(1));
      expect(body!['stream'], isTrue);
    } finally {
      await server.close();
    }
  });
}

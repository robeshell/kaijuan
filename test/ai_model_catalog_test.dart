import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_model_catalog.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';

void main() {
  test(
    'OpenAI-compatible catalog uses bearer auth and filters non-chat models',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final requestSeen = server.first.then((request) async {
        expect(request.uri.path, '/v1/models');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer sk-test',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'text-embedding-3-small'},
              {'id': 'gpt-5-mini'},
              {'id': 'gpt-5'},
            ],
          }),
        );
        await request.response.close();
      });

      final models = await const DefaultAiModelCatalog().listModels(
        providerKind: AiProviderKind.openai,
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'sk-test',
      );
      await requestSeen;

      expect(models.map((model) => model.id), ['gpt-5', 'gpt-5-mini']);
    },
  );

  test(
    'Anthropic catalog uses Messages headers, pagination limit and display name',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final requestSeen = server.first.then((request) async {
        expect(request.uri.path, '/v1/models');
        expect(request.uri.queryParameters['limit'], '1000');
        expect(request.headers.value('x-api-key'), 'ant-test');
        expect(request.headers.value('anthropic-version'), '2023-06-01');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'id': 'claude-sonnet-test',
                'display_name': 'Claude Sonnet Test',
              },
            ],
          }),
        );
        await request.response.close();
      });

      final models = await const DefaultAiModelCatalog().listModels(
        providerKind: AiProviderKind.anthropic,
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'ant-test',
      );
      await requestSeen;

      expect(models.single.id, 'claude-sonnet-test');
      expect(models.single.label, 'Claude Sonnet Test');
    },
  );

  test('catalog cancellation aborts a pending HTTP request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestStarted = server.first;
    final cancel = CancelToken();
    final pending = const DefaultAiModelCatalog().listModels(
      providerKind: AiProviderKind.openai,
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
      apiKey: 'sk-test',
      cancelToken: cancel,
    );

    final request = await requestStarted;
    cancel.cancel();

    await expectLater(
      pending,
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          '已取消',
        ),
      ),
    );
    await request.response.close();
  });
}

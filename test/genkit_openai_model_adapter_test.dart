import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaijuan/ai/adapters/genkit_openai_model_adapter.dart';
import 'package:kaijuan/ai/ai_chat_tools.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_models.dart';

void main() {
  test(
    'Genkit adapter sends native tools to an OpenAI-compatible endpoint',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        const body = '''
data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1,"model":"deepseek-chat","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"search_book","arguments":"{\\"query\\":\\"张居正\\"}"}}]},"finish_reason":null}]}

data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1,"model":"deepseek-chat","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1,"model":"deepseek-chat","choices":[],"usage":{"prompt_tokens":20,"completion_tokens":3,"total_tokens":23}}

data: [DONE]

''';
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final adapter = GenkitOpenAiModelAdapter(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'test-key',
        model: 'deepseek-chat',
        httpClient: client,
      );

      final events = await adapter
          .streamTurn(
            const AiModelTurnRequest(
              messages: [
                AiModelMessage(role: AiModelRole.system, text: 'system'),
                AiModelMessage(role: AiModelRole.user, text: '张居正是谁？'),
              ],
              tools: AiChatTools.nativeDefinitions,
            ),
          )
          .toList();
      final result = events.whereType<AiModelTurnCompleted>().single;

      expect(
        captured!.url.toString(),
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(captured!.headers['Authorization'], 'Bearer test-key');
      final requestJson = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(requestJson['model'], 'deepseek-chat');
      expect(requestJson['stream'], isTrue);
      expect(requestJson['tools'], isA<List>());
      expect((requestJson['tools'] as List), hasLength(5));
      expect(result.toolCalls.single.name, AiChatToolNames.searchBook);
      expect(result.toolCalls.single.arguments, {'query': '张居正'});
      // Some compatible streaming APIs omit usage even when the final SSE
      // includes it; the app contract deliberately keeps both counts optional.
      expect(result.inputTokens, isNull);
      expect(result.outputTokens, isNull);

      await adapter.close();
      client.close();
    },
  );

  test(
    'Genkit adapter requests and validates structured JSON output',
    () async {
      Map<String, dynamic>? requestJson;
      final client = MockClient((request) async {
        requestJson = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'chatcmpl-json',
            'object': 'chat.completion',
            'created': 1,
            'model': 'gpt-compatible',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': '{"summary":"完成"}'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 8,
              'completion_tokens': 4,
              'total_tokens': 12,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final adapter = GenkitOpenAiModelAdapter(
        baseUrl: 'https://compatible.example/v1',
        apiKey: 'test-key',
        model: 'gpt-compatible',
        httpClient: client,
      );

      final result = await adapter.completeJson(
        const AiModelJsonRequest(
          messages: [AiModelMessage(role: AiModelRole.user, text: '总结')],
          schema: {
            'type': 'object',
            'properties': {
              'summary': {'type': 'string'},
            },
            'required': ['summary'],
            'additionalProperties': false,
          },
        ),
      );

      expect(result.value, {'summary': '完成'});
      expect(result.inputTokens, isNull);
      expect(result.outputTokens, isNull);
      expect(requestJson!['stream'], isNot(true));
      expect(requestJson!['response_format'], isA<Map>());

      await adapter.close();
      client.close();
    },
  );

  test(
    'rejects a stream that closes without a terminal finish reason',
    () async {
      final client = MockClient((request) async {
        const body = '''
data: {"id":"incomplete","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{"role":"assistant","content":"部分回答"},"finish_reason":null}]}

data: [DONE]

''';
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final adapter = GenkitOpenAiModelAdapter(
        baseUrl: 'https://compatible.example/v1',
        apiKey: 'test-key',
        model: 'test',
        httpClient: client,
        maxAttempts: 1,
      );
      final events = <AiModelTurnEvent>[];
      Object? failure;

      try {
        await for (final event in adapter.streamTurn(
          const AiModelTurnRequest(
            messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
          ),
        )) {
          events.add(event);
        }
      } catch (error) {
        failure = error;
      }

      expect(events.whereType<AiModelTextDelta>().single.text, '部分回答');
      expect(failure, isA<AiProviderException>());
      expect('$failure', contains('成功终态'));
      await adapter.close();
      client.close();
    },
  );

  test('retries a transient HTTP failure before publishing text', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (requests == 1) {
        return http.Response(
          '{"error":{"message":"temporary"}}',
          503,
          headers: {'content-type': 'application/json'},
        );
      }
      const body = '''
data: {"id":"retry","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{"role":"assistant","content":"成功"},"finish_reason":null}]}

data: {"id":"retry","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''';
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final adapter = GenkitOpenAiModelAdapter(
      baseUrl: 'https://compatible.example/v1',
      apiKey: 'test-key',
      model: 'test',
      httpClient: client,
      retryDelay: Duration.zero,
    );

    final events = await adapter
        .streamTurn(
          const AiModelTurnRequest(
            messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
          ),
        )
        .toList();

    expect(requests, 2);
    expect(events.whereType<AiModelTextDelta>().single.text, '成功');
    expect(events.last, isA<AiModelTurnCompleted>());
    await adapter.close();
    client.close();
  });

  test('retries one compatibility 422 before publishing text', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (requests == 1) {
        return http.Response(
          '{"error":{"message":"schema could not be processed"}}',
          422,
          headers: {'content-type': 'application/json'},
        );
      }
      const body = '''
data: {"id":"retry-422","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{"role":"assistant","content":"大纲"},"finish_reason":null}]}

data: {"id":"retry-422","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''';
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final adapter = GenkitOpenAiModelAdapter(
      baseUrl: 'https://compatible.example/v1',
      apiKey: 'test-key',
      model: 'test',
      httpClient: client,
      retryDelay: Duration.zero,
    );

    final events = await adapter
        .streamTurn(
          const AiModelTurnRequest(
            messages: [AiModelMessage(role: AiModelRole.user, text: '生成大纲')],
          ),
        )
        .toList();

    expect(requests, 2);
    expect(events.whereType<AiModelTextDelta>().single.text, '大纲');
    await adapter.close();
    client.close();
  });

  test('fails a request that exceeds the transport timeout', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return http.Response('', 200);
    });
    final adapter = GenkitOpenAiModelAdapter(
      baseUrl: 'https://compatible.example/v1',
      apiKey: 'test-key',
      model: 'test',
      httpClient: client,
      requestTimeout: const Duration(milliseconds: 5),
      maxAttempts: 1,
    );

    await expectLater(
      adapter
          .streamTurn(
            const AiModelTurnRequest(
              messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
            ),
          )
          .toList(),
      throwsA(isA<AiProviderException>()),
    );
    await adapter.close();
    client.close();
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaijuan/ai/adapters/genkit_openai_model_adapter.dart';
import 'package:kaijuan/ai/ai_chat_tools.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';

void main() {
  test('maps reasoning control for every OpenAI-compatible provider', () async {
    final cases =
        <
          ({
            AiProviderKind provider,
            String model,
            bool enabled,
            Object? expectedEffort,
            Object? expectedThinking,
          })
        >[
          (
            provider: AiProviderKind.openai,
            model: 'gpt-5.4-mini',
            enabled: false,
            expectedEffort: 'none',
            expectedThinking: null,
          ),
          (
            provider: AiProviderKind.openai,
            model: 'gpt-5.4-mini',
            enabled: true,
            expectedEffort: 'high',
            expectedThinking: null,
          ),
          (
            provider: AiProviderKind.xai,
            model: 'grok-4.5',
            enabled: false,
            expectedEffort: 'low',
            expectedThinking: null,
          ),
          (
            provider: AiProviderKind.ollama,
            model: 'qwen3',
            enabled: false,
            expectedEffort: 'none',
            expectedThinking: null,
          ),
          (
            provider: AiProviderKind.custom,
            model: 'compatible',
            enabled: false,
            expectedEffort: null,
            expectedThinking: null,
          ),
          (
            provider: AiProviderKind.custom,
            model: 'compatible',
            enabled: true,
            expectedEffort: 'high',
            expectedThinking: null,
          ),
          (
            provider: AiProviderKind.deepseek,
            model: 'deepseek-v4-flash',
            enabled: true,
            expectedEffort: null,
            expectedThinking: 'enabled',
          ),
        ];

    for (final entry in cases) {
      Map<String, dynamic>? captured;
      final client = MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, dynamic>;
        const body = '''
data: {"id":"reasoning-map","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{"role":"assistant","content":"ok"},"finish_reason":null}]}

data: {"id":"reasoning-map","object":"chat.completion.chunk","created":1,"model":"test","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

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
        model: entry.model,
        providerKind: entry.provider,
        reasoningEnabled: entry.enabled,
        httpClient: client,
      );
      try {
        await adapter
            .streamTurn(
              const AiModelTurnRequest(
                messages: [AiModelMessage(role: AiModelRole.user, text: 'hi')],
              ),
            )
            .drain<void>();
        expect(
          captured!['reasoning_effort'],
          entry.expectedEffort,
          reason: '${entry.provider.name} enabled=${entry.enabled}',
        );
        expect(
          (captured!['thinking'] as Map?)?['type'],
          entry.expectedThinking,
          reason: '${entry.provider.name} enabled=${entry.enabled}',
        );
      } finally {
        await adapter.close();
        client.close();
      }
    }
  });

  test(
    'maps common compatible thinking field as a reasoning summary',
    () async {
      final client = MockClient((request) async {
        const body = '''
data: {"id":"grok-thinking","object":"chat.completion.chunk","created":1,"model":"grok-4.5","choices":[{"index":0,"delta":{"role":"assistant","thinking":"先核对证据。"},"finish_reason":null}]}

data: {"id":"grok-thinking","object":"chat.completion.chunk","created":1,"model":"grok-4.5","choices":[{"index":0,"delta":{"content":"结论。"},"finish_reason":null}]}

data: {"id":"grok-thinking","object":"chat.completion.chunk","created":1,"model":"grok-4.5","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''';
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final adapter = GenkitOpenAiModelAdapter(
        baseUrl: 'https://api.x.ai/v1',
        apiKey: 'test-key',
        model: 'grok-4.5',
        providerKind: AiProviderKind.xai,
        reasoningEnabled: true,
        httpClient: client,
      );
      try {
        final events = await adapter
            .streamTurn(
              const AiModelTurnRequest(
                messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
              ),
            )
            .toList();
        final reasoning = events.whereType<AiModelReasoningDelta>().single;
        expect(reasoning.text, '先核对证据。');
        expect(reasoning.kind, AiReasoningContentKind.summary);
      } finally {
        await adapter.close();
        client.close();
      }
    },
  );

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
        providerKind: AiProviderKind.deepseek,
        httpClient: client,
        reasoningEnabled: false,
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
      expect(requestJson['thinking'], {'type': 'disabled'});
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
        providerKind: AiProviderKind.custom,
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
      expect(requestJson!.containsKey('thinking'), isFalse);
      expect(requestJson!['response_format'], isA<Map>());
      expect((requestJson!['response_format'] as Map)['type'], 'json_schema');
      expect(adapter.runtimeName, 'genkit-openai/0.3.7');

      await adapter.close();
      client.close();
    },
  );

  test(
    'DeepSeek structured output uses native json_object with schema guidance',
    () async {
      Map<String, dynamic>? requestJson;
      final client = MockClient((request) async {
        requestJson = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'deepseek-json',
            'object': 'chat.completion',
            'created': 1,
            'model': 'deepseek-v4-flash',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': '{"summary":"完成"}'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final adapter = GenkitOpenAiModelAdapter(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'test-key',
        model: 'deepseek-v4-flash',
        providerKind: AiProviderKind.deepseek,
        reasoningEnabled: false,
        httpClient: client,
      );

      try {
        final result = await adapter.completeJson(
          const AiModelJsonRequest(
            messages: [
              AiModelMessage(role: AiModelRole.system, text: '只返回结果。'),
              AiModelMessage(role: AiModelRole.user, text: '总结'),
            ],
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
        expect(requestJson!['response_format'], {'type': 'json_object'});
        expect(requestJson!['thinking'], {'type': 'disabled'});
        final messages = (requestJson!['messages'] as List).cast<Map>();
        final system = messages.firstWhere(
          (message) => message['role'] == 'system',
        );
        expect(system['content'], contains('JSON Schema'));
        expect(system['content'], contains('"summary"'));
        expect(system['content'], isNot(contains('```')));
      } finally {
        await adapter.close();
        client.close();
      }
    },
  );

  test(
    'DeepSeek thinking streams reasoning and preserves native tool continuity',
    () async {
      final requests = <Map<String, dynamic>>[];
      var requestCount = 0;
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        requestCount++;
        if (requestCount == 1) {
          const body = '''
data: {"id":"thinking-1","object":"chat.completion.chunk","created":1,"model":"deepseek-v4-flash","choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"先查找相关段落。"},"finish_reason":null}]}

data: {"id":"thinking-1","object":"chat.completion.chunk","created":1,"model":"deepseek-v4-flash","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_search","type":"function","function":{"name":"search_book","arguments":"{\\"query\\":\\"张居正\\"}"}}]},"finish_reason":null}]}

data: {"id":"thinking-1","object":"chat.completion.chunk","created":1,"model":"deepseek-v4-flash","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''';
          return http.Response.bytes(
            utf8.encode(body),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        const body = '''
data: {"id":"thinking-2","object":"chat.completion.chunk","created":1,"model":"deepseek-v4-flash","choices":[{"index":0,"delta":{"role":"assistant","content":"张居正是书中的关键人物。"},"finish_reason":null}]}

data: {"id":"thinking-2","object":"chat.completion.chunk","created":1,"model":"deepseek-v4-flash","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

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
        model: 'deepseek-v4-flash',
        providerKind: AiProviderKind.deepseek,
        httpClient: client,
        reasoningEnabled: true,
      );

      try {
        final firstEvents = await adapter
            .streamTurn(
              const AiModelTurnRequest(
                messages: [
                  AiModelMessage(role: AiModelRole.user, text: '张居正是谁？'),
                ],
                tools: AiChatTools.nativeDefinitions,
              ),
            )
            .toList();
        final first = firstEvents.whereType<AiModelTurnCompleted>().single;
        expect(
          firstEvents.whereType<AiModelReasoningDelta>().single.text,
          '先查找相关段落。',
        );
        expect(first.reasoningText, '先查找相关段落。');
        expect(first.toolCalls, hasLength(1));

        await adapter
            .streamTurn(
              AiModelTurnRequest(
                messages: [
                  const AiModelMessage(role: AiModelRole.user, text: '张居正是谁？'),
                  AiModelMessage(
                    role: AiModelRole.assistant,
                    reasoningText: first.reasoningText,
                    toolCalls: first.toolCalls,
                  ),
                  const AiModelMessage(
                    role: AiModelRole.tool,
                    toolResults: [
                      AiModelToolResult(
                        callId: 'call_search',
                        name: 'search_book',
                        output: '张居正，明代政治家。',
                      ),
                    ],
                  ),
                ],
                tools: AiChatTools.nativeDefinitions,
              ),
            )
            .drain<void>();

        expect(requests, hasLength(2));
        expect(requests[0]['thinking'], {'type': 'enabled'});
        expect(requests[1]['thinking'], {'type': 'enabled'});
        final secondMessages = requests[1]['messages'] as List;
        final assistant = secondMessages.cast<Map>().singleWhere(
          (message) => message['role'] == 'assistant',
        );
        expect(assistant['reasoning_content'], '先查找相关段落。');
      } finally {
        await adapter.close();
        client.close();
      }
    },
  );

  test('rejects structured output with a length terminal', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'id': 'chatcmpl-json-length',
          'object': 'chat.completion',
          'created': 1,
          'model': 'gpt-compatible',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': '{"summary":"不完整"}'},
              'finish_reason': 'length',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final adapter = GenkitOpenAiModelAdapter(
      baseUrl: 'https://compatible.example/v1',
      apiKey: 'test-key',
      model: 'gpt-compatible',
      providerKind: AiProviderKind.custom,
      httpClient: client,
      maxAttempts: 1,
    );

    try {
      await expectLater(
        adapter.completeJson(
          const AiModelJsonRequest(
            messages: [AiModelMessage(role: AiModelRole.user, text: '总结')],
            schema: {
              'type': 'object',
              'properties': {
                'summary': {'type': 'string'},
              },
              'required': ['summary'],
            },
          ),
        ),
        throwsA(isA<AiModelOutputTruncatedException>()),
      );
    } finally {
      await adapter.close();
      client.close();
    }
  });

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
        providerKind: AiProviderKind.custom,
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
      providerKind: AiProviderKind.custom,
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
      providerKind: AiProviderKind.custom,
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
      providerKind: AiProviderKind.custom,
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

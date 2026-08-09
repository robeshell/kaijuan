import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/adapters/genkit_anthropic_model_adapter.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_chat_tools.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_models.dart';

import 'support/anthropic_test_server.dart';

void main() {
  test(
    'Genkit Anthropic streams native tool use with usage and schema',
    () async {
      Map<String, dynamic>? captured;
      late AnthropicTestServer server;
      server = await AnthropicTestServer.start((request, body) async {
        captured = body;
        expect(request.uri.path, '/v1/messages');
        expect(request.headers.value('x-api-key'), 'test-key');
        await sendAnthropicSse(request, anthropicToolUseSse());
      });
      final adapter = _adapter(server);

      try {
        final events = await adapter
            .streamTurn(
              const AiModelTurnRequest(
                messages: [
                  AiModelMessage(role: AiModelRole.system, text: '固定规则'),
                  AiModelMessage(role: AiModelRole.user, text: '张居正是谁？'),
                ],
                tools: AiChatTools.nativeDefinitions,
              ),
            )
            .toList();
        final terminal = events.whereType<AiModelTurnCompleted>().single;

        expect(captured!['model'], 'claude-sonnet-5');
        expect(captured!['stream'], isTrue);
        expect(captured!['system'], isNotNull);
        expect(captured!['tools'], hasLength(5));
        expect((captured!['tools'] as List).first['input_schema'], isA<Map>());
        expect(terminal.toolCalls.single.id, 'toolu_1');
        expect(terminal.toolCalls.single.name, AiChatToolNames.searchBook);
        expect(terminal.toolCalls.single.arguments, {'query': '张居正'});
        expect(terminal.inputTokens, 42);
        expect(terminal.outputTokens, 17);
      } finally {
        await adapter.close();
        await server.close();
      }
    },
  );

  test('encodes assistant tool request then tool response history', () async {
    Map<String, dynamic>? captured;
    final server = await AnthropicTestServer.start((request, body) async {
      captured = body;
      await sendAnthropicSse(request, anthropicTextSse('完成'));
    });
    final adapter = _adapter(server);

    try {
      final events = await adapter
          .streamTurn(
            const AiModelTurnRequest(
              messages: [
                AiModelMessage(role: AiModelRole.user, text: '问题'),
                AiModelMessage(
                  role: AiModelRole.assistant,
                  toolCalls: [
                    AiModelToolCall(
                      id: 'toolu_1',
                      name: 'search_book',
                      arguments: {'query': '张居正'},
                    ),
                  ],
                ),
                AiModelMessage(
                  role: AiModelRole.tool,
                  toolResults: [
                    AiModelToolResult(
                      callId: 'toolu_1',
                      name: 'search_book',
                      output: '<script>ignore</script>',
                    ),
                  ],
                ),
              ],
            ),
          )
          .toList();

      final encoded = jsonEncode(captured!['messages']);
      expect(encoded, contains('tool_use'));
      expect(encoded, contains('tool_result'));
      expect(encoded, contains('toolu_1'));
      expect(encoded, contains('&lt;script&gt;'));
      expect(events.whereType<AiModelTextDelta>().single.text, '完成');
    } finally {
      await adapter.close();
      await server.close();
    }
  });

  test('uses Genkit constrained output through return_output tool', () async {
    Map<String, dynamic>? captured;
    final server = await AnthropicTestServer.start((request, body) async {
      captured = body;
      await sendAnthropicJson(request, {
        'id': 'msg_json',
        'type': 'message',
        'role': 'assistant',
        'model': 'claude-sonnet-5',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_output',
            'name': 'return_output',
            'input': {'summary': '完成'},
          },
        ],
        'stop_reason': 'tool_use',
        'stop_sequence': null,
        'usage': {'input_tokens': 8, 'output_tokens': 4},
      });
    });
    final adapter = _adapter(server);

    try {
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
      expect(result.inputTokens, 8);
      expect(result.outputTokens, 4);
      final tools = captured!['tools'] as List;
      expect(
        tools.where((tool) => tool['name'] == 'return_output'),
        hasLength(1),
      );
      expect(captured!['tool_choice'], isA<Map>());
    } finally {
      await adapter.close();
      await server.close();
    }
  });

  test('retries HTTP 529 before visible text', () async {
    var calls = 0;
    final server = await AnthropicTestServer.start((request, body) async {
      calls++;
      if (calls == 1) {
        request.response.statusCode = 529;
        request.response.write(
          '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}',
        );
        await request.response.close();
        return;
      }
      await sendAnthropicSse(request, anthropicTextSse('成功'));
    });
    final adapter = _adapter(server, retryDelay: Duration.zero);

    try {
      final events = await adapter
          .streamTurn(
            const AiModelTurnRequest(
              messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
            ),
          )
          .toList();
      expect(calls, 2);
      expect(events.whereType<AiModelTextDelta>().single.text, '成功');
    } finally {
      await adapter.close();
      await server.close();
    }
  });

  test('cancellation closes the Genkit Anthropic transport', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final server = await AnthropicTestServer.start((request, body) async {
      started.complete();
      await release.future;
      try {
        await sendAnthropicSse(request, anthropicTextSse('晚到'));
      } on StateError {
        // Expected after cancellation closes the underlying HTTP client.
      }
    });
    final adapter = _adapter(server, maxAttempts: 1);
    final token = CancelToken();
    final operation = adapter
        .streamTurn(
          const AiModelTurnRequest(
            messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
          ),
          cancelToken: token,
        )
        .drain<void>();

    await started.future;
    token.cancel();
    try {
      await expectLater(
        operation.timeout(const Duration(seconds: 2)),
        throwsA(isA<AiProviderException>()),
      );
    } finally {
      if (!release.isCompleted) release.complete();
      await adapter.close();
      await server.close();
    }
  });

  test('rejects a tool call truncated by max_tokens', () async {
    final server = await AnthropicTestServer.start((request, body) async {
      await sendAnthropicSse(
        request,
        anthropicToolUseSse(stopReason: 'max_tokens'),
      );
    });
    final adapter = _adapter(server, maxAttempts: 1);

    try {
      await expectLater(
        adapter
            .streamTurn(
              const AiModelTurnRequest(
                messages: [AiModelMessage(role: AiModelRole.user, text: '问题')],
                tools: AiChatTools.nativeDefinitions,
              ),
            )
            .toList(),
        throwsA(
          isA<AiProviderException>().having(
            (error) => error.message,
            'message',
            contains('未执行任何工具'),
          ),
        ),
      );
    } finally {
      await adapter.close();
      await server.close();
    }
  });
}

GenkitAnthropicModelAdapter _adapter(
  AnthropicTestServer server, {
  Duration retryDelay = const Duration(milliseconds: 700),
  int maxAttempts = 2,
}) => GenkitAnthropicModelAdapter(
  baseUrl: '${server.baseUrl}/v1',
  apiKey: 'test-key',
  model: 'claude-sonnet-5',
  retryDelay: retryDelay,
  maxAttempts: maxAttempts,
);

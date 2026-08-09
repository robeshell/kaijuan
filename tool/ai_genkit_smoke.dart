import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart' as genkit;
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_model_adapter_factory.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:schemantic/schemantic.dart';

/// Optional Genkit CLI trace smoke for a user-supplied BYOK endpoint.
///
/// Example:
/// AI_SMOKE_PROVIDER=anthropic \
/// AI_SMOKE_BASE_URL=https://api.anthropic.com \
/// AI_SMOKE_MODEL=claude-sonnet-4-6 \
/// AI_SMOKE_API_KEY=... \
/// npx genkit-cli flow:run --non-interactive aiAdapterSmoke '"anthropic"' \
///   -- dart run tool/ai_genkit_smoke.dart
///
/// Use `"local"` with no environment variables for a credential-free trace.
/// It starts an in-process OpenAI-compatible fake endpoint for this run only.
///
/// The flow returns only short synthetic outputs and never logs credentials.
void main() {
  final flows = genkit.Genkit(promptDir: null);
  flows.defineFlow<String, String, Never, Never>(
    name: 'aiAdapterSmoke',
    inputSchema: SchemanticType.string(),
    outputSchema: SchemanticType.string(),
    fn: (providerName, _) async {
      final environment = Platform.environment;
      final configuredProvider = environment['AI_SMOKE_PROVIDER']
          ?.trim()
          .toLowerCase();
      final requestedProvider = providerName.trim().toLowerCase();
      if (configuredProvider != null &&
          configuredProvider.isNotEmpty &&
          configuredProvider != requestedProvider) {
        throw StateError('AI_SMOKE_PROVIDER does not match flow input');
      }
      HttpServer? localServer;
      var baseUrl = environment['AI_SMOKE_BASE_URL']?.trim() ?? '';
      final model = environment['AI_SMOKE_MODEL']?.trim() ?? '';
      var apiKey = environment['AI_SMOKE_API_KEY']?.trim() ?? '';
      var resolvedModel = model;
      final AiProviderKind providerKind;
      if (requestedProvider == 'local') {
        localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        localServer.listen(_serveLocalOpenAiSmoke);
        baseUrl = 'http://${localServer.address.host}:${localServer.port}/v1';
        apiKey = 'local-smoke';
        resolvedModel = 'local-smoke-model';
        providerKind = AiProviderKind.custom;
      } else {
        providerKind = AiProviderKind.fromStorage(requestedProvider);
      }
      if (baseUrl.isEmpty || resolvedModel.isEmpty) {
        await localServer?.close(force: true);
        throw StateError('AI smoke endpoint and model are required');
      }
      final adapter = const DefaultAiModelAdapterFactory().create(
        providerKind: providerKind,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: resolvedModel,
      );
      if (adapter == null || adapter is! AiStructuredOutputAdapter) {
        await adapter?.close();
        await localServer?.close(force: true);
        throw StateError('AI smoke adapter is unavailable');
      }
      final structuredAdapter = adapter as AiStructuredOutputAdapter;
      try {
        AiModelTurnCompleted? terminal;
        await for (final event in adapter.streamTurn(
          const AiModelTurnRequest(
            messages: [
              AiModelMessage(
                role: AiModelRole.user,
                text: 'Reply with exactly: ok',
              ),
            ],
            maxTokens: 32,
            temperature: 0,
          ),
        )) {
          if (event is AiModelTurnCompleted) terminal = event;
        }
        final completed = terminal;
        if (completed == null ||
            completed.truncated ||
            completed.toolCalls.isNotEmpty) {
          throw StateError('AI smoke text turn did not complete cleanly');
        }
        final structured = await structuredAdapter.completeJson(
          const AiModelJsonRequest(
            messages: [
              AiModelMessage(role: AiModelRole.user, text: 'Return ok=true.'),
            ],
            schema: {
              'type': 'object',
              'properties': {
                'ok': {'type': 'boolean'},
              },
              'required': ['ok'],
              'additionalProperties': false,
            },
            maxTokens: 32,
            temperature: 0,
          ),
        );
        return jsonEncode({
          'runtime': adapter.runtimeName,
          'text': completed.text.trim(),
          'structured': structured.value,
        });
      } finally {
        await adapter.close();
        await localServer?.close(force: true);
      }
    },
  );
}

Future<void> _serveLocalOpenAiSmoke(HttpRequest request) async {
  final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
  final streaming = body['stream'] == true;
  request.response.statusCode = HttpStatus.ok;
  if (streaming) {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.write('''
data: {"id":"smoke-text","object":"chat.completion.chunk","created":1,"model":"local-smoke-model","choices":[{"index":0,"delta":{"role":"assistant","content":"ok"},"finish_reason":null}]}

data: {"id":"smoke-text","object":"chat.completion.chunk","created":1,"model":"local-smoke-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''');
  } else {
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'id': 'smoke-json',
        'object': 'chat.completion',
        'created': 1,
        'model': 'local-smoke-model',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': '{"ok":true}'},
            'finish_reason': 'stop',
          },
        ],
      }),
    );
  }
  await request.response.close();
}

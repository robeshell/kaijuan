import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider.dart';
import 'package:kaijuan/ai/ai_provider_factory.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_search.dart';
import 'package:kaijuan/ai/ai_settings.dart';
import 'package:kaijuan/ai/ai_settings_store.dart';
import 'package:kaijuan/ai/ai_translation.dart';
import 'package:kaijuan/ai/anthropic_provider.dart';
import 'package:kaijuan/ai/openai_compatible_provider.dart';
import 'package:kaijuan/presentation/controllers/ai_settings_controller.dart';

void main() {
  group('AiProviderKind', () {
    test('resolves storage and defaults', () {
      expect(AiProviderKind.fromStorage('deepseek'), AiProviderKind.deepseek);
      expect(AiProviderKind.openai.defaultBaseUrl, contains('openai.com'));
      expect(AiProviderKind.anthropic.fixedProtocol, AiApiProtocol.anthropic);
      expect(AiProviderKind.deepseek.fixedProtocol, AiApiProtocol.openai);
      expect(AiProviderKind.custom.fixedProtocol, isNull);
    });

    test('ollama is local and OpenAI-compatible', () {
      expect(AiProviderKind.ollama.isLocalBackend, isTrue);
      expect(AiProviderKind.ollama.fixedProtocol, AiApiProtocol.openai);
      expect(AiProviderKind.ollama.defaultBaseUrl, contains('localhost:11434'));
      expect(AiProviderKind.fromStorage('ollama'), AiProviderKind.ollama);
      expect(AiProviderKind.openai.isLocalBackend, isFalse);
    });
  });

  group('DefaultAiProviderFactory', () {
    test('local backend may create without api key', () {
      const factory = DefaultAiProviderFactory();
      final provider = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.ollama,
          baseUrl: 'http://localhost:11434/v1',
          model: 'llama3.2',
        ),
        apiKey: '',
      );
      expect(provider, isNotNull);
      expect(provider, isA<OpenAiCompatibleAiProvider>());
    });

    test('cloud backend without key returns null', () {
      const factory = DefaultAiProviderFactory();
      final provider = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.openai,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-5.4-mini',
        ),
        apiKey: '',
      );
      expect(provider, isNull);
    });
  });

  group('AiSettings protocol', () {
    test('custom protocol selects anthropic transport', () {
      const settings = AiSettings(
        providerKind: AiProviderKind.custom,
        customProtocol: AiApiProtocol.anthropic,
        baseUrl: 'https://proxy.example/v1',
        model: 'claude-x',
      );
      expect(settings.usesAnthropicProtocol, isTrue);
      expect(settings.resolvedProtocol, AiApiProtocol.anthropic);
    });

    test('preset ignores customProtocol field', () {
      const settings = AiSettings(
        providerKind: AiProviderKind.openai,
        customProtocol: AiApiProtocol.anthropic,
      );
      expect(settings.usesOpenAiProtocol, isTrue);
      expect(settings.resolvedProtocol, AiApiProtocol.openai);
    });

    test('local backend skips api key requirement', () {
      const local = AiSettings(providerKind: AiProviderKind.ollama);
      expect(local.requiresApiKey, isFalse);
      expect(local.resolvedBaseUrl, 'http://localhost:11434/v1');
      expect(local.resolvedModel, isEmpty);

      const cloud = AiSettings(providerKind: AiProviderKind.openai);
      expect(cloud.requiresApiKey, isTrue);
    });

    test('plaintext endpoints are limited to no-key loopback backends', () {
      const cloud = AiSettings(
        providerKind: AiProviderKind.custom,
        baseUrl: 'http://api.example.com/v1',
        model: 'model',
      );
      expect(cloud.hasValidEndpoint, isFalse);
      expect(cloud.endpointValidationError, contains('HTTPS'));

      const local = AiSettings(
        providerKind: AiProviderKind.ollama,
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'llama3.2',
      );
      expect(local.hasValidEndpoint, isTrue);
    });
  });

  group('AiSettings', () {
    test('resolved url strips trailing slash and falls back to preset', () {
      const empty = AiSettings(providerKind: AiProviderKind.openai);
      expect(empty.resolvedBaseUrl, 'https://api.openai.com/v1');
      expect(empty.resolvedModel, 'gpt-5.4-mini');

      const custom = AiSettings(
        providerKind: AiProviderKind.custom,
        baseUrl: 'https://api.x.ai/v1/',
        model: 'grok-4.5',
      );
      expect(custom.resolvedBaseUrl, 'https://api.x.ai/v1');
      expect(custom.resolvedModel, 'grok-4.5');
    });

    test('json round-trip omits secrets', () {
      const settings = AiSettings(
        enabled: true,
        providerKind: AiProviderKind.anthropic,
        baseUrl: 'https://api.anthropic.com',
        model: 'claude-sonnet-4-5',
        allowUnreadContext: true,
      );
      final encoded = jsonEncode(settings.toJson());
      expect(encoded, isNot(contains('sk-')));
      final restored = AiSettings.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(restored.enabled, isTrue);
      expect(restored.providerKind, AiProviderKind.anthropic);
      expect(restored.allowUnreadContext, isTrue);
    });

    test('json round-trip keeps translation preferences', () {
      const settings = AiSettings(
        translation: AiTranslationPreferences(
          targetLanguage: AiTranslationLanguage.en,
          directionMode: AiTranslationDirectionMode.smartBidi,
          style: AiTranslationStyle.literal,
          displayMode: AiTranslationDisplayMode.bilingual,
          includeContext: true,
          noteFormat: AiTranslationNoteFormat.sourceAndTranslation,
        ),
      );
      final restored = AiSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.translation.targetLanguage, AiTranslationLanguage.en);
      expect(
        restored.translation.directionMode,
        AiTranslationDirectionMode.smartBidi,
      );
      expect(restored.translation.style, AiTranslationStyle.literal);
      expect(
        restored.translation.displayMode,
        AiTranslationDisplayMode.bilingual,
      );
      expect(restored.translation.includeContext, isTrue);
      expect(
        restored.translation.noteFormat,
        AiTranslationNoteFormat.sourceAndTranslation,
      );
    });

    test('json round-trip keeps search provider kind', () {
      const settings = AiSettings(
        searchProviderKind: AiSearchProviderKind.brave,
      );
      final restored = AiSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.searchProviderKind, AiSearchProviderKind.brave);
      expect(jsonEncode(settings.toJson()), isNot(contains('sk-')));
    });

    test('json store recovers the previous atomic generation', () async {
      final directory = await Directory.systemTemp.createTemp('ai-settings-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/ai_settings.json');
      final store = JsonAiSettingsStore(file);
      await store.write(const AiSettings(enabled: false));
      await store.write(const AiSettings(enabled: true));
      await file.writeAsString('{broken', flush: true);

      final recovered = await store.read();

      expect(recovered.enabled, isFalse);
    });
  });

  group('search credentials', () {
    test('search keys are per provider and never in settings json', () async {
      final settingsStore = MemoryAiSettingsStore();
      final credentials = MemoryAiCredentialStore();
      final controller = AiSettingsController(
        settingsStore: settingsStore,
        credentialStore: credentials,
      );
      await controller.load();
      expect(controller.isSearchReady, isFalse);

      await controller.setSearchApiKey('tvly-test-key');
      await controller.setEnabled(true);
      expect(controller.isSearchReady, isTrue);
      expect(controller.searchApiKey, 'tvly-test-key');
      expect(
        await credentials.readSearchApiKey(AiSearchProviderKind.tavily),
        'tvly-test-key',
      );

      await controller.setSearchProviderKind(AiSearchProviderKind.brave);
      expect(controller.searchApiKey, isEmpty);
      expect(controller.isSearchReady, isFalse);
      expect(
        await credentials.readSearchApiKey(AiSearchProviderKind.tavily),
        'tvly-test-key',
      );

      await controller.setSearchApiKey('brave-key');
      expect(controller.isSearchReady, isTrue);

      final persisted = await settingsStore.read();
      expect(persisted.searchProviderKind, AiSearchProviderKind.brave);
      expect(jsonEncode(persisted.toJson()), isNot(contains('brave-key')));
      expect(jsonEncode(persisted.toJson()), isNot(contains('tvly-test-key')));
    });
  });

  group('buildAiWebSearchQuery', () {
    test('maps long overview prompt to short book topic query', () {
      final q = buildAiWebSearchQuery(
        userText: '请根据提供的各部分正文，概括整本书的主线与主题，用几句话即可。必须覆盖全书结构',
        bookTitle: '万历十五年',
        bookAuthor: '黄仁宇',
      );
      expect(q, contains('万历十五年'));
      expect(q, contains('内容简介'));
      expect(q.length, lessThan(80));
    });

    test('keeps short free-form questions', () {
      final q = buildAiWebSearchQuery(userText: '张居正父亲叫什么', bookTitle: '万历十五年');
      expect(q, contains('张居正父亲叫什么'));
      expect(q, contains('万历十五年'));
    });
  });

  group('AiWebSearchService', () {
    test('tavily parses results', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.tavily.com');
        expect(request.headers['Authorization'], 'Bearer k');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['api_key'], 'k');
        expect(body['query'], '张居正');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'title': '张居正',
                'url': 'https://example.com/a',
                'content': '明代首辅',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AiWebSearchService(client: client);
      final hits = await service.search(
        provider: AiSearchProviderKind.tavily,
        apiKey: 'k',
        query: '张居正',
      );
      expect(hits, hasLength(1));
      expect(hits.single.title, '张居正');
      expect(hits.single.snippet, '明代首辅');
    });

    test('empty key throws', () async {
      final service = AiWebSearchService(
        client: MockClient((_) async {
          fail('should not request');
        }),
      );
      expect(
        () => service.search(
          provider: AiSearchProviderKind.tavily,
          apiKey: '  ',
          query: 'q',
        ),
        throwsA(isA<AiProviderException>()),
      );
    });

    test(
      'cancel ends a pending search without waiting for the response',
      () async {
        final response = Completer<http.Response>();
        final service = AiWebSearchService(
          client: MockClient((_) => response.future),
        );
        final cancel = CancelToken();
        final pending = service.search(
          provider: AiSearchProviderKind.tavily,
          apiKey: 'key',
          query: 'query',
          cancelToken: cancel,
        );

        cancel.cancel();

        await expectLater(
          pending.timeout(const Duration(seconds: 1)),
          throwsA(isA<AiProviderException>()),
        );
        response.complete(http.Response('{"results":[]}', 200));
      },
    );
  });

  group('OpenAiCompatibleAiProvider', () {
    test('cancel aborts an in-flight completion immediately', () async {
      final client = _AbortableClient();
      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o-mini',
        client: client,
      );
      final cancel = CancelToken();
      final pending = provider.complete(
        const AiCompletionRequest(
          messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
          timeout: Duration(seconds: 120),
        ),
        cancelToken: cancel,
      );
      await client.started.future;

      cancel.cancel();

      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
      expect(client.closed, isTrue);
    });

    test('cancel aborts an in-flight stream immediately', () async {
      final client = _AbortableClient();
      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o-mini',
        client: client,
      );
      final cancel = CancelToken();
      final pending = provider
          .stream(
            const AiCompletionRequest(
              messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
            ),
            cancelToken: cancel,
          )
          .drain<void>();
      await client.started.future;

      cancel.cancel();

      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
      expect(client.closed, isTrue);
    });

    test('complete parses chat completions payload', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.openai.com/v1/chat/completions',
        );
        expect(request.headers['Authorization'], 'Bearer test-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['stream'], isFalse);
        expect(body['model'], 'gpt-4o-mini');
        expect(body.containsKey('thinking'), isFalse);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o-mini',
        client: client,
      );
      final result = await provider.complete(
        const AiCompletionRequest(
          messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
        ),
      );
      expect(result.text, 'ok');
    });

    test('stream reports a length-truncated terminal chunk', () async {
      final client = MockClient((request) async {
        return http.Response(
          'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o-mini',
        client: client,
      );

      final chunks = await provider
          .stream(
            const AiCompletionRequest(
              messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
            ),
          )
          .toList();

      expect(chunks.first.text, 'partial');
      expect(chunks.last.isFinal, isTrue);
      expect(chunks.last.truncated, isTrue);
    });

    test('stream rejects EOF without a protocol completion event', () async {
      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o-mini',
        client: MockClient(
          (_) async => http.Response(
            'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );

      await expectLater(
        provider
            .stream(
              const AiCompletionRequest(
                messages: [
                  AiMessage(role: AiMessageRole.user, content: 'ping'),
                ],
              ),
            )
            .drain<void>(),
        throwsA(
          isA<AiProviderException>().having(
            (error) => error.message,
            'message',
            contains('意外中断'),
          ),
        ),
      );
    });

    test('openai multiparts and anthropic text blocks parse', () {
      expect(
        OpenAiCompatibleAiProvider.extractMessageText({
          'content': [
            {'type': 'text', 'text': 'hello '},
            {'type': 'text', 'text': 'world'},
          ],
        }),
        'hello world',
      );
      expect(
        AnthropicAiProvider.extractContentText([
          {'type': 'thinking', 'thinking': 'scratch'},
          {'type': 'text', 'text': 'final'},
        ]),
        'final',
      );
      expect(
        AnthropicAiProvider.extractContentText([
          {'type': 'thinking', 'thinking': 'only thinking'},
        ]),
        'only thinking',
      );
    });

    test(
      'deepseek disables thinking and reads reasoning_content fallback',
      () async {
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['thinking'], {'type': 'disabled'});
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'reasoning_content': 'ok from reasoning',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final provider = OpenAiCompatibleAiProvider(
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'k',
          model: 'deepseek-v4-flash',
          client: client,
        );
        final result = await provider.complete(
          const AiCompletionRequest(
            messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
          ),
        );
        expect(result.text, 'ok from reasoning');
      },
    );

    test('listModels filters non-chat ids', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/models'));
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'gpt-4o-mini'},
              {'id': 'text-embedding-3-small'},
              {'id': 'whisper-1'},
              {'id': 'deepseek-chat'},
            ],
          }),
          200,
        );
      });
      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'k',
        model: '',
        client: client,
      );
      final models = await provider.listModels();
      expect(models.map((m) => m.id), ['deepseek-chat', 'gpt-4o-mini']);
    });

    test('maps 401 to readable Chinese error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Incorrect API key provided'},
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      final provider = OpenAiCompatibleAiProvider(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'bad',
        model: 'deepseek-chat',
        client: client,
      );
      expect(
        () => provider.complete(
          const AiCompletionRequest(
            messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
          ),
        ),
        throwsA(
          isA<AiProviderException>().having(
            (e) => e.message,
            'message',
            'API Key 无效或没有访问权限，请检查设置',
          ),
        ),
      );
    });
  });

  group('AnthropicAiProvider', () {
    test('cancel aborts an in-flight completion immediately', () async {
      final client = _AbortableClient();
      final provider = AnthropicAiProvider(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'anth-key',
        model: 'claude-sonnet-4-5',
        client: client,
      );
      final cancel = CancelToken();
      final pending = provider.complete(
        const AiCompletionRequest(
          messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
          timeout: Duration(seconds: 120),
        ),
        cancelToken: cancel,
      );
      await client.started.future;

      cancel.cancel();

      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
      expect(client.closed, isTrue);
    });

    test('cancel aborts an in-flight stream immediately', () async {
      final client = _AbortableClient();
      final provider = AnthropicAiProvider(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'anth-key',
        model: 'claude-sonnet-4-5',
        client: client,
      );
      final cancel = CancelToken();
      final pending = provider
          .stream(
            const AiCompletionRequest(
              messages: [AiMessage(role: AiMessageRole.user, content: 'ping')],
            ),
            cancelToken: cancel,
          )
          .drain<void>();
      await client.started.future;

      cancel.cancel();

      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
      expect(client.closed, isTrue);
    });

    test('complete uses messages endpoint and x-api-key', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(request.headers['x-api-key'], 'anth-key');
        expect(request.headers['anthropic-version'], '2023-06-01');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['system'], 'Be brief.');
        expect(body['messages'], isA<List>());
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = AnthropicAiProvider(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'anth-key',
        model: 'claude-sonnet-4-5',
        client: client,
      );
      final result = await provider.complete(
        const AiCompletionRequest(
          messages: [
            AiMessage(role: AiMessageRole.system, content: 'Be brief.'),
            AiMessage(role: AiMessageRole.user, content: 'Hi'),
          ],
        ),
      );
      expect(result.text, 'hello');
    });

    test(
      'stream surfaces error events instead of completing normally',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            'data: {"type":"error","error":{"message":"overloaded"}}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        final provider = AnthropicAiProvider(
          baseUrl: 'https://api.anthropic.com',
          apiKey: 'anth-key',
          model: 'claude-sonnet-4-5',
          client: client,
        );

        expect(
          provider
              .stream(
                const AiCompletionRequest(
                  messages: [
                    AiMessage(role: AiMessageRole.user, content: 'Hi'),
                  ],
                ),
              )
              .drain<void>(),
          throwsA(
            isA<AiProviderException>().having(
              (error) => error.message,
              'message',
              'AI 服务返回错误，请稍后重试',
            ),
          ),
        );
      },
    );

    test('stream rejects EOF without message_stop', () async {
      final provider = AnthropicAiProvider(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'anth-key',
        model: 'claude-sonnet-4-5',
        client: MockClient(
          (_) async => http.Response(
            'data: {"type":"content_block_delta","delta":{"text":"partial"}}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );

      await expectLater(
        provider
            .stream(
              const AiCompletionRequest(
                messages: [AiMessage(role: AiMessageRole.user, content: 'Hi')],
              ),
            )
            .drain<void>(),
        throwsA(isA<AiProviderException>()),
      );
    });

    test('listModels parses Anthropic data', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://api.anthropic.com/v1/models');
        expect(request.headers['x-api-key'], 'anth-key');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'claude-sonnet-4-5', 'display_name': 'Claude Sonnet 4.5'},
              {'id': 'claude-haiku-4-5', 'display_name': 'Claude Haiku 4.5'},
            ],
          }),
          200,
        );
      });
      final provider = AnthropicAiProvider(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'anth-key',
        model: '',
        client: client,
      );
      final models = await provider.listModels();
      expect(models.first.id, 'claude-sonnet-4-5');
      expect(models.first.displayName, 'Claude Sonnet 4.5');
    });
  });

  group('AiSettingsController', () {
    test('ready flag requires enable + key + resolvable model', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await controller.load();
      expect(controller.isReadyForRequests, isFalse);

      await controller.setEnabled(true);
      expect(controller.isReadyForRequests, isFalse);

      await controller.setApiKey('sk-test');
      expect(controller.isReadyForRequests, isTrue);
    });

    test('global switch also gates web search readiness', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await controller.load();
      await controller.setSearchApiKey('search-key');
      expect(controller.hasSearchApiKey, isTrue);
      expect(controller.isSearchReady, isFalse);

      await controller.setEnabled(true);
      expect(controller.isSearchReady, isTrue);
      await controller.setEnabled(false);
      expect(controller.isSearchReady, isFalse);
    });

    test(
      'reader AI preference switches persist through the settings store',
      () async {
        final settingsStore = MemoryAiSettingsStore();
        final controller = AiSettingsController(
          settingsStore: settingsStore,
          credentialStore: MemoryAiCredentialStore(),
        );
        await controller.load();

        await controller.setAllowUnreadContext(true);
        await controller.updateTranslation(
          (translation) => translation.copyWith(includeContext: true),
        );

        final reloaded = AiSettingsController(
          settingsStore: settingsStore,
          credentialStore: MemoryAiCredentialStore(),
        );
        await reloaded.load();
        expect(reloaded.settings.allowUnreadContext, isTrue);
        expect(reloaded.settings.translation.includeContext, isTrue);
      },
    );

    test('search connection test cannot bypass the global switch', () async {
      var requested = false;
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
        searchService: AiWebSearchService(
          client: MockClient((_) async {
            requested = true;
            return http.Response('{"results":[]}', 200);
          }),
        ),
      );
      await controller.load();
      await controller.setSearchApiKey('search-key');

      await controller.testSearch();

      expect(requested, isFalse);
      expect(controller.searchTestMessage, '请先启用 AI');
    });

    test('switching preset refreshes default url and model', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await controller.load();
      await controller.setProviderKind(AiProviderKind.deepseek);
      expect(controller.settings.baseUrl, contains('deepseek'));
      expect(controller.settings.model, 'deepseek-v4-flash');

      await controller.setProviderKind(AiProviderKind.anthropic);
      expect(controller.settings.baseUrl, contains('anthropic'));
      expect(controller.settings.model, contains('claude'));
    });

    test('switching to local ollama resets url/model and skips key', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await controller.load();
      await controller.setProviderKind(AiProviderKind.openai);
      await controller.setApiKey('sk-openai');

      await controller.setProviderKind(AiProviderKind.ollama);
      expect(controller.settings.providerKind, AiProviderKind.ollama);
      expect(controller.settings.baseUrl, contains('localhost:11434'));
      expect(controller.settings.model, isEmpty);
      expect(controller.apiKey, isEmpty);
      // Local backend becomes ready without an API key.
      await controller.setEnabled(true);
      await controller.setModel('llama3.2');
      expect(controller.isReadyForRequests, isTrue);

      // Back to cloud: preset defaults restore and the provider key returns.
      await controller.setProviderKind(AiProviderKind.openai);
      expect(controller.settings.baseUrl, contains('openai.com'));
      expect(controller.settings.model, 'gpt-5.4-mini');
      expect(controller.apiKey, 'sk-openai');
    });

    test('each provider keeps its own api key', () async {
      final credentials = MemoryAiCredentialStore();
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: credentials,
      );
      await controller.load();
      expect(controller.settings.providerKind, AiProviderKind.openai);
      await controller.setApiKey('sk-openai');
      await controller.setProviderKind(AiProviderKind.deepseek);
      expect(controller.apiKey, isEmpty);
      await controller.setApiKey('sk-deepseek');
      await controller.setProviderKind(AiProviderKind.openai);
      expect(controller.apiKey, 'sk-openai');
      await controller.setProviderKind(AiProviderKind.deepseek);
      expect(controller.apiKey, 'sk-deepseek');
      expect(await credentials.readApiKey(AiProviderKind.anthropic), isNull);
    });

    test('testConnection succeeds via factory mock', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
        providerFactory: _FakeProviderFactory(
          OpenAiCompatibleAiProvider(
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'k',
            model: 'm',
            client: MockClient((request) async {
              return http.Response(
                jsonEncode({
                  'choices': [
                    {
                      'message': {'content': 'ok'},
                    },
                  ],
                }),
                200,
              );
            }),
          ),
        ),
      );
      await controller.load();
      await controller.setEnabled(true);
      await controller.setApiKey('k');
      await controller.setModel('m');
      final result = await controller.testConnection();
      expect(result.ok, isTrue);
      expect(controller.testOk, isTrue);
    });

    test('fetchModels stores available models', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
        providerFactory: _FakeProviderFactory(
          OpenAiCompatibleAiProvider(
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'k',
            model: '',
            client: MockClient((request) async {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({
                  'data': [
                    {'id': 'gpt-4o-mini'},
                    {'id': 'gpt-4o'},
                  ],
                }),
                200,
              );
            }),
          ),
        ),
      );
      await controller.load();
      await controller.setApiKey('k');
      final models = await controller.fetchModels(
        baseUrl: 'https://api.openai.com/v1',
      );
      expect(models.map((m) => m.id), containsAll(['gpt-4o', 'gpt-4o-mini']));
      expect(controller.availableModels, hasLength(2));
    });

    test('openProvider is null when disabled', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await controller.load();
      await controller.setApiKey('k');
      expect(controller.openProvider(), isNull);
      await controller.setEnabled(true);
      // Default openai model resolves even when model field empty.
      expect(controller.openProvider(), isNotNull);
    });
  });

  group('DefaultAiProviderFactory', () {
    test('routes anthropic vs openai protocols', () {
      const factory = DefaultAiProviderFactory();
      final openai = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.openai,
          model: 'gpt-4o-mini',
        ),
        apiKey: 'k',
      );
      final anthropic = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.anthropic,
          model: 'claude-sonnet-4-5',
        ),
        apiKey: 'k',
      );
      final deepseek = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.deepseek,
          model: 'deepseek-v4-flash',
        ),
        apiKey: 'k',
      );
      final xai = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.xai,
          model: 'grok-4.5',
        ),
        apiKey: 'k',
      );
      final customAnthropic = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.custom,
          customProtocol: AiApiProtocol.anthropic,
          baseUrl: 'https://proxy.example',
          model: 'm',
        ),
        apiKey: 'k',
      );
      final customOpenai = factory.create(
        settings: const AiSettings(
          providerKind: AiProviderKind.custom,
          customProtocol: AiApiProtocol.openai,
          baseUrl: 'https://proxy.example/v1',
          model: 'm',
        ),
        apiKey: 'k',
      );
      expect(openai, isA<OpenAiCompatibleAiProvider>());
      expect(anthropic, isA<AnthropicAiProvider>());
      expect(deepseek, isA<OpenAiCompatibleAiProvider>());
      expect(xai, isA<OpenAiCompatibleAiProvider>());
      expect(customAnthropic, isA<AnthropicAiProvider>());
      expect(customOpenai, isA<OpenAiCompatibleAiProvider>());
      expect(AiProviderKind.xai.defaultBaseUrl, 'https://api.x.ai/v1');
      expect(AiProviderKind.xai.defaultModel, 'grok-4.5');
      expect(AiProviderKind.xai.fixedProtocol, AiApiProtocol.openai);
    });
  });
}

class _AbortableClient extends http.BaseClient {
  final started = Completer<void>();
  final _response = Completer<http.StreamedResponse>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!started.isCompleted) started.complete();
    return _response.future;
  }

  @override
  void close() {
    closed = true;
    if (!_response.isCompleted) {
      _response.completeError(StateError('request aborted'));
    }
  }
}

class _FakeProviderFactory implements AiProviderFactory {
  _FakeProviderFactory(this.provider);

  final AiProvider provider;

  @override
  AiProvider? create({required AiSettings settings, required String apiKey}) =>
      provider;
}

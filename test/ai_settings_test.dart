import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaijuan/ai/adapters/genkit_anthropic_model_adapter.dart';
import 'package:kaijuan/ai/adapters/genkit_openai_model_adapter.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_model_adapter_factory.dart';
import 'package:kaijuan/ai/ai_model_catalog.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_search.dart';
import 'package:kaijuan/ai/ai_settings.dart';
import 'package:kaijuan/ai/ai_settings_store.dart';
import 'package:kaijuan/ai/ai_translation.dart';
import 'package:kaijuan/presentation/controllers/ai_settings_controller.dart';

void main() {
  group('AiProviderKind', () {
    test('resolves storage and defaults', () {
      expect(AiProviderKind.fromStorage('deepseek'), AiProviderKind.deepseek);
      expect(AiProviderKind.openai.defaultBaseUrl, contains('openai.com'));
      expect(
        AiProviderKind.anthropic.defaultBaseUrl,
        'https://api.anthropic.com',
      );
      expect(AiProviderKind.anthropic.defaultModel, 'claude-sonnet-5');
      expect(AiProviderKind.fromStorage('anthropic'), AiProviderKind.anthropic);
      expect(AiProviderKind.deepseek.defaultBaseUrl, contains('deepseek.com'));
    });

    test('ollama is local and OpenAI-compatible', () {
      expect(AiProviderKind.ollama.isLocalBackend, isTrue);
      expect(AiProviderKind.ollama.defaultBaseUrl, contains('localhost:11434'));
      expect(AiProviderKind.fromStorage('ollama'), AiProviderKind.ollama);
      expect(AiProviderKind.openai.isLocalBackend, isFalse);
    });
  });

  group('AiSettings endpoint policy', () {
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
        providerKind: AiProviderKind.deepseek,
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
        allowUnreadContext: true,
      );
      final encoded = jsonEncode(settings.toJson());
      expect(encoded, isNot(contains('sk-')));
      final restored = AiSettings.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(restored.enabled, isTrue);
      expect(restored.providerKind, AiProviderKind.deepseek);
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
      expect(await credentials.readApiKey(AiProviderKind.xai), isNull);
    });

    test('testConnection succeeds through the model adapter', () async {
      final adapter = _ConnectionAdapter();
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
        modelAdapterFactory: _FakeModelAdapterFactory(adapter),
      );
      await controller.load();
      await controller.setEnabled(true);
      await controller.setApiKey('k');
      await controller.setModel('m');
      final result = await controller.testConnection();
      expect(result.ok, isTrue);
      expect(controller.testOk, isTrue);
      expect(adapter.closed, isTrue);
    });

    test(
      'testConnection rejects an empty terminal and still closes adapter',
      () async {
        final adapter = _ConnectionAdapter(text: '');
        final controller = AiSettingsController(
          settingsStore: MemoryAiSettingsStore(),
          credentialStore: MemoryAiCredentialStore(),
          modelAdapterFactory: _FakeModelAdapterFactory(adapter),
        );
        await controller.load();
        await controller.setEnabled(true);
        await controller.setApiKey('k');
        final result = await controller.testConnection();

        expect(result.ok, isFalse);
        expect(adapter.closed, isTrue);
      },
    );

    test('fetchModels stores available models', () async {
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
        modelCatalog: const _FakeModelCatalog([
          AiModelInfo(id: 'gpt-4o-mini'),
          AiModelInfo(id: 'gpt-4o'),
        ]),
      );
      await controller.load();
      await controller.setApiKey('k');
      final models = await controller.fetchModels(
        baseUrl: 'https://api.openai.com/v1',
      );
      expect(models.map((m) => m.id), containsAll(['gpt-4o', 'gpt-4o-mini']));
      expect(controller.availableModels, hasLength(2));
    });

    test('openModelAdapter is null when disabled', () async {
      final adapter = _ConnectionAdapter();
      final controller = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
        modelAdapterFactory: _FakeModelAdapterFactory(adapter),
      );
      await controller.load();
      await controller.setApiKey('k');
      expect(controller.openModelAdapter(), isNull);
      await controller.setEnabled(true);
      // Default openai model resolves even when model field empty.
      expect(controller.openModelAdapter(), same(adapter));
    });
  });

  group('DefaultAiModelAdapterFactory', () {
    test('uses Anthropic adapter only for Anthropic preset', () {
      const factory = DefaultAiModelAdapterFactory();
      final anthropic = factory.create(
        providerKind: AiProviderKind.anthropic,
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'k',
        model: 'claude-sonnet-4-6',
      );
      final deepseek = factory.create(
        providerKind: AiProviderKind.deepseek,
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'k',
        model: 'deepseek-v4-flash',
      );

      expect(anthropic, isA<GenkitAnthropicModelAdapter>());
      expect(deepseek, isA<GenkitOpenAiModelAdapter>());
    });

    test('does not construct Anthropic adapter without a key', () {
      const factory = DefaultAiModelAdapterFactory();
      expect(
        factory.create(
          providerKind: AiProviderKind.anthropic,
          baseUrl: 'https://api.anthropic.com',
          apiKey: '',
          model: 'claude-sonnet-4-6',
        ),
        isNull,
      );
    });
  });
}

final class _FakeModelAdapterFactory implements AiModelAdapterFactory {
  const _FakeModelAdapterFactory(this.adapter);

  final AiModelAdapter adapter;

  @override
  AiModelAdapter? create({
    required AiProviderKind providerKind,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) => adapter;
}

final class _ConnectionAdapter implements AiModelAdapter {
  _ConnectionAdapter({this.text = 'ok'});

  final String text;
  bool closed = false;

  @override
  String get runtimeName => 'connection-test';

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) async* {
    yield AiModelTurnCompleted(
      text: text,
      toolCalls: const [],
      truncated: false,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _FakeModelCatalog implements AiModelCatalog {
  const _FakeModelCatalog(this.models);

  final List<AiModelInfo> models;

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderKind providerKind,
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  }) async => models;
}

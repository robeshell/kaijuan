import 'package:flutter/foundation.dart';

import '../../ai/ai_log.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_provider.dart';
import '../../ai/ai_provider_kind.dart';
import '../../ai/ai_search.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_translation.dart';

/// Presentation state for AI settings. Never exposes raw HTTP or secure storage
/// handles to widgets.
class AiSettingsController extends ChangeNotifier {
  AiSettingsController({
    required this.settingsStore,
    required this.credentialStore,
    this.providerFactory = const DefaultAiProviderFactory(),
    AiWebSearchService? searchService,
  }) : searchService = searchService ?? AiWebSearchService();

  final AiSettingsStore settingsStore;
  final AiCredentialStore credentialStore;
  final AiProviderFactory providerFactory;
  final AiWebSearchService searchService;

  AiSettings _settings = const AiSettings();
  String _apiKey = '';
  String _searchApiKey = '';
  bool _loaded = false;
  bool _testing = false;
  bool _listingModels = false;
  String? _testMessage;
  bool? _testOk;
  List<AiModelInfo> _availableModels = const [];
  String? _modelsError;

  AiSettings get settings => _settings;
  String get apiKey => _apiKey;
  String get searchApiKey => _searchApiKey;
  bool get isLoaded => _loaded;
  bool get isTesting => _testing;
  bool _testingSearch = false;
  bool get isTestingSearch => _testingSearch;
  String? _searchTestMessage;
  String? get searchTestMessage => _searchTestMessage;
  bool get isListingModels => _listingModels;
  bool get isBusy => _testing || _listingModels;
  String? get testMessage => _testMessage;
  bool? get testOk => _testOk;
  List<AiModelInfo> get availableModels => _availableModels;
  String? get modelsError => _modelsError;

  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  bool get hasSearchApiKey => _searchApiKey.trim().isNotEmpty;

  /// Search Key present for the selected search provider (chat 联网 toggle).
  bool get isSearchReady => hasSearchApiKey;

  /// Ready for M1+ language features: switch on, key present (cloud only),
  /// URL/model resolvable.
  bool get isReadyForRequests =>
      _settings.enabled &&
      (!_settings.requiresApiKey || hasApiKey) &&
      _settings.resolvedBaseUrl.isNotEmpty &&
      _settings.resolvedModel.isNotEmpty;

  Future<void> load() async {
    _settings = await settingsStore.read();
    _apiKey =
        await credentialStore.readApiKey(_settings.providerKind) ?? '';
    _searchApiKey =
        await credentialStore.readSearchApiKey(_settings.searchProviderKind) ??
        '';
    _loaded = true;
    _testMessage = null;
    _testOk = null;
    _availableModels = const [];
    _modelsError = null;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_settings.enabled == value) return;
    _settings = _settings.copyWith(enabled: value);
    await settingsStore.write(_settings);
    notifyListeners();
  }

  Future<void> setProviderKind(AiProviderKind kind) async {
    if (_settings.providerKind == kind) return;
    final previous = _settings.providerKind;
    // Persist the key currently in memory under the provider we are leaving.
    // Skip empty writes: callers flush non-empty drafts first; empty would only
    // trigger a no-op/delete that can fail on some macOS keychain setups.
    if (_apiKey.trim().isNotEmpty) {
      await credentialStore.writeApiKey(previous, _apiKey);
    }

    var baseUrl = _settings.baseUrl;
    var model = _settings.model;
    // Local backends have a fixed localhost endpoint and no cross-provider
    // model; switching to/from them resets both. Cloud presets keep a user's
    // custom URL but swap the preset default for the new provider's default.
    if (kind.isLocalBackend || previous.isLocalBackend) {
      baseUrl = kind.defaultBaseUrl;
      model = kind.defaultModel;
    } else {
      if (baseUrl.trim().isEmpty || baseUrl.trim() == previous.defaultBaseUrl) {
        baseUrl = kind.defaultBaseUrl;
      }
      if (model.trim().isEmpty || model.trim() == previous.defaultModel) {
        model = kind.defaultModel;
      }
    }
    _settings = _settings.copyWith(
      providerKind: kind,
      baseUrl: baseUrl,
      model: model,
    );
    await settingsStore.write(_settings);
    // Load the destination provider's own key — never reuse the previous one.
    _apiKey = await credentialStore.readApiKey(kind) ?? '';
    _availableModels = const [];
    _modelsError = null;
    _clearTest();
    notifyListeners();
  }

  Future<void> setCustomProtocol(AiApiProtocol protocol) async {
    if (_settings.customProtocol == protocol) return;
    _settings = _settings.copyWith(customProtocol: protocol);
    await settingsStore.write(_settings);
    _availableModels = const [];
    _modelsError = null;
    _clearTest();
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    if (_settings.baseUrl == value) return;
    _settings = _settings.copyWith(baseUrl: value);
    await settingsStore.write(_settings);
    _availableModels = const [];
    _modelsError = null;
    _clearTest();
    notifyListeners();
  }

  Future<void> setModel(String value) async {
    if (_settings.model == value) return;
    _settings = _settings.copyWith(model: value);
    await settingsStore.write(_settings);
    _clearTest();
    notifyListeners();
  }

  Future<void> setAllowUnreadContext(bool value) async {
    if (_settings.allowUnreadContext == value) return;
    _settings = _settings.copyWith(allowUnreadContext: value);
    await settingsStore.write(_settings);
    notifyListeners();
  }

  Future<void> setTranslation(AiTranslationPreferences value) async {
    _settings = _settings.copyWith(translation: value);
    await settingsStore.write(_settings);
    notifyListeners();
  }

  Future<void> updateTranslation(
    AiTranslationPreferences Function(AiTranslationPreferences current) update,
  ) {
    return setTranslation(update(_settings.translation));
  }

  Future<void> setSearchProviderKind(AiSearchProviderKind kind) async {
    if (_settings.searchProviderKind == kind) return;
    final previous = _settings.searchProviderKind;
    if (_searchApiKey.trim().isNotEmpty) {
      await credentialStore.writeSearchApiKey(previous, _searchApiKey);
    }
    _settings = _settings.copyWith(searchProviderKind: kind);
    await settingsStore.write(_settings);
    _searchApiKey = await credentialStore.readSearchApiKey(kind) ?? '';
    notifyListeners();
  }

  Future<void> setSearchApiKey(String value, {bool notify = true}) async {
    if (_searchApiKey == value) return;
    _searchApiKey = value;
    await credentialStore.writeSearchApiKey(
      _settings.searchProviderKind,
      value,
    );
    if (notify) notifyListeners();
  }

  Future<void> clearSearchApiKey() async {
    _searchApiKey = '';
    await credentialStore.deleteSearchApiKey(_settings.searchProviderKind);
    notifyListeners();
  }

  /// Live web search for book chat when the in-panel 联网 switch is on.
  Future<List<AiWebSearchHit>> searchWeb(
    String query, {
    int maxResults = 5,
  }) {
    return searchService.search(
      provider: _settings.searchProviderKind,
      apiKey: _searchApiKey,
      query: query,
      maxResults: maxResults,
    );
  }

  /// Persist API key for the **current** provider.
  /// Prefer [notify]: false while the user is typing so the settings form does
  /// not rebuild mid-keystroke / mid-paste on macOS.
  Future<void> setApiKey(String value, {bool notify = true}) async {
    if (_apiKey == value) return;
    _apiKey = value;
    await credentialStore.writeApiKey(_settings.providerKind, value);
    _clearTest();
    if (notify) notifyListeners();
  }

  Future<void> clearApiKey() async {
    _apiKey = '';
    await credentialStore.deleteApiKey(_settings.providerKind);
    _clearTest();
    notifyListeners();
  }

  /// Applies field values from the settings form without intermediate rebuilds.
  /// The API key is written only for [AiSettings.providerKind].
  Future<void> applyDraft({
    required String apiKey,
    required String baseUrl,
    required String model,
    AiGraphRuleWords? graphRuleWords,
  }) async {
    final key = apiKey;
    final url = baseUrl.trim();
    final modelId = model.trim();
    var changed = false;

    if (_apiKey != key) {
      _apiKey = key;
      await credentialStore.writeApiKey(_settings.providerKind, key);
      changed = true;
    }
    if (_settings.baseUrl != url || _settings.model != modelId) {
      _settings = _settings.copyWith(baseUrl: url, model: modelId);
      await settingsStore.write(_settings);
      changed = true;
    }
    final words = graphRuleWords;
    if (words != null && !_sameRuleWords(_settings.graphRuleWords, words)) {
      _settings = _settings.copyWith(graphRuleWords: words);
      await settingsStore.write(_settings);
      changed = true;
    }
    if (changed) {
      _clearTest();
      notifyListeners();
    }
  }

  static bool _sameRuleWords(AiGraphRuleWords a, AiGraphRuleWords b) {
    bool sameList(List<String> x, List<String> y) {
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
      return true;
    }

    return sameList(a.appendixUnits, b.appendixUnits) &&
        sameList(a.metadataUnits, b.metadataUnits) &&
        sameList(a.citationQuoteTemplates, b.citationQuoteTemplates) &&
        sameList(a.relationTypes, b.relationTypes) &&
        _sameMap(a.relationTypeAliases, b.relationTypeAliases) &&
        sameList(a.personTitleSuffixes, b.personTitleSuffixes) &&
        sameList(a.genericPersonTerms, b.genericPersonTerms) &&
        _samePriors(a.bookNamePriors, b.bookNamePriors);
  }

  static bool _samePriors(
    Map<String, Map<String, String>> a,
    Map<String, Map<String, String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!_sameMap(entry.value, b[entry.key] ?? const {})) return false;
    }
    return true;
  }

  static bool _sameMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Builds a live provider when settings + key are complete. Null otherwise.
  AiProvider? openProvider() {
    if (!_settings.enabled) return null;
    if (_settings.resolvedModel.isEmpty) return null;
    return providerFactory.create(settings: _settings, apiKey: _apiKey);
  }

  /// Probes the configured search provider with one trivial query.
  Future<void> testSearch() async {
    if (_testingSearch) return;
    _testingSearch = true;
    _searchTestMessage = null;
    notifyListeners();
    try {
      final hits = await AiWebSearchService().search(
        provider: _settings.searchProviderKind,
        apiKey: _searchApiKey,
        query: '开卷阅读器联网搜索测试',
        maxResults: 1,
      );
      _searchTestMessage = hits.isEmpty
          ? '搜索服务可用，但返回了空结果'
          : '搜索服务可用（测试返回 ${hits.length} 条结果）';
    } catch (e) {
      _searchTestMessage = '搜索失败：$e';
    } finally {
      _testingSearch = false;
      notifyListeners();
    }
  }

  Future<AiConnectionTestResult> testConnection({
    String? apiKey,
    String? baseUrl,
    String? model,
  }) async {
    if (_testing) {
      AiLog.d('testConnection skipped: already testing');
      return const AiConnectionTestResult.failure('正在测试中');
    }
    if (apiKey != null || baseUrl != null || model != null) {
      await applyDraft(
        apiKey: apiKey ?? _apiKey,
        baseUrl: baseUrl ?? _settings.baseUrl,
        model: model ?? _settings.model,
      );
    }

    final key = _apiKey.trim();
    AiLog.d(
      'testConnection start provider=${_settings.providerKind.displayName} '
      'protocol=${_settings.resolvedProtocol.displayName} '
      'base=${_settings.resolvedBaseUrl} model=${_settings.resolvedModel} '
      'key=${AiLog.maskKey(key)}',
    );
    if (_settings.requiresApiKey && key.isEmpty) {
      final result = const AiConnectionTestResult.failure('请先填写 API Key');
      AiLog.d('testConnection fail: empty key');
      _applyTest(result);
      notifyListeners();
      return result;
    }
    if (_settings.resolvedBaseUrl.isEmpty) {
      final result = const AiConnectionTestResult.failure('请填写接口地址');
      AiLog.d('testConnection fail: empty base url');
      _applyTest(result);
      notifyListeners();
      return result;
    }
    if (_settings.resolvedModel.isEmpty) {
      final result = const AiConnectionTestResult.failure('请填写模型名称');
      AiLog.d('testConnection fail: empty model');
      _applyTest(result);
      notifyListeners();
      return result;
    }

    final provider = providerFactory.create(
      settings: _settings,
      apiKey: key,
    );
    if (provider == null) {
      final result = const AiConnectionTestResult.failure('无法创建连接，请检查配置');
      AiLog.d('testConnection fail: factory returned null');
      _applyTest(result);
      notifyListeners();
      return result;
    }

    _testing = true;
    _testMessage = null;
    _testOk = null;
    notifyListeners();

    final sw = Stopwatch()..start();
    try {
      // maxTokens must leave room beyond any residual reasoning; DeepSeek
      // thinking is disabled in the OpenAI-compatible body for deepseek hosts.
      final completion = await provider.complete(
        const AiCompletionRequest(
          messages: [
            AiMessage(
              role: AiMessageRole.user,
              content: 'Reply with exactly: ok',
            ),
          ],
          maxTokens: 64,
          temperature: 0,
        ),
      );
      final detail = completion.text.length > 80
          ? '${completion.text.substring(0, 80)}…'
          : completion.text;
      final result = AiConnectionTestResult.success(detail: detail);
      AiLog.d(
        'testConnection ok in ${sw.elapsedMilliseconds}ms '
        'reply="${AiLog.bodyPreview(detail, max: 80)}"',
      );
      _applyTest(result);
      return result;
    } on AiProviderException catch (error) {
      AiLog.d(
        'testConnection fail in ${sw.elapsedMilliseconds}ms '
        'status=${error.statusCode} msg=${error.message}',
      );
      final result = AiConnectionTestResult.failure(error.message);
      _applyTest(result);
      return result;
    } catch (error, stack) {
      AiLog.d(
        'testConnection error in ${sw.elapsedMilliseconds}ms: $error\n$stack',
      );
      final result = const AiConnectionTestResult.failure(
        '无法连接，请检查网络与接口地址',
      );
      _applyTest(result);
      return result;
    } finally {
      _testing = false;
      notifyListeners();
    }
  }

  Future<List<AiModelInfo>> fetchModels({
    String? apiKey,
    String? baseUrl,
    String? model,
  }) async {
    if (_listingModels) return _availableModels;
    if (apiKey != null || baseUrl != null || model != null) {
      await applyDraft(
        apiKey: apiKey ?? _apiKey,
        baseUrl: baseUrl ?? _settings.baseUrl,
        model: model ?? _settings.model,
      );
    }

    final key = _apiKey.trim();
    AiLog.d(
      'fetchModels start provider=${_settings.providerKind.displayName} '
      'protocol=${_settings.resolvedProtocol.displayName} '
      'base=${_settings.resolvedBaseUrl} key=${AiLog.maskKey(key)}',
    );
    if (_settings.requiresApiKey && key.isEmpty) {
      _modelsError = '请先填写 API Key';
      _availableModels = const [];
      notifyListeners();
      AiLog.d('fetchModels fail: empty key');
      throw AiProviderException(_modelsError!);
    }
    if (_settings.resolvedBaseUrl.isEmpty) {
      _modelsError = '请填写接口地址';
      _availableModels = const [];
      notifyListeners();
      AiLog.d('fetchModels fail: empty base url');
      throw AiProviderException(_modelsError!);
    }

    final provider = providerFactory.create(
      settings: _settings,
      apiKey: key,
    );
    if (provider == null) {
      _modelsError = '无法创建连接，请检查配置';
      _availableModels = const [];
      notifyListeners();
      AiLog.d('fetchModels fail: factory returned null');
      throw AiProviderException(_modelsError!);
    }

    _listingModels = true;
    _modelsError = null;
    notifyListeners();

    final sw = Stopwatch()..start();
    try {
      final models = await provider.listModels();
      _availableModels = models;
      _modelsError = null;
      AiLog.d(
        'fetchModels ok in ${sw.elapsedMilliseconds}ms count=${models.length} '
        'sample=${models.take(5).map((m) => m.id).join(', ')}',
      );
      return models;
    } on AiProviderException catch (error) {
      _availableModels = const [];
      _modelsError = error.message;
      AiLog.d(
        'fetchModels fail in ${sw.elapsedMilliseconds}ms '
        'status=${error.statusCode} msg=${error.message}',
      );
      rethrow;
    } catch (error, stack) {
      _availableModels = const [];
      _modelsError = '获取模型失败，请检查网络与接口地址';
      AiLog.d(
        'fetchModels error in ${sw.elapsedMilliseconds}ms: $error\n$stack',
      );
      throw AiProviderException(_modelsError!);
    } finally {
      _listingModels = false;
      notifyListeners();
    }
  }

  void _applyTest(AiConnectionTestResult result) {
    _testOk = result.ok;
    _testMessage = result.ok
        ? (result.detail == null || result.detail!.isEmpty
              ? result.message
              : '${result.message}（${result.detail}）')
        : result.message;
  }

  void _clearTest() {
    _testMessage = null;
    _testOk = null;
  }
}

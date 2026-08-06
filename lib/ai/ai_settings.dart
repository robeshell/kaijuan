import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_provider_kind.dart';
import 'ai_search.dart';
import 'ai_translation.dart';

/// Tunable word lists that drive the graph-pipeline hard rules. Kept in
/// settings so the user can extend them without a code change; the const
/// constructor carries today's built-in defaults.
class AiGraphRuleWords {
  const AiGraphRuleWords({
    this.appendixUnits = defaultAppendixUnits,
    this.metadataUnits = defaultMetadataUnits,
    this.citationQuoteTemplates = defaultCitationQuoteTemplates,
  });

  /// Front/back-matter unit words matched as a PREFIX of a section label
  /// (附录, 后记, 文前辅文, 序 ...). Lines starting with `!` are exclusions
  /// applied as a leading negative lookahead (e.g. `!序曲` keeps 序曲 as a
  /// body opening instead of a front-matter 序).
  final List<String> appendixUnits;

  /// Metadata titles matched EXACTLY (目录, 版权, 封面 ...).
  final List<String> metadataUnits;

  /// Citation-quote templates; `{name}` is replaced with the entity name
  /// (e.g. `据{name}`, `{name}写道`).
  final List<String> citationQuoteTemplates;

  static const defaultAppendixUnits = <String>[
    '附录',
    '参考书目',
    '参考文献',
    '参考资料',
    '人名索引',
    '地名索引',
    '主题索引',
    '关键词索引',
    '索引',
    '致谢',
    '谢辞',
    '鸣谢',
    '后记',
    '跋',
    '注释',
    '年表',
    '词汇表',
    '术语表',
    '缩略语表',
    '勘误',
    '勘误表',
    '卷末',
    '书末',
    '前言',
    '序言',
    '序',
    '自序',
    '代序',
    '弁言',
    '小引',
    '凡例',
    '出版说明',
    '出版前言',
    '出版后记',
    '出版者的话',
    '编者按',
    '导读',
    '题记',
    '题词',
    '题辞',
    '题献',
    '献词',
    '献页',
    '致献',
    '重印前记',
    '重印后记',
    '再版前记',
    '再版后记',
    '再版说明',
    '重印说明',
    '修订说明',
    '修订版说明',
    '校订说明',
    '点校说明',
    '整理说明',
    '编译说明',
    '编写说明',
    '译者序',
    '译者前言',
    '译者后记',
    '译后记',
    '译序',
    '校后记',
    '编后',
    '编后记',
    '文前辅文',
    '文前',
    '辅文',
    '前置部分',
    '卷首',
    '卷首语',
    '扉页',
    '书名页',
    '版权页',
    '衬页',
    '环衬',
    '飞页',
    '插页',
    '内容简介',
    '内容提要',
    '图书简介',
    '作者简介',
    '关于作者',
    '关于本书',
    '封面语',
    '封底语',
    '!序曲',
    '!序章',
    '!序幕',
    '!序篇',
  ];

  static const defaultMetadataUnits = <String>[
    '目录',
    '总目录',
    '全书目录',
    '章节目录',
    '目次',
    '版权',
    '版权信息',
    '版权页',
    '版权记录',
    '出版',
    '出版信息',
    '出版说明',
    '出版记录',
    '出版前言',
    '出版后记',
    '图书在版编目',
    '版本记录',
    '封面',
    '封底',
    '扉页',
    '书名页',
    '护封',
    '腰封',
  ];

  static const defaultCitationQuoteTemplates = <String>[
    '据{name}',
    '按{name}',
    '如{name}所言',
    '正如{name}所说',
    '{name}曾说',
    '{name}写道',
    '{name}所言',
    '据说{name}',
  ];

  AiGraphRuleWords copyWith({
    List<String>? appendixUnits,
    List<String>? metadataUnits,
    List<String>? citationQuoteTemplates,
  }) {
    return AiGraphRuleWords(
      appendixUnits: appendixUnits ?? this.appendixUnits,
      metadataUnits: metadataUnits ?? this.metadataUnits,
      citationQuoteTemplates:
          citationQuoteTemplates ?? this.citationQuoteTemplates,
    );
  }

  Map<String, Object?> toJson() => {
    'appendixUnits': appendixUnits,
    'metadataUnits': metadataUnits,
    'citationQuoteTemplates': citationQuoteTemplates,
  };

  static AiGraphRuleWords fromJson(Object? json) {
    if (json is! Map) return const AiGraphRuleWords();
    final map = Map<String, dynamic>.from(json);
    return AiGraphRuleWords(
      appendixUnits:
          (map['appendixUnits'] as List?)?.cast<String>() ??
          const AiGraphRuleWords().appendixUnits,
      metadataUnits:
          (map['metadataUnits'] as List?)?.cast<String>() ??
          const AiGraphRuleWords().metadataUnits,
      citationQuoteTemplates:
          (map['citationQuoteTemplates'] as List?)?.cast<String>() ??
          const AiGraphRuleWords().citationQuoteTemplates,
    );
  }
}

/// Non-secret AI preferences. The API key lives only in secure storage.
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.providerKind = AiProviderKind.openai,
    this.customProtocol = AiApiProtocol.openai,
    this.baseUrl = '',
    this.model = '',
    this.allowUnreadContext = false,
    this.translation = const AiTranslationPreferences(),
    this.searchProviderKind = AiSearchProviderKind.tavily,
    this.graphRuleWords = const AiGraphRuleWords(),
  });

  final bool enabled;
  final AiProviderKind providerKind;

  /// API wire format when [providerKind] is [AiProviderKind.custom].
  /// Presets ignore this and use [AiProviderKind.fixedProtocol].
  final AiApiProtocol customProtocol;

  /// Effective base URL. Empty means "use the preset default".
  final String baseUrl;

  /// Model id. Empty means "use the preset default".
  final String model;

  /// When true, generated book outlines may include unread sections.
  final bool allowUnreadContext;

  /// Selection / whole-book translation preferences (not per-provider).
  final AiTranslationPreferences translation;

  /// Web search backend for book-chat「联网」(key in secure storage).
  final AiSearchProviderKind searchProviderKind;

  /// Word lists driving the graph pipeline hard rules.
  final AiGraphRuleWords graphRuleWords;

  /// Resolved protocol for the current provider selection.
  AiApiProtocol get resolvedProtocol =>
      providerKind.fixedProtocol ?? customProtocol;

  bool get usesAnthropicProtocol =>
      resolvedProtocol == AiApiProtocol.anthropic;

  bool get usesOpenAiProtocol => resolvedProtocol == AiApiProtocol.openai;

  String get resolvedBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.isNotEmpty) return _stripTrailingSlash(trimmed);
    return _stripTrailingSlash(providerKind.defaultBaseUrl);
  }

  String get resolvedModel {
    final trimmed = model.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return providerKind.defaultModel;
  }

  /// Cloud presets always need an API key; local backends (Ollama) skip it.
  bool get requiresApiKey => !providerKind.isLocalBackend;

  AiSettings copyWith({
    bool? enabled,
    AiProviderKind? providerKind,
    AiApiProtocol? customProtocol,
    String? baseUrl,
    String? model,
    bool? allowUnreadContext,
    AiTranslationPreferences? translation,
    AiSearchProviderKind? searchProviderKind,
    AiGraphRuleWords? graphRuleWords,
  }) {
    return AiSettings(
      enabled: enabled ?? this.enabled,
      providerKind: providerKind ?? this.providerKind,
      customProtocol: customProtocol ?? this.customProtocol,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      allowUnreadContext: allowUnreadContext ?? this.allowUnreadContext,
      translation: translation ?? this.translation,
      searchProviderKind: searchProviderKind ?? this.searchProviderKind,
      graphRuleWords: graphRuleWords ?? this.graphRuleWords,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'providerKind': providerKind.storageValue,
    'customProtocol': customProtocol.storageValue,
    'baseUrl': baseUrl,
    'model': model,
    'allowUnreadContext': allowUnreadContext,
    'translation': translation.toJson(),
    'searchProviderKind': searchProviderKind.storageValue,
    'graphRuleWords': graphRuleWords.toJson(),
  };

  static AiSettings fromJson(Map<String, dynamic> json) {
    final translationRaw = json['translation'];
    return AiSettings(
      enabled: json['enabled'] as bool? ?? false,
      providerKind: AiProviderKind.fromStorage(json['providerKind'] as String?),
      customProtocol: AiApiProtocol.fromStorage(
        json['customProtocol'] as String?,
      ),
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      allowUnreadContext: json['allowUnreadContext'] as bool? ?? false,
      translation: AiTranslationPreferences.fromJson(
        translationRaw is Map
            ? Map<String, dynamic>.from(translationRaw)
            : null,
      ),
      searchProviderKind: AiSearchProviderKind.fromStorage(
        json['searchProviderKind'] as String?,
      ),
      graphRuleWords: AiGraphRuleWords.fromJson(json['graphRuleWords']),
    );
  }

  static String _stripTrailingSlash(String value) {
    if (value.length > 1 && value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}

abstract interface class AiSettingsStore {
  Future<AiSettings> read();
  Future<void> write(AiSettings settings);
}

/// API keys are stored **per** [AiProviderKind] so switching providers never
/// reuses another vendor's secret. Search keys are per [AiSearchProviderKind].
abstract interface class AiCredentialStore {
  Future<String?> readApiKey(AiProviderKind kind);
  Future<void> writeApiKey(AiProviderKind kind, String apiKey);
  Future<void> deleteApiKey(AiProviderKind kind);

  Future<String?> readSearchApiKey(AiSearchProviderKind kind);
  Future<void> writeSearchApiKey(AiSearchProviderKind kind, String apiKey);
  Future<void> deleteSearchApiKey(AiSearchProviderKind kind);
}

class JsonAiSettingsStore implements AiSettingsStore {
  JsonAiSettingsStore(this._file);

  final File _file;

  @override
  Future<AiSettings> read() async {
    try {
      if (!await _file.exists()) return const AiSettings();
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return const AiSettings();
      return AiSettings.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return const AiSettings();
    }
  }

  @override
  Future<void> write(AiSettings settings) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(settings.toJson()),
      flush: true,
    );
  }
}

class SecureAiCredentialStore implements AiCredentialStore {
  SecureAiCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Same as WebDAV credentials: avoid data-protection keychain so
            // ad-hoc sandboxed macOS debug builds do not need Keychain Sharing.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  /// Pre–per-provider key; migrated into the active provider slot once.
  static const _legacyKey = 'kaijuan.ai.api_key';

  final FlutterSecureStorage _storage;
  bool _legacyMigrated = false;

  String _storageKey(AiProviderKind kind) =>
      'kaijuan.ai.api_key.${kind.storageValue}';

  String _searchStorageKey(AiSearchProviderKind kind) =>
      'kaijuan.ai.search_api_key.${kind.storageValue}';

  @override
  Future<String?> readApiKey(AiProviderKind kind) async {
    await _migrateLegacyIfNeeded(kind);
    try {
      final value = await _storage.read(key: _storageKey(kind));
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      // Missing entitlement / keychain errors must not crash settings UI.
      return null;
    }
  }

  @override
  Future<void> writeApiKey(AiProviderKind kind, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteApiKey(kind);
      return;
    }
    try {
      await _storage.write(key: _storageKey(kind), value: trimmed);
    } catch (_) {
      // Best-effort; UI still holds the in-memory draft.
    }
  }

  @override
  Future<void> deleteApiKey(AiProviderKind kind) async {
    final key = _storageKey(kind);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // macOS can return -34018 (missing entitlement) on delete for some
      // ad-hoc sandbox setups. Overwrite with empty so reads treat as cleared.
      try {
        await _storage.write(key: key, value: '');
      } catch (_) {}
    }
  }

  @override
  Future<String?> readSearchApiKey(AiSearchProviderKind kind) async {
    try {
      final value = await _storage.read(key: _searchStorageKey(kind));
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeSearchApiKey(
    AiSearchProviderKind kind,
    String apiKey,
  ) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteSearchApiKey(kind);
      return;
    }
    try {
      await _storage.write(key: _searchStorageKey(kind), value: trimmed);
    } catch (_) {}
  }

  @override
  Future<void> deleteSearchApiKey(AiSearchProviderKind kind) async {
    final key = _searchStorageKey(kind);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      try {
        await _storage.write(key: key, value: '');
      } catch (_) {}
    }
  }

  /// One-shot: if an old single-key value exists and the slot for [kind] is
  /// empty, copy it there then remove the legacy entry.
  Future<void> _migrateLegacyIfNeeded(AiProviderKind kind) async {
    if (_legacyMigrated) return;
    _legacyMigrated = true;
    try {
      final legacy = await _storage.read(key: _legacyKey);
      if (legacy == null || legacy.isEmpty) return;
      final existing = await _storage.read(key: _storageKey(kind));
      if (existing == null || existing.isEmpty) {
        await _storage.write(key: _storageKey(kind), value: legacy);
      }
      try {
        await _storage.delete(key: _legacyKey);
      } catch (_) {
        try {
          await _storage.write(key: _legacyKey, value: '');
        } catch (_) {}
      }
    } catch (_) {
      // Best-effort migration; ignore secure-storage edge failures.
    }
  }
}

class MemoryAiSettingsStore implements AiSettingsStore {
  AiSettings _settings = const AiSettings();

  @override
  Future<AiSettings> read() async => _settings;

  @override
  Future<void> write(AiSettings settings) async {
    _settings = settings;
  }
}

class MemoryAiCredentialStore implements AiCredentialStore {
  final Map<AiProviderKind, String> _keys = {};
  final Map<AiSearchProviderKind, String> _searchKeys = {};

  @override
  Future<String?> readApiKey(AiProviderKind kind) async => _keys[kind];

  @override
  Future<void> writeApiKey(AiProviderKind kind, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      _keys.remove(kind);
    } else {
      _keys[kind] = trimmed;
    }
  }

  @override
  Future<void> deleteApiKey(AiProviderKind kind) async {
    _keys.remove(kind);
  }

  @override
  Future<String?> readSearchApiKey(AiSearchProviderKind kind) async =>
      _searchKeys[kind];

  @override
  Future<void> writeSearchApiKey(
    AiSearchProviderKind kind,
    String apiKey,
  ) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      _searchKeys.remove(kind);
    } else {
      _searchKeys[kind] = trimmed;
    }
  }

  @override
  Future<void> deleteSearchApiKey(AiSearchProviderKind kind) async {
    _searchKeys.remove(kind);
  }
}

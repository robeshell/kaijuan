import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_provider_kind.dart';
import 'ai_search.dart';
import 'ai_settings.dart';

abstract interface class AiSettingsStore {
  Future<AiSettings> read();
  Future<void> write(AiSettings settings);
}

/// Secrets are stored per provider so switching vendors never reuses a key.
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
  File get _backup => File('${_file.path}.previous');

  Future<AiSettings> _decode(File file) async {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) throw const FormatException('AI 设置格式无法识别');
    return AiSettings.fromJson(Map<String, dynamic>.from(json));
  }

  @override
  Future<AiSettings> read() async {
    try {
      if (await _file.exists()) return await _decode(_file);
      if (await _backup.exists()) return await _decode(_backup);
      return const AiSettings();
    } catch (_) {
      try {
        if (await _backup.exists()) return await _decode(_backup);
      } catch (_) {}
      return const AiSettings();
    }
  }

  @override
  Future<void> write(AiSettings settings) async {
    await _file.parent.create(recursive: true);
    final temporary = File(
      '${_file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
      if (await _file.exists()) {
        if (await _backup.exists()) await _backup.delete();
        await _file.rename(_backup.path);
        try {
          await temporary.rename(_file.path);
        } catch (_) {
          if (!await _file.exists() && await _backup.exists()) {
            await _backup.rename(_file.path);
          }
          rethrow;
        }
      } else {
        await temporary.rename(_file.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class SecureAiCredentialStore implements AiCredentialStore {
  SecureAiCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

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
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeApiKey(AiProviderKind kind, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return deleteApiKey(kind);
    try {
      await _storage.write(key: _storageKey(kind), value: trimmed);
    } catch (_) {}
  }

  @override
  Future<void> deleteApiKey(AiProviderKind kind) async {
    final key = _storageKey(kind);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      try {
        await _storage.write(key: key, value: '');
      } catch (_) {}
    }
  }

  @override
  Future<String?> readSearchApiKey(AiSearchProviderKind kind) async {
    try {
      final value = await _storage.read(key: _searchStorageKey(kind));
      return value == null || value.isEmpty ? null : value;
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
    if (trimmed.isEmpty) return deleteSearchApiKey(kind);
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
    } catch (_) {}
  }
}

class MemoryAiSettingsStore implements AiSettingsStore {
  AiSettings _settings = const AiSettings();

  @override
  Future<AiSettings> read() async => _settings;

  @override
  Future<void> write(AiSettings settings) async => _settings = settings;
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
  Future<void> deleteApiKey(AiProviderKind kind) async => _keys.remove(kind);

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
  Future<void> deleteSearchApiKey(AiSearchProviderKind kind) async =>
      _searchKeys.remove(kind);
}

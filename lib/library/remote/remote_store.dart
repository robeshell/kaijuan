import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'remote_models.dart';

abstract interface class RemoteConnectionStore {
  Future<List<RemoteConnection>> read();

  Future<void> write(List<RemoteConnection> connections);
}

class JsonRemoteConnectionStore implements RemoteConnectionStore {
  JsonRemoteConnectionStore(this.file);

  final File file;

  @override
  Future<List<RemoteConnection>> read() async {
    if (!await file.exists()) return const [];
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! List) return const [];
      final connections = <RemoteConnection>[];
      for (final item in value.whereType<Map>()) {
        final connection = RemoteConnection.fromJson(
          item.map<String, Object?>((key, value) => MapEntry('$key', value)),
        );
        if (connection != null) connections.add(connection);
      }
      return connections;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<RemoteConnection> connections) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.partial');
    await temp.writeAsString(
      jsonEncode([for (final connection in connections) connection.toJson()]),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

abstract interface class RemoteCredentialStore {
  Future<RemoteCredentials?> read(String connectionId);

  Future<void> write(String connectionId, RemoteCredentials credentials);

  Future<void> delete(String connectionId);
}

class SecureRemoteCredentialStore implements RemoteCredentialStore {
  SecureRemoteCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The macOS data-protection keychain requires Keychain Sharing
            // entitlements, which would force local debug builds away from
            // the repository's ad-hoc signing setup. The standard macOS
            // keychain is still protected by the OS and works in sandboxed
            // ad-hoc debug builds.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  String _key(String id) => 'kaijuan.remote.credentials.$id';

  @override
  Future<RemoteCredentials?> read(String connectionId) async {
    final value = await _storage.read(key: _key(connectionId));
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map) return null;
      return RemoteCredentials(
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String connectionId, RemoteCredentials credentials) {
    return _storage.write(
      key: _key(connectionId),
      value: jsonEncode({
        'username': credentials.username,
        'password': credentials.password,
      }),
    );
  }

  @override
  Future<void> delete(String connectionId) =>
      _storage.delete(key: _key(connectionId));
}

class MemoryRemoteConnectionStore implements RemoteConnectionStore {
  List<RemoteConnection> _connections = const [];

  @override
  Future<List<RemoteConnection>> read() async => List.of(_connections);

  @override
  Future<void> write(List<RemoteConnection> connections) async {
    _connections = List.unmodifiable(connections);
  }
}

class MemoryRemoteCredentialStore implements RemoteCredentialStore {
  final Map<String, RemoteCredentials> _values = {};

  @override
  Future<RemoteCredentials?> read(String connectionId) async =>
      _values[connectionId];

  @override
  Future<void> write(String connectionId, RemoteCredentials credentials) async {
    _values[connectionId] = credentials;
  }

  @override
  Future<void> delete(String connectionId) async {
    _values.remove(connectionId);
  }
}

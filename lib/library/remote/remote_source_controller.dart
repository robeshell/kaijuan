import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'opds_client.dart';
import 'remote_models.dart';
import 'remote_store.dart';
import 'webdav_client.dart';

class RemoteSourceController extends ChangeNotifier {
  RemoteSourceController({
    required this.connectionStore,
    required this.credentialStore,
    WebDavClient? webDav,
    OpdsClient? opds,
  }) : webDav = webDav ?? WebDavClient(),
       opds = opds ?? OpdsClient();

  final RemoteConnectionStore connectionStore;
  final RemoteCredentialStore credentialStore;
  final WebDavClient webDav;
  final OpdsClient opds;

  List<RemoteConnection> _connections = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<RemoteConnection> connectionsFor(RemoteSourceType type) => [
    for (final connection in _connections)
      if (connection.type == type) connection,
  ];

  Future<void> load() async {
    _connections = await connectionStore.read();
    _loaded = true;
    notifyListeners();
  }

  RemoteConnection? connectionById(String id) {
    for (final connection in _connections) {
      if (connection.id == id) return connection;
    }
    return null;
  }

  Future<RemoteProbeResult> probeDraft({
    required RemoteSourceType type,
    required String url,
    required RemoteCredentials credentials,
    bool allowBadCertificate = false,
  }) {
    return switch (type) {
      RemoteSourceType.webDav => webDav.probe(
        WebDavClient.normalizeWebDavUrl(url),
        credentials: credentials,
        allowBadCertificate: allowBadCertificate,
      ),
      RemoteSourceType.opds => opds.probe(
        _normalizeOpdsUrl(url),
        credentials: credentials,
      ),
    };
  }

  Future<RemoteProbeResult> saveConnection({
    RemoteConnection? existing,
    required RemoteSourceType type,
    required String displayName,
    required String url,
    required RemoteCredentials credentials,
    bool allowBadCertificate = false,
  }) async {
    final normalizedUrl = switch (type) {
      RemoteSourceType.webDav => WebDavClient.normalizeWebDavUrl(url),
      RemoteSourceType.opds => _normalizeOpdsUrl(url),
    };
    final id = _stableId(type, normalizedUrl);
    final oldCredential = existing == null
        ? null
        : await credentialStore.read(existing.id);
    final savedCredential = oldCredential == null
        ? credentials
        : RemoteCredentials(
            username: credentials.username.isEmpty
                ? oldCredential.username
                : credentials.username,
            password: credentials.password.isEmpty
                ? oldCredential.password
                : credentials.password,
          );
    final now = DateTime.now().toUtc();
    final record = RemoteConnection(
      id: id,
      type: type,
      displayName: displayName.trim().isEmpty
          ? Uri.parse(normalizedUrl).host
          : displayName.trim(),
      url: normalizedUrl,
      status: RemoteConnectionStatus.checking,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      allowBadCertificate: allowBadCertificate,
    );
    if (existing != null && existing.id != id) {
      _connections = [
        for (final connection in _connections)
          if (connection.id != existing.id) connection,
      ];
    }
    _replace(record);
    await credentialStore.write(id, savedCredential);
    if (existing != null && existing.id != id) {
      await credentialStore.delete(existing.id);
    }
    await _persist();

    final result = await probeDraft(
      type: type,
      url: normalizedUrl,
      credentials: savedCredential,
      allowBadCertificate: allowBadCertificate,
    );
    _replace(
      record.copyWith(
        status: _statusFor(result),
        lastError: result.error,
        lastCheckedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        clearLastError: result.isSuccess,
      ),
    );
    await _persist();
    return result;
  }

  Future<RemoteProbeResult> testConnection(RemoteConnection connection) async {
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    _replace(
      connection.copyWith(
        status: RemoteConnectionStatus.checking,
        clearLastError: true,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _persist();
    final result = await probeDraft(
      type: connection.type,
      url: connection.url,
      credentials: credentials,
      allowBadCertificate: connection.allowBadCertificate,
    );
    _replace(
      connection.copyWith(
        status: _statusFor(result),
        lastError: result.error,
        lastCheckedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        clearLastError: result.isSuccess,
      ),
    );
    await _persist();
    return result;
  }

  Future<void> removeConnection(String id) async {
    _connections = [
      for (final connection in _connections)
        if (connection.id != id) connection,
    ];
    await credentialStore.delete(id);
    await _persist();
    notifyListeners();
  }

  Future<List<RemoteEntry>> browse(
    RemoteConnection connection, {
    String? url,
  }) async {
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    final target = url ?? connection.url;
    return switch (connection.type) {
      RemoteSourceType.webDav => webDav.list(
        target,
        credentials: credentials,
        allowBadCertificate: connection.allowBadCertificate,
      ),
      RemoteSourceType.opds => (await opds.browse(
        target,
        credentials: credentials,
      )).entries,
    };
  }

  Future<RemoteProbeResult> browsePage(
    RemoteConnection connection, {
    String? url,
  }) async {
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    final target = url ?? connection.url;
    return switch (connection.type) {
      RemoteSourceType.webDav => RemoteProbeResult(
        entries: await webDav.list(
          target,
          credentials: credentials,
          allowBadCertificate: connection.allowBadCertificate,
        ),
      ),
      RemoteSourceType.opds => opds.browse(target, credentials: credentials),
    };
  }

  /// Expands a selected remote folder into importable files.
  ///
  /// A folder is a navigation item, not a downloadable object. Traversal is
  /// kept here so WebDAV and OPDS use the same recursive-selection behavior,
  /// including OPDS pagination inside nested categories.
  Future<List<RemoteEntry>> collectFilesRecursively(
    RemoteConnection connection,
    RemoteEntry folder,
  ) async {
    if (!folder.isDirectory) {
      return _isImportable(folder) ? [folder] : const [];
    }

    final visited = <String>{};
    final files = <RemoteEntry>[];

    Future<void> visit(String url) async {
      if (!visited.add(url)) return;
      var page = await browsePage(connection, url: url);
      while (true) {
        for (final entry in page.entries) {
          if (entry.isDirectory) {
            await visit(entry.effectiveNavigationUri);
          } else if (_isImportable(entry)) {
            files.add(entry);
          }
        }
        final next = page.nextUri;
        if (next == null || !visited.add(next)) return;
        page = await browsePage(connection, url: next);
      }
    }

    await visit(folder.effectiveNavigationUri);
    return files;
  }

  Stream<List<int>> download(
    RemoteConnection connection,
    RemoteEntry entry,
  ) async* {
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    final url = entry.effectiveDownloadUri;
    switch (connection.type) {
      case RemoteSourceType.webDav:
        yield* webDav.download(
          url,
          credentials: credentials,
          allowBadCertificate: connection.allowBadCertificate,
        );
      case RemoteSourceType.opds:
        yield* opds.download(url, credentials: credentials);
    }
  }

  Future<Uint8List> loadCover(RemoteConnection connection, String url) async {
    final credentials =
        await credentialStore.read(connection.id) ?? const RemoteCredentials();
    final stream = switch (connection.type) {
      RemoteSourceType.webDav => webDav.download(
        url,
        credentials: credentials,
        allowBadCertificate: connection.allowBadCertificate,
      ),
      RemoteSourceType.opds => opds.download(url, credentials: credentials),
    };
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        throw const FormatException('封面图片超过 8 MiB 限制');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  bool _isImportable(RemoteEntry entry) =>
      entry.isSupportedFile || entry.downloadUri != null;

  void _replace(RemoteConnection record) {
    var found = false;
    final updated = <RemoteConnection>[];
    for (final connection in _connections) {
      if (connection.id == record.id) {
        updated.add(record);
        found = true;
      } else {
        updated.add(connection);
      }
    }
    if (!found) updated.add(record);
    _connections = List.unmodifiable(updated);
    notifyListeners();
  }

  Future<void> _persist() => connectionStore.write(_connections);

  static RemoteConnectionStatus _statusFor(RemoteProbeResult result) {
    if (result.isSuccess) return RemoteConnectionStatus.connected;
    if (result.authenticationFailed) {
      return RemoteConnectionStatus.authenticationFailed;
    }
    final text = result.error?.toLowerCase() ?? '';
    if (text.contains('超时') || text.contains('无法连接')) {
      return RemoteConnectionStatus.unreachable;
    }
    return RemoteConnectionStatus.error;
  }

  static String _stableId(RemoteSourceType type, String url) =>
      'remote:${type.name}:${sha256.convert(utf8.encode(url))}';

  static String _normalizeOpdsUrl(String value) {
    final uri = Uri.parse(value.trim());
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const FormatException('OPDS 地址必须是有效的 HTTP(S) URL');
    }
    if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const FormatException('请把凭据填在账号密码字段中');
    }
    return uri.toString();
  }
}

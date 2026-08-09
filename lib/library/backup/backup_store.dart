import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import '../remote/remote_models.dart';
import '../remote/webdav_client.dart';
import 'backup_exporter.dart';
import 'backup_format.dart';

class JsonBackupTargetSettingsStore {
  JsonBackupTargetSettingsStore(this.file);

  final File file;

  Future<BackupTargetSettings> read() async {
    for (final candidate in [file, File('${file.path}.previous')]) {
      try {
        if (!await candidate.exists()) continue;
        return BackupTargetSettings.fromJson(
          jsonDecode(await candidate.readAsString()),
        );
      } catch (_) {
        // A crash during replacement may leave the current generation
        // unreadable while the previous one is still recoverable.
      }
    }
    return const BackupTargetSettings();
  }

  Future<void> write(BackupTargetSettings settings) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.partial.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    final previous = File('${file.path}.previous');
    try {
      await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
      if (await file.exists()) {
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      try {
        await temporary.rename(file.path);
      } catch (_) {
        if (!await file.exists() && await previous.exists()) {
          await previous.rename(file.path);
        }
        rethrow;
      }
      if (await previous.exists()) {
        try {
          await previous.delete();
        } catch (_) {
          // The new settings generation is already committed.
        }
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class WebDavBackupStore {
  WebDavBackupStore({
    required this.connection,
    required this.credentials,
    WebDavClient? client,
  }) : _client = client ?? WebDavClient();

  final RemoteConnection connection;
  final RemoteCredentials credentials;
  final WebDavClient _client;

  static Uri objectManifestUri(Uri root, String hash) =>
      _append(root, 'objects/$hash/object.json');

  static String sanitizeRelativePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.split('/').any((part) => part == '..')) {
      throw const FormatException('备份目录必须是当前 WebDAV 根目录下的相对路径');
    }
    return normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  Uri get rootUri => _join(sanitizeRelativePath(''));

  Future<T> withSession<T>(
    String remotePath,
    Future<T> Function(WebDavSession session, Uri root) action,
  ) async {
    _requireSecureConnection();
    final root = _join(sanitizeRelativePath(remotePath));
    final session = _client.openSession(
      credentials: credentials,
      allowBadCertificate: connection.allowBadCertificate,
    );
    try {
      await _ensureDirectory(session, root);
      return await action(session, root);
    } finally {
      await session.close();
    }
  }

  Future<List<BackupSnapshotManifest>> listSnapshots(String remotePath) async {
    _requireSecureConnection();
    final snapshotsRoot = _append(
      _join(sanitizeRelativePath(remotePath)),
      'snapshots',
    );
    final List<RemoteEntry> devices;
    try {
      devices = await _client.list(
        snapshotsRoot.toString(),
        credentials: credentials,
        allowBadCertificate: connection.allowBadCertificate,
      );
    } on RemoteProtocolException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 410) return const [];
      rethrow;
    }
    final manifests = <BackupSnapshotManifest>[];
    for (final device in devices.where((entry) => entry.isDirectory)) {
      final List<RemoteEntry> snapshots;
      try {
        snapshots = await _client.list(
          device.effectiveNavigationUri,
          credentials: credentials,
          allowBadCertificate: connection.allowBadCertificate,
        );
      } on RemoteProtocolException catch (error) {
        if (error.statusCode == 404 || error.statusCode == 410) continue;
        rethrow;
      }
      for (final snapshot in snapshots.where((entry) => entry.isDirectory)) {
        final manifestUri = _append(
          Uri.parse(snapshot.effectiveNavigationUri),
          'manifest.json',
        );
        try {
          final bytes = await _readBytes(manifestUri);
          final manifest = BackupSnapshotManifest.fromJson(
            jsonDecode(utf8.decode(bytes)),
          );
          if (manifest == null) {
            throw const BackupStoreException('发现无法识别的备份快照清单');
          }
          manifests.add(manifest);
        } on RemoteProtocolException catch (error) {
          if (error.statusCode == 404 || error.statusCode == 410) {
            // Incomplete uploads have no published manifest and remain
            // invisible until a later successful publish.
            continue;
          }
          rethrow;
        } on BackupStoreException {
          rethrow;
        } catch (_) {
          throw const BackupStoreException('备份快照清单已损坏，无法列出备份');
        }
      }
    }
    manifests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return manifests;
  }

  Future<BackupSnapshotManifest?> readManifest(
    String remotePath,
    String deviceId,
    String snapshotId,
  ) async {
    _requireSecureConnection();
    final uri = _append(
      _join(sanitizeRelativePath(remotePath)),
      'snapshots/$deviceId/$snapshotId/manifest.json',
    );
    try {
      final bytes = await _readBytes(uri);
      final manifest = BackupSnapshotManifest.fromJson(
        jsonDecode(utf8.decode(bytes)),
      );
      if (manifest == null) {
        throw const BackupStoreException('备份快照清单格式不受支持');
      }
      return manifest;
    } on RemoteProtocolException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 410) return null;
      rethrow;
    } on BackupStoreException {
      rethrow;
    } catch (_) {
      throw const BackupStoreException('备份快照清单已损坏，无法读取');
    }
  }

  Future<BackupRecords> readRecords(
    WebDavSession session,
    Uri root,
    BackupSnapshotManifest manifest,
  ) async {
    final uri = _append(
      _append(root, 'snapshots/${manifest.deviceId}/${manifest.snapshotId}'),
      'data.json.gz',
    );
    final compressed = await _readBytesWithSession(
      session,
      uri,
      maxBytes: KaijuanBackupFormat.maxCompressedRecordsBytes,
    );
    if (compressed.length != manifest.recordsBytes ||
        sha256.convert(compressed).toString() != manifest.recordsSha256) {
      throw const BackupStoreException('备份记录校验失败');
    }
    try {
      final inflated = await _readLimitedStream(
        gzip.decoder.bind(Stream<List<int>>.value(compressed)),
        maxBytes: KaijuanBackupFormat.maxUncompressedRecordsBytes,
        tooLargeMessage: '备份记录解压后超过大小限制',
      );
      final decoded = jsonDecode(utf8.decode(inflated));
      final records = BackupRecords.fromJson(decoded);
      if (records == null) throw const BackupStoreException('备份记录格式不受支持');
      return records;
    } catch (error) {
      if (error is BackupStoreException) rethrow;
      throw const BackupStoreException('备份记录无法解析');
    }
  }

  Future<void> uploadObject(
    WebDavSession session,
    Uri root,
    BackupObjectExport object,
  ) async {
    final objectRoot = _append(root, 'objects/${object.descriptor.hash}');
    final chunksRoot = _append(objectRoot, 'chunks');
    await _ensureDirectory(session, chunksRoot);
    final input = await object.file.open();
    try {
      for (final chunk in object.descriptor.chunks) {
        final bytes = await input.read(chunk.size);
        if (bytes.length != chunk.size ||
            sha256.convert(bytes).toString() != chunk.hash) {
          throw const BackupStoreException('本地书籍分块校验失败');
        }
        final target = _append(
          chunksRoot,
          '${chunk.index.toString().padLeft(6, '0')}-${chunk.hash}.bin',
        );
        final existing = await session.stat(target);
        if (existing?.contentLength == chunk.size) {
          try {
            final remoteBytes = await _readBytesWithSession(
              session,
              target,
              maxBytes: chunk.size,
            );
            if (remoteBytes.length == chunk.size &&
                sha256.convert(remoteBytes).toString() == chunk.hash) {
              continue;
            }
          } on RemoteProtocolException catch (error) {
            if (error.statusCode != 404 && error.statusCode != 410) rethrow;
          }
        }

        final temporary = _append(
          chunksRoot,
          '.${chunk.index.toString().padLeft(6, '0')}-${chunk.hash}.partial',
        );
        await session.putStream(
          temporary,
          Stream<List<int>>.value(bytes),
          length: chunk.size,
        );
        await session.move(temporary, target, overwrite: true);
      }
    } finally {
      await input.close();
    }
    final objectJson = utf8.encode(jsonEncode(object.descriptor.toJson()));
    final objectPart = _append(objectRoot, '.object.json.partial');
    final objectFile = _append(objectRoot, 'object.json');
    await session.putBytes(objectPart, objectJson);
    await session.move(objectPart, objectFile, overwrite: true);
  }

  Future<void> uploadRecords(
    WebDavSession session,
    Uri root,
    BackupSnapshotManifest manifest,
    BackupRecords records,
  ) async {
    final snapshotRoot = _append(
      root,
      'snapshots/${manifest.deviceId}/${manifest.snapshotId}',
    );
    await _ensureDirectory(session, snapshotRoot);
    final encoded = utf8.encode(records.encode());
    if (encoded.length > KaijuanBackupFormat.maxUncompressedRecordsBytes) {
      throw const BackupStoreException('备份记录超过大小限制');
    }
    final compressed = gzip.encode(encoded);
    if (compressed.length > KaijuanBackupFormat.maxCompressedRecordsBytes) {
      throw const BackupStoreException('备份记录压缩后超过大小限制');
    }
    final part = _append(snapshotRoot, '.data.json.gz.partial');
    await session.putBytes(part, compressed);
    await session.move(
      part,
      _append(snapshotRoot, 'data.json.gz'),
      overwrite: true,
    );
  }

  Future<void> publishManifest(
    WebDavSession session,
    Uri root,
    BackupSnapshotManifest manifest,
  ) async {
    final snapshotRoot = _append(
      root,
      'snapshots/${manifest.deviceId}/${manifest.snapshotId}',
    );
    await _ensureDirectory(session, snapshotRoot);
    final part = _append(snapshotRoot, '.manifest.json.partial');
    await session.putBytes(part, utf8.encode(manifest.encode()));

    final deviceRoot = _append(root, 'devices/${manifest.deviceId}');
    await _ensureDirectory(session, deviceRoot);
    final latestPart = _append(deviceRoot, '.latest.json.partial');
    await session.putBytes(
      latestPart,
      utf8.encode(
        jsonEncode({
          'snapshotId': manifest.snapshotId,
          'createdAt': manifest.createdAt.toUtc().toIso8601String(),
        }),
      ),
    );
    await session.move(
      latestPart,
      _append(deviceRoot, 'latest.json'),
      overwrite: true,
    );

    // manifest.json is the only visibility/commit point. Keep it last so a
    // failure above cannot produce a usable snapshot reported as failed.
    await session.move(
      part,
      _append(snapshotRoot, 'manifest.json'),
      overwrite: true,
    );
  }

  Future<void> downloadObject(
    WebDavSession session,
    Uri root,
    BackupObjectDescriptor descriptor,
    File destination,
  ) async {
    await destination.parent.create(recursive: true);
    final output = destination.openWrite();
    final full = _DigestSink();
    final conversion = sha256.startChunkedConversion(full);
    var total = 0;
    try {
      for (final chunk in descriptor.chunks) {
        final uri = _append(
          _append(root, 'objects/${descriptor.hash}/chunks'),
          '${chunk.index.toString().padLeft(6, '0')}-${chunk.hash}.bin',
        );
        final bytes = await _readBytesWithSession(
          session,
          uri,
          maxBytes: chunk.size + 1024,
        );
        if (bytes.length != chunk.size ||
            sha256.convert(bytes).toString() != chunk.hash) {
          throw const BackupStoreException('备份书籍分块校验失败');
        }
        conversion.add(bytes);
        output.add(bytes);
        total += bytes.length;
      }
      await output.flush();
      await output.close();
      conversion.close();
    } catch (_) {
      await output.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    if (total != descriptor.size || full.value.toString() != descriptor.hash) {
      if (await destination.exists()) await destination.delete();
      throw const BackupStoreException('备份书籍校验失败');
    }
  }

  Future<void> _ensureDirectory(WebDavSession session, Uri directory) async {
    final base = Uri.parse(connection.url);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    final relativePath = directory.path.startsWith(basePath)
        ? directory.path.substring(basePath.length)
        : '';
    var current = basePath;
    for (final segment
        in relativePath.split('/').where((value) => value.isNotEmpty)) {
      current = '$current$segment/';
      await session.makeCollection(base.replace(path: current));
    }
  }

  Uri _join(String relative) => _append(Uri.parse(connection.url), relative);

  static Uri _append(Uri base, String relative) {
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    final path =
        '$basePath${relative.split('/').where((value) => value.isNotEmpty).join('/')}';
    return base.replace(path: path);
  }

  Future<Uint8List> _readBytes(Uri uri) async {
    final session = _client.openSession(
      credentials: credentials,
      allowBadCertificate: connection.allowBadCertificate,
    );
    try {
      return await _readBytesWithSession(
        session,
        uri,
        maxBytes: 4 * 1024 * 1024,
      );
    } finally {
      await session.close();
    }
  }

  static Future<Uint8List> _readBytesWithSession(
    WebDavSession session,
    Uri uri, {
    required int maxBytes,
  }) async {
    return _readLimitedStream(
      session.download(uri),
      maxBytes: maxBytes,
      tooLargeMessage: '备份文件超过大小限制',
    );
  }

  static Future<Uint8List> _readLimitedStream(
    Stream<List<int>> stream, {
    required int maxBytes,
    required String tooLargeMessage,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw BackupStoreException(tooLargeMessage);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void _requireSecureConnection() {
    final uri = Uri.parse(connection.url);
    if (uri.scheme.toLowerCase() != 'https') {
      throw const BackupStoreException('备份位置需要使用 HTTPS。请编辑 WebDAV 连接地址后重试');
    }
  }
}

class BackupStoreException implements Exception {
  const BackupStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest ?? (throw StateError('digest not available'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

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
    if (!await file.exists()) return const BackupTargetSettings();
    try {
      return BackupTargetSettings.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (_) {
      return const BackupTargetSettings();
    }
  }

  Future<void> write(BackupTargetSettings settings) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.partial');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
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
    final snapshotsRoot = _append(
      _join(sanitizeRelativePath(remotePath)),
      'snapshots',
    );
    final devices = await _client.list(
      snapshotsRoot.toString(),
      credentials: credentials,
      allowBadCertificate: connection.allowBadCertificate,
    );
    final manifests = <BackupSnapshotManifest>[];
    for (final device in devices.where((entry) => entry.isDirectory)) {
      final snapshots = await _client.list(
        device.effectiveNavigationUri,
        credentials: credentials,
        allowBadCertificate: connection.allowBadCertificate,
      );
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
          if (manifest != null) manifests.add(manifest);
        } catch (_) {
          // An incomplete upload has no published manifest and is invisible
          // to restore; leave it for the next backup/cleanup pass.
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
    final uri = _append(
      _join(sanitizeRelativePath(remotePath)),
      'snapshots/$deviceId/$snapshotId/manifest.json',
    );
    try {
      final bytes = await _readBytes(uri);
      return BackupSnapshotManifest.fromJson(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return null;
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
      maxBytes: 64 * 1024 * 1024,
    );
    if (compressed.length != manifest.recordsBytes ||
        sha256.convert(compressed).toString() != manifest.recordsSha256) {
      throw const BackupStoreException('备份记录校验失败');
    }
    try {
      final decoded = jsonDecode(utf8.decode(gzip.decode(compressed)));
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
        if (existing?.contentLength == chunk.size) continue;

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
    final compressed = gzip.encode(utf8.encode(records.encode()));
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
    await session.move(
      part,
      _append(snapshotRoot, 'manifest.json'),
      overwrite: true,
    );

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
        maxBytes: 64 * 1024 * 1024,
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
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in session.download(uri)) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const BackupStoreException('备份文件超过大小限制');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
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

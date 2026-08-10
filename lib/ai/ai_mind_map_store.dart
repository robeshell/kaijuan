import 'dart:convert';
import 'dart:io';

import 'ai_log.dart';
import 'ai_mind_map.dart';

class AiBookMindMapStore {
  AiBookMindMapStore(this.directory);

  final Directory directory;

  static String fileNameFor(String contentHash, {String? workKey}) {
    final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (workKey == null) return '$safe.json';
    final key = workKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '$safe.$key.json';
  }

  static String? workKeyOfFile(String fileName, String contentHash) {
    final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final stem = fileName.endsWith('.json')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
    if (stem == safe) return null;
    if (stem.startsWith('$safe.')) {
      final value = stem.substring(safe.length + 1);
      return value.isEmpty ? null : value;
    }
    return null;
  }

  File _resultFile(String hash, {String? workKey}) => File(
    '${directory.path}${Platform.pathSeparator}'
    '${fileNameFor(hash, workKey: workKey)}',
  );

  File _checkpointFile(String hash, {String? workKey}) {
    final resultPath = _resultFile(hash, workKey: workKey).path;
    return File(
      '${resultPath.substring(0, resultPath.length - 5)}.checkpoint.json',
    );
  }

  Future<AiBookMindMap?> read(String hash, {String? workKey}) async {
    final file = _resultFile(hash, workKey: workKey);
    for (final candidate in [file, File('${file.path}.previous')]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = jsonDecode(await candidate.readAsString());
        final mindMap = AiBookMindMap.fromJson(decoded);
        if (mindMap != null) return mindMap;
      } catch (error) {
        AiLog.d('AiBookMindMapStore skipped ${candidate.path}: $error');
      }
    }
    return null;
  }

  Future<Map<String, AiBookMindMap>> readAllFor(String hash) async {
    if (!await directory.exists()) return const {};
    final result = <String, AiBookMindMap>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !entity.path.endsWith('.json') ||
          entity.path.endsWith('.checkpoint.json')) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final key = workKeyOfFile(name, hash);
      if (key == null) continue;
      try {
        final parsed = AiBookMindMap.fromJson(
          jsonDecode(await entity.readAsString()),
        );
        if (parsed != null) result[key] = parsed;
      } catch (_) {}
    }
    return result;
  }

  Future<AiMindMapCheckpoint?> readCheckpoint(
    String hash, {
    String? workKey,
  }) async {
    final file = _checkpointFile(hash, workKey: workKey);
    for (final candidate in [file, File('${file.path}.previous')]) {
      try {
        if (!await candidate.exists()) continue;
        final checkpoint = AiMindMapCheckpoint.fromJson(
          jsonDecode(await candidate.readAsString()),
        );
        if (checkpoint != null) return checkpoint;
      } catch (error) {
        AiLog.d('AiBookMindMapStore skipped ${candidate.path}: $error');
      }
    }
    return null;
  }

  Future<void> write(AiBookMindMap value) async {
    await directory.create(recursive: true);
    await _atomicWrite(
      _resultFile(value.contentHash, workKey: value.workKey),
      value.toJson(),
    );
  }

  Future<void> writeCheckpoint(AiMindMapCheckpoint value) async {
    await directory.create(recursive: true);
    await _atomicWrite(
      _checkpointFile(value.contentHash, workKey: value.workKey),
      value.toJson(),
    );
  }

  Future<void> deleteCheckpoint(String hash, {String? workKey}) async {
    final file = _checkpointFile(hash, workKey: workKey);
    if (await file.exists()) await file.delete();
    final previous = File('${file.path}.previous');
    if (await previous.exists()) await previous.delete();
  }

  Future<void> delete(String hash, {String? workKey}) async {
    final file = _resultFile(hash, workKey: workKey);
    if (await file.exists()) await file.delete();
    final previous = File('${file.path}.previous');
    if (await previous.exists()) await previous.delete();
    await deleteCheckpoint(hash, workKey: workKey);
  }

  Future<void> _atomicWrite(File file, Object value) async {
    final temporary = File(
      '${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(jsonEncode(value), flush: true);
      if (await file.exists()) {
        final previous = File('${file.path}.previous');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
        try {
          await temporary.rename(file.path);
          await previous.delete();
        } catch (_) {
          if (!await file.exists() && await previous.exists()) {
            await previous.rename(file.path);
          }
          rethrow;
        }
      } else {
        await temporary.rename(file.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

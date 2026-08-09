import 'dart:convert';
import 'dart:io';

import 'ai_graph.dart';
import 'ai_log.dart';

/// File-backed graph cache: one JSON file per contentHash under `ai_graph/`.
class AiGraphStore {
  AiGraphStore(this._directory);

  final Directory _directory;

  /// One file per graph. A collection keeps one graph per work:
  /// `$hash.json` for the whole book and `$hash.$workKey.json` for one work.
  static String fileNameFor(String contentHash, {String? workKey}) {
    final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (workKey == null) return '$safe.json';
    final safeKey = workKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '$safe.$safeKey.json';
  }

  File _fileFor(String contentHash, {String? workKey}) => File(
    '${_directory.path}${Platform.pathSeparator}'
    '${fileNameFor(contentHash, workKey: workKey)}',
  );

  /// The per-work key embedded in a collection file name, or null for a
  /// whole-book graph. Parses `$hash.$workKey.json`.
  static String? workKeyOfFile(String fileName, String contentHash) {
    final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final stem = fileName.endsWith('.json')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
    if (stem == safe) return null;
    if (stem.startsWith('$safe.')) {
      final key = stem.substring(safe.length + 1);
      if (key.isNotEmpty) return key;
    }
    return null;
  }

  Future<AiBookGraph?> read(String contentHash, {String? workKey}) async {
    final file = _fileFor(contentHash, workKey: workKey);
    for (final candidate in [file, File('${file.path}.previous')]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map) continue;
        final graph = AiBookGraph.fromJson(Map<String, dynamic>.from(decoded));
        if (graph != null) return graph;
      } catch (error) {
        AiLog.d('AiGraphStore skipped ${candidate.path}: $error');
      }
    }
    return null;
  }

  /// All per-work graphs for [contentHash], keyed by workKey.
  Future<Map<String, AiBookGraph>> readAllFor(String contentHash) async {
    try {
      if (!await _directory.exists()) return {};
      final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final result = <String, AiBookGraph>{};
      await for (final entity in _directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final key = workKeyOfFile(entity.uri.pathSegments.last, safe);
        if (key == null) continue;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map) continue;
          final graph = AiBookGraph.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (graph != null) result[key] = graph;
        } catch (error) {
          AiLog.d('AiGraphStore skipped ${entity.path}: $error');
        }
      }
      return result;
    } catch (error) {
      AiLog.d('AiGraphStore readAllFor failed: $error');
      return {};
    }
  }

  Future<void> write(AiBookGraph graph, {String? workKey}) async {
    await _directory.create(recursive: true);
    final file = _fileFor(graph.contentHash, workKey: workKey);
    final temporary = File(
      '${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(jsonEncode(graph.toJson()), flush: true);
      if (await file.exists()) {
        final backup = File('${file.path}.previous');
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
        try {
          await temporary.rename(file.path);
          await backup.delete();
        } catch (_) {
          if (!await file.exists() && await backup.exists()) {
            await backup.rename(file.path);
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

  Future<void> delete(String contentHash, {String? workKey}) async {
    final file = _fileFor(contentHash, workKey: workKey);
    if (await file.exists()) await file.delete();
    final previous = File('${file.path}.previous');
    if (await previous.exists()) await previous.delete();
  }
}

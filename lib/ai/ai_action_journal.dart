import 'dart:convert';
import 'dart:io';

import 'ai_product_action_protocol.dart';

/// File-backed local control journal. It is intentionally separate from
/// ai_chat and is never included in WebDAV conversation snapshots.
class JsonAiActionJournalStore implements AiActionJournalStore {
  JsonAiActionJournalStore(this.directory);

  final Directory directory;

  File _fileFor(String proposalId) => File(
    '${directory.path}${Platform.pathSeparator}${proposalId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.json',
  );

  File _backupFor(String proposalId) =>
      File('${_fileFor(proposalId).path}.bak');

  Future<AiActionJournalEntry?> _readFile(File file) async {
    if (!await file.exists()) return null;
    final raw = jsonDecode(await file.readAsString());
    return AiActionJournalEntry.fromJson(raw);
  }

  @override
  Future<AiActionJournalEntry?> read(String proposalId) async {
    final primary = await _readFile(_fileFor(proposalId));
    if (primary != null) return primary;
    return _readFile(_backupFor(proposalId));
  }

  @override
  Future<List<AiActionJournalEntry>> readAll() async {
    if (!await directory.exists()) return const [];
    final result = <AiActionJournalEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final entry = await _readFile(entity);
        if (entry != null) result.add(entry);
      } catch (_) {
        // A corrupt entry remains inspectable on disk and does not prevent
        // recovery of unrelated product actions.
      }
    }
    result.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return List.unmodifiable(result);
  }

  @override
  Future<void> write(AiActionJournalEntry entry) async {
    await directory.create(recursive: true);
    final current = await read(entry.proposal.proposalId);
    if (current != null && entry.stateVersion <= current.stateVersion) {
      throw StateError('Stale journal version');
    }
    final file = _fileFor(entry.proposal.proposalId);
    final backup = _backupFor(entry.proposal.proposalId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(entry.toJson()), flush: true);
    if (await file.exists()) {
      await file.copy(backup.path);
    }
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}

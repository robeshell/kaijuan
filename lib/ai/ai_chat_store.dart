import 'dart:convert';
import 'dart:io';

import 'ai_chat.dart';

/// Local conversation persistence, keyed by publication content hash.
///
/// Re-importing the same file keeps its memory. Library-row deletion must not
/// call [delete]; only the explicit user action should remove the conversation.
abstract interface class AiChatHistoryStore {
  Future<AiChatSession?> read({
    required String contentHash,
    required String itemId,
  });

  Future<void> write(AiChatSession session);

  Future<void> delete(String contentHash);
}

class JsonAiChatHistoryStore implements AiChatHistoryStore {
  JsonAiChatHistoryStore(this._directory);

  final Directory _directory;

  File _fileFor(String contentHash) {
    final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${_directory.path}${Platform.pathSeparator}$safe.json');
  }

  File _backupFor(String contentHash) =>
      File('${_fileFor(contentHash).path}.bak');

  Future<AiChatSession> _decodeFile(
    File file, {
    required String contentHash,
    required String itemId,
  }) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('会话文件格式无法识别');
    }
    final session = AiChatSession.fromJson(Map<String, dynamic>.from(decoded));
    return session.itemId != itemId && itemId.isNotEmpty
        ? session.copyWith(itemId: itemId)
        : session;
  }

  @override
  Future<AiChatSession?> read({
    required String contentHash,
    required String itemId,
  }) async {
    final file = _fileFor(contentHash);
    final backup = _backupFor(contentHash);
    if (!await file.exists()) {
      if (await backup.exists()) {
        return _decodeFile(backup, contentHash: contentHash, itemId: itemId);
      }
      return AiChatSession(contentHash: contentHash, itemId: itemId);
    }
    try {
      return await _decodeFile(file, contentHash: contentHash, itemId: itemId);
    } catch (primaryError, primaryStack) {
      if (await backup.exists()) {
        try {
          return await _decodeFile(
            backup,
            contentHash: contentHash,
            itemId: itemId,
          );
        } catch (_) {
          // Preserve and report the primary-file error below. Neither file is
          // deleted or overwritten, so a future recovery can still inspect it.
        }
      }
      Error.throwWithStackTrace(primaryError, primaryStack);
    }
  }

  @override
  Future<void> write(AiChatSession session) async {
    await _directory.create(recursive: true);
    final file = _fileFor(session.contentHash);
    final backup = _backupFor(session.contentHash);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
    if (await file.exists()) {
      await file.copy(backup.path);
    }
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      // Windows cannot atomically rename over an existing target. The backup
      // keeps the previous valid generation recoverable during replacement.
      if (await file.exists()) await file.delete();
      try {
        await temporary.rename(file.path);
      } catch (_) {
        if (!await file.exists() && await backup.exists()) {
          await backup.copy(file.path);
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> delete(String contentHash) async {
    final file = _fileFor(contentHash);
    if (await file.exists()) await file.delete();
    final backup = _backupFor(contentHash);
    if (await backup.exists()) await backup.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }
}

class MemoryAiChatHistoryStore implements AiChatHistoryStore {
  final Map<String, AiChatSession> _sessions = {};

  @override
  Future<AiChatSession?> read({
    required String contentHash,
    required String itemId,
  }) async {
    return _sessions[contentHash] ??
        AiChatSession(contentHash: contentHash, itemId: itemId);
  }

  @override
  Future<void> write(AiChatSession session) async {
    _sessions[session.contentHash] = session;
  }

  @override
  Future<void> delete(String contentHash) async {
    _sessions.remove(contentHash);
  }
}

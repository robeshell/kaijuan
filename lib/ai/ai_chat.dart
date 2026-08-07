import 'dart:convert';
import 'dart:io';

import 'ai_models.dart';
import 'ai_outline.dart';

/// One user or assistant bubble in the book chat.
class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    this.pinned = false,
    this.createdAt,
    this.webHitCount,
    this.suggestedQuestions = const [],
  });

  final AiMessageRole role;
  final String content;
  final bool pinned;
  final DateTime? createdAt;

  /// When set on a **user** turn: search ran (`0` = empty hits, `n` = n results).
  /// `null` = 联网 off for that turn.
  final int? webHitCount;

  /// One answer-specific follow-up generated after an assistant reply.
  final List<String> suggestedQuestions;

  bool get usedWebSearch => webHitCount != null;

  AiChatMessage copyWith({
    AiMessageRole? role,
    String? content,
    bool? pinned,
    DateTime? createdAt,
    int? webHitCount,
    List<String>? suggestedQuestions,
    bool clearWebHitCount = false,
  }) {
    return AiChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      webHitCount: clearWebHitCount ? null : (webHitCount ?? this.webHitCount),
      suggestedQuestions: suggestedQuestions ?? this.suggestedQuestions,
    );
  }

  Map<String, Object?> toJson() => {
    'role': role.name,
    'content': content,
    'pinned': pinned,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (webHitCount != null) 'webHitCount': webHitCount,
    if (suggestedQuestions.isNotEmpty) 'suggestedQuestions': suggestedQuestions,
  };

  static AiChatMessage fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String? ?? 'user';
    final role = AiMessageRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => AiMessageRole.user,
    );
    final createdRaw = json['createdAt'] as String?;
    final rawHits = json['webHitCount'];
    final rawSuggestions = json['suggestedQuestions'];
    return AiChatMessage(
      role: role,
      content: json['content'] as String? ?? '',
      pinned: json['pinned'] as bool? ?? false,
      createdAt: createdRaw == null ? null : DateTime.tryParse(createdRaw),
      webHitCount: rawHits is int ? rawHits : int.tryParse('$rawHits'),
      suggestedQuestions: rawSuggestions is List
          ? rawSuggestions
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }
}

/// Context for one chat turn — lean seed + tools for more body.
class AiChatContextBundle {
  const AiChatContextBundle({
    this.chapterTitle = '',
    this.chapterText = '',
    this.selectionText = '',
    this.bookBody = '',
    this.tocOutline = const [],
  });

  /// Where the reader is now (for "这一章" questions).
  final String chapterTitle;

  /// Current section body (focus seed; not the whole book).
  final String chapterText;

  /// Optional highlight attachment.
  final String selectionText;

  /// Optional multi-section corpus (legacy / tool host cache). Prefer tools.
  final String bookBody;

  /// Section titles only (cheap). Full list also available via get_toc tool.
  final List<String> tocOutline;

  bool get hasSelection => selectionText.trim().isNotEmpty;

  bool get hasAnyBody =>
      bookBody.trim().isNotEmpty ||
      chapterText.trim().isNotEmpty ||
      selectionText.trim().isNotEmpty;
}

/// One-tap prompts shown at contextual points in the book chat.
class AiChatShortcut {
  const AiChatShortcut({
    required this.label,
    required this.prompt,
    this.needsSelection = false,
  });

  final String label;
  final String prompt;
  final bool needsSelection;
}

/// Shortcuts for a whole-book companion (not progress-gated).
const kAiChatShortcuts = <AiChatShortcut>[
  AiChatShortcut(label: '总结这一章', prompt: '请总结我正在读的这一章：主线、关键转折，尽量简短。'),
  AiChatShortcut(
    label: '这本书在讲什么',
    prompt:
        '请根据提供的各部分正文，概括整本书的主线与主题，用几句话即可。'
        '必须覆盖全书结构（例如多讲/多时代），不要只写我正在读的那一讲。',
  ),
  AiChatShortcut(
    label: '解释这段',
    prompt: '请解释我划出的这段话：在说什么，有什么用意。',
    needsSelection: true,
  ),
  AiChatShortcut(
    label: '人物关系',
    prompt:
        '请根据提供的各部分正文，梳理整本书的主要人物及其关系。'
        '按书中结构组织，不要只列当前这一讲的人物。',
  ),
  AiChatShortcut(
    label: '时代背景',
    prompt:
        '结合书里写到的内容，谈谈相关的时代、制度或社会背景。'
        '书里没写的部分用「补充说明」；若本轮已联网，请用检索结果充实补充说明并简述来源。',
  ),
];

const _kAiChatSelectionShortcuts = <AiChatShortcut>[
  AiChatShortcut(
    label: '解释这段',
    prompt: '请解释我划出的这段话：在说什么，有什么用意。',
    needsSelection: true,
  ),
  AiChatShortcut(
    label: '这段和本章的关系',
    prompt: '请结合我划出的这段话和当前章节，说明它在本章中起什么作用。',
    needsSelection: true,
  ),
  AiChatShortcut(
    label: '作者为什么这样写',
    prompt: '请结合我划出的这段话的上下文，分析作者为什么这样写。',
    needsSelection: true,
  ),
];

const _kAiChatFollowUpShortcuts = <AiChatShortcut>[
  AiChatShortcut(label: '结合书中内容再展开', prompt: '请基于刚才的回答，结合书中的具体内容再展开讲讲。'),
  AiChatShortcut(label: '和本章主线有什么关系', prompt: '请基于刚才的回答，说明这和当前章节的主线有什么关系。'),
  AiChatShortcut(label: '有哪些容易忽略的细节', prompt: '请基于刚才的回答，补充书中容易忽略但值得注意的细节。'),
];

const _kAiChatSelectionFollowUpShortcuts = <AiChatShortcut>[
  AiChatShortcut(
    label: '结合上下文再解释',
    prompt: '请结合我划出的这段话前后的上下文，再解释得具体一些。',
    needsSelection: true,
  ),
  AiChatShortcut(
    label: '这段在本章中的作用',
    prompt: '请结合刚才的回答，说明我划出的这段话在本章中起什么作用。',
    needsSelection: true,
  ),
  AiChatShortcut(
    label: '和全书主题有什么关联',
    prompt: '请结合刚才的回答，说明我划出的这段话和全书主题有什么关联。',
    needsSelection: true,
  ),
];

/// Three opening questions, tailored to whether the reader brought a quote.
List<AiChatShortcut> aiChatOpeningShortcuts({required bool hasSelection}) {
  final source = hasSelection ? _kAiChatSelectionShortcuts : kAiChatShortcuts;
  return source
      .where((shortcut) => !shortcut.needsSelection || hasSelection)
      .take(3)
      .toList(growable: false);
}

/// Three low-cost follow-up questions; the model receives the prior turn via
/// chat history, so these remain relevant without a separate generation call.
List<AiChatShortcut> aiChatFollowUpShortcuts({
  required bool hasSelection,
  List<String> generatedQuestions = const [],
}) {
  final source = hasSelection
      ? _kAiChatSelectionFollowUpShortcuts
      : _kAiChatFollowUpShortcuts;
  final generated = generatedQuestions
      .map((question) => question.trim())
      .where((question) => question.isNotEmpty)
      .take(1)
      .map(
        (question) => AiChatShortcut(
          label: question,
          prompt: question,
          needsSelection: hasSelection,
        ),
      )
      .toList(growable: false);
  if (generated.isNotEmpty) {
    return [...source.take(2), ...generated];
  }
  return source.toList(growable: false);
}

/// Per-book chat state (isolated by [contentHash]).
class AiChatSession {
  const AiChatSession({
    required this.contentHash,
    required this.itemId,
    this.messages = const [],
    this.outline,
    this.workOutlines = const {},
  });

  final String contentHash;
  final String itemId;
  final List<AiChatMessage> messages;

  /// Whole-book outline (plain books; collections keep per-work outlines in
  /// [workOutlines] instead).
  final AiBookOutline? outline;

  /// Per-work outlines of a collection, keyed by the work key (graph
  /// workKey, e.g. 's4'). The 读哪本跟哪本 model: each work generates and
  /// loads its own outline; the tab follows the reading position.
  final Map<String, AiBookOutline> workOutlines;

  AiChatSession copyWith({
    String? contentHash,
    String? itemId,
    List<AiChatMessage>? messages,
    AiBookOutline? outline,
    Map<String, AiBookOutline>? workOutlines,
    bool clearOutline = false,
    String? clearWorkOutlineKey,
  }) {
    return AiChatSession(
      contentHash: contentHash ?? this.contentHash,
      itemId: itemId ?? this.itemId,
      messages: messages ?? this.messages,
      outline: clearOutline ? null : (outline ?? this.outline),
      workOutlines: clearWorkOutlineKey != null
          ? {
              for (final entry in (workOutlines ?? this.workOutlines).entries)
                if (entry.key != clearWorkOutlineKey) entry.key: entry.value,
            }
          : (workOutlines ?? this.workOutlines),
    );
  }

  Map<String, Object?> toJson() => {
    'contentHash': contentHash,
    'itemId': itemId,
    'messages': messages.map((m) => m.toJson()).toList(growable: false),
    if (outline != null) 'outline': outline!.toJson(),
    if (workOutlines.isNotEmpty)
      'workOutlines': workOutlines.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
  };

  static AiChatSession fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <AiChatMessage>[];
    if (rawMessages is List) {
      for (final row in rawMessages) {
        if (row is Map) {
          messages.add(AiChatMessage.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    final rawWorkOutlines = json['workOutlines'];
    final workOutlines = <String, AiBookOutline>{};
    if (rawWorkOutlines is Map) {
      for (final entry in rawWorkOutlines.entries) {
        if (entry.value is Map) {
          final parsed = AiBookOutline.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          if (parsed != null) {
            workOutlines[entry.key] = parsed;
          }
        }
      }
    }
    return AiChatSession(
      contentHash: json['contentHash'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      messages: messages,
      outline: AiBookOutline.fromJson(json['outline']),
      workOutlines: workOutlines,
    );
  }
}

/// Local JSON store — one file per [contentHash].
///
/// Product: **same file re-import keeps memory**. Library row delete must NOT
/// call [delete]; only the user "清空对话" action should. Not in WebDAV backup.
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

  @override
  Future<AiChatSession?> read({
    required String contentHash,
    required String itemId,
  }) async {
    try {
      final file = _fileFor(contentHash);
      if (!await file.exists()) {
        return AiChatSession(contentHash: contentHash, itemId: itemId);
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return AiChatSession(contentHash: contentHash, itemId: itemId);
      }
      final session = AiChatSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (session.itemId != itemId && itemId.isNotEmpty) {
        return session.copyWith(itemId: itemId);
      }
      return session;
    } catch (_) {
      return AiChatSession(contentHash: contentHash, itemId: itemId);
    }
  }

  @override
  Future<void> write(AiChatSession session) async {
    await _directory.create(recursive: true);
    final file = _fileFor(session.contentHash);
    await file.writeAsString(jsonEncode(session.toJson()), flush: true);
  }

  @override
  Future<void> delete(String contentHash) async {
    final file = _fileFor(contentHash);
    if (await file.exists()) {
      await file.delete();
    }
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

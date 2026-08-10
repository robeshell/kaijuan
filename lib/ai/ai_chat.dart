import 'ai_models.dart';
import 'ai_book_structure.dart';
import 'ai_mind_map.dart';
import 'ai_outline.dart';
import 'ai_provider_kind.dart';

enum AiChatTurnStatus {
  pending,
  completed,
  failed,
  cancelled;

  static AiChatTurnStatus fromStorage(Object? value) {
    final name = '$value';
    return AiChatTurnStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => AiChatTurnStatus.completed,
    );
  }
}

enum AiMindMapRequestScope {
  unspecified,
  currentChapter,
  currentWork,
  wholeBook,
}

enum AiMindMapStructureRoute { wholePublication, sequentialUnits, chooseUnits }

AiMindMapStructureRoute resolveAiMindMapStructureRoute(
  AiBookStructureManifest? manifest,
) {
  if (manifest == null || manifest.works.length < 2) {
    return AiMindMapStructureRoute.wholePublication;
  }
  return switch (manifest.kind) {
    AiBookStructureKind.segmentedSingleWork =>
      AiMindMapStructureRoute.sequentialUnits,
    AiBookStructureKind.multiWorkOmnibus ||
    AiBookStructureKind.uncertain => AiMindMapStructureRoute.chooseUnits,
    AiBookStructureKind.singleWork => AiMindMapStructureRoute.wholePublication,
  };
}

/// Routes only product mind-map requests. Explicit Mermaid requests remain
/// ordinary rich chat content even when they mention a mind map.
AiMindMapRequestScope? resolveAiMindMapRequestScope(String text) {
  final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final asksForMap =
      normalized.contains('思维导图') ||
      normalized.contains('脑图') ||
      normalized.contains('mindmap');
  if (!asksForMap || normalized.contains('mermaid')) return null;
  final asksHowOrWhy = const [
    '为什么',
    '为何',
    '怎么',
    '如何',
    'howto',
    'why',
  ].any(normalized.contains);
  if (asksHowOrWhy) return null;
  final hasGenerationAction = const [
    '重新生成',
    '生成',
    '创建',
    '制作',
    '绘制',
    '画',
    '做',
    '整理成',
    '梳理成',
    'generate',
    'create',
    'draw',
    'make',
  ].any(normalized.contains);
  if (!hasGenerationAction) return null;
  if (const ['当前章', '当前章节', '这一章', '这章', '本章'].any(normalized.contains)) {
    return AiMindMapRequestScope.currentChapter;
  }
  if (const ['当前作品', '这部作品', '当前这部', '这一部'].any(normalized.contains)) {
    return AiMindMapRequestScope.currentWork;
  }
  if (const ['这本书', '本书', '整本书', '全书'].any(normalized.contains)) {
    return AiMindMapRequestScope.wholeBook;
  }
  if (const ['合集', '全部作品', '整部合集'].any(normalized.contains)) {
    return AiMindMapRequestScope.wholeBook;
  }
  return AiMindMapRequestScope.unspecified;
}

/// One user or assistant bubble in the book chat.
class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent = '',
    this.reasoningKind = AiReasoningContentKind.process,
    this.pinned = false,
    this.createdAt,
    this.webHitCount,
    this.suggestedQuestions = const [],
    this.turnId,
    this.status = AiChatTurnStatus.completed,
    this.mindMap,
  });

  final AiMessageRole role;
  final String content;

  /// Optional provider-supplied reasoning shown in a separate disclosure.
  /// It is excluded from answer copy and future model history.
  final String reasoningContent;
  final AiReasoningContentKind reasoningKind;
  final bool pinned;
  final DateTime? createdAt;

  /// When set on a **user** turn: search ran (`0` = empty hits, `n` = n results).
  /// `null` = 联网 off for that turn.
  final int? webHitCount;

  /// One answer-specific follow-up generated after an assistant reply.
  final List<String> suggestedQuestions;

  /// Stable identity shared by the user message and its assistant reply.
  /// Legacy messages have no id and are treated as completed history.
  final String? turnId;

  /// Non-completed turns remain visible to the reader but are excluded from
  /// future model history, so a failed request cannot poison the next prompt.
  final AiChatTurnStatus status;

  /// App-owned structured artifact rendered inside this conversation turn.
  /// It is never sent back to the chat model as Mermaid or prompt text.
  final AiBookMindMap? mindMap;

  AiChatMessage copyWith({
    AiMessageRole? role,
    String? content,
    String? reasoningContent,
    AiReasoningContentKind? reasoningKind,
    bool? pinned,
    DateTime? createdAt,
    int? webHitCount,
    List<String>? suggestedQuestions,
    String? turnId,
    AiChatTurnStatus? status,
    AiBookMindMap? mindMap,
    bool clearWebHitCount = false,
    bool clearMindMap = false,
  }) {
    return AiChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      reasoningKind: reasoningKind ?? this.reasoningKind,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      webHitCount: clearWebHitCount ? null : (webHitCount ?? this.webHitCount),
      suggestedQuestions: suggestedQuestions ?? this.suggestedQuestions,
      turnId: turnId ?? this.turnId,
      status: status ?? this.status,
      mindMap: clearMindMap ? null : (mindMap ?? this.mindMap),
    );
  }

  Map<String, Object?> toJson() => {
    'role': role.name,
    'content': content,
    if (reasoningContent.isNotEmpty) 'reasoningContent': reasoningContent,
    if (reasoningContent.isNotEmpty)
      'reasoningKind': reasoningKind.storageValue,
    'pinned': pinned,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (webHitCount != null) 'webHitCount': webHitCount,
    if (suggestedQuestions.isNotEmpty) 'suggestedQuestions': suggestedQuestions,
    if (turnId != null) 'turnId': turnId,
    'status': status.name,
    if (mindMap != null) 'mindMap': mindMap!.toJson(),
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
      reasoningContent: json['reasoningContent'] as String? ?? '',
      reasoningKind: AiReasoningContentKind.fromStorage(json['reasoningKind']),
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
      turnId: json['turnId'] as String?,
      status: AiChatTurnStatus.fromStorage(json['status']),
      mindMap: AiBookMindMap.fromJson(json['mindMap']),
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
    this.scopeLabel,
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

  /// When set (collections / volume-split books), chat is scoped to this one
  /// work inside the book — the model must answer for this work alone, not
  /// the whole set. TOC and tool bodies are already trimmed to its range.
  final String? scopeLabel;
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
  AiChatShortcut(
    label: '生成本书大纲',
    prompt:
        '请为当前这本书生成一份清晰、完整的大纲。先用一段话概括全书主线与核心主题，'
        '再按内容推进列出主要结构阶段；每一项包含简短标题和说明，并覆盖全书的重要部分。'
        '请直接基于书中内容回答。',
  ),
  AiChatShortcut(label: '生成本章思维导图', prompt: '请为当前章生成思维导图'),
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
    this.workMessages = const {},
  });

  final String contentHash;
  final String itemId;

  /// Whole-book chat messages (plain books). Collections keep per-work
  /// messages in [workMessages] instead — same 读哪本跟哪本 model as
  /// [workOutlines]: each work's conversation is isolated so its history
  /// never leaks another work's characters/plot into the LLM context.
  final List<AiChatMessage> messages;

  /// Whole-book outline (plain books; collections keep per-work outlines in
  /// [workOutlines] instead).
  final AiBookOutline? outline;

  /// Per-work outlines of a collection, keyed by the work key (graph
  /// workKey, e.g. 's4'). The 读哪本跟哪本 model: each work generates and
  /// loads its own outline; the tab follows the reading position.
  final Map<String, AiBookOutline> workOutlines;

  /// Per-work chat messages of a collection, keyed by work key. See
  /// [messages] for why collections don't share one list.
  final Map<String, List<AiChatMessage>> workMessages;

  /// Messages for [workKey]: the per-work list for collections, the shared
  /// whole-book list when [workKey] is null (plain books).
  List<AiChatMessage> messagesFor(String? workKey) =>
      workKey == null ? messages : (workMessages[workKey] ?? const []);

  AiChatSession copyWith({
    String? contentHash,
    String? itemId,
    List<AiChatMessage>? messages,
    AiBookOutline? outline,
    Map<String, AiBookOutline>? workOutlines,
    Map<String, List<AiChatMessage>>? workMessages,
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
      workMessages: workMessages ?? this.workMessages,
    );
  }

  /// Returns a copy with [messages] stored under [workKey] (collections), or
  /// as the whole-book list when [workKey] is null.
  AiChatSession withMessagesFor(String? workKey, List<AiChatMessage> msgs) {
    if (workKey == null) return copyWith(messages: msgs);
    return copyWith(workMessages: {...workMessages, workKey: msgs});
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
    if (workMessages.isNotEmpty)
      'workMessages': workMessages.map(
        (key, value) =>
            MapEntry(key, value.map((m) => m.toJson()).toList(growable: false)),
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
    final rawWorkMessages = json['workMessages'];
    final workMessages = <String, List<AiChatMessage>>{};
    if (rawWorkMessages is Map) {
      for (final entry in rawWorkMessages.entries) {
        if (entry.value is List) {
          workMessages[entry.key] = [
            for (final row in entry.value as List)
              if (row is Map)
                AiChatMessage.fromJson(Map<String, dynamic>.from(row)),
          ];
        }
      }
    }
    return AiChatSession(
      contentHash: json['contentHash'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      messages: messages,
      outline: AiBookOutline.fromJson(json['outline']),
      workOutlines: workOutlines,
      workMessages: workMessages,
    );
  }
}

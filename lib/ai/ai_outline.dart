import 'dart:convert';

import 'ai_chat_retrieve.dart';
import 'ai_log.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_settings.dart';

/// Outline calls carry long prompts (whole TOC units of a collection book
/// inside a summarize batch) and emit sizeable JSON; the provider default
/// (45s) is a chat-friendly budget and times out on long collection books.
const Duration _outlineCallTimeout = Duration(seconds: 120);

/// How a node's reading range was determined. The model never creates this.
enum AiOutlineNodeSource {
  toc,
  heading,
  semantic;

  String get wireName => name;

  static AiOutlineNodeSource fromWireName(Object? value) => switch (value) {
    'heading' => AiOutlineNodeSource.heading,
    'semantic' => AiOutlineNodeSource.semantic,
    _ => AiOutlineNodeSource.toc,
  };
}

/// A bounded, reader-derived range that may become a child outline node.
class AiBookOutlineCandidate {
  const AiBookOutlineCandidate({
    required this.label,
    required this.startSectionIndex,
    required this.text,
    required this.source,
    this.endSectionIndexExclusive,
  });

  final String label;
  final int startSectionIndex;
  final int? endSectionIndexExclusive;
  final String text;
  final AiOutlineNodeSource source;
}

/// One generated section in a book-scoped AI outline.
class AiBookOutlineChapter {
  const AiBookOutlineChapter({
    required this.sectionIndex,
    required this.title,
    required this.summary,
    this.keyPoints = const [],
    this.sourceSectionIndex,
    this.nodeId = '',
    this.endSectionIndexExclusive,
    this.source = AiOutlineNodeSource.toc,
    this.children,
  });

  final int sectionIndex;
  final String title;
  final String summary;
  final List<String> keyPoints;

  /// 1-based original EPUB spine section; differs for logical split units.
  final int? sourceSectionIndex;

  /// Stable path within the cached outline tree.
  final String nodeId;

  /// Exclusive 1-based spine endpoint when the reader can determine one.
  final int? endSectionIndexExclusive;

  final AiOutlineNodeSource source;

  /// `null` means not loaded; an empty list means there are no child nodes.
  final List<AiBookOutlineChapter>? children;

  String get stableNodeId => nodeId.isEmpty ? 'node-$sectionIndex' : nodeId;

  AiBookOutlineChapter copyWith({
    String? title,
    String? summary,
    List<String>? keyPoints,
    List<AiBookOutlineChapter>? children,
  }) => AiBookOutlineChapter(
    sectionIndex: sectionIndex,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    keyPoints: keyPoints ?? this.keyPoints,
    sourceSectionIndex: sourceSectionIndex,
    nodeId: nodeId,
    endSectionIndexExclusive: endSectionIndexExclusive,
    source: source,
    children: children ?? this.children,
  );

  Map<String, Object?> toJson() => {
    'sectionIndex': sectionIndex,
    'title': title,
    'summary': summary,
    if (keyPoints.isNotEmpty) 'keyPoints': keyPoints,
    if (sourceSectionIndex != null && sourceSectionIndex != sectionIndex)
      'sourceSectionIndex': sourceSectionIndex,
    if (nodeId.isNotEmpty) 'nodeId': nodeId,
    if (endSectionIndexExclusive != null)
      'endSectionIndexExclusive': endSectionIndexExclusive,
    if (source != AiOutlineNodeSource.toc) 'source': source.wireName,
    if (children != null)
      'children': [for (final child in children!) child.toJson()],
  };

  static AiBookOutlineChapter? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sectionIndex = raw['sectionIndex'];
    final title = raw['title'];
    final summary = raw['summary'];
    if (sectionIndex is! int ||
        sectionIndex < 1 ||
        title is! String ||
        title.trim().isEmpty ||
        summary is! String ||
        summary.trim().isEmpty) {
      return null;
    }
    final points = raw['keyPoints'];
    final sourceSectionIndex = raw['sourceSectionIndex'];
    final endSectionIndexExclusive = raw['endSectionIndexExclusive'];
    final childrenRaw = raw['children'];
    List<AiBookOutlineChapter>? children;
    if (childrenRaw is List) {
      children = [
        for (final value in childrenRaw) ?AiBookOutlineChapter.fromJson(value),
      ];
    }
    return AiBookOutlineChapter(
      sectionIndex: sectionIndex,
      title: title.trim(),
      summary: summary.trim(),
      keyPoints: points is List
          ? points
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .take(4)
                .toList(growable: false)
          : <String>[],
      sourceSectionIndex: sourceSectionIndex is int && sourceSectionIndex >= 1
          ? sourceSectionIndex
          : null,
      nodeId: raw['nodeId'] is String ? (raw['nodeId'] as String).trim() : '',
      endSectionIndexExclusive:
          endSectionIndexExclusive is int && endSectionIndexExclusive >= 2
          ? endSectionIndexExclusive
          : null,
      source: AiOutlineNodeSource.fromWireName(raw['source']),
      children: children,
    );
  }
}

/// Cached outline for one exact book file ([contentHash]).
class AiBookOutline {
  const AiBookOutline({
    required this.createdAt,
    required this.model,
    required this.includesUnread,
    required this.overview,
    required this.chapters,
    this.themes = const [],
  });

  static const currentVersion = 12;

  final DateTime createdAt;
  final String model;
  final bool includesUnread;
  final String overview;
  final List<String> themes;
  final List<AiBookOutlineChapter> chapters;

  AiBookOutline copyWith({List<AiBookOutlineChapter>? chapters}) =>
      AiBookOutline(
        createdAt: createdAt,
        model: model,
        includesUnread: includesUnread,
        overview: overview,
        themes: themes,
        chapters: chapters ?? this.chapters,
      );

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'model': model,
    'includesUnread': includesUnread,
    'overview': overview,
    if (themes.isNotEmpty) 'themes': themes,
    'chapters': [for (final chapter in chapters) chapter.toJson()],
  };

  static AiBookOutline? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['version'] != currentVersion) return null;
    final createdAt = DateTime.tryParse('${raw['createdAt'] ?? ''}');
    final model = raw['model'];
    final overview = raw['overview'];
    final chapters = raw['chapters'];
    if (createdAt == null ||
        model is! String ||
        overview is! String ||
        chapters is! List) {
      return null;
    }
    final parsed = <AiBookOutlineChapter>[];
    for (final row in chapters) {
      final chapter = AiBookOutlineChapter.fromJson(row);
      if (chapter != null) parsed.add(chapter);
    }
    if (parsed.isEmpty) return null;
    final themes = raw['themes'];
    return AiBookOutline(
      createdAt: createdAt,
      model: model,
      includesUnread: raw['includesUnread'] as bool? ?? false,
      overview: overview.trim(),
      themes: themes is List
          ? themes
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .take(6)
                .toList(growable: false)
          : const [],
      chapters: parsed,
    );
  }
}

/// Visible status for an outline generation job.
class AiOutlineProgress {
  const AiOutlineProgress({
    required this.completed,
    required this.total,
    required this.label,
    this.finalizing = false,
  });

  final int completed;
  final int total;
  final String label;
  final bool finalizing;
}

/// Produces a deterministic, per-section outline without sending an entire
/// long book in one request. The caller owns persistence and cancellation.
class AiBookOutlineService {
  factory AiBookOutlineService({
    required bool Function() isAvailable,
    required AiProvider? Function() openProvider,
    required AiSettings Function() settings,
  }) => AiBookOutlineService._(
    isAvailable: isAvailable,
    openProvider: openProvider,
    settings: settings,
  );

  AiBookOutlineService._({
    required this._isAvailable,
    required this._openProvider,
    required this._settings,
  });

  final bool Function() _isAvailable;
  final AiProvider? Function() _openProvider;
  final AiSettings Function() _settings;

  static const _maxSectionSampleChars = 3600;
  static const maxBookBodyChars = 1500000;
  static const _maxStructurePlanChars = 36000;
  static const _maxStructureLabelChars = 120;
  static const _maxStructureSampleChars = 320;
  static const _maxBatchChars = 15000;
  static const _maxBatchUnits = 4;
  static const _maxDirectNavigationUnits = 24;
  static const _maxOverviewChars = 36000;

  Future<AiBookOutline> generate({
    required String bookTitle,
    String? bookAuthor,
    required List<AiBookSectionSlice> sections,
    required bool includesUnread,
    /// Pre-arranged top-level units taken from the book's TOC tree: skips
    /// the AI structure pass (the reader's own directory is authoritative).
    /// [preplannedRoots] carries the TOC tree; AI summaries/overview are
    /// merged back into it so nested directory items keep their titles.
    List<AiBookSectionSlice>? preplannedUnits,
    List<AiBookOutlineChapter>? preplannedRoots,
    CancelToken? cancelToken,
    void Function(AiOutlineProgress progress)? onProgress,
  }) async {
    if (!_isAvailable()) throw AiProviderException('AI 未启用或未配置');
    final provider = _openProvider();
    if (provider == null) throw AiProviderException('AI 未启用或未配置');
    if (sections.isEmpty) throw AiProviderException('无法读取本书正文');

    cancelToken?.throwIfCancelled();
    onProgress?.call(
      AiOutlineProgress(
        completed: 0,
        total: sections.length,
        label: '正在识别全书结构',
      ),
    );
    final units = preplannedUnits ??
        await planStructure(
          provider: provider,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          sections: sections,
          cancelToken: cancelToken,
        );
    cancelToken?.throwIfCancelled();
    final batches = _batches(units);
    final chapters = <AiBookOutlineChapter>[];
    for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      cancelToken?.throwIfCancelled();
      final batch = batches[batchIndex];
      final completed = chapters.length;
      final first = batch.first;
      onProgress?.call(
        AiOutlineProgress(
          completed: completed,
          total: units.length,
          label: '正在分析第 ${first.index} 节',
        ),
      );
      final generated = await _summarizeBatch(
        provider: provider,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        batch: batch,
        cancelToken: cancelToken,
      );
      cancelToken?.throwIfCancelled();
      final byIndex = {
        for (final chapter in generated) chapter.sectionIndex: chapter,
      };
      if (byIndex.length != batch.length ||
          batch.any((section) => !byIndex.containsKey(section.index))) {
        throw AiProviderException('章节大纲不完整，请重试');
      }
      for (final section in batch) {
        final generatedChapter = byIndex[section.index]!;
        chapters.add(
          AiBookOutlineChapter(
            sectionIndex: generatedChapter.sectionIndex,
            title: generatedChapter.title,
            summary: generatedChapter.summary,
            keyPoints: generatedChapter.keyPoints,
            sourceSectionIndex: section.sourceSectionIndex,
            nodeId: 'top-${section.index}',
          ),
        );
      }
      onProgress?.call(
        AiOutlineProgress(
          completed: chapters.length,
          total: units.length,
          label: '已分析 ${chapters.length}/${units.length} 节',
        ),
      );
    }
    if (chapters.isEmpty) throw AiProviderException('未能生成可用大纲');

    // Merge the AI summaries into the TOC tree (if one was given): the
    // directory structure is authoritative, AI only enriches it.
    final byChapterIndex = {
      for (final chapter in chapters) chapter.sectionIndex: chapter,
    };
    final finalChapters = preplannedRoots == null
        ? chapters
        : [
            for (final root in preplannedRoots)
              (() {
                final enriched = byChapterIndex[root.sectionIndex];
                if (enriched == null) return root;
                return root.copyWith(
                  title: enriched.title,
                  summary: enriched.summary,
                  keyPoints: enriched.keyPoints,
                );
              }()),
          ];

    cancelToken?.throwIfCancelled();
    onProgress?.call(
      AiOutlineProgress(
        completed: chapters.length,
        total: units.length,
        label: '正在整理全书脉络',
        finalizing: true,
      ),
    );
    final overview = await _buildOverview(
      provider: provider,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      chapters: chapters,
      cancelToken: cancelToken,
    );
    cancelToken?.throwIfCancelled();
    return AiBookOutline(
      createdAt: DateTime.now(),
      model: _settings().resolvedModel,
      includesUnread: includesUnread,
      overview: overview.overview,
      themes: overview.themes,
      chapters: finalChapters,
    );
  }





  /// Lets the model identify works and volumes before summaries are requested.
  /// A malformed plan must never make body sections disappear, so it falls
  /// back to a one-section-per-unit plan.
  /// One-shot structural recognition: groups contiguous spine sections into
  /// logical units (a chapter, a volume, or a whole work inside a collection).
  /// Public so graph generation can detect collections before an outline
  /// exists (docs/specs/ai-graph.md §合集选书).
  Future<List<AiBookSectionSlice>> planStructure({
    AiProvider? provider,
    required String bookTitle,
    required String? bookAuthor,
    required List<AiBookSectionSlice> sections,
    CancelToken? cancelToken,
  }) async {
    final resolvedProvider = provider ?? _openProvider();
    if (resolvedProvider == null) {
      throw AiProviderException('AI 未启用或未配置');
    }
    final manifest = _structureManifest(sections);
    if (sections.length <= _maxDirectNavigationUnits &&
        sections.every((section) => section.isNavigationUnit)) {
      AiLog.d('outline structure skipped: ${sections.length} navigation units');
      return sections;
    }
    AiLog.d(
      'outline structure input=${sections.length} '
      'indexes=${sections.map((section) => section.index).join(',')}',
    );
    final result = await completeWithRetry(
      resolvedProvider,
      AiCompletionRequest(
        messages: [
          const AiMessage(
            role: AiMessageRole.system,
            content:
                '你是电子书结构编辑。先识别一本书的叙事或论述单元。'
                '普通书通常一节一个单元；合集、文集、分卷作品应把属于同一部作品或一卷的连续节合并。'
                '只能根据给出的节标题和短样本判断，不能编造标题或内容。'
                '只有确实属于目录、版权、扉页、出版信息等非正文元数据的节才能忽略；不确定时必须放进一个 group。'
                '每个输入 sectionIndex 必须恰好出现一次：要么在一个 group 的 sectionIndexes 中，要么在 ignoredSectionIndexes 中。'
                '不得遗漏、重复或使用未提供的 sectionIndex。'
                '只返回 JSON 对象，不要 Markdown 或解释：'
                '{"groups":[{"title":"单元标题","sectionIndexes":[1,2]}],"ignoredSectionIndexes":[3]}。',
          ),
          AiMessage(
            role: AiMessageRole.user,
            content:
                '书名：$bookTitle'
                '${bookAuthor == null || bookAuthor.trim().isEmpty ? '' : '\n作者：${bookAuthor.trim()}'}'
                '\n\n结构清单：\n$manifest',
          ),
        ],
        maxTokens: 5000,
        temperature: 0.1,
        timeout: _outlineCallTimeout,
      ),
      cancelToken: cancelToken,
    );
    final plan = _parseStructurePlan(result.text, sections);
    if (plan == null) {
      AiLog.d(
        'outline structure invalid; falling back to ${sections.length} units',
      );
      return sections;
    }
    final byIndex = {for (final section in sections) section.index: section};
    final units = <AiBookSectionSlice>[];
    for (final group in plan.groups) {
      final members = [
        for (final index in group.sectionIndexes) byIndex[index]!,
      ]..sort((a, b) => a.index.compareTo(b.index));
      units.add(
        AiBookSectionSlice(
          index: members.first.index,
          label: group.title,
          text: _groupSample(members),
          sourceSectionIndex: members.first.originSectionIndex,
        ),
      );
    }
    units.sort((a, b) => a.index.compareTo(b.index));
    AiLog.d(
      'outline structure groups=${units.length} '
      'indexes=${units.map((unit) => unit.index).join(',')}',
    );
    return units.isEmpty ? sections : units;
  }

  String _structureManifest(List<AiBookSectionSlice> sections) {
    final headers = <String>[
      for (final section in sections)
        '[§${section.index} ${_clip(section.label.trim(), _maxStructureLabelChars)}]',
    ];
    final headerChars = headers.fold<int>(
      0,
      (sum, value) => sum + value.length + 1,
    );
    final sampleBudget = (_maxStructurePlanChars - headerChars)
        .clamp(0, _maxStructureSampleChars * sections.length)
        .toInt();
    final perSection = sections.isEmpty
        ? 0
        : (sampleBudget ~/ sections.length)
              .clamp(0, _maxStructureSampleChars)
              .toInt();
    final out = StringBuffer();
    for (var i = 0; i < sections.length; i++) {
      out.writeln(headers[i]);
      if (perSection > 0) {
        out.writeln(_clip(sections[i].text.trim(), perSection));
      }
    }
    return out.toString().trim();
  }

  _OutlineStructurePlan? _parseStructurePlan(
    String text,
    List<AiBookSectionSlice> sections,
  ) {
    final raw = _decodeJsonObject(text);
    final groupsRaw = raw?['groups'];
    final ignoredRaw = raw?['ignoredSectionIndexes'];
    if (groupsRaw is! List || ignoredRaw is! List) return null;

    final expected = {for (final section in sections) section.index};
    final byIndex = {for (final section in sections) section.index: section};
    final seen = <int>{};
    final groups = <_OutlineStructureGroup>[];
    for (final row in groupsRaw) {
      if (row is! Map) return null;
      final title = row['title'];
      final indexes = row['sectionIndexes'];
      if (title is! String || title.trim().isEmpty || indexes is! List) {
        return null;
      }
      final parsedIndexes = <int>[];
      for (final index in indexes) {
        if (index is! int || !expected.contains(index) || !seen.add(index)) {
          return null;
        }
        parsedIndexes.add(index);
      }
      if (parsedIndexes.isEmpty) return null;
      groups.add(
        _OutlineStructureGroup(
          title: title.trim(),
          sectionIndexes: parsedIndexes,
        ),
      );
    }
    for (final index in ignoredRaw) {
      if (index is! int ||
          !expected.contains(index) ||
          !seen.add(index) ||
          !_isUnambiguousMetadataSection(byIndex[index]!)) {
        return null;
      }
    }
    if (groups.isEmpty || seen.length != expected.length) return null;
    return _OutlineStructurePlan(groups: groups);
  }

  bool _isUnambiguousMetadataSection(AiBookSectionSlice section) {
    final title = section.label.trim().replaceAll(RegExp(r'\s+'), '');
    if (RegExp(
      r'^(目录|总目录|全书目录|章节目录|目次|版权(?:信息)?|出版(?:信息|说明)?|图书在版编目|封面|封底|扉页|书名页)$',
    ).hasMatch(title)) {
      return true;
    }
    final text = section.text.trim();
    if (text.isEmpty) return true;
    final prefix = text.length > 640 ? text.substring(0, 640) : text;
    final compact = prefix.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^(目录|目次)(?:[：:]|$)').hasMatch(compact)) return true;
    final hasCopyrightSignal = RegExp(
      r'ISBN|图书在版编目|版权所有|版权归属|版权信息',
    ).hasMatch(prefix);
    return hasCopyrightSignal && RegExp(r'出版|出版社|版权|编目').hasMatch(prefix);
  }

  List<List<AiBookSectionSlice>> _batches(List<AiBookSectionSlice> sections) {
    final output = <List<AiBookSectionSlice>>[];
    var current = <AiBookSectionSlice>[];
    var used = 0;
    for (final section in sections) {
      final sample = _sample(section);
      final length = sample.text.length + sample.label.length + 32;
      if (current.isNotEmpty &&
          (used + length > _maxBatchChars ||
              current.length >= _maxBatchUnits)) {
        output.add(current);
        current = <AiBookSectionSlice>[];
        used = 0;
      }
      current.add(sample);
      used += length;
    }
    if (current.isNotEmpty) output.add(current);
    return output;
  }

  AiBookSectionSlice _sample(AiBookSectionSlice section) {
    final text = section.text.trim();
    if (text.length <= _maxSectionSampleChars) return section;
    final head = (_maxSectionSampleChars * 0.72).round();
    final tail = _maxSectionSampleChars - head;
    return AiBookSectionSlice(
      index: section.index,
      label: section.label,
      text:
          '${text.substring(0, head)}\n…\n${text.substring(text.length - tail)}',
      sourceSectionIndex: section.sourceSectionIndex,
    );
  }

  String _groupSample(List<AiBookSectionSlice> members) {
    if (members.length == 1) return _sample(members.single).text;
    const maxBodyChars = 3000;
    final perMember = (maxBodyChars ~/ members.length).clamp(80, 600).toInt();
    final out = StringBuffer();
    for (final member in members) {
      final label = member.label.trim();
      if (label.isNotEmpty) out.writeln('【$label】');
      out.writeln(_clip(member.text.trim(), perMember));
    }
    return out.toString().trim();
  }

  String _clip(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final head = (maxChars * 0.72).round();
    final tail = maxChars - head;
    return '${text.substring(0, head)}\n…\n${text.substring(text.length - tail)}';
  }

  Future<List<AiBookOutlineChapter>> _summarizeBatch({
    required AiProvider provider,
    required String bookTitle,
    required String? bookAuthor,
    required List<AiBookSectionSlice> batch,
    CancelToken? cancelToken,
  }) async {
    AiLog.d(
      'outline summarize indexes=${batch.map((section) => section.index).join(',')}',
    );
    final body = StringBuffer();
    for (final section in batch) {
      body
        ..writeln('[§${section.index} ${section.label}]')
        ..writeln(section.text.trim())
        ..writeln();
    }
    final result = await completeWithRetry(
      provider,
      AiCompletionRequest(
        messages: [
          const AiMessage(
            role: AiMessageRole.system,
            content:
                '你是阅读助手，负责把书籍章节整理成可靠的大纲。'
                '只依据提供的正文，不补写不存在的情节。'
                '输入单元可能是一章，也可能是合集中的一部作品或一卷；'
                '标题必须反映该单元，不要把目录、版权等元数据说成正文。'
                '只返回 JSON 数组，不要 Markdown 或解释。'
                '数组中每个对象必须是 '
                '{"sectionIndex":数字,"title":"单元标题","summary":"100至220字摘要","keyPoints":["要点"]}。'
                '必须为每个提供的 § 返回一个对象，sectionIndex 不得改写。',
          ),
          AiMessage(
            role: AiMessageRole.user,
            content:
                '书名：$bookTitle'
                '${bookAuthor == null || bookAuthor.trim().isEmpty ? '' : '\n作者：${bookAuthor.trim()}'}'
                '\n\n以下是需要归纳的章节：\n$body',
          ),
        ],
        maxTokens: 1800,
        temperature: 0.2,
        timeout: _outlineCallTimeout,
      ),
      cancelToken: cancelToken,
    );
    final parsed = _parseChapterArray(result.text);
    if (parsed.isEmpty) throw AiProviderException('大纲格式无效，请重试');
    return parsed;
  }

  Future<({String overview, List<String> themes})> _buildOverview({
    required AiProvider provider,
    required String bookTitle,
    required String? bookAuthor,
    required List<AiBookOutlineChapter> chapters,
    CancelToken? cancelToken,
  }) async {
    final summaries = StringBuffer();
    for (final chapter in chapters) {
      summaries.writeln(
        '§${chapter.sectionIndex} ${chapter.title}：${chapter.summary}',
      );
      if (summaries.length >= _maxOverviewChars) break;
    }
    final result = await completeWithRetry(
      provider,
      AiCompletionRequest(
        messages: [
          const AiMessage(
            role: AiMessageRole.system,
            content:
                '你是阅读助手。根据章节摘要总结全书，不补写书中没有的内容。'
                '若书是合集，先说明由哪些作品、分卷或主题构成，再概括它们的关联。'
                '只返回 JSON 对象：'
                '{"overview":"120至220字的全书脉络","themes":["主题"]}。',
          ),
          AiMessage(
            role: AiMessageRole.user,
            content:
                '书名：$bookTitle'
                '${bookAuthor == null || bookAuthor.trim().isEmpty ? '' : '\n作者：${bookAuthor.trim()}'}'
                '\n\n章节摘要：\n$summaries',
          ),
        ],
        maxTokens: 900,
        temperature: 0.2,
        timeout: _outlineCallTimeout,
      ),
      cancelToken: cancelToken,
    );
    final raw = _decodeJsonObject(result.text);
    final overview = raw?['overview'];
    final themes = raw?['themes'];
    if (overview is! String || overview.trim().isEmpty) {
      throw AiProviderException('全书概览格式无效，请重试');
    }
    return (
      overview: overview.trim(),
      themes: themes is List
          ? themes
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .take(6)
                .toList(growable: false)
          : <String>[],
    );
  }

  static List<AiBookOutlineChapter> _parseChapterArray(String text) {
    final raw = _decodeJsonArray(text);
    if (raw == null) return const [];
    final seen = <int>{};
    final output = <AiBookOutlineChapter>[];
    for (final value in raw) {
      final chapter = AiBookOutlineChapter.fromJson(value);
      if (chapter != null && seen.add(chapter.sectionIndex)) {
        output.add(chapter);
      }
    }
    return output;
  }

  static List<Object?>? _decodeJsonArray(String text) {
    final candidate = _jsonCandidate(text, '[', ']');
    if (candidate == null) return null;
    try {
      final value = jsonDecode(candidate);
      return value is List ? List<Object?>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeJsonObject(String text) {
    final candidate = _jsonCandidate(text, '{', '}');
    if (candidate == null) return null;
    try {
      final value = jsonDecode(candidate);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static String? _jsonCandidate(String text, String open, String close) {
    var value = text.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false),
        '',
      );
      value = value.replaceFirst(RegExp(r'\s*```\s*$'), '');
    }
    final start = value.indexOf(open);
    final end = value.lastIndexOf(close);
    if (start < 0 || end < start) return null;
    return value.substring(start, end + 1);
  }
}

class _OutlineStructurePlan {
  const _OutlineStructurePlan({required this.groups});

  final List<_OutlineStructureGroup> groups;
}

class _OutlineStructureGroup {
  const _OutlineStructureGroup({
    required this.title,
    required this.sectionIndexes,
  });

  final String title;
  final List<int> sectionIndexes;
}

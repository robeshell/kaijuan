import 'dart:convert';

import 'ai_chat_retrieve.dart';
import 'ai_graph.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_settings.dart';

/// Progress of one incremental graph run (per section).
class AiGraphProgress {
  const AiGraphProgress({
    required this.completed,
    required this.total,
    required this.label,
  });

  final int completed;
  final int total;
  final String label;
}

/// Raised when a run stopped (cancel / chapter failure / bad output).
///
/// Carries the graph merged so far so callers can persist partial progress —
/// stop and per-chapter failures must never lose already-extracted sections.
class AiGraphGenerationException implements Exception {
  const AiGraphGenerationException(this.message, {this.partial});

  final String message;
  final AiBookGraph? partial;

  @override
  String toString() => message;
}

/// Book-scoped entity / relation extraction.
///
/// Pipeline (docs/specs/ai-graph.md §4): pick un-covered sections inside the
/// allowed range → fenced-JSON extraction per chunk → quote back-fill →
/// sequential incremental co-reference merge → return the merged graph.
///
/// The caller owns persistence (AiGraphStore) and cancellation tokens.
class AiBookGraphService {
  AiBookGraphService({
    required bool Function() isAvailable,
    required AiProvider? Function() openProvider,
    required AiSettings Function() settings,
  }) : _isAvailable = isAvailable,
       _openProvider = openProvider,
       _settings = settings;

  final bool Function() _isAvailable;
  final AiProvider? Function() _openProvider;
  final AiSettings Function() _settings;

  /// Max characters of one chapter sent per extraction call. Smaller chunks
  /// keep single-response output (and latency) bounded; a halving fallback
  /// below handles dense sections whose entities exceed the token budget.
  static const int chunkMaxChars = 6000;

  /// Overlap between adjacent chunks so relations spanning a cut survive.
  static const int chunkOverlapChars = 200;

  /// Max sections extracted in parallel per batch. Extraction is independent
  /// per section; merge stays sequential to keep co-reference deterministic.
  static const int maxConcurrentSections = 3;

  /// Output budget per extraction call. Generous so dense sections are not
  /// truncated, but the halving fallback (not this budget) is the real guard.
  static const int extractionMaxTokens = 8192;

  /// Whole-run corpus budget (mirrors outline's cap).
  static const int maxBookBodyChars = 1500000;

  Future<AiBookGraph> generate({
    required String bookTitle,
    String? bookAuthor,
    required List<AiBookSectionSlice> sections,
    required bool includesUnread,
    int? readThroughSection,
    AiBookGraph? existing,
    CancelToken? cancelToken,
    void Function(AiGraphProgress progress)? onProgress,
  }) async {
    if (!_isAvailable()) {
      throw const AiGraphGenerationException('AI 未启用或未配置');
    }
    final provider = _openProvider();
    if (provider == null) {
      throw const AiGraphGenerationException('AI 未启用或未配置');
    }

    try {
      cancelToken?.throwIfCancelled();
    } on AiProviderException {
      throw AiGraphGenerationException('图谱生成已停止', partial: existing);
    }

    // Working set: sections inside the read range that are not yet covered.
    final usable = sections
        .where((s) => s.text.trim().isNotEmpty)
        .toList(growable: false);
    if (usable.isEmpty) {
      throw const AiGraphGenerationException('无法读取本书正文');
    }

    final working = <AiBookSectionSlice>[];
    for (final s in usable) {
      final origin = s.originSectionIndex;
      if (!includesUnread &&
          readThroughSection != null &&
          origin > readThroughSection) {
        continue;
      }
      if (existing?.coveredSections.contains(origin) ?? false) continue;
      working.add(s);
    }

    final covered = <int>[...?existing?.coveredSections];
    final entities = <AiGraphEntity>[...?existing?.entities];
    final relations = <AiGraphRelation>[...?existing?.relations];

    // Sequential incremental co-reference cache: type -> alias -> canonical.
    final canonical = <AiGraphEntityType, Map<String, String>>{};
    for (final e in entities) {
      final bucket = canonical.putIfAbsent(e.type, () => {});
      bucket[e.name] = e.name;
      for (final alias in e.aliases) {
        bucket[alias] = e.name;
      }
    }

    final entityIndex = <String, AiGraphEntity>{
      for (final e in entities) e.id: e,
    };
    final relationIndex = <String, AiGraphRelation>{
      for (final r in relations) r.mergeKey: r,
    };

    onProgress?.call(
      AiGraphProgress(
        completed: 0,
        total: working.length,
        label: '正在抽取实体与关系',
      ),
    );

    try {
      for (var batchStart = 0;
          batchStart < working.length;
          batchStart += maxConcurrentSections) {
        cancelToken?.throwIfCancelled();
        final batchEnd = (batchStart + maxConcurrentSections) < working.length
            ? batchStart + maxConcurrentSections
            : working.length;
        final batch = working.sublist(batchStart, batchEnd);
        // Extract every section of the batch in parallel (each section's
        // chunks stay sequential inside); merge stays ordered afterwards.
        final results = await Future.wait<List<Map<String, Object?>>>([
          for (final section in batch)
            _extractSection(
              provider,
              section,
              bookTitle: bookTitle,
              bookAuthor: bookAuthor,
              cancelToken: cancelToken,
            ),
        ]);
        // Merge sequentially in chapter order so co-reference is stable.
        for (var i = 0; i < batch.length; i++) {
          cancelToken?.throwIfCancelled();
          final section = batch[i];
          final origin = section.originSectionIndex;
          for (final raw in results[i]) {
            _mergeChunk(
              canonical: canonical,
              entityIndex: entityIndex,
              relationIndex: relationIndex,
              entities: entities,
              relations: relations,
              sectionIndex: origin,
              sectionText: section.text,
              raw: raw,
            );
          }
          if (!covered.contains(origin)) covered.add(origin);
          covered.sort();
          onProgress?.call(
            AiGraphProgress(
              completed: batchStart + i + 1,
              total: working.length,
              label: '已处理第 $origin 节',
            ),
          );
        }
      }
    } on AiProviderException catch (e) {
      final message = e.message.contains('已取消')
          ? '图谱生成已停止'
          : '图谱抽取失败：${e.message}';
      throw AiGraphGenerationException(
        message,
        partial: _partialGraph(
          existing,
          contentHash: existing?.contentHash ?? '',
          includesUnread: includesUnread,
          covered: covered,
          entities: entities,
          relations: relations,
        ),
      );
    } on AiGraphGenerationException {
      rethrow;
    } catch (e) {
      throw AiGraphGenerationException(
        '图谱抽取失败：$e',
        partial: _partialGraph(
          existing,
          contentHash: existing?.contentHash ?? '',
          includesUnread: includesUnread,
          covered: covered,
          entities: entities,
          relations: relations,
        ),
      );
    }

    entities.sort(_byFrequencyThenName);
    relations.sort((a, b) => b.evidence.length.compareTo(a.evidence.length));
    return AiBookGraph(
      contentHash: existing?.contentHash ?? '',
      generatedAt: DateTime.now().toUtc(),
      model: _settings().resolvedModel,
      includesUnread: includesUnread,
      coveredSections: covered,
      entities: entities,
      relations: relations,
    );
  }

  AiBookGraph _partialGraph(
    AiBookGraph? existing, {
    required String contentHash,
    required bool includesUnread,
    required List<int> covered,
    required List<AiGraphEntity> entities,
    required List<AiGraphRelation> relations,
  }) {
    final dirty =
        covered.length != (existing?.coveredSections.length ?? 0) ||
        entities.length != (existing?.entities.length ?? 0) ||
        relations.length != (existing?.relations.length ?? 0);
    if (!dirty) return existing ?? AiBookGraph(contentHash: contentHash);
    return AiBookGraph(
      contentHash: contentHash,
      generatedAt: DateTime.now().toUtc(),
      model: _settings().resolvedModel,
      includesUnread: includesUnread,
      coveredSections: covered,
      entities: entities,
      relations: relations,
    );
  }

  static int _byFrequencyThenName(AiGraphEntity a, AiGraphEntity b) {
    final fa = a.chapterFreq.values.fold<int>(0, (sum, v) => sum + v);
    final fb = b.chapterFreq.values.fold<int>(0, (sum, v) => sum + v);
    if (fa != fb) return fb.compareTo(fa);
    return a.name.compareTo(b.name);
  }

  /// Split a chapter into bounded chunks with overlap.
  static List<String> _chunkText(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    if (t.length <= chunkMaxChars) return [t];
    final out = <String>[];
    var start = 0;
    while (start < t.length) {
      var end = start + chunkMaxChars;
      if (end < t.length) {
        final cut = t.lastIndexOf('\n', end);
        if (cut > start + chunkMaxChars ~/ 2) end = cut;
      }
      if (end > t.length) end = t.length;
      out.add(t.substring(start, end));
      if (end >= t.length) break;
      start = end - chunkOverlapChars;
    }
    return out;
  }

  /// Extracts every chunk of one section sequentially; returns the raw
  /// per-chunk payloads in chunk order for the ordered merge phase.
  Future<List<Map<String, Object?>>> _extractSection(
    AiProvider provider,
    AiBookSectionSlice section, {
    required String bookTitle,
    required String? bookAuthor,
    required CancelToken? cancelToken,
  }) async {
    final origin = section.originSectionIndex;
    final chunks = _chunkText(section.text);
    final raws = <Map<String, Object?>>[];
    for (final chunk in chunks) {
      cancelToken?.throwIfCancelled();
      try {
        raws.add(
          await _extractChunk(
            provider,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            sectionIndex: origin,
            chunkText: chunk,
            cancelToken: cancelToken,
          ),
        );
      } on AiGraphGenerationException {
        // Invalid / truncated output (finish=length on dense sections): halve
        // the chunk so the model has room to close the JSON. One level only;
        // a sub-chunk failure still surfaces to the caller.
        if (chunk.length < 600) rethrow;
        cancelToken?.throwIfCancelled();
        final halves = _splitChunk(chunk);
        raws.add(
          await _extractChunk(
            provider,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            sectionIndex: origin,
            chunkText: halves[0],
            cancelToken: cancelToken,
          ),
        );
        raws.add(
          await _extractChunk(
            provider,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            sectionIndex: origin,
            chunkText: halves[1],
            cancelToken: cancelToken,
          ),
        );
      }
    }
    return raws;
  }

  /// Splits a chunk near its midpoint, preferring a line break, so each half
  /// is a coherent text unit with its own extraction call.
  static List<String> _splitChunk(String chunk) {
    final mid = chunk.length ~/ 2;
    var cut = chunk.indexOf('\n', mid - 200);
    if (cut < 0 || cut > mid + 200) {
      cut = chunk.lastIndexOf('\n', mid);
    }
    if (cut <= 0 || cut >= chunk.length - 1) {
      cut = mid;
    }
    final first = chunk.substring(0, cut).trim();
    final second = chunk.substring(cut).trim();
    if (first.isEmpty || second.isEmpty) {
      final hard = mid;
      return [
        chunk.substring(0, hard).trim(),
        chunk.substring(hard).trim(),
      ];
    }
    return [first, second];
  }

  Future<Map<String, Object?>> _extractChunk(
    AiProvider provider, {
    required String bookTitle,
    required String? bookAuthor,
    required int sectionIndex,
    required String chunkText,
    required CancelToken? cancelToken,
  }) async {
    final messages = [
      AiMessage(
        role: AiMessageRole.system,
        content:
            '你是书籍分析引擎。只依据给定原文抽取人物、地点、事件实体与它们之间的关系，'
            '禁止使用原文以外的知识。严格只输出一个 JSON 对象，不要输出 JSON 之外的任何文字。',
      ),
      AiMessage(
        role: AiMessageRole.user,
        content:
            '书名：《$bookTitle》${bookAuthor == null ? '' : '  作者：$bookAuthor'}\n'
            '章节编号：$sectionIndex\n\n'
            '抽取要求：只输出如下结构的 JSON：\n'
            '{"entities":[{"name":"规范名","type":"person|location|event",'
            '"aliases":["别名"],"description":"3-5句","evidence":[{"section":'
            '$sectionIndex,"quote":"原文连续片段"}]}],'
            '"relations":[{"source":"实体A","target":"实体B",'
            '"type":"snake_case关系类型","description":"一句",'
            '"evidence":[{"section":$sectionIndex,"quote":"原文连续片段"}]}]}\n'
            '规则：name 用书中最常见称呼；aliases 含其余称呼；'
            'quote 必须逐字来自以下正文；evidence 至少 1 条；'
            'type 取值仅限 person/location/event；关系类型用小写 snake_case；'
            '本章无实体或关系时对应数组输出 []。\n\n'
            '正文：\n$chunkText',
      ),
    ];

    final request = AiCompletionRequest(
      messages: messages,
      maxTokens: extractionMaxTokens,
      temperature: 0,
    );

    var decoded = _decodeJsonObject(
      (await completeWithRetry(provider, request, cancelToken: cancelToken))
          .text,
    );
    if (decoded == null) {
      // One re-probe with an explicit "only JSON" nudge before giving up.
      final retryRequest = AiCompletionRequest(
        messages: [
          ...messages,
          AiMessage(
            role: AiMessageRole.user,
            content:
                '你上一次的回复不是有效 JSON。请只输出一个 JSON 对象，不要代码块之外的文字。',
          ),
        ],
        maxTokens: extractionMaxTokens,
        temperature: 0,
      );
      decoded = _decodeJsonObject(
        (await completeWithRetry(provider, retryRequest, cancelToken: cancelToken))
            .text,
      );
    }
    if (decoded == null) {
      throw const AiGraphGenerationException('图谱抽取输出无效，请重试');
    }

    final rawEntities = decoded['entities'];
    final rawRelations = decoded['relations'];
    if (rawEntities is! List || rawRelations is! List) {
      throw const AiGraphGenerationException('图谱抽取格式无效，请重试');
    }
    return {'entities': rawEntities, 'relations': rawRelations};
  }

  /// Sequential incremental merge: alias→canonical by type bucket, unique
  /// `name+type` / `source+target+type`, evidence appended never overwritten.
  static void _mergeChunk({
    required Map<AiGraphEntityType, Map<String, String>> canonical,
    required Map<String, AiGraphEntity> entityIndex,
    required Map<String, AiGraphRelation> relationIndex,
    required List<AiGraphEntity> entities,
    required List<AiGraphRelation> relations,
    required int sectionIndex,
    required String sectionText,
    required Map<String, Object?> raw,
  }) {
    final rawEntities = raw['entities'];
    if (rawEntities is List) {
      for (final item in rawEntities) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final name = map['name'];
        final typeRaw = map['type'];
        if (name is! String || name.trim().isEmpty) continue;
        final type = AiGraphEntityType.fromWireName(typeRaw);
        final originalName = name.trim();
        final canonicalName = _resolveCanonical(
          canonical,
          type,
          originalName,
        ) ??
            _resolveAliases(canonical, type, map['aliases']) ??
            originalName;

        final bucket = canonical.putIfAbsent(type, () => {});
        bucket[canonicalName] = canonicalName;
        // Immutable chain: never mutate the _stringList result, which can be
        // a const [] (fixed-length) when the model omits the aliases field.
        // When this entity's own name resolved to an existing canonical, the
        // original name must survive as an alias (e.g. 三哥 → 张三).
        final aliases = _stringList(
          map['aliases'],
        ).where((alias) => alias != canonicalName).toList();
        if (originalName != canonicalName && !aliases.contains(originalName)) {
          aliases.add(originalName);
        }
        for (final alias in aliases) {
          bucket[alias] = canonicalName;
        }

        final key = '$canonicalName|${type.wireName}';
        final existing = entityIndex[key];
        if (existing != null) {
          final next = _mergeEntityEvidence(
            existing,
            aliases,
            map['description'],
            sectionIndex,
            rawEvidence: map['evidence'],
            sectionText: sectionText,
          );
          entityIndex[key] = next;
          final at = entities.indexOf(existing);
          if (at >= 0) entities[at] = next;
        } else {
          final evidence = _evidenceFor(
            map['evidence'],
            sectionIndex,
            sectionText,
          );
          if (evidence.isEmpty) continue;
          final first = evidence.first.sectionIndex;
          final entity = AiGraphEntity(
            name: canonicalName,
            type: type,
            aliases: aliases,
            description: map['description'] as String? ?? '',
            evidence: evidence,
            chapterFreq: {sectionIndex: evidence.length},
            firstSection: first,
            lastSection: first,
          );
          entityIndex[key] = entity;
          entities.add(entity);
        }
      }
    }

    final rawRelations = raw['relations'];
    if (rawRelations is List) {
      for (final item in rawRelations) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final sourceRaw = map['source'];
        final targetRaw = map['target'];
        final typeRaw = map['type'];
        if (sourceRaw is! String ||
            targetRaw is! String ||
            typeRaw is! String) {
          continue;
        }
        final sourceType = _typeOf(entities, entityIndex, sourceRaw.trim());
        final targetType = _typeOf(entities, entityIndex, targetRaw.trim());
        final source =
            _resolveCanonical(canonical, sourceType, sourceRaw.trim()) ??
            sourceRaw.trim();
        final target =
            _resolveCanonical(canonical, targetType, targetRaw.trim()) ??
            targetRaw.trim();
        final type = typeRaw.trim().toLowerCase().replaceAll(' ', '_');
        if (source.isEmpty || target.isEmpty || source == target) continue;

        final key = '$source\u0000$target\u0000$type';
        final existing = relationIndex[key];
        if (existing != null) {
          final next = _mergeRelationEvidence(
            existing,
            map['description'],
            sectionIndex,
            rawEvidence: map['evidence'],
            sectionText: sectionText,
          );
          relationIndex[key] = next;
          final at = relations.indexOf(existing);
          if (at >= 0) relations[at] = next;
        } else {
          final evidence = _evidenceFor(
            map['evidence'],
            sectionIndex,
            sectionText,
          );
          if (evidence.isEmpty) continue;
          final relation = AiGraphRelation(
            source: source,
            target: target,
            type: type,
            description: map['description'] as String? ?? '',
            evidence: evidence,
            weight: evidence.length.toDouble(),
          );
          relationIndex[key] = relation;
          relations.add(relation);
        }
      }
    }
  }

  static String? _resolveCanonical(
    Map<AiGraphEntityType, Map<String, String>> canonical,
    AiGraphEntityType type,
    String name,
  ) {
    return canonical[type]?[name];
  }

  static String? _resolveAliases(
    Map<AiGraphEntityType, Map<String, String>> canonical,
    AiGraphEntityType type,
    Object? rawAliases,
  ) {
    final bucket = canonical[type];
    if (bucket == null) return null;
    for (final alias in _stringList(rawAliases)) {
      final hit = bucket[alias];
      if (hit != null) return hit;
    }
    return null;
  }

  static AiGraphEntityType _typeOf(
    List<AiGraphEntity> entities,
    Map<String, AiGraphEntity> entityIndex,
    String name,
  ) {
    for (final entity in entityIndex.values) {
      if (entity.name == name) return entity.type;
      if (entity.aliases.contains(name)) return entity.type;
    }
    final counts = <AiGraphEntityType, int>{};
    for (final e in entities) {
      if (e.aliases.contains(name)) {
        counts[e.type] = (counts[e.type] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return AiGraphEntityType.person;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static AiGraphEntity _mergeEntityEvidence(
    AiGraphEntity entity,
    List<String> aliases,
    Object? descriptionRaw,
    int sectionIndex, {
    required Object? rawEvidence,
    required String sectionText,
  }) {
    final evidence = [...entity.evidence];
    final seen = <String>{for (final e in evidence) e.quote};
    final chapterFreq = {...entity.chapterFreq};
    for (final e in _evidenceFor(rawEvidence, sectionIndex, sectionText)) {
      if (seen.add(e.quote)) evidence.add(e);
    }
    chapterFreq[sectionIndex] = (chapterFreq[sectionIndex] ?? 0) + 1;
    final first = entity.firstSection == 0
        ? sectionIndex
        : (sectionIndex < entity.firstSection
              ? sectionIndex
              : entity.firstSection);
    final last = sectionIndex > entity.lastSection
        ? sectionIndex
        : entity.lastSection;
    final mergedAliases = [...entity.aliases];
    for (final alias in aliases) {
      if (!mergedAliases.contains(alias)) mergedAliases.add(alias);
    }
    final description = descriptionRaw is String &&
            descriptionRaw.trim().isNotEmpty &&
            entity.description.isEmpty
        ? descriptionRaw.trim()
        : entity.description;
    return entity.copyWith(
      aliases: mergedAliases,
      description: description,
      evidence: evidence,
      chapterFreq: chapterFreq,
      firstSection: first,
      lastSection: last,
    );
  }

  static AiGraphRelation _mergeRelationEvidence(
    AiGraphRelation relation,
    Object? descriptionRaw,
    int sectionIndex, {
    required Object? rawEvidence,
    required String sectionText,
  }) {
    final evidence = [...relation.evidence];
    final seen = <String>{for (final e in evidence) e.quote};
    for (final e in _evidenceFor(rawEvidence, sectionIndex, sectionText)) {
      if (seen.add(e.quote)) evidence.add(e);
    }
    final description = descriptionRaw is String &&
            descriptionRaw.trim().isNotEmpty &&
            relation.description.isEmpty
        ? descriptionRaw.trim()
        : relation.description;
    return relation.copyWith(
      description: description,
      evidence: evidence,
      weight: evidence.length.toDouble(),
    );
  }

  static List<AiGraphEvidence> _evidenceFor(
    Object? raw,
    int sectionIndex,
    String sectionText,
  ) {
    if (raw is! List) return const [];
    final out = <AiGraphEvidence>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final quote = map['quote'];
      if (quote is! String || quote.trim().isEmpty) continue;
      final quoteText = quote.trim();
      if (!seen.add(quoteText)) continue;
      final rawSection = map['section'];
      final section = rawSection is int
          ? rawSection
          : int.tryParse('$rawSection') ?? sectionIndex;
      final progress = _resolveQuote(sectionText, quoteText);
      out.add(
        AiGraphEvidence(
          sectionIndex: section,
          quote: quoteText,
          progressInSection: progress,
          spanResolved: progress != null,
        ),
      );
    }
    return out;
  }

  /// Locate a quote in the section text with whitespace normalization.
  /// Returns the fractional start offset (0..1) or null when not found.
  static double? _resolveQuote(String sectionText, String quote) {
    final trimmed = quote.trim();
    if (trimmed.isEmpty) return null;
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), '');
    final normalized = norm(sectionText);
    final q = norm(trimmed);
    if (normalized.isEmpty || q.isEmpty) return null;
    final idx = normalized.indexOf(q);
    if (idx < 0) return null;
    return (idx / normalized.length).clamp(0.0, 1.0);
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _decodeJsonObject(String text) {
    final candidate = _jsonCandidate(text);
    if (candidate == null) return null;
    try {
      final value = jsonDecode(candidate);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static String? _jsonCandidate(String text) {
    var value = text.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false),
        '',
      );
      value = value.replaceFirst(RegExp(r'\s*```\s*$'), '');
    }
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start < 0 || end < start) return null;
    return value.substring(start, end + 1);
  }
}

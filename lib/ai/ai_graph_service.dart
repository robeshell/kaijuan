import 'dart:convert';

import 'ai_chat_retrieve.dart';
import 'ai_graph.dart';
import 'ai_log.dart';
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

  /// Curated Chinese relation-type vocabulary (from AI settings, defaults in
  /// `AiGraphRuleWords`). The extraction prompt asks the model to pick from
  /// these; [normalizeRelationType] folds anything else (English NER tags,
  /// free-form words) back into this set, so the UI never shows raw model
  /// output (e.g. "trusts", "teacher_student").
  List<String> get _relationTypes =>
      _settings().graphRuleWords.relationTypes;

  Map<String, String> get _relationTypeAliases =>
      _settings().graphRuleWords.relationTypeAliases;

  /// Maps any raw relation-type string (Chinese or English NER tag) into the
  /// curated Chinese vocabulary. Unknown values collapse to [relationFallback].
  String normalizeRelationType(String raw) {
    final key = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (key.isEmpty) return relationFallback;
    final aliased = _relationTypeAliases[key];
    if (aliased != null) return aliased;
    if (_relationTypes.contains(key)) return key;
    return relationFallback;
  }

  /// Fallback for unrecognised relation types; keeps the edge (and its
  /// evidence) instead of silently dropping the model's finding.
  static const String relationFallback = '相关';

  /// Max sections extracted in parallel per batch. Extraction is independent
  /// per section; merge stays sequential to keep co-reference deterministic.
  /// 5 keeps deepseek-class endpoints saturated without tripping rate limits.
  static const int maxConcurrentSections = 5;

  /// Output budget per extraction call. Generous so dense sections are not
  /// truncated, but the halving fallback (not this budget) is the real guard.
  static const int extractionMaxTokens = 8192;

  /// Whole-run corpus budget (mirrors outline's cap).
  static const int maxBookBodyChars = 1500000;

  /// Step-0 display plan call (spec: docs/specs/ai-graph-narration.md §3).
  ///
  /// One whole-book call (title + outline labels + body sample) asking the
  /// model for the five-dimension narration profile and the recommended
  /// default view. The result only drives *display* preferences; it never
  /// touches entity/relation data. Returns null on any failure — the caller
  /// silently falls back to the default view instead of blocking generation.
  static const int narrationMaxTokens = 2048;

  /// Sections sampled for the body glimpse (first N sections).
  static const int narrationSampleSections = 3;

  /// Chars taken from the head of each sampled section.
  static const int narrationSampleChars = 600;

  Future<AiNarrationPlan?> analyzeNarration({
    required String bookTitle,
    String? bookAuthor,
    required List<AiBookSectionSlice> sections,
    CancelToken? cancelToken,
  }) async {
    try {
      cancelToken?.throwIfCancelled();
      if (!_isAvailable()) return null;
      final provider = _openProvider();
      if (provider == null) return null;
      final outline = [
        for (final s in sections.take(200))
          if (s.label.trim().isNotEmpty) s.label.trim(),
      ].toList(growable: false);
      final sample = sections
          .take(narrationSampleSections)
          .map((s) => s.text.length > narrationSampleChars
              ? s.text.substring(0, narrationSampleChars)
              : s.text)
          .join('\n……\n');
      final messages = [
        AiMessage(
          role: AiMessageRole.system,
          content: '你是书籍阅读体验设计师。基于给定信息判断这本书适合怎样'
              '展示知识图谱，严格只输出一个 JSON 对象，不要输出 JSON 之外的任何文字。',
        ),
        AiMessage(
          role: AiMessageRole.user,
          content:
              '书名：《$bookTitle》${bookAuthor == null ? '' : '  作者：$bookAuthor'}\n'
              '大纲（章节标题）：${outline.isEmpty ? '（无）' : outline.join(' / ')}\n\n'
              '正文抽样：\n$sample\n\n'
              '要求：输出如下结构的 JSON：\n'
              '{"features":{"eventDriven":0-1,"characterEnsemble":0-1,'
              '"organization":0-1,"geography":0-1,"essay":0-1},'
              '"defaultView":"persons|locations|events|graph|family_tree|org_tree",'
              '"viewOrder":["推荐顺序，defaultView 第一"],"wantMap":true|false}\n'
              '特征语义（各自独立 0-1，不必相加为 1）：\n'
              '- eventDriven：情节/事件推进叙事（如冒险、案件）\n'
              '- characterEnsemble：人物群像、多主角、关系网是核心（如群像小说）\n'
              '- organization：组织/势力/家族/派系博弈是主线\n'
              '- geography：地理空间/旅途/多地点场景是重要叙事要素\n'
              '- essay：散文/随笔/杂文/评论集（非虚构叙述、议论为主）\n'
              'defaultView 推荐规则：家族/组织博弈为主选 family_tree；'
              '人物关系是核心选 persons；事件主线清晰选 events；'
              '地点重要选 locations；混合型选最值得先看的视图。'
              'viewOrder 是全部候选视图的排列（包含 defaultView 且它排第一，'
              '可含 future 的 org_tree）。wantMap=true 仅当地理叙事显著且地图'
              '能帮助读者时。',
        ),
      ];
      final request = AiCompletionRequest(
        messages: messages,
        maxTokens: narrationMaxTokens,
        temperature: 0,
      );
      final result = await completeWithRetry(
        provider,
        request,
        cancelToken: cancelToken,
      );
      final decoded = _decodeJsonObject(result.text);
      if (decoded == null) return null;
      final plan = AiNarrationPlan.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (plan != null) {
        AiLog.d('graph narration plan: default=${plan.defaultView} '
            'order=${plan.viewOrder.join(',')} wantMap=${plan.wantMap}');
      }
      return plan;
    } on AiProviderException {
      // A cancelled step-0 call must surface the stop, not silently fall
      // back (otherwise the user's stop only takes effect at extraction).
      rethrow;
    } catch (_) {
      // Silent fallback: a failed plan call never blocks graph generation.
      return null;
    }
  }

  Future<AiBookGraph> generate({
    required String bookTitle,
    String? bookAuthor,
    required List<AiBookSectionSlice> sections,
    required bool includesUnread,
    int? readThroughSection,
    AiBookGraph? existing,
    /// User-confirmed display plan from the pre-generation dialog. When
    /// null the pipeline auto-runs step 0 (or reuses [existing]'s plan).
    AiNarrationPlan? plannedNarration,
    CancelToken? cancelToken,
    void Function(AiGraphProgress progress)? onProgress,
  }) async {    if (!_isAvailable()) {
      throw const AiGraphGenerationException('AI 未启用或未配置');
    }
    final provider = _openProvider();
    if (provider == null) {
      throw const AiGraphGenerationException('AI 未启用或未配置');
    }
    final sw = Stopwatch()..start();

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

    // Step 0: display plan (once per graph). A failure or a missing provider
    // silently skips narration — generation proceeds with the default view.
    AiNarrationPlan? narration = plannedNarration ?? existing?.narration;
    if (narration == null && working.isNotEmpty) {
      onProgress?.call(
        AiGraphProgress(
          completed: 0,
          total: working.length,
          label: '正在分析本书的展示方案…',
        ),
      );
      narration = await analyzeNarration(
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        sections: sections,
        cancelToken: cancelToken,
      );
    }

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
        // Known-entity table from the merge cache so far: tells the model
        // which entities already exist, so a chapter only emits new relations
        // and evidence instead of re-describing known characters.
        final knownEntities = _knownEntitiesText(entities);
        // Extract every section of the batch in parallel (each section's
        // chunks stay sequential inside); merge stays ordered afterwards.
        final results = await Future.wait<List<Map<String, Object?>>>([
          for (final section in batch)
            _extractSection(
              provider,
              section,
              bookTitle: bookTitle,
              bookAuthor: bookAuthor,
              knownEntities: knownEntities,
              narration: narration,
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
              label: '正在分析第 ${batchStart + i + 1} / ${working.length} 节',
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
          generationSeconds: sw.elapsed.inSeconds,
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
          generationSeconds: sw.elapsed.inSeconds,
        ),
      );
    }

    // Metadata entities (the book's author / preface writers) are not story
    // entities: drop them and any edge that only touches them.
    final metaNames = <String>{
      bookTitle.trim(),
      if (bookAuthor != null && bookAuthor.trim().isNotEmpty)
        bookAuthor.trim(),
    };
    if (metaNames.isNotEmpty) {
      final storyNames = <String>{};
      entities.removeWhere((e) {
        final drop = metaNames.contains(e.name) ||
            e.aliases.any(metaNames.contains);
        if (!drop) storyNames.add(e.name);
        return drop;
      });
      relations.removeWhere(
        (r) => !storyNames.contains(r.source) || !storyNames.contains(r.target),
      );
    }

    // Hard rules that only downgrade (never upgrade) the model's scope:
    // a quote matching a citation pattern (据X / 如X所言 / X写道 ...) marks
    // the entity as a reference — e.g. 罗素 in an essay collection.
    // There is deliberately no single-chapter rule: in essay collections
    // every chapter is a standalone piece, so single-chapter people are
    // normal book content, not citations. Low-frequency entities are kept
    // out of the graph by the top-N cut anyway.
    _applyScopeHardRules(entities);

    entities.sort(_byFrequencyThenName);
    relations.sort((a, b) => b.evidence.length.compareTo(a.evidence.length));
    return AiBookGraph(
      contentHash: existing?.contentHash ?? '',
      generatedAt: DateTime.now().toUtc(),
      generationSeconds: sw.elapsed.inSeconds,
      model: _settings().resolvedModel,
      includesUnread: includesUnread,
      coveredSections: covered,
      sectionTitles: {
        for (final section in sections)
          section.originSectionIndex: section.label,
      },
      entities: entities,
      relations: relations,
      narration: narration,
    );
  }

  AiBookGraph _partialGraph(
    AiBookGraph? existing, {
    required String contentHash,
    required bool includesUnread,
    required List<int> covered,
    required List<AiGraphEntity> entities,
    required List<AiGraphRelation> relations,
    required int? generationSeconds,
  }) {
    final dirty =
        covered.length != (existing?.coveredSections.length ?? 0) ||
        entities.length != (existing?.entities.length ?? 0) ||
        relations.length != (existing?.relations.length ?? 0);
    if (!dirty) return existing ?? AiBookGraph(contentHash: contentHash);
    return AiBookGraph(
      contentHash: contentHash,
      generatedAt: DateTime.now().toUtc(),
      generationSeconds: generationSeconds,
      model: _settings().resolvedModel,
      includesUnread: includesUnread,
      coveredSections: covered,
      sectionTitles: existing?.sectionTitles ?? const {},
      entities: entities,
      relations: relations,
      narration: existing?.narration,
    );
  }

  static int _byFrequencyThenName(AiGraphEntity a, AiGraphEntity b) {
    final fa = a.chapterFreq.values.fold<int>(0, (sum, v) => sum + v);
    final fb = b.chapterFreq.values.fold<int>(0, (sum, v) => sum + v);
    if (fa != fb) return fb.compareTo(fa);
    return a.name.compareTo(b.name);
  }

  /// Downgrades entities to [AiGraphEntityScope.reference] when hard evidence
  /// says they are citations, not story. Only downgrades — a setting entity
  /// is never re-marked reference by the model's own word alone, and an
  /// entity the model called reference is never upgraded here.
  void _applyScopeHardRules(List<AiGraphEntity> entities) {
    if (entities.isEmpty) return;
    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];
      if (entity.scope == AiGraphEntityScope.reference) continue;
      final citedByQuote = entity.evidence.any(
        (ev) => _isCitationQuote(ev.quote, entity.name, entity.aliases),
      );
      if (citedByQuote) {
        entities[i] = entity.copyWith(scope: AiGraphEntityScope.reference);
      }
    }
  }

  /// True when the quote frames [name] (or an alias) as an outside citation
  /// rather than a story event, e.g. 据X / 按X / 如X所言 / 正如X所说 / X曾说 /
  /// X写道 / X所言 / 据说X. Deliberately excludes 说/认为/指出 alone —
  /// those are also ordinary narration verbs inside a story. Templates come
  /// from AI settings; `{name}` is replaced with the entity name.
  bool _isCitationQuote(String quote, String name, List<String> aliases) {
    if (quote.isEmpty || name.isEmpty) return false;
    final templates =
        _settings().graphRuleWords.citationQuoteTemplates;
    if (templates.isEmpty) return false;
    for (final n in {name, ...aliases}) {
      if (n.isEmpty) continue;
      for (final template in templates) {
        if (quote.contains(template.replaceAll('{name}', n))) return true;
      }
    }
    return false;
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

  /// Formats the top entities (by frequency) as a compact known-entity table
  /// for the extraction prompt. Bounded so prompt size stays flat.
  static String _knownEntitiesText(List<AiGraphEntity> entities) {
    if (entities.isEmpty) return '';
    final sorted = [...entities]..sort(_byFrequencyThenName);
    final lines = <String>[];
    for (final entity in sorted.take(80)) {
      final aliases = entity.aliases.take(3).join('、');
      lines.add(
        aliases.isEmpty
            ? '  ${entity.name}'
            : '  ${entity.name}（$aliases）',
      );
    }
    return lines.join('\n');
  }

  /// Extracts every chunk of one section sequentially; returns the raw
  /// per-chunk payloads in chunk order for the ordered merge phase.
  Future<List<Map<String, Object?>>> _extractSection(
    AiProvider provider,
    AiBookSectionSlice section, {
    required String bookTitle,
    required String? bookAuthor,
    required String knownEntities,
    required AiNarrationPlan? narration,
    required CancelToken? cancelToken,
  }) async {
    final origin = section.originSectionIndex;
    final chunks = _chunkText(section.text);
    final raws = <Map<String, Object?>>[];
    for (final chunk in chunks) {
      cancelToken?.throwIfCancelled();
      raws.addAll(
        await _extractChunkWithFallback(
          provider,
          origin,
          chunk,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          knownEntities: knownEntities,
          narration: narration,
          cancelToken: cancelToken,
        ),
      );
    }
    return raws;
  }

  /// Extracts one chunk, halving it recursively when output is invalid or
  /// truncated (finish=length on dense sections), so the model always has
  /// room to close the JSON. Depth is bounded; a small chunk failure surfaces.
  Future<List<Map<String, Object?>>> _extractChunkWithFallback(
    AiProvider provider,
    int sectionIndex,
    String chunk, {
    required String bookTitle,
    required String? bookAuthor,
    required String knownEntities,
    required AiNarrationPlan? narration,
    required CancelToken? cancelToken,
    int depth = 0,
  }) async {
    try {
      return [
        await _extractChunk(
          provider,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          sectionIndex: sectionIndex,
          chunkText: chunk,
          knownEntities: knownEntities,
          narration: narration,
          cancelToken: cancelToken,
        ),
      ];
    } on AiGraphGenerationException {
      if (chunk.length < 2000 || depth >= 2) rethrow;
      cancelToken?.throwIfCancelled();
      final halves = _splitChunk(chunk);
      final first = await _extractChunkWithFallback(
        provider,
        sectionIndex,
        halves[0],
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        knownEntities: knownEntities,
        narration: narration,
        cancelToken: cancelToken,
        depth: depth + 1,
      );
      final second = await _extractChunkWithFallback(
        provider,
        sectionIndex,
        halves[1],
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        knownEntities: knownEntities,
        narration: narration,
        cancelToken: cancelToken,
        depth: depth + 1,
      );
      return [...first, ...second];
    }
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
    // Never split a UTF-16 surrogate pair (emoji / rare CJK ext chars):
    // back up if the cut lands right after a high surrogate.
    if (cut > 0 &&
        cut < chunk.length &&
        chunk.codeUnitAt(cut - 1) >= 0xd800 &&
        chunk.codeUnitAt(cut - 1) <= 0xdbff) {
      cut -= 1;
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
    required String knownEntities,
    required AiNarrationPlan? narration,
    required CancelToken? cancelToken,
  }) async {
    final knownBlock = knownEntities.isEmpty
        ? ''
        : '已知实体（已存在，本章只补充它们的新关系与证据，'
              '不要重复创建，不要为它们写 description）：\n'
              '$knownEntities\n\n';
    // Narration-driven extraction branches (spec §3.3): the step-0 plan
    // tunes the prompt per book, without touching the validation/merge
    // pipeline. Organization books may emit `organization` entities.
    final narrationBlock = narration == null
        ? ''
        : [
            if (narration.feature('organization') >= 0.5)
              '本书以组织/势力/家族博弈为主：实体类型额外允许 organization'
              '（家族、组织、势力、派系，如「史塔克家族」），'
              '并多抽隶属关系（隶属/效力/追随）；',
            if (narration.feature('geography') >= 0.5)
              '地理叙事显著：location 实体仅限地理地点（城市/国家/区域/'
              '自然地貌/街道/建筑场所），船只、机构、组织、公司等不算 location；'
              'location 的 description 应包含方位与地点间的相对关系'
              '（如「位于城北，紧邻港口」）；',
            if (narration.feature('essay') >= 0.5)
              '本书为散文/随笔/议论集：scope 判定从严，单章举例引述的'
              '人物一律 reference，只有全书反复出现的讨论对象可标 setting；',
          ].join();
    final entityTypes = (narration?.feature('organization') ?? 0) >= 0.5
        ? 'person|location|event|organization'
        : 'person|location|event';
    final messages = [
      AiMessage(
        role: AiMessageRole.system,
        content:
            '你是书籍分析引擎。只依据给定原文抽取人物、地点、事件实体与它们之间的关系，'
            '禁止使用原文以外的知识。严格只输出一个 JSON 对象，不要输出 JSON 之外的任何文字。\n'
            // Fixed extraction rules live in the system message (stable
            // prefix → DeepSeek context-cache hits at 0.02元 vs 1元).
            // The section number / body / known-entity list stay in the user
            // message so the system prefix never changes across sections.
            '规则：name 用书中最常见称呼；aliases 含其余称呼、不超过 3 个；'
            'description 用一句话、不超过 20 字，紧扣证据；'
            'quote 必须逐字来自正文，单条不超过 30 字；evidence 至少 1 条；'
            'type 取值仅限 $entityTypes；'
            'type 为 event 时必须输出 eventType（仅限 战斗/成长/社交/旅行/'
            '角色登场/物品交接/组织变动/关系变化 之一，用最贴切的一个）'
            '与 importance（1-3 整数，3=重大情节）；'
            'scope 判定：绝大多数实体都应是 setting——本书正文中出现的'
            '任何角色、地点、事件、讨论对象（包括作者亲历、叙述的主题）；'
            'reference 仅限明显的外部引用：举例、论证时引用的书外人名，'
            '典型句式「据X」「按X」「如X所言」「正如X所说」「X曾说」「X写道」'
            '（如散文中引用的罗素、苏东坡）。'
            '标错 reference 会让该实体从图谱主视图中隐藏，'
            '所以只对真正的引用标 reference；'
            '$narrationBlock'
            '${_relationTypes.isEmpty
                ? '关系类型不受限制，自由描述（中文，如 结盟、背叛）；'
                : '关系类型仅限以下中文：${_relationTypes.join('、')}，用最贴切的一个；'}'
            '方向性关系（亲属/师徒/隶属/效力/追随）必须固定方向：'
            'source=长辈/师父/上级/被效力方/被追随者，'
            'target=晚辈/徒弟/下级/效力者/追随者，方向颠倒即为错误；'
            '婚配/同盟/敌对等无方向关系不做方向要求；'
            '不要抽取书作者、作序者、编者、译者等元信息人物，'
            '除非他们作为故事角色实际登场；'
            '本章无实体或关系时对应数组输出 []。',
      ),
      AiMessage(
        role: AiMessageRole.user,
        content:
            '书名：《$bookTitle》${bookAuthor == null ? '' : '  作者：$bookAuthor'}\n'
            '章节编号：$sectionIndex\n\n'
            '抽取要求：只输出如下结构的 JSON：\n'
            '{"entities":[{"name":"规范名","type":"$entityTypes",'
            '"scope":"setting|reference",'
            '"aliases":["别名"],"description":"一句话","evidence":[{"section":'
            '$sectionIndex,"quote":"原文连续片段"}]}],'
            '"relations":[{"source":"实体A","target":"实体B",'
            '"type":"snake_case关系类型","description":"一句",'
            '"kin":"具体称谓（仅亲属/婚配/师徒等关系，如 父子/夫妻/兄弟/师徒）",'
            '"evidence":[{"section":$sectionIndex,"quote":"原文连续片段"}]}]}\n\n'
            '正文：\n$chunkText\n\n'
            '已抽取实体（合并时参考，避免重复输出）：\n$knownBlock',
      ),
    ];

    final request = AiCompletionRequest(
      messages: messages,
      maxTokens: extractionMaxTokens,
      temperature: 0,
    );

    final firstResult = await completeWithRetry(
      provider,
      request,
      cancelToken: cancelToken,
    );
    var decoded = _decodeJsonObject(firstResult.text);
    if (decoded == null && firstResult.truncated) {
      // finish=length: the JSON is cut mid-object and the same request would
      // truncate again. Halving (handled by the section loop) is cheaper
      // than a wasted retry.
      throw const AiGraphGenerationException('图谱抽取输出被截断');
    }
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
  void _mergeChunk({
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
        // Unknown types are dropped, not silently bucketed as person.
        if (typeRaw is! String ||
            (typeRaw != 'person' &&
                typeRaw != 'location' &&
                typeRaw != 'event' &&
                typeRaw != 'organization')) {
          continue;
        }
        final type = AiGraphEntityType.fromWireName(typeRaw);
        final scopeRaw = map['scope'];
        final scope = scopeRaw is String
            ? AiGraphEntityScope.fromWireName(scopeRaw)
            : AiGraphEntityScope.setting;
        final eventType = type == AiGraphEntityType.event
            ? AiGraphEventType.fromWireName(map['eventType'])
            : AiGraphEventType.other;
        final importance = type == AiGraphEntityType.event &&
                map['importance'] is int
            ? (map['importance'] as int).clamp(0, 3)
            : 0;
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
          // Any source marking the entity as setting wins: the model is more
          // reliable at recognizing story entities than at excluding them.
          final mergedScope = existing.scope == AiGraphEntityScope.setting ||
                  scope == AiGraphEntityScope.setting
              ? AiGraphEntityScope.setting
              : AiGraphEntityScope.reference;
          // Event metadata: keep the first non-other category, max importance.
          final mergedEventType =
              existing.eventType == AiGraphEventType.other
              ? eventType
              : existing.eventType;
          final mergedImportance =
              existing.importance > importance ? existing.importance : importance;
          final updated = mergedScope == existing.scope &&
                  mergedEventType == existing.eventType &&
                  mergedImportance == existing.importance
              ? next
              : next.copyWith(
                  scope: mergedScope,
                  eventType: mergedEventType,
                  importance: mergedImportance,
                );
          entityIndex[key] = updated;
          final at = entities.indexOf(existing);
          if (at >= 0) entities[at] = updated;
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
            scope: scope,
            aliases: aliases,
            description: map['description'] as String? ?? '',
            evidence: evidence,
            chapterFreq: {sectionIndex: evidence.length},
            firstSection: first,
            lastSection: first,
            eventType: eventType,
            importance: importance,
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
        final type = normalizeRelationType(typeRaw);
        if (source.isEmpty || target.isEmpty || source == target) continue;

        final key = '$source\u0000$target\u0000$type';
        final existing = relationIndex[key];
        if (existing != null) {
          final next = _mergeRelationEvidence(
            existing,
            map['description'],
            map['kin'],
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
            kin: map['kin'] as String? ?? '',
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
    Object? kinRaw,
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
    final kin = kinRaw is String &&
            kinRaw.trim().isNotEmpty &&
            relation.kin.isEmpty
        ? kinRaw.trim()
        : relation.kin;
    return relation.copyWith(
      description: description,
      kin: kin,
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
      // Evidence always belongs to the section being extracted; ignore any
      // `section` the model echoes back (a hallucinated number would skew
      // progress gating, legacy attribution and quote jumps).
      final section = sectionIndex;
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

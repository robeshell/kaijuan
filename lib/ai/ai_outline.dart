import 'dart:convert';

import 'ai_chat_retrieve.dart';
import 'ai_log.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_settings.dart';

/// Outline calls carry long prompts (whole-book bodies) and emit sizeable
/// JSON; the provider default (45s) is a chat-friendly budget and times out
/// on long collection books.
const Duration _outlineCallTimeout = Duration(seconds: 120);

/// One structural unit in the book's outline: a section of the book the AI
/// identified as a coherent block (an essay in a collection, a part in a
/// novel, a topic cluster in nonfiction).
class AiOutlineUnit {
  const AiOutlineUnit({
    required this.title,
    required this.blurb,
  });

  final String title;
  final String blurb;

  Map<String, Object?> toJson() => {'title': title, 'blurb': blurb};

  static AiOutlineUnit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final blurb = raw['blurb'];
    if (title is! String || title.trim().isEmpty) return null;
    if (blurb is! String || blurb.trim().isEmpty) return null;
    return AiOutlineUnit(title: title.trim(), blurb: blurb.trim());
  }
}

/// Structural outline for one exact book file ([contentHash]): a paragraph
/// overview + a list of units in reading order. Chapter-level navigation is
/// the reader's own TOC, not this.
///
/// ## 版本规则
///
/// [currentVersion] 单调递增，永不复用。[fromJson] 只接受严格等于
/// currentVersion 的 JSON——其他版本返回 null，调用方重新生成。大纲
/// 内容便宜可再生（一次 LLM 调用），不为老版本写迁移。
///
/// 何时该 bump version：仅当 schema 发生**破坏性变更**（删字段、改字段
/// 含义、改嵌套结构）。新增可选字段、改字段名（提供别名解析）不应 bump。
class AiBookOutline {
  const AiBookOutline({
    required this.createdAt,
    required this.model,
    required this.overview,
    required this.units,
  });

  static const currentVersion = 14;

  final DateTime createdAt;
  final String model;

  /// One paragraph (200-300 chars) describing the book's overall arc.
  final String overview;

  /// 5-15 structural units in reading order.
  final List<AiOutlineUnit> units;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'model': model,
    'overview': overview,
    'units': [for (final unit in units) unit.toJson()],
  };

  static AiBookOutline? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['version'] != currentVersion) return null;
    final createdAt = DateTime.tryParse('${raw['createdAt'] ?? ''}');
    final model = raw['model'];
    final overview = raw['overview'];
    final unitsRaw = raw['units'];
    if (createdAt == null ||
        model is! String ||
        overview is! String ||
        overview.trim().isEmpty ||
        unitsRaw is! List) {
      return null;
    }
    final units = [
      for (final row in unitsRaw) ?AiOutlineUnit.fromJson(row),
    ];
    if (units.isEmpty) return null;
    return AiBookOutline(
      createdAt: createdAt,
      model: model,
      overview: overview.trim(),
      units: units,
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

/// One-shot structural outline over the whole (or current-work) body. The
/// caller owns persistence and cancellation.
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

  static const _maxBodyChars = 24000;
  static const maxBookBodyChars = 1500000;

  /// Per-unit sampling floor: a multi-unit book (multi-volume novel like
  /// 《明朝那些事儿》 with one unit per 部) must still give each unit a real
  /// head+tail sample, or later volumes vanish from the prompt. Long books
  /// therefore get a larger total budget than the 24k default.
  static const _minUnitSampleChars = 1500;
  static const _maxPackedBodyChars = 80000;

  Future<AiBookOutline> generate({
    required String bookTitle,
    String? bookAuthor,

    /// When set, [bookTitle] is one work inside the collection
    /// [collectionTitle] — the overview must describe this work alone, not
    /// the whole set. Keeps a collection's per-work outline from drifting
    /// into a set-level summary (the LLM otherwise anchors on the set name).
    String? collectionTitle,
    required List<AiBookSectionSlice> sections,
    CancelToken? cancelToken,
    void Function(AiOutlineProgress progress)? onProgress,
  }) async {
    if (!_isAvailable()) throw AiProviderException('AI 未启用或未配置');
    final provider = _openProvider();
    if (provider == null) throw AiProviderException('AI 未启用或未配置');
    if (sections.isEmpty) throw AiProviderException('无法读取本书正文');

    onProgress?.call(
      const AiOutlineProgress(completed: 0, total: 1, label: '正在提炼大纲'),
    );
    cancelToken?.throwIfCancelled();

    final body = _packBody(sections);
    if (body.isEmpty) throw AiProviderException('没有可用于生成大纲的正文');

    // 单元目标跟结构规模走：单元数 ≈ 目录单元数，短篇 5、长篇多卷放大到 30。
    // 多部长篇（明朝 15 部 / 三体三部曲）固定 5-15 会漏整部，按目录单元数
    // 给足——每一部/卷至少能占一个单元。
    final unitGoal = sections.length.clamp(5, 30);

    final result = await completeWithRetry(
      provider,
      AiCompletionRequest(
        messages: [
          AiMessage(
            role: AiMessageRole.system,
            content:
                '你是图书编辑。读完整本书（或一部作品）后，产出它的结构大纲——'
                '这本书按什么顺序、分哪几块推进。'
                '不要按章节罗列，不要逐篇摘要；要回答的是"这本书是怎么组织的"。'
                '只返回 JSON 对象，不要 Markdown 或解释：'
                '{"overview":"一段话综述全书的整体脉络（200-300字，讲清主旨、推进方式、核心张力）",'
                '"units":[{"title":"单元名（2-12字，体现这一块的议题或内容）",'
                '"blurb":"一段话说清这块讲了什么、在全书里的作用（80-150字）"}]}。'
                'units 数量约 $unitGoal 个（5-$unitGoal 之间），按书中出现顺序排列，'
                '覆盖全书从头到尾，不能只覆盖开头。'
                '如果这本书分若干部/卷（如"第壹部""三体II"），按部组织单元——'
                '每一部至少一个单元，单元名带上所属部/卷（如"第壹部·洪武建国"）；'
                '部名识别不出时按内容板块划分即可。'
                '只根据给出的正文归纳，不要编造书里没讲的内容。',
          ),
          AiMessage(
            role: AiMessageRole.user,
            content:
                '书名：$bookTitle'
                '${collectionTitle == null || collectionTitle.trim().isEmpty ? '' : '\n所属合集：${collectionTitle.trim()}（只针对《$bookTitle》这一部作品写大纲，不要综述整个合集）'}'
                '${bookAuthor == null || bookAuthor.trim().isEmpty ? '' : '\n作者：${bookAuthor.trim()}'}'
                '\n\n正文：\n$body',
          ),
        ],
        maxTokens: (2000 + unitGoal * 150).clamp(4000, 8000),
        temperature: 0.3,
        timeout: _outlineCallTimeout,
      ),
      cancelToken: cancelToken,
    );

    final parsed = _parseOutline(result.text);
    if (parsed == null) {
      AiLog.d('outline parse failed: ${result.text}');
      throw AiProviderException('大纲提炼失败，请重试');
    }

    onProgress?.call(
      const AiOutlineProgress(
        completed: 1,
        total: 1,
        label: '完成',
        finalizing: true,
      ),
    );
    return AiBookOutline(
      createdAt: DateTime.now(),
      model: _settings().resolvedModel,
      overview: parsed.overview,
      units: parsed.units,
    );
  }

  /// Sample every section (head + tail) so the model sees the WHOLE book's
  /// arc, not just the opening — a naive "concatenate then cut" feeds a
  /// 300k-char novel's first ~8% and the overview describes only the
  /// beginning. Section labels are kept so the model can anchor units to
  /// chapter/volume titles. Total budget scales with section count (floor
  /// [_minUnitSampleChars] per unit, capped at [_maxPackedBodyChars]) so a
  /// multi-volume book still samples every 部; per-section budget shrinks as
  /// section count grows within that budget.
  String _packBody(List<AiBookSectionSlice> sections) {
    final nonEmpty = [
      for (final s in sections)
        if (s.text.trim().isNotEmpty) s,
    ];
    if (nonEmpty.isEmpty) return '';
    // Multi-unit books get a larger total budget so every unit keeps a real
    // sample (a 15-部 novel would otherwise starve later units to ~1 page).
    final budget = (_maxBodyChars)
        .clamp(
          _minUnitSampleChars * nonEmpty.length,
          _maxPackedBodyChars,
        )
        .toInt();
    final perSection = (budget ~/ nonEmpty.length).clamp(600, 6000);
    final buf = StringBuffer();
    for (final section in nonEmpty) {
      final text = section.text.trim();
      final label = section.label.trim();
      if (buf.isNotEmpty) buf.write('\n\n');
      if (label.isNotEmpty) buf.write('【$label】\n');
      if (text.length <= perSection) {
        buf.write(text);
      } else {
        // Head + tail: the opening sets up the unit, the close resolves it.
        final head = perSection * 2 ~/ 3;
        final tail = perSection - head;
        buf.write(text.substring(0, head));
        buf.write('\n…（中略）…\n');
        buf.write(text.substring(text.length - tail));
      }
      if (buf.length >= budget) break;
    }
    final body = buf.toString();
    return body.length <= budget ? body : body.substring(0, budget);
  }

  ({String overview, List<AiOutlineUnit> units})? _parseOutline(String raw) {
    final text = raw.trim();
    final fenced = text.startsWith('```')
        ? text
              .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
              .replaceFirst(RegExp(r'\s*```$'), '')
        : text;
    // Tolerate prose around the JSON ("好的，以下是大纲：{...} 希望对你有帮助")
    // — models at temperature 0.3 sometimes wrap the answer. Extract the first
    // '{' to the last '}' before decoding; a bare fence-strip + whole-text
    // decode hard-fails on any preamble and costs the user a full retry.
    final start = fenced.indexOf('{');
    final end = fenced.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final candidate = fenced.substring(start, end + 1);
    Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final overview = decoded['overview'];
    final unitsRaw = decoded['units'];
    if (overview is! String || overview.trim().isEmpty) return null;
    if (unitsRaw is! List) return null;
    final units = <AiOutlineUnit>[];
    for (final row in unitsRaw) {
      if (row is! Map) continue;
      final title = row['title'];
      final blurb = row['blurb'];
      if (title is String && blurb is String) {
        final t = title.trim();
        final b = blurb.trim();
        if (t.isNotEmpty && b.isNotEmpty) {
          units.add(AiOutlineUnit(title: t, blurb: b));
        }
      }
    }
    if (units.isEmpty) return null;
    return (overview: overview.trim(), units: units);
  }
}

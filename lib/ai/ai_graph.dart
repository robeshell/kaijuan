/// Book knowledge graph (AI M5): entities (person / location / event),
/// typed relations and quote-backed evidence.
///
/// Spec: docs/specs/ai-graph.md.
library;

import 'dart:convert';
import 'dart:io';

import 'ai_log.dart';

/// One selectable work/volume inside a collection when generating a graph.
///
/// Derived from the outline: `_planStructure` already merges each work/volume
/// of a collection into one unit that spans multiple spine sections, so a
/// candidate = outline chapter with `endSectionIndexExclusive - start > 1`.
class AiGraphWorkCandidate {
  const AiGraphWorkCandidate({
    required this.title,
    required this.startSection,
    required this.endSectionExclusive,
    this.sample = '',
  });

  /// Work/volume title (outline group title).
  final String title;

  /// Inclusive 1-based spine section where the work starts.
  final int startSection;

  /// Exclusive 1-based spine endpoint of the work. Null for the last work in
  /// the outline: its end is the book's tail, only known at generation time.
  final int? endSectionExclusive;

  /// Outline summary sample, used as the dialog subtitle.
  final String sample;

  int get sectionCount =>
      endSectionExclusive == null ? 0 : endSectionExclusive! - startSection;

  bool get isOpenEnded => endSectionExclusive == null;

  bool contains(int spineSection) =>
      spineSection >= startSection &&
      (isOpenEnded || spineSection < endSectionExclusive!);
}

/// Entity kinds extracted for v1. `item / concept` are reserved for later
/// versions and never generated today; `organization` is only generated when
/// the narration plan says the book is organization-driven (§3.3).
enum AiGraphEntityType {
  person,
  location,
  event,
  organization;

  String get wireName => name;

  static AiGraphEntityType fromWireName(Object? value) => switch (value) {
    'person' => AiGraphEntityType.person,
    'location' => AiGraphEntityType.location,
    'event' => AiGraphEntityType.event,
    'organization' => AiGraphEntityType.organization,
    _ => AiGraphEntityType.person,
  };
}

/// Whether an entity is part of the book's own story/setting or merely
/// referenced by it.
///
/// - [setting]: protagonists, recurring cast, world-building — the entities
///   that form the readable core of the graph.
/// - [reference]: people / places / events the book only cites or digresses
///   to (e.g. 罗素 in 王小波's essays). Kept in the data, folded out of the
///   main graph view.
enum AiGraphEntityScope {
  setting,
  reference;

  String get wireName => name;

  static AiGraphEntityScope fromWireName(Object? value) => switch (value) {
    'reference' => AiGraphEntityScope.reference,
    _ => AiGraphEntityScope.setting,
  };
}

/// One quote-backed provenance record.
///
/// The LLM only supplies [sectionIndex] and [quote]; [progressInSection] is
/// resolved by the program searching the quote back in the original text
/// (models cannot compute offsets reliably).
class AiGraphEvidence {
  const AiGraphEvidence({
    required this.sectionIndex,
    required this.quote,
    this.progressInSection,
    this.spanResolved = false,
  });

  /// 1-based spine section (aligned with [BookLocator.sectionIndex]).
  final int sectionIndex;

  /// Contiguous original-text fragment (LLM output, program-verified).
  final String quote;

  /// Program-resolved paragraph progress within the section (0..1).
  final double? progressInSection;

  /// Whether the quote was located back in the original text.
  final bool spanResolved;

  Map<String, Object?> toJson() => {
    'sectionIndex': sectionIndex,
    'quote': quote,
    if (progressInSection != null) 'progressInSection': progressInSection,
    'spanResolved': spanResolved,
  };

  static AiGraphEvidence fromJson(Map<String, dynamic> json) {
    final rawSection = json['sectionIndex'];
    final rawProgress = json['progressInSection'];
    return AiGraphEvidence(
      sectionIndex: rawSection is int
          ? rawSection
          : int.tryParse('$rawSection') ?? 0,
      quote: json['quote'] as String? ?? '',
      progressInSection: rawProgress is num ? rawProgress.toDouble() : null,
      spanResolved: json['spanResolved'] as bool? ?? false,
    );
  }
}

/// Event sub-category used by the timeline view (AI-Reader-V2 style).
/// `other` is the fallback for old caches and unmatched model output.
enum AiGraphEventType {
  combat('战斗'),
  growth('成长'),
  social('社交'),
  travel('旅行'),
  appearance('角色登场'),
  object('物品交接'),
  organization('组织变动'),
  relationship('关系变化'),
  other('其他');

  const AiGraphEventType(this.label);

  final String label;

  static AiGraphEventType fromWireName(Object? raw) {
    if (raw is String) {
      for (final value in values) {
        // The prompt asks the model for the Chinese label (战斗/成长/…),
        // while persisted JSON uses the English enum name; accept both.
        if (value.wireName == raw || value.label == raw) return value;
      }
    }
    return AiGraphEventType.other;
  }

  String get wireName => name;
}

/// A book entity. Unique key is `name + type`.
class AiGraphEntity {
  const AiGraphEntity({
    required this.name,
    required this.type,
    this.scope = AiGraphEntityScope.setting,
    this.aliases = const [],
    this.description = '',
    this.evidence = const [],
    this.chapterFreq = const {},
    this.firstSection = 0,
    this.lastSection = 0,
    this.eventType = AiGraphEventType.other,
    this.importance = 0,
  });

  /// Canonical name (never renamed on re-extraction).
  final String name;
  final AiGraphEntityType type;

  /// Whether this entity is part of the book's own setting or only
  /// referenced by it. Old caches without the field default to [setting]
  /// (never wrong, just less precise).
  final AiGraphEntityScope scope;

  /// Alternative names merged into this entity.
  final List<String> aliases;

  /// Evidence-driven description (3-5 sentences when available).
  final String description;

  /// Quote-backed provenance (appended, never overwritten).
  final List<AiGraphEvidence> evidence;

  /// sectionIndex -> occurrence count in that section.
  final Map<int, int> chapterFreq;

  /// First / last section this entity appears in (for read-progress gating).
  final int firstSection;
  final int lastSection;

  /// Event sub-category (meaningful only when [type] is event).
  final AiGraphEventType eventType;

  /// Event importance 0-3 (0 = unmarked, 3 = major plot event).
  final int importance;

  String get id => '$name|${type.wireName}';

  AiGraphEntity copyWith({
    AiGraphEntityScope? scope,
    List<String>? aliases,
    String? description,
    List<AiGraphEvidence>? evidence,
    Map<int, int>? chapterFreq,
    int? firstSection,
    int? lastSection,
    AiGraphEventType? eventType,
    int? importance,
  }) {
    return AiGraphEntity(
      name: name,
      type: type,
      scope: scope ?? this.scope,
      aliases: aliases ?? this.aliases,
      description: description ?? this.description,
      evidence: evidence ?? this.evidence,
      chapterFreq: chapterFreq ?? this.chapterFreq,
      firstSection: firstSection ?? this.firstSection,
      lastSection: lastSection ?? this.lastSection,
      eventType: eventType ?? this.eventType,
      importance: importance ?? this.importance,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.wireName,
    'scope': scope.wireName,
    'aliases': aliases,
    'description': description,
    'evidence': [for (final e in evidence) e.toJson()],
    'chapterFreq': {
      for (final entry in chapterFreq.entries)
        '${entry.key}': entry.value,
    },
    'firstSection': firstSection,
    'lastSection': lastSection,
    'eventType': eventType.wireName,
    'importance': importance,
  };

  static AiGraphEntity? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final rawFreq = json['chapterFreq'];
    final freq = <int, int>{};
    if (rawFreq is Map) {
      for (final entry in rawFreq.entries) {
        final key = int.tryParse('${entry.key}');
        final value = entry.value;
        if (key != null && value is int) freq[key] = value;
      }
    }
    final rawEvidence = json['evidence'];
    final rawAliases = json['aliases'];
    return AiGraphEntity(
      name: name.trim(),
      type: AiGraphEntityType.fromWireName(json['type']),
      scope: AiGraphEntityScope.fromWireName(json['scope']),
      aliases: rawAliases is List
          ? rawAliases
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const [],
      description: json['description'] as String? ?? '',
      evidence: _evidenceList(rawEvidence),
      chapterFreq: freq,
      firstSection: json['firstSection'] as int? ?? 0,
      lastSection: json['lastSection'] as int? ?? 0,
      eventType: AiGraphEventType.fromWireName(json['eventType']),
      importance: json['importance'] is int
          ? (json['importance'] as int).clamp(0, 3)
          : 0,
    );
  }

  static List<AiGraphEvidence> _evidenceList(Object? raw) {
    if (raw is! List) return const [];
    final out = <AiGraphEvidence>[];
    for (final item in raw) {
      if (item is Map) {
        final evidence = AiGraphEvidence.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (evidence.sectionIndex > 0 && evidence.quote.trim().isNotEmpty) {
          out.add(evidence);
        }
      }
    }
    return out;
  }
}

/// A typed relation between two entities.
class AiGraphRelation {
  const AiGraphRelation({
    required this.source,
    required this.target,
    required this.type,
    this.description = '',
    this.kin = '',
    this.evidence = const [],
    this.weight = 1,
  });

  final String source;
  final String target;

  /// Lowercase snake_case relation type (e.g. `married_to`, `father_of`).
  final String type;
  final String description;

  /// Concrete kinship label for 亲属/婚配 relations (父子/夫妻/兄弟…); empty
  /// for non-kin or graphs generated before this field existed. Shown on
  /// family-tree edges (spec: ai-graph-narration §5.1).
  final String kin;
  final List<AiGraphEvidence> evidence;

  /// Evidence count after merge (chapter coverage).
  final double weight;

  /// Merge key keeps direction: `A father_of B` != `B father_of A`.
  String get mergeKey => '$source\u0000$target\u0000$type';

  AiGraphRelation copyWith({
    String? description,
    String? kin,
    List<AiGraphEvidence>? evidence,
    double? weight,
  }) {
    return AiGraphRelation(
      source: source,
      target: target,
      type: type,
      description: description ?? this.description,
      kin: kin ?? this.kin,
      evidence: evidence ?? this.evidence,
      weight: weight ?? this.weight,
    );
  }

  Map<String, Object?> toJson() => {
    'source': source,
    'target': target,
    'type': type,
    'description': description,
    if (kin.isNotEmpty) 'kin': kin,
    'evidence': [for (final e in evidence) e.toJson()],
    'weight': weight,
  };

  static AiGraphRelation? fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final target = json['target'];
    final type = json['type'];
    if (source is! String ||
        target is! String ||
        type is! String ||
        source.trim().isEmpty ||
        target.trim().isEmpty ||
        type.trim().isEmpty) {
      return null;
    }
    final rawEvidence = json['evidence'];
    return AiGraphRelation(
      source: source.trim(),
      target: target.trim(),
      type: type.trim(),
      description: json['description'] as String? ?? '',
      kin: json['kin'] as String? ?? '',
      evidence: AiGraphEntity._evidenceList(rawEvidence),
      weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 1,
    );
  }
}

/// Book-level display plan (spec: docs/specs/ai-graph-narration.md §3).
///
/// Produced by the model at pipeline step 0 from the book title, outline and
/// a body sample. Only affects *display* preferences — default view, entry
/// order, and which extraction branches get extra prompting — never
/// entity/relation correctness (those stay evidence-anchored).
///
/// Older graphs have no `narration` segment; the UI then falls back to the
/// default person list exactly as before this feature.
class AiNarrationPlan {
  const AiNarrationPlan({
    required this.features,
    required this.defaultView,
    required this.viewOrder,
    this.wantMap = false,
  });

  /// Five narration dimensions, each independent 0..1.
  final Map<String, double> features;

  /// Recommended default view. One of [knownViews]; `org_tree` is not
  /// produced until the organization tree lands.
  final String defaultView;

  /// Entry order (a permutation of the available views, [defaultView] first).
  final List<String> viewOrder;

  /// Whether a map would help the reader; UI shows the text location chain
  /// (地图文字版) when true — no real map is rendered.
  final bool wantMap;

  static const List<String> knownFeatures = [
    'eventDriven', // 事件驱动
    'characterEnsemble', // 人物群像
    'organization', // 组织博弈
    'geography', // 地理叙事
    'essay', // 散文随笔
  ];

  static const List<String> knownViews = [
    'persons',
    'locations',
    'events',
    'graph',
    'family_tree',
    'org_tree',
  ];

  double feature(String key) => features[key] ?? 0;

  /// Returns a copy with a different recommended view; [viewOrder] is
  /// re-ordered so the new view leads (used by the pre-generation confirm
  /// dialog when the user picks a different default).
  AiNarrationPlan withDefaultView(String view) {
    if (view == defaultView) return this;
    return AiNarrationPlan(
      features: features,
      defaultView: view,
      viewOrder: [
        view,
        for (final v in viewOrder)
          if (v != view) v,
      ],
      wantMap: wantMap,
    );
  }

  Map<String, Object?> toJson() => {
    'features': features,
    'defaultView': defaultView,
    'viewOrder': viewOrder,
    'wantMap': wantMap,
  };

  /// Null when the payload is missing or invalid — caller falls back to the
  /// default person list (same behavior as graphs generated before this
  /// feature). Values are clamped, not rejected, so a slightly out-of-range
  /// model number never invalidates an otherwise good plan.
  static AiNarrationPlan? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rawFeatures = json['features'];
    if (rawFeatures is! Map) return null;
    final features = <String, double>{};
    for (final key in knownFeatures) {
      final raw = rawFeatures[key];
      if (raw is! num) return null;
      features[key] = raw.toDouble().clamp(0.0, 1.0);
    }
    final view = json['defaultView'];
    final order = json['viewOrder'];
    if (view is! String || !knownViews.contains(view)) return null;
    final viewOrder =
        order is List ? order.whereType<String>().toList(growable: false) : <String>[];
    if (viewOrder.isEmpty || !viewOrder.contains(view)) return null;
    return AiNarrationPlan(
      features: features,
      defaultView: view,
      viewOrder: viewOrder,
      wantMap: json['wantMap'] as bool? ?? false,
    );
  }
}

/// The whole cached graph for one exact book file (keyed by [contentHash]).
class AiBookGraph {
  const AiBookGraph({
    required this.contentHash,
    this.generatedAt,
    this.generationSeconds,
    this.model = '',
    this.includesUnread = false,
    this.coveredSections = const [],
    this.sectionTitles = const {},
    this.excludedGraphSections = const [],
    this.mergeLog = const [],
    this.entities = const [],
    this.relations = const [],
    this.narration,
  });

  static const int currentVersion = 1;

  final String contentHash;
  final DateTime? generatedAt;

  /// Wall-clock seconds of the latest generation run (shown in the UI).
  final int? generationSeconds;
  final String model;

  /// True when the graph was generated over the whole book (allowUnread on).
  final bool includesUnread;

  /// 1-based sections already extracted; drives incremental runs.
  final List<int> coveredSections;

  /// spine (1-based) → section label, so views can show real chapter titles
  /// instead of raw spine numbers. Empty for graphs made before this field.
  final Map<int, String> sectionTitles;

  /// TOC-section indices (AiBookSectionSlice.index) the user excluded in the
  /// pre-generation chooser. Persisted so a regeneration reopens with the
  /// same manual slice (incremental runs keep excluding them too).
  final List<int> excludedGraphSections;

  /// Audit trail of fuzzy (non-exact) entity merges: each entry is
  /// {from, to, score, reason, section} — the ER pipeline's merge log
  /// (Dedupe/Splink convention) so wrong merges are traceable and fixable.
  final List<Map<String, Object?>> mergeLog;

  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;

  /// Display plan from pipeline step 0; null for graphs generated before
  /// this feature or when the plan call failed (silent default fallback).
  final AiNarrationPlan? narration;

  AiBookGraph copyWith({
    String? contentHash,
    DateTime? generatedAt,
    int? generationSeconds,
    String? model,
    bool? includesUnread,
    List<int>? coveredSections,
    Map<int, String>? sectionTitles,
    List<int>? excludedGraphSections,
    List<Map<String, Object?>>? mergeLog,
    List<AiGraphEntity>? entities,
    List<AiGraphRelation>? relations,
    AiNarrationPlan? narration,
  }) {
    return AiBookGraph(
      contentHash: contentHash ?? this.contentHash,
      generatedAt: generatedAt ?? this.generatedAt,
      generationSeconds: generationSeconds ?? this.generationSeconds,
      model: model ?? this.model,
      includesUnread: includesUnread ?? this.includesUnread,
      coveredSections: coveredSections ?? this.coveredSections,
      sectionTitles: sectionTitles ?? this.sectionTitles,
      excludedGraphSections:
          excludedGraphSections ?? this.excludedGraphSections,
      mergeLog: mergeLog ?? this.mergeLog,
      entities: entities ?? this.entities,
      relations: relations ?? this.relations,
      narration: narration ?? this.narration,
    );
  }

  bool get isEmpty => entities.isEmpty && relations.isEmpty;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'contentHash': contentHash,
    if (generatedAt != null) 'generatedAt': generatedAt!.toUtc().toIso8601String(),
    if (generationSeconds != null) 'generationSeconds': generationSeconds,
    'model': model,
    'includesUnread': includesUnread,
    'coveredSections': coveredSections,
    'excludedGraphSections': excludedGraphSections,
    'mergeLog': mergeLog,
    'sectionTitles': {
      for (final entry in sectionTitles.entries) '${entry.key}': entry.value,
    },
    'entities': [for (final e in entities) e.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    if (narration != null) 'narration': narration!.toJson(),
  };

  /// Null when the payload is invalid or produced by an older generator.
  static AiBookGraph? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || version != currentVersion) return null;
    final hash = json['contentHash'];
    if (hash is! String || hash.isEmpty) return null;
    final rawEntities = json['entities'];
    final rawRelations = json['relations'];
    final entities = <AiGraphEntity>[];
    if (rawEntities is List) {
      for (final item in rawEntities) {
        if (item is Map) {
          final entity = AiGraphEntity.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (entity != null) entities.add(entity);
        }
      }
    }
    final relations = <AiGraphRelation>[];
    if (rawRelations is List) {
      for (final item in rawRelations) {
        if (item is Map) {
          final relation = AiGraphRelation.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (relation != null) relations.add(relation);
        }
      }
    }
    final rawCovered = json['coveredSections'];
    final rawExcluded = json['excludedGraphSections'];
    final rawMergeLog = json['mergeLog'];
    final rawTitles = json['sectionTitles'];
    return AiBookGraph(
      contentHash: hash,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      generationSeconds: json['generationSeconds'] as int?,
      model: json['model'] as String? ?? '',
      includesUnread: json['includesUnread'] as bool? ?? false,
      coveredSections: rawCovered is List
          ? rawCovered.whereType<int>().toList(growable: false)
          : const [],
      excludedGraphSections: rawExcluded is List
          ? rawExcluded.whereType<int>().toList(growable: false)
          : const [],
      mergeLog: rawMergeLog is List
          ? [
              for (final entry in rawMergeLog)
                if (entry is Map)
                  Map<String, Object?>.from(entry),
            ]
          : const [],
      sectionTitles: rawTitles is Map
          ? {
              for (final entry in rawTitles.entries)
                if (int.tryParse('${entry.key}') case final int key)
                  key: '${entry.value}',
            }
          : const {},
      entities: entities,
      relations: relations,
      narration: AiNarrationPlan.fromJson(
        json['narration'] is Map
            ? Map<String, dynamic>.from(json['narration'] as Map)
            : null,
      ),
    );
  }
}

/// File-backed graph cache: one JSON file per contentHash under `ai_graph/`.
class AiGraphStore {
  AiGraphStore(this._directory);

  final Directory _directory;

  /// One file per graph. A collection keeps one graph per work
  /// (docs/specs/ai-graph.md §合集选书): `$hash.json` for the whole book,
  /// `$hash.$workKey.json` for a single work inside a collection.
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
    try {
      final file = _fileFor(contentHash, workKey: workKey);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return AiBookGraph.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      AiLog.d('AiGraphStore read failed: $error');
      return null;
    }
  }

  /// All per-work graphs for [contentHash] (collection files `$hash.*.json`),
  /// keyed by workKey. Whole-book files (`$hash.json`) are not included.
  Future<Map<String, AiBookGraph>> readAllFor(String contentHash) async {
    try {
      if (!await _directory.exists()) return {};
      final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final result = <String, AiBookGraph>{};
      await for (final entity in _directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final key = workKeyOfFile(entity.uri.pathSegments.last, safe);
        if (key == null) continue;
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final graph = AiBookGraph.fromJson(Map<String, dynamic>.from(decoded));
        if (graph != null) result[key] = graph;
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
    await file.writeAsString(jsonEncode(graph.toJson()), flush: true);
  }

  Future<void> delete(String contentHash, {String? workKey}) async {
    final file = _fileFor(contentHash, workKey: workKey);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Book knowledge graph (AI M5): entities (person / location / event),
/// typed relations and quote-backed evidence.
///
/// Spec: docs/specs/ai-graph.md.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_book_structure.dart';
import 'ai_log.dart';

/// Compatibility name for graph UI while book structure ownership moves out
/// of the graph domain. Chat, outline and graph now share [AiBookWork].
typedef AiGraphWorkCandidate = AiBookWork;

/// Evidence-backed entity kinds extracted from literary and non-fiction text.
/// Every kind is always legal; the narration plan may tune recall emphasis
/// but never changes this schema.
enum AiGraphEntityType {
  person,
  location,
  event,
  organization,
  item,
  concept,
  creature;

  String get wireName => name;

  static AiGraphEntityType fromWireName(Object? value) => switch (value) {
    'person' => AiGraphEntityType.person,
    'location' => AiGraphEntityType.location,
    'event' => AiGraphEntityType.event,
    'organization' => AiGraphEntityType.organization,
    'item' => AiGraphEntityType.item,
    'concept' => AiGraphEntityType.concept,
    'creature' => AiGraphEntityType.creature,
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
      spanResolved:
          json['spanResolved'] as bool? ?? json['progressInSection'] is num,
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

String graphEntityIdFor({
  required AiGraphEntityType type,
  required String name,
  String identityHint = '',
}) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  // Hint is only hashed when the caller is splitting same-name rows in
  // one text unit. Unique names must pass an empty hint so later
  // life-stage wording cannot mint a second ID.
  final seed =
      '${type.wireName}\u0000${normalize(name)}\u0000'
      '${normalize(identityHint)}';
  return 'e_${sha1.convert(utf8.encode(seed)).toString().substring(0, 20)}';
}

/// A book entity. [entityId] is the identity key; [name] is display data.
class AiGraphEntity {
  const AiGraphEntity({
    this.entityId = '',
    required this.name,
    required this.type,
    this.identityHint = '',
    this.scope = AiGraphEntityScope.setting,
    this.aliases = const [],
    this.aliasSections = const {},
    this.description = '',
    this.descriptionSection = 0,
    this.evidence = const [],
    this.chapterFreq = const {},
    this.firstSection = 0,
    this.lastSection = 0,
    this.eventType = AiGraphEventType.other,
    this.importance = 0,
    this.needsReview = false,
  });

  /// Stable, non-display identity. Empty is accepted only for source-level
  /// compatibility with old const fixtures; [id] always exposes a real value.
  final String entityId;

  /// Canonical name (never renamed on re-extraction).
  final String name;
  final AiGraphEntityType type;

  /// Short role/context used to keep same-name, same-type entities distinct.
  final String identityHint;

  /// Whether this entity is part of the book's own setting or only
  /// referenced by it. Old caches without the field default to [setting]
  /// (never wrong, just less precise).
  final AiGraphEntityScope scope;

  /// Alternative names merged into this entity.
  final List<String> aliases;

  /// Alias -> first section that established it. Drives read-safe snapshots.
  final Map<String, int> aliasSections;

  /// Evidence-driven description (3-5 sentences when available).
  final String description;

  /// Latest section used to produce [description]. Zero means legacy/unknown.
  final int descriptionSection;

  /// Quote-backed provenance (appended, never overwritten).
  final List<AiGraphEvidence> evidence;

  /// sectionIndex -> resolved evidence count in that section. This is not a
  /// literal source-text mention frequency.
  final Map<int, int> chapterFreq;

  /// First / last section this entity appears in (for read-progress gating).
  final int firstSection;
  final int lastSection;

  /// Event sub-category (meaningful only when [type] is event).
  final AiGraphEventType eventType;

  /// Event importance 0-3 (0 = unmarked, 3 = major plot event).
  final int importance;

  /// Candidate lacks enough resolved evidence or has unresolved identity.
  final bool needsReview;

  String get id => entityId.isEmpty
      ? graphEntityIdFor(type: type, name: name, identityHint: identityHint)
      : entityId;

  AiGraphEntity copyWith({
    String? entityId,
    String? name,
    String? identityHint,
    AiGraphEntityScope? scope,
    List<String>? aliases,
    Map<String, int>? aliasSections,
    String? description,
    int? descriptionSection,
    List<AiGraphEvidence>? evidence,
    Map<int, int>? chapterFreq,
    int? firstSection,
    int? lastSection,
    AiGraphEventType? eventType,
    int? importance,
    bool? needsReview,
  }) {
    return AiGraphEntity(
      entityId: entityId ?? id,
      name: name ?? this.name,
      type: type,
      identityHint: identityHint ?? this.identityHint,
      scope: scope ?? this.scope,
      aliases: aliases ?? this.aliases,
      aliasSections: aliasSections ?? this.aliasSections,
      description: description ?? this.description,
      descriptionSection: descriptionSection ?? this.descriptionSection,
      evidence: evidence ?? this.evidence,
      chapterFreq: chapterFreq ?? this.chapterFreq,
      firstSection: firstSection ?? this.firstSection,
      lastSection: lastSection ?? this.lastSection,
      eventType: eventType ?? this.eventType,
      importance: importance ?? this.importance,
      needsReview: needsReview ?? this.needsReview,
    );
  }

  Map<String, Object?> toJson() => {
    'entityId': id,
    'name': name,
    'type': type.wireName,
    if (identityHint.isNotEmpty) 'identityHint': identityHint,
    'scope': scope.wireName,
    'aliases': aliases,
    'aliasSections': aliasSections,
    'description': description,
    'descriptionSection': descriptionSection,
    'evidence': [for (final e in evidence) e.toJson()],
    'chapterFreq': {
      for (final entry in chapterFreq.entries) '${entry.key}': entry.value,
    },
    'firstSection': firstSection,
    'lastSection': lastSection,
    'eventType': eventType.wireName,
    'importance': importance,
    if (needsReview) 'needsReview': true,
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
    final type = AiGraphEntityType.fromWireName(json['type']);
    final hint = (json['identityHint'] as String? ?? '').trim();
    final rawAliasSections = json['aliasSections'];
    final aliasSections = <String, int>{};
    if (rawAliasSections is Map) {
      for (final entry in rawAliasSections.entries) {
        final section = entry.value;
        if (section is int && '${entry.key}'.trim().isNotEmpty) {
          aliasSections['${entry.key}'.trim()] = section;
        }
      }
    }
    return AiGraphEntity(
      entityId: (json['entityId'] as String? ?? '').trim(),
      name: name.trim(),
      type: type,
      identityHint: hint,
      scope: AiGraphEntityScope.fromWireName(json['scope']),
      aliases: rawAliases is List
          ? rawAliases
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const [],
      aliasSections: aliasSections,
      description: json['description'] as String? ?? '',
      descriptionSection: json['descriptionSection'] as int? ?? 0,
      evidence: _evidenceList(rawEvidence),
      chapterFreq: freq,
      firstSection: json['firstSection'] as int? ?? 0,
      lastSection: json['lastSection'] as int? ?? 0,
      eventType: AiGraphEventType.fromWireName(json['eventType']),
      importance: json['importance'] is int
          ? (json['importance'] as int).clamp(0, 3)
          : 0,
      needsReview: json['needsReview'] as bool? ?? false,
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
    this.sourceId = '',
    this.targetId = '',
    required this.source,
    required this.target,
    required this.type,
    this.description = '',
    this.kin = '',
    this.evidence = const [],
    this.weight = 1,
    this.needsReview = false,
  });

  final String sourceId;
  final String targetId;
  final String source;
  final String target;

  /// Lowercase snake_case relation type (e.g. `married_to`, `father_of`).
  final String type;
  final String description;

  /// Concrete kinship label for 亲属/婚配 relations (父子/夫妻/兄弟…); empty
  /// for non-kin or graphs generated before this field existed. Shown on
  /// family-tree edges (spec: ai-graph §7.4).
  final String kin;
  final List<AiGraphEvidence> evidence;

  /// Evidence count after merge (chapter coverage).
  final double weight;
  final bool needsReview;

  /// Merge key keeps direction and is stable across display-name changes.
  String get mergeKey =>
      '${sourceId.isEmpty ? source : sourceId}\u0000'
      '${targetId.isEmpty ? target : targetId}\u0000$type';

  AiGraphRelation copyWith({
    String? sourceId,
    String? targetId,
    String? source,
    String? target,
    String? description,
    String? kin,
    List<AiGraphEvidence>? evidence,
    double? weight,
    bool? needsReview,
  }) {
    return AiGraphRelation(
      sourceId: sourceId ?? this.sourceId,
      targetId: targetId ?? this.targetId,
      source: source ?? this.source,
      target: target ?? this.target,
      type: type,
      description: description ?? this.description,
      kin: kin ?? this.kin,
      evidence: evidence ?? this.evidence,
      weight: weight ?? this.weight,
      needsReview: needsReview ?? this.needsReview,
    );
  }

  Map<String, Object?> toJson() => {
    if (sourceId.isNotEmpty) 'sourceId': sourceId,
    if (targetId.isNotEmpty) 'targetId': targetId,
    'source': source,
    'target': target,
    'type': type,
    'description': description,
    if (kin.isNotEmpty) 'kin': kin,
    'evidence': [for (final e in evidence) e.toJson()],
    'weight': weight,
    if (needsReview) 'needsReview': true,
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
      sourceId: (json['sourceId'] as String? ?? '').trim(),
      targetId: (json['targetId'] as String? ?? '').trim(),
      source: source.trim(),
      target: target.trim(),
      type: type.trim(),
      description: json['description'] as String? ?? '',
      kin: json['kin'] as String? ?? '',
      evidence: AiGraphEntity._evidenceList(rawEvidence),
      weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 1,
      needsReview: json['needsReview'] as bool? ?? false,
    );
  }
}

/// Book-level display plan (spec: docs/specs/ai-graph.md §6.1).
///
/// Produced by the model at pipeline step 0 from the book title, outline and
/// a body sample. Only affects *display* preferences — default view, entry
/// order, and which extraction branches get extra prompting — never
/// entity/relation correctness (those stay evidence-anchored).
///
/// Older graphs have no `narration` segment; the UI then falls back to the
/// default person list exactly as before this feature.
enum AiNarrationPlanMode { autoAnalyze, confirmed, skip }

class AiNarrationPlan {
  const AiNarrationPlan({
    required this.features,
    required this.defaultView,
    required this.viewOrder,
    this.wantMap = false,
  });

  /// Five narration dimensions, each independent 0..1.
  final Map<String, double> features;

  /// Recommended default view. One of [knownViews].
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
    'organizations',
    'things',
    'graph',
    'family_tree',
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
  /// feature). Tolerant parsing: a missing feature dimension defaults to 0,
  /// an unknown/absent defaultView falls back to the strongest feature's
  /// view, and an empty or invalid viewOrder is rebuilt — a slightly
  /// incomplete model reply never invalidates an otherwise good plan (this
  /// only drives display preferences, so degrading beats failing).
  static AiNarrationPlan? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rawFeatures = json['features'];
    if (rawFeatures is! Map) return null;
    final features = <String, double>{};
    for (final key in knownFeatures) {
      final raw = rawFeatures[key];
      features[key] = (raw is num ? raw.toDouble() : 0.0).clamp(0.0, 1.0);
    }
    // Essays (散文/杂文/评论) carry no lineage or faction structure — a
    // family-tree entry makes no sense there, even when the model guessed one.
    final essayHigh = (features['essay'] ?? 0.0) >= 0.5;
    String? normalizeView(Object? raw) {
      if (raw == 'org_tree') return 'organizations';
      return raw is String ? raw : null;
    }

    final view = normalizeView(json['defaultView']);
    final derived = _deriveDefaultView(features);
    var resolvedView = (view is String && knownViews.contains(view))
        ? view
        : derived;
    if (essayHigh && resolvedView == 'family_tree') {
      resolvedView = 'graph';
    }
    final rawOrder = json['viewOrder'] is List
        ? json['viewOrder'] as List
        : const <dynamic>[];
    final modelOrder = rawOrder
        .map(normalizeView)
        .whereType<String>()
        .where(knownViews.contains)
        .where((v) => !essayHigh || v != 'family_tree')
        .toList();
    final viewOrder = [
      resolvedView,
      for (final v in modelOrder)
        if (v != resolvedView) v,
      for (final v in knownViews)
        if (v != resolvedView &&
            !modelOrder.contains(v) &&
            (!essayHigh || v != 'family_tree'))
          v,
    ];
    return AiNarrationPlan(
      features: features,
      defaultView: resolvedView,
      viewOrder: viewOrder,
      wantMap: json['wantMap'] as bool? ?? false,
    );
  }

  /// The strongest feature's recommended view; ties keep the earlier entry,
  /// essays default to the plain relation graph.
  static String _deriveDefaultView(Map<String, double> features) {
    const mapping = <String, String>{
      'organization': 'organizations',
      'characterEnsemble': 'persons',
      'eventDriven': 'events',
      'geography': 'locations',
    };
    var best = 'graph';
    var highest = -1.0;
    for (final entry in mapping.entries) {
      final value = features[entry.key] ?? 0.0;
      if (value > highest) {
        highest = value;
        best = entry.value;
      }
    }
    return best;
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
    this.sectionScheme = 'toc',
    this.coveredSections = const [],
    this.sectionTitles = const {},
    this.excludedGraphSections = const [],
    this.mergeLog = const [],
    this.qualityIssues = const [],
    this.hiddenEntityIds = const [],
    this.entities = const [],
    this.relations = const [],
    this.narration,
  });

  static const int currentVersion = 2;

  final String contentHash;
  final DateTime? generatedAt;

  /// Wall-clock seconds of the latest generation run (shown in the UI).
  final int? generationSeconds;
  final String model;

  /// True when the graph was generated over the whole book (allowUnread on).
  final bool includesUnread;

  /// Body-splitting scheme the covered/excluded indices refer to: 'toc'
  /// (whole-book range, one logical section per TOC unit) or 'spine'
  /// (per-work range, one logical section per heading inside each spine
  /// document). Incremental runs only trust [coveredSections] /
  /// [excludedGraphSections] when the scheme matches the current range — a
  /// mismatch forces a full re-extraction instead of silently skipping pieces.
  final String sectionScheme;

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

  /// Production quality-gate findings. Empty means the structural gate passed.
  final List<String> qualityIssues;

  /// User-level suppression overrides. Stable IDs make the choice survive
  /// incremental extraction and regeneration merges.
  final List<String> hiddenEntityIds;

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
    String? sectionScheme,
    List<int>? coveredSections,
    Map<int, String>? sectionTitles,
    List<int>? excludedGraphSections,
    List<Map<String, Object?>>? mergeLog,
    List<String>? qualityIssues,
    List<String>? hiddenEntityIds,
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
      sectionScheme: sectionScheme ?? this.sectionScheme,
      coveredSections: coveredSections ?? this.coveredSections,
      sectionTitles: sectionTitles ?? this.sectionTitles,
      excludedGraphSections:
          excludedGraphSections ?? this.excludedGraphSections,
      mergeLog: mergeLog ?? this.mergeLog,
      qualityIssues: qualityIssues ?? this.qualityIssues,
      hiddenEntityIds: hiddenEntityIds ?? this.hiddenEntityIds,
      entities: entities ?? this.entities,
      relations: relations ?? this.relations,
      narration: narration ?? this.narration,
    );
  }

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'contentHash': contentHash,
    if (generatedAt != null)
      'generatedAt': generatedAt!.toUtc().toIso8601String(),
    if (generationSeconds != null) 'generationSeconds': generationSeconds,
    'model': model,
    'includesUnread': includesUnread,
    'sectionScheme': sectionScheme,
    'coveredSections': coveredSections,
    'excludedGraphSections': excludedGraphSections,
    'mergeLog': mergeLog,
    'qualityIssues': qualityIssues,
    'hiddenEntityIds': hiddenEntityIds,
    'sectionTitles': {
      for (final entry in sectionTitles.entries) '${entry.key}': entry.value,
    },
    'entities': [for (final e in entities) e.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    if (narration != null) 'narration': narration!.toJson(),
  };

  /// Reads v2 and migrates v1 identity-by-name caches to deterministic IDs.
  static AiBookGraph? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || (version != 1 && version != currentVersion)) {
      return null;
    }
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
          if (entity != null) {
            entities.add(
              entity.entityId.isEmpty
                  ? entity.copyWith(entityId: entity.id)
                  : entity,
            );
          }
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
    final rawQualityIssues = json['qualityIssues'];
    final rawHiddenEntityIds = json['hiddenEntityIds'];
    final rawTitles = json['sectionTitles'];
    final idsByName = <String, List<String>>{};
    for (final entity in entities) {
      idsByName.putIfAbsent(entity.name, () => []).add(entity.id);
      for (final alias in entity.aliases) {
        idsByName.putIfAbsent(alias, () => []).add(entity.id);
      }
    }
    final migratedRelations = <AiGraphRelation>[];
    for (final relation in relations) {
      String uniqueId(String name) {
        final ids = idsByName[name]?.toSet() ?? const <String>{};
        return ids.length == 1 ? ids.single : '';
      }

      migratedRelations.add(
        relation.copyWith(
          sourceId: relation.sourceId.isEmpty
              ? uniqueId(relation.source)
              : relation.sourceId,
          targetId: relation.targetId.isEmpty
              ? uniqueId(relation.target)
              : relation.targetId,
          needsReview:
              relation.needsReview ||
              (relation.sourceId.isEmpty &&
                  uniqueId(relation.source).isEmpty) ||
              (relation.targetId.isEmpty && uniqueId(relation.target).isEmpty),
        ),
      );
    }
    return AiBookGraph(
      contentHash: hash,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      generationSeconds: json['generationSeconds'] as int?,
      model: json['model'] as String? ?? '',
      includesUnread: json['includesUnread'] as bool? ?? false,
      sectionScheme: json['sectionScheme'] as String? ?? 'toc',
      coveredSections: rawCovered is List
          ? rawCovered.whereType<int>().toList(growable: false)
          : const [],
      excludedGraphSections: rawExcluded is List
          ? rawExcluded.whereType<int>().toList(growable: false)
          : const [],
      mergeLog: rawMergeLog is List
          ? [
              for (final entry in rawMergeLog)
                if (entry is Map) Map<String, Object?>.from(entry),
            ]
          : const [],
      qualityIssues: rawQualityIssues is List
          ? rawQualityIssues.whereType<String>().toList(growable: false)
          : const [],
      hiddenEntityIds: rawHiddenEntityIds is List
          ? rawHiddenEntityIds.whereType<String>().toList(growable: false)
          : const [],
      sectionTitles: rawTitles is Map
          ? {
              for (final entry in rawTitles.entries)
                if (int.tryParse('${entry.key}') case final int key)
                  key: '${entry.value}',
            }
          : const {},
      entities: entities,
      relations: migratedRelations,
      narration: AiNarrationPlan.fromJson(
        json['narration'] is Map
            ? Map<String, dynamic>.from(json['narration'] as Map)
            : null,
      ),
    ).repairDuplicateEntityIds().repairEquivalentMentions();
  }

  /// Repairs graphs produced before the exact-ID merge invariant was
  /// enforced. Duplicate IDs represent the same logical entity, so their
  /// evidence and metadata are fused instead of discarding an arbitrary row.
  /// Relations are collapsed by their stable endpoint/type key as well.
  AiBookGraph repairDuplicateEntityIds() {
    final entitiesById = <String, AiGraphEntity>{};
    var changed = false;

    for (final entity in entities) {
      final current = entitiesById[entity.id];
      if (current == null) {
        entitiesById[entity.id] = entity;
        continue;
      }
      changed = true;
      entitiesById[entity.id] = _mergeDuplicateEntity(current, entity);
    }

    final relationsByKey = <String, AiGraphRelation>{};
    for (final relation in relations) {
      final current = relationsByKey[relation.mergeKey];
      if (current == null) {
        relationsByKey[relation.mergeKey] = relation;
        continue;
      }
      changed = true;
      relationsByKey[relation.mergeKey] = _mergeDuplicateRelation(
        current,
        relation,
      );
    }

    if (!changed) return this;
    AiLog.d(
      'graph identity repair: entities ${entities.length}→${entitiesById.length}, '
      'relations ${relations.length}→${relationsByKey.length}',
    );
    return copyWith(
      entities: entitiesById.values.toList(growable: false),
      relations: relationsByKey.values.toList(growable: false),
      qualityIssues: qualityIssues
          .where((issue) => !issue.contains('重复实体 ID'))
          .toList(growable: false),
    );
  }

  /// Repairs one logical entity that the extractor emitted several times in
  /// the same text unit with changing life-stage/role hints. Exact display
  /// name alone is never enough (two 张伟 must survive); a non-name alias
  /// shared by the rows is required positive identity evidence. Every
  /// relation endpoint is rewired to the strongest representative ID.
  AiBookGraph repairEquivalentMentions() {
    final groups = <String, List<AiGraphEntity>>{};
    for (final entity in entities) {
      groups
          .putIfAbsent('${entity.type.wireName}\u0000${entity.name}', () => [])
          .add(entity);
    }
    final replacements = <String, String>{};
    final repairedEntities = <AiGraphEntity>[];

    Set<String> identityAliases(AiGraphEntity entity) => entity.aliases
        .map((alias) => alias.trim())
        .where((alias) => alias.isNotEmpty && alias != entity.name)
        .toSet();

    for (final group in groups.values) {
      if (group.length == 1) {
        repairedEntities.add(group.single);
        continue;
      }
      final pending = [...group];
      while (pending.isNotEmpty) {
        final component = <AiGraphEntity>[pending.removeAt(0)];
        final aliases = identityAliases(component.single);
        var expanded = true;
        while (expanded) {
          expanded = false;
          for (var i = pending.length - 1; i >= 0; i--) {
            final candidateAliases = identityAliases(pending[i]);
            if (aliases.intersection(candidateAliases).isEmpty) continue;
            final candidate = pending.removeAt(i);
            component.add(candidate);
            aliases.addAll(candidateAliases);
            expanded = true;
          }
        }
        if (component.length == 1) {
          repairedEntities.add(component.single);
          continue;
        }
        component.sort((a, b) {
          final byEvidence = b.evidence.length.compareTo(a.evidence.length);
          if (byEvidence != 0) return byEvidence;
          return a.firstSection.compareTo(b.firstSection);
        });
        var merged = component.first;
        for (final duplicate in component.skip(1)) {
          merged = _mergeDuplicateEntity(merged, duplicate);
          replacements[duplicate.id] = component.first.id;
        }
        replacements[component.first.id] = component.first.id;
        repairedEntities.add(merged);
      }
    }

    if (replacements.isEmpty) return this;
    final repairedById = {
      for (final entity in repairedEntities) entity.id: entity,
    };
    final repairedRelations = <String, AiGraphRelation>{};
    for (final relation in relations) {
      final sourceId = replacements[relation.sourceId] ?? relation.sourceId;
      final targetId = replacements[relation.targetId] ?? relation.targetId;
      if (sourceId.isNotEmpty && sourceId == targetId) continue;
      final rewired = relation.copyWith(
        sourceId: sourceId,
        targetId: targetId,
        source: repairedById[sourceId]?.name ?? relation.source,
        target: repairedById[targetId]?.name ?? relation.target,
      );
      final current = repairedRelations[rewired.mergeKey];
      repairedRelations[rewired.mergeKey] = current == null
          ? rewired
          : _mergeDuplicateRelation(current, rewired);
    }
    AiLog.d(
      'graph mention repair: entities ${entities.length}→${repairedEntities.length}, '
      'relations ${relations.length}→${repairedRelations.length}',
    );
    return copyWith(
      entities: repairedEntities,
      relations: repairedRelations.values.toList(growable: false),
      hiddenEntityIds: hiddenEntityIds
          .map((id) => replacements[id] ?? id)
          .toSet()
          .toList(growable: false),
    );
  }

  AiGraphEntity? entityById(String id) {
    for (final entity in entities) {
      if (entity.id == id) return entity;
    }
    return null;
  }

  /// Entities the user hid; still stored, just not shown.
  List<AiGraphEntity> get hiddenEntities => [
    for (final entity in entities)
      if (hiddenEntityIds.contains(entity.id)) entity,
  ];

  AiBookGraph hideEntity(String entityId) {
    if (entityById(entityId) == null) return this;
    if (hiddenEntityIds.contains(entityId)) return this;
    return copyWith(hiddenEntityIds: [...hiddenEntityIds, entityId]);
  }

  AiBookGraph unhideEntity(String entityId) {
    if (!hiddenEntityIds.contains(entityId)) return this;
    return copyWith(
      hiddenEntityIds: [
        for (final id in hiddenEntityIds)
          if (id != entityId) id,
      ],
    );
  }

  /// Absorbs [absorbId] into [keepId]. Same type only; [keepId]'s display
  /// name wins, and the absorbed name becomes an alias. Returns null when
  /// the pair is missing, identical, or mixed type.
  AiBookGraph? mergeEntities({
    required String keepId,
    required String absorbId,
  }) {
    if (keepId == absorbId) return null;
    final keep = entityById(keepId);
    final absorb = entityById(absorbId);
    if (keep == null || absorb == null || keep.type != absorb.type) {
      return null;
    }

    final absorbAsAlias = absorb.copyWith(
      aliases: {
        ...absorb.aliases,
        if (absorb.name != keep.name) absorb.name,
      }.toList(growable: false),
      aliasSections: {
        ...absorb.aliasSections,
        if (absorb.name != keep.name && absorb.firstSection > 0)
          absorb.name: absorb.firstSection,
      },
    );
    var merged = _mergeDuplicateEntity(keep, absorbAsAlias);
    if (keep.description.isNotEmpty) {
      merged = merged.copyWith(
        description: keep.description,
        descriptionSection: keep.descriptionSection,
      );
    }

    final nextEntities = <AiGraphEntity>[
      for (final entity in entities)
        if (entity.id == keepId) merged else if (entity.id != absorbId) entity,
    ];

    final nextRelations = <String, AiGraphRelation>{};
    for (final relation in relations) {
      final sourceId = relation.sourceId == absorbId
          ? keepId
          : relation.sourceId;
      final targetId = relation.targetId == absorbId
          ? keepId
          : relation.targetId;
      if (sourceId.isNotEmpty && sourceId == targetId) continue;
      final rewired = relation.copyWith(
        sourceId: sourceId,
        targetId: targetId,
        source: sourceId == keepId ? merged.name : relation.source,
        target: targetId == keepId ? merged.name : relation.target,
      );
      final current = nextRelations[rewired.mergeKey];
      nextRelations[rewired.mergeKey] = current == null
          ? rewired
          : _mergeDuplicateRelation(current, rewired);
    }

    return copyWith(
      entities: nextEntities,
      relations: nextRelations.values.toList(growable: false),
      hiddenEntityIds: [
        for (final id in hiddenEntityIds)
          if (id != absorbId) id,
      ],
      mergeLog: [
        ...mergeLog,
        {
          'from': absorb.name,
          'to': keep.name,
          'score': 1.0,
          'reason': 'manual',
          'section': absorb.firstSection,
        },
      ],
    );
  }

  /// Immutable spoiler-safe projection used whenever a full-book graph is
  /// viewed with unread context disabled.
  AiBookGraph readSafeThrough(int section) {
    final visibleEntities = <AiGraphEntity>[];
    for (final entity in entities) {
      final evidence = entity.evidence
          .where((item) => item.sectionIndex <= section)
          .toList(growable: false);
      if (evidence.isEmpty) continue;
      final aliases = entity.aliases
          .where((alias) {
            final established = entity.aliasSections[alias];
            return established == null
                ? entity.lastSection <= section
                : established <= section;
          })
          .toList(growable: false);
      final descriptionSafe = entity.descriptionSection > 0
          ? entity.descriptionSection <= section
          : entity.lastSection <= section;
      visibleEntities.add(
        entity.copyWith(
          aliases: aliases,
          aliasSections: {
            for (final alias in aliases)
              alias: entity.aliasSections[alias] ?? entity.lastSection,
          },
          description: descriptionSafe ? entity.description : '',
          evidence: evidence,
          chapterFreq: {
            for (final entry in entity.chapterFreq.entries)
              if (entry.key <= section) entry.key: entry.value,
          },
          lastSection: evidence
              .map((item) => item.sectionIndex)
              .reduce((left, right) => left > right ? left : right),
        ),
      );
    }
    final visibleIds = {for (final entity in visibleEntities) entity.id};
    final visibleRelations = <AiGraphRelation>[];
    for (final relation in relations) {
      if (relation.sourceId.isEmpty || relation.targetId.isEmpty) continue;
      final evidence = relation.evidence
          .where((item) => item.sectionIndex <= section)
          .toList(growable: false);
      if (evidence.isEmpty) continue;
      final sourceVisible = visibleIds.contains(relation.sourceId);
      final targetVisible = visibleIds.contains(relation.targetId);
      if (!sourceVisible || !targetVisible) continue;
      visibleRelations.add(
        relation.copyWith(
          evidence: evidence,
          weight: evidence.length.toDouble(),
        ),
      );
    }
    return copyWith(entities: visibleEntities, relations: visibleRelations);
  }

  /// Removes claims that cannot be traced back to an exact source span.
  /// Unresolved candidates remain in the stored graph for a later repair run,
  /// but are not presented as established facts.
  AiBookGraph verifiedForDisplay() {
    final visibleEntities = <AiGraphEntity>[];
    for (final entity in entities) {
      if (hiddenEntityIds.contains(entity.id)) continue;
      final evidence = entity.evidence
          .where((item) => item.spanResolved)
          .toList(growable: false);
      if (evidence.isEmpty) continue;
      visibleEntities.add(
        entity.copyWith(
          evidence: evidence,
          chapterFreq: {
            for (final section
                in evidence.map((item) => item.sectionIndex).toSet())
              section: evidence
                  .where((item) => item.sectionIndex == section)
                  .length,
          },
          needsReview: false,
        ),
      );
    }
    final ids = {for (final entity in visibleEntities) entity.id};
    final visibleRelations = <AiGraphRelation>[];
    for (final relation in relations) {
      if (relation.sourceId.isEmpty || relation.targetId.isEmpty) continue;
      final evidence = relation.evidence
          .where((item) => item.spanResolved)
          .toList(growable: false);
      if (evidence.isEmpty) continue;
      final sourceVisible = ids.contains(relation.sourceId);
      final targetVisible = ids.contains(relation.targetId);
      if (!sourceVisible || !targetVisible) continue;
      visibleRelations.add(
        relation.copyWith(
          evidence: evidence,
          weight: evidence.length.toDouble(),
          needsReview: false,
        ),
      );
    }
    return copyWith(entities: visibleEntities, relations: visibleRelations);
  }
}

AiGraphEntity _mergeDuplicateEntity(AiGraphEntity first, AiGraphEntity second) {
  final evidenceByQuote = <String, AiGraphEvidence>{};
  for (final evidence in [...first.evidence, ...second.evidence]) {
    final key = '${evidence.sectionIndex}\u0000${evidence.quote.trim()}';
    final current = evidenceByQuote[key];
    if (current == null || (!current.spanResolved && evidence.spanResolved)) {
      evidenceByQuote[key] = evidence;
    }
  }
  final evidence = evidenceByQuote.values.toList(growable: false)
    ..sort((a, b) => a.sectionIndex.compareTo(b.sectionIndex));
  final chapterFreq = <int, int>{};
  if (evidence.isNotEmpty) {
    for (final item in evidence) {
      chapterFreq[item.sectionIndex] =
          (chapterFreq[item.sectionIndex] ?? 0) + 1;
    }
  } else {
    for (final entry in [
      ...first.chapterFreq.entries,
      ...second.chapterFreq.entries,
    ]) {
      final current = chapterFreq[entry.key] ?? 0;
      if (entry.value > current) chapterFreq[entry.key] = entry.value;
    }
  }

  final aliases = <String>{
    ...first.aliases,
    ...second.aliases,
  }.toList(growable: false);
  final aliasSections = <String, int>{};
  for (final alias in aliases) {
    final a = first.aliasSections[alias];
    final b = second.aliasSections[alias];
    aliasSections[alias] = switch ((a, b)) {
      (final int left, final int right) => left < right ? left : right,
      (final int value, null) || (null, final int value) => value,
      _ => first.firstSection > 0 ? first.firstSection : second.firstSection,
    };
  }

  final preferSecondDescription =
      second.description.isNotEmpty &&
      (first.description.isEmpty ||
          second.descriptionSection > first.descriptionSection ||
          (second.descriptionSection == first.descriptionSection &&
              second.description.length > first.description.length));
  final positiveFirstSections = [
    first.firstSection,
    second.firstSection,
  ].where((value) => value > 0);
  final firstSection = positiveFirstSections.isEmpty
      ? 0
      : positiveFirstSections.reduce((a, b) => a < b ? a : b);
  final lastSection = first.lastSection > second.lastSection
      ? first.lastSection
      : second.lastSection;

  return first.copyWith(
    identityHint: first.identityHint.isNotEmpty
        ? first.identityHint
        : second.identityHint,
    scope:
        first.scope == AiGraphEntityScope.setting ||
            second.scope == AiGraphEntityScope.setting
        ? AiGraphEntityScope.setting
        : AiGraphEntityScope.reference,
    aliases: aliases,
    aliasSections: aliasSections,
    description: preferSecondDescription
        ? second.description
        : first.description,
    descriptionSection: preferSecondDescription
        ? second.descriptionSection
        : first.descriptionSection,
    evidence: evidence,
    chapterFreq: chapterFreq,
    firstSection: firstSection,
    lastSection: lastSection,
    eventType: first.eventType != AiGraphEventType.other
        ? first.eventType
        : second.eventType,
    importance: first.importance > second.importance
        ? first.importance
        : second.importance,
    needsReview: first.needsReview || second.needsReview,
  );
}

AiGraphRelation _mergeDuplicateRelation(
  AiGraphRelation first,
  AiGraphRelation second,
) {
  final evidenceByQuote = <String, AiGraphEvidence>{};
  for (final evidence in [...first.evidence, ...second.evidence]) {
    final key = '${evidence.sectionIndex}\u0000${evidence.quote.trim()}';
    final current = evidenceByQuote[key];
    if (current == null || (!current.spanResolved && evidence.spanResolved)) {
      evidenceByQuote[key] = evidence;
    }
  }
  final evidence = evidenceByQuote.values.toList(growable: false)
    ..sort((a, b) => a.sectionIndex.compareTo(b.sectionIndex));
  return first.copyWith(
    description: first.description.isNotEmpty
        ? first.description
        : second.description,
    kin: first.kin.isNotEmpty ? first.kin : second.kin,
    evidence: evidence,
    weight: evidence.length.toDouble(),
    needsReview: first.needsReview || second.needsReview,
  );
}

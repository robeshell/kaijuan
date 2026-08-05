/// Book knowledge graph (AI M5): entities (person / location / event),
/// typed relations and quote-backed evidence.
///
/// Spec: docs/specs/ai-graph.md.
library;

import 'dart:convert';
import 'dart:io';

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

/// Entity kinds extracted for v1. `organization / item / concept` are
/// reserved for later versions and never generated today.
enum AiGraphEntityType {
  person,
  location,
  event;

  String get wireName => name;

  static AiGraphEntityType fromWireName(Object? value) => switch (value) {
    'person' => AiGraphEntityType.person,
    'location' => AiGraphEntityType.location,
    'event' => AiGraphEntityType.event,
    _ => AiGraphEntityType.person,
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

/// A book entity. Unique key is `name + type`.
class AiGraphEntity {
  const AiGraphEntity({
    required this.name,
    required this.type,
    this.aliases = const [],
    this.description = '',
    this.evidence = const [],
    this.chapterFreq = const {},
    this.firstSection = 0,
    this.lastSection = 0,
  });

  /// Canonical name (never renamed on re-extraction).
  final String name;
  final AiGraphEntityType type;

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

  String get id => '$name|${type.wireName}';

  AiGraphEntity copyWith({
    List<String>? aliases,
    String? description,
    List<AiGraphEvidence>? evidence,
    Map<int, int>? chapterFreq,
    int? firstSection,
    int? lastSection,
  }) {
    return AiGraphEntity(
      name: name,
      type: type,
      aliases: aliases ?? this.aliases,
      description: description ?? this.description,
      evidence: evidence ?? this.evidence,
      chapterFreq: chapterFreq ?? this.chapterFreq,
      firstSection: firstSection ?? this.firstSection,
      lastSection: lastSection ?? this.lastSection,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.wireName,
    'aliases': aliases,
    'description': description,
    'evidence': [for (final e in evidence) e.toJson()],
    'chapterFreq': {
      for (final entry in chapterFreq.entries)
        '${entry.key}': entry.value,
    },
    'firstSection': firstSection,
    'lastSection': lastSection,
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
    this.evidence = const [],
    this.weight = 1,
  });

  final String source;
  final String target;

  /// Lowercase snake_case relation type (e.g. `married_to`, `father_of`).
  final String type;
  final String description;
  final List<AiGraphEvidence> evidence;

  /// Evidence count after merge (chapter coverage).
  final double weight;

  /// Merge key keeps direction: `A father_of B` != `B father_of A`.
  String get mergeKey => '$source\u0000$target\u0000$type';

  AiGraphRelation copyWith({
    String? description,
    List<AiGraphEvidence>? evidence,
    double? weight,
  }) {
    return AiGraphRelation(
      source: source,
      target: target,
      type: type,
      description: description ?? this.description,
      evidence: evidence ?? this.evidence,
      weight: weight ?? this.weight,
    );
  }

  Map<String, Object?> toJson() => {
    'source': source,
    'target': target,
    'type': type,
    'description': description,
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
      evidence: AiGraphEntity._evidenceList(rawEvidence),
      weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 1,
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
    this.entities = const [],
    this.relations = const [],
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
  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;

  AiBookGraph copyWith({
    String? contentHash,
    DateTime? generatedAt,
    int? generationSeconds,
    String? model,
    bool? includesUnread,
    List<int>? coveredSections,
    List<AiGraphEntity>? entities,
    List<AiGraphRelation>? relations,
  }) {
    return AiBookGraph(
      contentHash: contentHash ?? this.contentHash,
      generatedAt: generatedAt ?? this.generatedAt,
      generationSeconds: generationSeconds ?? this.generationSeconds,
      model: model ?? this.model,
      includesUnread: includesUnread ?? this.includesUnread,
      coveredSections: coveredSections ?? this.coveredSections,
      entities: entities ?? this.entities,
      relations: relations ?? this.relations,
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
    'entities': [for (final e in entities) e.toJson()],
    'relations': [for (final r in relations) r.toJson()],
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
    return AiBookGraph(
      contentHash: hash,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      generationSeconds: json['generationSeconds'] as int?,
      model: json['model'] as String? ?? '',
      includesUnread: json['includesUnread'] as bool? ?? false,
      coveredSections: rawCovered is List
          ? rawCovered.whereType<int>().toList(growable: false)
          : const [],
      entities: entities,
      relations: relations,
    );
  }
}

/// File-backed graph cache: one JSON file per contentHash under `ai_graph/`.
class AiGraphStore {
  AiGraphStore(this._directory);

  final Directory _directory;

  File _fileFor(String contentHash) {
    final safe = contentHash.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${_directory.path}${Platform.pathSeparator}$safe.json');
  }

  Future<AiBookGraph?> read(String contentHash) async {
    try {
      final file = _fileFor(contentHash);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return AiBookGraph.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AiBookGraph graph) async {
    await _directory.create(recursive: true);
    final file = _fileFor(graph.contentHash);
    await file.writeAsString(jsonEncode(graph.toJson()), flush: true);
  }

  Future<void> delete(String contentHash) async {
    final file = _fileFor(contentHash);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

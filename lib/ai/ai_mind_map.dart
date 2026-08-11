import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AiMindMapLayout { radial, rightFacing, bidirectional }

enum AiMindMapContentKind { narrative, argumentative, reference, mixed }

class AiMindMapEvidence {
  const AiMindMapEvidence({
    required this.sectionIndex,
    required this.quote,
    required this.progressInSection,
    required this.spanResolved,
  });

  /// 1-based physical EPUB/Foliate section used by the reader locator.
  /// Multiple quotes from one chapter intentionally share this value and are
  /// distinguished by [progressInSection].
  final int sectionIndex;
  final String quote;
  final double progressInSection;
  final bool spanResolved;

  Map<String, Object?> toJson() => {
    'sectionIndex': sectionIndex,
    'quote': quote,
    'progressInSection': progressInSection,
    'spanResolved': spanResolved,
  };

  static AiMindMapEvidence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final section = raw['sectionIndex'];
    final quote = raw['quote'];
    final progress = raw['progressInSection'];
    if (section is! num || quote is! String || quote.trim().isEmpty) {
      return null;
    }
    return AiMindMapEvidence(
      sectionIndex: section.toInt(),
      quote: quote.trim(),
      progressInSection: progress is num ? progress.toDouble().clamp(0, 1) : 0,
      spanResolved: raw['spanResolved'] == true,
    );
  }
}

class AiBookMindMapNode {
  const AiBookMindMapNode({
    required this.nodeId,
    required this.parentId,
    required this.order,
    required this.level,
    required this.title,
    required this.summary,
    this.evidence = const [],
  });

  final String nodeId;
  final String? parentId;
  final int order;
  final int level;
  final String title;
  final String summary;
  final List<AiMindMapEvidence> evidence;

  Map<String, Object?> toJson() => {
    'nodeId': nodeId,
    if (parentId != null) 'parentId': parentId,
    'order': order,
    'level': level,
    'title': title,
    'summary': summary,
    'evidence': [for (final item in evidence) item.toJson()],
  };

  static AiBookMindMapNode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['nodeId'];
    final title = raw['title'];
    final summary = raw['summary'];
    final order = raw['order'];
    final level = raw['level'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        summary is! String ||
        summary.trim().isEmpty ||
        order is! num ||
        level is! num) {
      return null;
    }
    final evidence = <AiMindMapEvidence>[
      for (final item in (raw['evidence'] as List?) ?? const [])
        ?AiMindMapEvidence.fromJson(item),
    ];
    return AiBookMindMapNode(
      nodeId: id,
      parentId: raw['parentId'] is String ? raw['parentId'] as String : null,
      order: order.toInt(),
      level: level.toInt(),
      title: title.trim(),
      summary: summary.trim(),
      evidence: List.unmodifiable(evidence),
    );
  }
}

class AiBookMindMap {
  const AiBookMindMap({
    required this.contentHash,
    required this.workKey,
    required this.createdAt,
    required this.model,
    required this.scopeSectionIndices,
    required this.scopeFingerprint,
    required this.contentKind,
    required this.layout,
    required this.nodes,
    this.artifactId,
    this.sourceArtifactId,
    this.revision = 1,
    this.organizingPrinciple = '',
  });

  static const currentVersion = 1;

  final String contentHash;
  final String? workKey;
  final DateTime createdAt;
  final String model;
  final List<int> scopeSectionIndices;
  final String scopeFingerprint;
  final AiMindMapContentKind contentKind;
  final String organizingPrinciple;
  final AiMindMapLayout layout;
  final List<AiBookMindMapNode> nodes;

  /// App-owned identity for this rendered artifact. It is intentionally
  /// optional so maps persisted before artifact identity was introduced stay
  /// readable and can be addressed through their message turn as a fallback.
  final String? artifactId;

  /// Identity of the artifact this map was revised from, when applicable.
  final String? sourceArtifactId;

  /// Monotonic revision within an artifact lineage. Existing maps default to
  /// the first revision when this field is absent in persisted JSON.
  final int revision;

  AiBookMindMapNode get root =>
      nodes.singleWhere((node) => node.parentId == null);

  AiBookMindMap copyWith({
    AiMindMapLayout? layout,
    String? artifactId,
    String? sourceArtifactId,
    int? revision,
  }) => AiBookMindMap(
    contentHash: contentHash,
    workKey: workKey,
    createdAt: createdAt,
    model: model,
    scopeSectionIndices: scopeSectionIndices,
    scopeFingerprint: scopeFingerprint,
    contentKind: contentKind,
    organizingPrinciple: organizingPrinciple,
    layout: layout ?? this.layout,
    nodes: nodes,
    artifactId: artifactId ?? this.artifactId,
    sourceArtifactId: sourceArtifactId ?? this.sourceArtifactId,
    revision: revision ?? this.revision,
  );

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'contentHash': contentHash,
    if (workKey != null) 'workKey': workKey,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'model': model,
    'scopeSectionIndices': scopeSectionIndices,
    'scopeFingerprint': scopeFingerprint,
    'contentKind': contentKind.name,
    if (artifactId != null) 'artifactId': artifactId,
    if (sourceArtifactId != null) 'sourceArtifactId': sourceArtifactId,
    'revision': revision,
    if (organizingPrinciple.isNotEmpty)
      'organizingPrinciple': organizingPrinciple,
    'layout': layout.name,
    'nodes': [for (final node in nodes) node.toJson()],
  };

  static AiBookMindMap? fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != currentVersion) return null;
    final hash = raw['contentHash'];
    final createdAt = DateTime.tryParse('${raw['createdAt'] ?? ''}');
    final model = raw['model'];
    final fingerprint = raw['scopeFingerprint'];
    final nodeRows = raw['nodes'];
    if (hash is! String ||
        hash.isEmpty ||
        createdAt == null ||
        model is! String ||
        fingerprint is! String ||
        nodeRows is! List) {
      return null;
    }
    final nodes = <AiBookMindMapNode>[
      for (final row in nodeRows) ?AiBookMindMapNode.fromJson(row),
    ];
    if (!validateAiBookMindMapNodes(nodes)) return null;
    return AiBookMindMap(
      contentHash: hash,
      workKey: raw['workKey'] is String ? raw['workKey'] as String : null,
      createdAt: createdAt,
      model: model,
      scopeSectionIndices:
          (raw['scopeSectionIndices'] as List?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false) ??
          const [],
      scopeFingerprint: fingerprint,
      contentKind: AiMindMapContentKind.values.firstWhere(
        (value) => value.name == raw['contentKind'],
        orElse: () => AiMindMapContentKind.mixed,
      ),
      organizingPrinciple: raw['organizingPrinciple'] is String
          ? (raw['organizingPrinciple'] as String).trim()
          : '',
      artifactId:
          raw['artifactId'] is String &&
              (raw['artifactId'] as String).trim().isNotEmpty
          ? (raw['artifactId'] as String).trim()
          : null,
      sourceArtifactId:
          raw['sourceArtifactId'] is String &&
              (raw['sourceArtifactId'] as String).trim().isNotEmpty
          ? (raw['sourceArtifactId'] as String).trim()
          : null,
      revision: raw['revision'] is num
          ? (raw['revision'] as num).toInt().clamp(1, 1 << 30)
          : 1,
      layout: AiMindMapLayout.values.firstWhere(
        (value) => value.name == raw['layout'],
        orElse: () => AiMindMapLayout.rightFacing,
      ),
      nodes: List.unmodifiable(nodes),
    );
  }
}

String aiMindMapScopeFingerprint({
  required String contentHash,
  String? workKey,
  required Iterable<int> sectionIndices,
}) {
  final sorted = sectionIndices.toSet().toList()..sort();
  return sha256
      .convert(
        utf8.encode('$contentHash\n${workKey ?? ''}\n${sorted.join(',')}'),
      )
      .toString();
}

bool validateAiBookMindMapNodes(List<AiBookMindMapNode> nodes) {
  if (nodes.isEmpty) return false;
  final byId = <String, AiBookMindMapNode>{};
  final childrenByParent = <String?, List<AiBookMindMapNode>>{};
  for (final node in nodes) {
    if (byId.containsKey(node.nodeId) ||
        node.nodeId.trim().isEmpty ||
        node.title.trim().isEmpty ||
        node.summary.trim().isEmpty ||
        node.level < 0 ||
        node.order < 0) {
      return false;
    }
    byId[node.nodeId] = node;
    childrenByParent.putIfAbsent(node.parentId, () => []).add(node);
  }
  final roots = nodes.where((node) => node.parentId == null).toList();
  if (roots.length != 1 || roots.single.level != 0 || roots.single.order != 0) {
    return false;
  }
  for (final node in nodes.where((node) => node.parentId != null)) {
    final parent = byId[node.parentId];
    if (parent == null || node.level != parent.level + 1) return false;
    final seen = <String>{node.nodeId};
    AiBookMindMapNode? cursor = parent;
    while (cursor != null) {
      if (!seen.add(cursor.nodeId)) return false;
      cursor = cursor.parentId == null ? null : byId[cursor.parentId];
    }
  }
  for (final siblings in childrenByParent.values) {
    final orders = siblings.map((node) => node.order).toList()..sort();
    for (var index = 0; index < orders.length; index++) {
      if (orders[index] != index) return false;
    }
  }
  return true;
}

AiMindMapLayout chooseAiMindMapLayout({
  required AiMindMapContentKind contentKind,
  required List<AiBookMindMapNode> nodes,
}) => AiMindMapLayout.bidirectional;

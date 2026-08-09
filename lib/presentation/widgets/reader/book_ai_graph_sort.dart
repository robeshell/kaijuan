import '../../../ai/ai_graph.dart';

/// The list being sorted. Sorting is deliberately view-specific: a useful
/// event order is not the same thing as a useful people or organization
/// order.
enum GraphEntityListKind { persons, locations, events, organizations, things }

enum GraphEntitySortOrder {
  appearance,
  chapters,
  evidence,
  relations,
  importance,
  type,
}

const _graphViewOrder = <String>[
  'persons',
  'locations',
  'events',
  'organizations',
  'things',
  'graph',
  'family_tree',
];

String _normalizeGraphView(String? view) => switch (view?.trim()) {
  'persons' => 'persons',
  'locations' => 'locations',
  'events' => 'events',
  'organizations' || 'org_tree' => 'organizations',
  'things' => 'things',
  'graph' => 'graph',
  'family_tree' => 'family_tree',
  _ => 'persons',
};

/// Chooses the first graph view from the final display-safe result.
///
/// The narration plan is generated before extraction, so its recommendation
/// can legitimately end up empty after grounding, user hiding, or spoiler
/// projection. Never open on that dead-end when another populated view exists.
String resolveGraphInitialView(AiBookGraph graph, String? recommended) {
  final preferred = _normalizeGraphView(recommended);
  if (graphViewHasContent(graph, preferred)) return preferred;
  for (final view in _graphViewOrder) {
    if (graphViewHasContent(graph, view)) return view;
  }
  return 'persons';
}

bool graphViewHasContent(AiBookGraph graph, String view) =>
    switch (_normalizeGraphView(view)) {
      'persons' => graph.entities.any(
        (entity) => entity.type == AiGraphEntityType.person,
      ),
      'locations' => graph.entities.any(
        (entity) => entity.type == AiGraphEntityType.location,
      ),
      'events' => graph.entities.any(
        (entity) => entity.type == AiGraphEntityType.event,
      ),
      'organizations' => graph.entities.any(
        (entity) => entity.type == AiGraphEntityType.organization,
      ),
      'things' => graph.entities.any(
        (entity) =>
            entity.type == AiGraphEntityType.item ||
            entity.type == AiGraphEntityType.concept ||
            entity.type == AiGraphEntityType.creature,
      ),
      'graph' => graph.relations.isNotEmpty,
      'family_tree' => graph.relations.any(
        (relation) =>
            relation.kin.trim().isNotEmpty ||
            relation.type == '亲属' ||
            relation.type == '婚配',
      ),
      _ => false,
    };

/// The switcher is useful only after extraction produced displayable data.
/// Rendering five zero-count destinations makes an empty checkpoint look like
/// a completed graph and hides the recovery action.
bool shouldShowGraphViewNavigation({
  required AiBookGraph? graph,
  required bool generating,
}) =>
    graph != null &&
    !generating &&
    (graph.entities.isNotEmpty || graph.relations.isNotEmpty);

GraphEntitySortOrder defaultGraphSortOrder(GraphEntityListKind kind) =>
    switch (kind) {
      GraphEntityListKind.persons => GraphEntitySortOrder.chapters,
      GraphEntityListKind.locations => GraphEntitySortOrder.appearance,
      GraphEntityListKind.events => GraphEntitySortOrder.appearance,
      GraphEntityListKind.organizations => GraphEntitySortOrder.relations,
      GraphEntityListKind.things => GraphEntitySortOrder.chapters,
    };

List<GraphEntitySortOrder> graphSortOrdersFor(GraphEntityListKind kind) =>
    switch (kind) {
      GraphEntityListKind.persons => const [
        GraphEntitySortOrder.chapters,
        GraphEntitySortOrder.relations,
        GraphEntitySortOrder.evidence,
        GraphEntitySortOrder.appearance,
      ],
      GraphEntityListKind.locations => const [
        GraphEntitySortOrder.appearance,
        GraphEntitySortOrder.chapters,
        GraphEntitySortOrder.evidence,
      ],
      GraphEntityListKind.events => const [
        GraphEntitySortOrder.appearance,
        GraphEntitySortOrder.importance,
        GraphEntitySortOrder.chapters,
      ],
      GraphEntityListKind.organizations => const [
        GraphEntitySortOrder.relations,
        GraphEntitySortOrder.chapters,
        GraphEntitySortOrder.evidence,
        GraphEntitySortOrder.appearance,
      ],
      GraphEntityListKind.things => const [
        GraphEntitySortOrder.chapters,
        GraphEntitySortOrder.relations,
        GraphEntitySortOrder.evidence,
        GraphEntitySortOrder.appearance,
        GraphEntitySortOrder.type,
      ],
    };

String graphSortOrderLabel(
  GraphEntitySortOrder order,
  GraphEntityListKind kind,
) => switch (order) {
  GraphEntitySortOrder.appearance =>
    kind == GraphEntityListKind.events
        ? '情节顺序'
        : kind == GraphEntityListKind.persons
        ? '首次出场'
        : '首次出现',
  GraphEntitySortOrder.chapters => '涉及章节',
  GraphEntitySortOrder.evidence => '出处数量',
  GraphEntitySortOrder.relations => '关系数量',
  GraphEntitySortOrder.importance => '重要程度',
  GraphEntitySortOrder.type => '实体类型',
};

int graphEntityEvidenceCount(AiGraphEntity entity) => entity.evidence.length;

int graphEntityChapterCount(AiGraphEntity entity) =>
    entity.chapterFreq.keys.length;

/// Counts distinct incident relation records for each stable entity ID.
/// Legacy name-only endpoints are resolved only when the name is unique.
Map<String, int> graphEntityRelationCounts(
  Iterable<AiGraphEntity> entities,
  Iterable<AiGraphRelation> relations,
) {
  final byUniqueName = <String, String>{};
  final ambiguousNames = <String>{};
  for (final entity in entities) {
    if (byUniqueName.containsKey(entity.name)) ambiguousNames.add(entity.name);
    byUniqueName[entity.name] = entity.id;
  }
  for (final name in ambiguousNames) {
    byUniqueName.remove(name);
  }

  final relationKeys = <String, Set<String>>{};
  for (final relation in relations) {
    final sourceId = relation.sourceId.isNotEmpty
        ? relation.sourceId
        : byUniqueName[relation.source];
    final targetId = relation.targetId.isNotEmpty
        ? relation.targetId
        : byUniqueName[relation.target];
    if (sourceId != null) {
      relationKeys
          .putIfAbsent(sourceId, () => <String>{})
          .add(relation.mergeKey);
    }
    if (targetId != null) {
      relationKeys
          .putIfAbsent(targetId, () => <String>{})
          .add(relation.mergeKey);
    }
  }
  return {
    for (final entry in relationKeys.entries) entry.key: entry.value.length,
  };
}

List<AiGraphEntity> sortGraphEntities(
  Iterable<AiGraphEntity> source, {
  required GraphEntitySortOrder order,
  Map<String, int> relationCounts = const {},
}) {
  final sorted = source.toList(growable: false);
  sorted.sort((left, right) {
    final primary = switch (order) {
      GraphEntitySortOrder.appearance => _compareAppearance(left, right),
      GraphEntitySortOrder.chapters => _compareDescending(
        graphEntityChapterCount(left),
        graphEntityChapterCount(right),
      ),
      GraphEntitySortOrder.evidence => _compareDescending(
        graphEntityEvidenceCount(left),
        graphEntityEvidenceCount(right),
      ),
      GraphEntitySortOrder.relations => _compareDescending(
        relationCounts[left.id] ?? 0,
        relationCounts[right.id] ?? 0,
      ),
      GraphEntitySortOrder.importance => _compareDescending(
        left.importance,
        right.importance,
      ),
      GraphEntitySortOrder.type => left.type.index.compareTo(right.type.index),
    };
    if (primary != 0) return primary;

    // Deterministic semantic tie-breakers. Never inherit the cache/provider
    // array order, because that makes an unchanged sort look random.
    final byChapters = _compareDescending(
      graphEntityChapterCount(left),
      graphEntityChapterCount(right),
    );
    if (byChapters != 0) return byChapters;
    final byRelations = _compareDescending(
      relationCounts[left.id] ?? 0,
      relationCounts[right.id] ?? 0,
    );
    if (byRelations != 0) return byRelations;
    final byEvidence = _compareDescending(
      graphEntityEvidenceCount(left),
      graphEntityEvidenceCount(right),
    );
    if (byEvidence != 0) return byEvidence;
    final byAppearance = _compareAppearance(left, right);
    if (byAppearance != 0) return byAppearance;
    final byName = left.name.compareTo(right.name);
    return byName != 0 ? byName : left.id.compareTo(right.id);
  });
  return sorted;
}

int _compareDescending(int left, int right) => right.compareTo(left);

int _compareAppearance(AiGraphEntity left, AiGraphEntity right) {
  final leftSection = _firstSection(left);
  final rightSection = _firstSection(right);
  final bySection = leftSection.compareTo(rightSection);
  if (bySection != 0) return bySection;

  final leftProgress = _firstProgress(left, leftSection);
  final rightProgress = _firstProgress(right, rightSection);
  return leftProgress.compareTo(rightProgress);
}

int _firstSection(AiGraphEntity entity) {
  if (entity.firstSection > 0) return entity.firstSection;
  if (entity.evidence.isEmpty) return 1 << 30;
  return entity.evidence
      .map((item) => item.sectionIndex)
      .where((section) => section > 0)
      .fold<int>(
        1 << 30,
        (current, section) => section < current ? section : current,
      );
}

double _firstProgress(AiGraphEntity entity, int firstSection) {
  var progress = double.infinity;
  for (final evidence in entity.evidence) {
    if (evidence.sectionIndex != firstSection ||
        evidence.progressInSection == null) {
      continue;
    }
    if (evidence.progressInSection! < progress) {
      progress = evidence.progressInSection!;
    }
  }
  return progress;
}

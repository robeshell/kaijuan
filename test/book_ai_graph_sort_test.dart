import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_graph_sort.dart';

void main() {
  test('each entity view exposes its own default and sort choices', () {
    expect(
      defaultGraphSortOrder(GraphEntityListKind.persons),
      GraphEntitySortOrder.chapters,
    );
    expect(
      defaultGraphSortOrder(GraphEntityListKind.locations),
      GraphEntitySortOrder.appearance,
    );
    expect(
      defaultGraphSortOrder(GraphEntityListKind.events),
      GraphEntitySortOrder.appearance,
    );
    expect(
      defaultGraphSortOrder(GraphEntityListKind.organizations),
      GraphEntitySortOrder.relations,
    );
    expect(
      graphSortOrdersFor(GraphEntityListKind.events),
      isNot(contains(GraphEntitySortOrder.evidence)),
    );
    expect(
      graphSortOrdersFor(GraphEntityListKind.things),
      contains(GraphEntitySortOrder.type),
    );
  });

  test(
    'evidence sorting ignores incoming cache order and uses the shown metric',
    () {
      final low = entity(
        'low',
        chapterFreq: const {1: 1, 2: 1},
        evidenceCount: 2,
      );
      final high = entity('high', chapterFreq: const {1: 4}, evidenceCount: 4);

      final sorted = sortGraphEntities([
        low,
        high,
      ], order: GraphEntitySortOrder.evidence);

      expect(sorted.map((item) => item.name), ['high', 'low']);
      expect(graphEntityEvidenceCount(sorted.first), 4);
    },
  );

  test('appearance sorting uses evidence position inside the same section', () {
    final later = entity('later', section: 3, progress: 0.8);
    final earlier = entity('earlier', section: 3, progress: 0.2);

    final sorted = sortGraphEntities([
      later,
      earlier,
    ], order: GraphEntitySortOrder.appearance);

    expect(sorted.map((item) => item.name), ['earlier', 'later']);
  });

  test(
    'organization relation sorting counts both incoming and outgoing edges',
    () {
      final a = entity('A');
      final b = entity('B');
      final c = entity('C');
      final relations = [
        relation(a, b, 'member_of'),
        relation(c, a, 'opposes'),
      ];
      final counts = graphEntityRelationCounts([a, b, c], relations);

      final sorted = sortGraphEntities(
        [b, c, a],
        order: GraphEntitySortOrder.relations,
        relationCounts: counts,
      );

      expect(sorted.first.name, 'A');
      expect(counts[a.id], 2);
    },
  );

  test('event importance takes precedence over chronology', () {
    final early = entity(
      'early',
      type: AiGraphEntityType.event,
      section: 1,
      importance: 1,
    );
    final major = entity(
      'major',
      type: AiGraphEntityType.event,
      section: 8,
      importance: 3,
    );

    final sorted = sortGraphEntities([
      early,
      major,
    ], order: GraphEntitySortOrder.importance);

    expect(sorted.map((item) => item.name), ['major', 'early']);
  });

  test('empty recommended view falls back to the first populated index', () {
    final graph = AiBookGraph(
      contentHash: 'fallback',
      entities: [entity('主角')],
    );

    expect(resolveGraphInitialView(graph, 'organizations'), 'persons');
    expect(resolveGraphInitialView(graph, 'org_tree'), 'persons');
  });

  test('populated recommendation remains the initial view', () {
    final graph = AiBookGraph(
      contentHash: 'organization',
      entities: [
        entity('议会', type: AiGraphEntityType.organization),
        entity('主角'),
      ],
    );

    expect(resolveGraphInitialView(graph, 'organizations'), 'organizations');
  });

  test('an empty graph does not masquerade as zero-count navigation', () {
    const graph = AiBookGraph(contentHash: 'empty');

    expect(resolveGraphInitialView(graph, 'organizations'), 'persons');
    expect(
      shouldShowGraphViewNavigation(graph: graph, generating: false),
      isFalse,
    );
    expect(
      shouldShowGraphViewNavigation(graph: graph, generating: true),
      isFalse,
    );
  });
}

AiGraphEntity entity(
  String name, {
  AiGraphEntityType type = AiGraphEntityType.person,
  int section = 1,
  double? progress,
  Map<int, int>? chapterFreq,
  int evidenceCount = 1,
  int importance = 0,
}) => AiGraphEntity(
  entityId: 'id-$name',
  name: name,
  type: type,
  evidence: [
    for (var i = 0; i < evidenceCount; i++)
      AiGraphEvidence(
        sectionIndex: section,
        quote: '$name-$i',
        progressInSection: progress,
        spanResolved: progress != null,
      ),
  ],
  chapterFreq: chapterFreq ?? {section: 1},
  firstSection: section,
  lastSection: section,
  importance: importance,
);

AiGraphRelation relation(
  AiGraphEntity source,
  AiGraphEntity target,
  String type,
) => AiGraphRelation(
  sourceId: source.id,
  targetId: target.id,
  source: source.name,
  target: target.name,
  type: type,
);

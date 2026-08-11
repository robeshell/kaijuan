import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_mind_map_layout.dart';

void main() {
  AiBookMindMap sample({AiMindMapLayout layout = AiMindMapLayout.rightFacing}) {
    return AiBookMindMap(
      contentHash: 'a' * 64,
      workKey: 's1',
      createdAt: DateTime.utc(2026, 8, 10),
      model: 'test-model',
      scopeSectionIndices: const [1, 2],
      scopeFingerprint: 'scope',
      contentKind: AiMindMapContentKind.argumentative,
      organizingPrinciple: '围绕问题与回应的论证结构',
      layout: layout,
      nodes: const [
        AiBookMindMapNode(
          nodeId: 'mm001',
          parentId: null,
          order: 0,
          level: 0,
          title: '全书',
          summary: '总览',
        ),
        AiBookMindMapNode(
          nodeId: 'mm002',
          parentId: 'mm001',
          order: 0,
          level: 1,
          title: '问题',
          summary: '提出问题',
          evidence: [
            AiMindMapEvidence(
              sectionIndex: 1,
              quote: '第一章证据',
              progressInSection: 0.1,
              spanResolved: true,
            ),
          ],
        ),
        AiBookMindMapNode(
          nodeId: 'mm003',
          parentId: 'mm002',
          order: 0,
          level: 2,
          title: '论据',
          summary: '展开论据',
          evidence: [
            AiMindMapEvidence(
              sectionIndex: 1,
              quote: '论据',
              progressInSection: 0.3,
              spanResolved: true,
            ),
          ],
        ),
        AiBookMindMapNode(
          nodeId: 'mm004',
          parentId: 'mm001',
          order: 1,
          level: 1,
          title: '回应',
          summary: '回应问题',
          evidence: [
            AiMindMapEvidence(
              sectionIndex: 2,
              quote: '第二章证据',
              progressInSection: 0.2,
              spanResolved: true,
            ),
          ],
        ),
      ],
    );
  }

  test('mind map JSON preserves stable nodes and evidence', () {
    final source = sample();
    final restored = AiBookMindMap.fromJson(source.toJson());
    expect(restored, isNotNull);
    expect(restored!.root.nodeId, 'mm001');
    expect(restored.organizingPrinciple, '围绕问题与回应的论证结构');
    expect(restored.nodes[2].parentId, 'mm002');
    expect(restored.nodes[1].evidence.single.spanResolved, isTrue);
  });

  test('artifact identity and revision survive JSON round-trip', () {
    final source = sample().copyWith(
      artifactId: 'turn-1-mind-map-1',
      sourceArtifactId: 'turn-0-mind-map-1',
      revision: 2,
    );
    final restored = AiBookMindMap.fromJson(source.toJson());

    expect(restored, isNotNull);
    expect(restored!.artifactId, 'turn-1-mind-map-1');
    expect(restored.sourceArtifactId, 'turn-0-mind-map-1');
    expect(restored.revision, 2);
  });

  test('maps persisted before artifact identity default to revision one', () {
    final json = sample().toJson()
      ..remove('artifactId')
      ..remove('sourceArtifactId')
      ..remove('revision');
    final restored = AiBookMindMap.fromJson(json);

    expect(restored, isNotNull);
    expect(restored!.artifactId, isNull);
    expect(restored.sourceArtifactId, isNull);
    expect(restored.revision, 1);
  });

  test('older persisted maps remain readable without organizing principle', () {
    final json = sample().toJson()..remove('organizingPrinciple');
    final restored = AiBookMindMap.fromJson(json);

    expect(restored, isNotNull);
    expect(restored!.organizingPrinciple, isEmpty);
  });

  test('mind map JSON rejects an empty persisted summary', () {
    final json = sample().toJson();
    final nodes = json['nodes']! as List<Map<String, Object?>>;
    nodes[1]['summary'] = '   ';

    expect(AiBookMindMap.fromJson(json), isNull);
  });

  test('node validator rejects cycles and inconsistent levels', () {
    final invalid = [
      const AiBookMindMapNode(
        nodeId: 'root',
        parentId: null,
        order: 0,
        level: 0,
        title: '根',
        summary: '',
      ),
      const AiBookMindMapNode(
        nodeId: 'a',
        parentId: 'b',
        order: 0,
        level: 1,
        title: '甲',
        summary: '',
      ),
      const AiBookMindMapNode(
        nodeId: 'b',
        parentId: 'a',
        order: 0,
        level: 2,
        title: '乙',
        summary: '',
      ),
    ];
    expect(validateAiBookMindMapNodes(invalid), isFalse);
  });

  test('node validator rejects duplicate or non-contiguous sibling order', () {
    final nodes = sample().nodes.toList();
    nodes[3] = const AiBookMindMapNode(
      nodeId: 'mm004',
      parentId: 'mm001',
      order: 0,
      level: 1,
      title: '回应',
      summary: '回应问题',
    );
    expect(validateAiBookMindMapNodes(nodes), isFalse);
  });

  test('scope fingerprint is order independent but work scoped', () {
    final first = aiMindMapScopeFingerprint(
      contentHash: 'hash',
      workKey: 's1',
      sectionIndices: const [3, 1, 2],
    );
    expect(
      first,
      aiMindMapScopeFingerprint(
        contentHash: 'hash',
        workKey: 's1',
        sectionIndices: const [2, 3, 1],
      ),
    );
    expect(
      first,
      isNot(
        aiMindMapScopeFingerprint(
          contentHash: 'hash',
          workKey: 's2',
          sectionIndices: const [1, 2, 3],
        ),
      ),
    );
  });

  test('all layouts are deterministic and collapse removes descendants', () {
    for (final kind in AiMindMapLayout.values) {
      final map = sample(layout: kind);
      final first = AiMindMapLayoutEngine.layout(map);
      final second = AiMindMapLayoutEngine.layout(map);
      expect(first.size, second.size);
      expect(first.nodeRects, second.nodeRects);
      expect(first.nodeRects.length, 4);
      final collapsed = AiMindMapLayoutEngine.layout(
        map,
        collapsedNodeIds: const {'mm002'},
      );
      expect(collapsed.nodeRects, isNot(contains('mm003')));
      expect(collapsed.edges.length, 2);
    }
  });

  test('new mind maps default to bidirectional layout', () {
    for (final contentKind in AiMindMapContentKind.values) {
      expect(
        chooseAiMindMapLayout(contentKind: contentKind, nodes: sample().nodes),
        AiMindMapLayout.bidirectional,
      );
    }
  });

  test('layout handles the 160-node storage boundary without overflow', () {
    final nodes = <AiBookMindMapNode>[
      const AiBookMindMapNode(
        nodeId: 'root',
        parentId: null,
        order: 0,
        level: 0,
        title: '全书',
        summary: '总览',
      ),
    ];
    var nextId = 1;
    for (var branch = 0; branch < 10; branch++) {
      final branchId = 'node${nextId++}';
      nodes.add(
        AiBookMindMapNode(
          nodeId: branchId,
          parentId: 'root',
          order: branch,
          level: 1,
          title: '分支$branch',
          summary: '分支摘要',
        ),
      );
      final childCount = branch == 9 ? 14 : 15;
      for (var child = 0; child < childCount; child++) {
        nodes.add(
          AiBookMindMapNode(
            nodeId: 'node${nextId++}',
            parentId: branchId,
            order: child,
            level: 2,
            title: '节点$child',
            summary: '节点摘要',
          ),
        );
      }
    }
    expect(nodes, hasLength(160));
    expect(validateAiBookMindMapNodes(nodes), isTrue);

    final watch = Stopwatch()..start();
    for (final layout in AiMindMapLayout.values) {
      final result = AiMindMapLayoutEngine.layout(
        AiBookMindMap(
          contentHash: 'b' * 64,
          workKey: null,
          createdAt: DateTime.utc(2026, 8, 10),
          model: 'performance-test',
          scopeSectionIndices: const [1],
          scopeFingerprint: 'scope',
          contentKind: AiMindMapContentKind.reference,
          layout: layout,
          nodes: nodes,
        ),
      );
      expect(result.nodeRects, hasLength(160));
      expect(result.edges, hasLength(159));
      expect(result.size.width.isFinite, isTrue);
      expect(result.size.height.isFinite, isTrue);
    }
    watch.stop();
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}

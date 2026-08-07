import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_family_tree.dart';

AiGraphEntity person(
  String name, {
  int firstSection = 1,
  AiGraphEntityScope scope = AiGraphEntityScope.setting,
}) {
  return AiGraphEntity(
    name: name,
    type: AiGraphEntityType.person,
    scope: scope,
    evidence: [
      AiGraphEvidence(sectionIndex: firstSection, quote: '$name 出场'),
    ],
    chapterFreq: {firstSection: 1},
    firstSection: firstSection,
    lastSection: firstSection,
  );
}

AiGraphRelation kin(
  String elder,
  String younger, {
  int evidenceCount = 1,
  String label = '父子',
}) {
  return AiGraphRelation(
    source: elder,
    target: younger,
    type: '亲属',
    kin: label,
    description: '',
    evidence: [
      for (var i = 0; i < evidenceCount; i++)
        AiGraphEvidence(sectionIndex: 1, quote: '$elder 与 $younger 是亲属 $i'),
    ],
    weight: evidenceCount.toDouble(),
  );
}

List<String> names(List<AiFamilyTreeNode> nodes) =>
    [for (final n in nodes) n.name];

/// Flattened book-order traversal for assertions.
List<String> flatten(AiFamilyTreeNode root) {
  final out = <String>[root.name];
  for (final child in root.children) {
    out.addAll(flatten(child));
  }
  return out;
}

List<AiFamilyTreeNode> _flattenNodes(AiFamilyTreeNode node) =>
    [node, for (final c in node.children) ..._flattenNodes(c)];

void main() {
  group('buildFamilyTree', () {
    test('plain lineage builds one root with nested children', () {
      final tree = buildFamilyTree(
        entities: [
          person('祖父', firstSection: 1),
          person('父亲', firstSection: 2),
          person('儿子', firstSection: 3),
        ],
        relations: [
          kin('祖父', '父亲'),
          kin('父亲', '儿子'),
        ],
      );

      expect(tree.isolatedCount, 0);
      expect(tree.complexNames, isEmpty);
      expect(names(tree.roots), ['祖父']);
      expect(flatten(tree.roots.single), ['祖父', '父亲', '儿子']);
    });

    test('multi-parent: strongest edge wins, runner-up is marked complex',
        () {
      final tree = buildFamilyTree(
        entities: [
          person('亲父', firstSection: 1),
          person('继父', firstSection: 2),
          person('孩子', firstSection: 3),
        ],
        relations: [
          kin('亲父', '孩子', evidenceCount: 3),
          kin('继父', '孩子', evidenceCount: 1),
        ],
      );

      expect(flatten(tree.roots.single), ['亲父', '孩子']);
      expect(tree.complexNames, ['继父']);
      expect(tree.isolatedCount, 0);
    });

    test('ring A-B-A keeps the stronger edge, breaks the other, marks complex',
        () {
      final tree = buildFamilyTree(
        entities: [
          person('甲', firstSection: 1),
          person('乙', firstSection: 2),
        ],
        relations: [
          kin('甲', '乙', evidenceCount: 2),
          kin('乙', '甲', evidenceCount: 1),
        ],
      );

      // 甲→乙 (2 证据) 保留；乙→甲 (1 证据) 被断 → 甲是根、乙是其子。
      expect(names(tree.roots), ['甲']);
      expect(flatten(tree.roots.single), ['甲', '乙']);
      expect(tree.complexNames, isNotEmpty);
      expect(tree.isolatedCount, 0);
    });

    test('three-node ring keeps one edge, drops the other two', () {
      final tree = buildFamilyTree(
        entities: [
          person('A', firstSection: 1),
          person('B', firstSection: 2),
          person('C', firstSection: 3),
        ],
        relations: [
          kin('A', 'B'),
          kin('B', 'C'),
          kin('C', 'A'),
        ],
      );

      expect(tree.roots.length, 1);
      expect(tree.complexNames.length, 2);
      expect(tree.isolatedCount, 0);
    });

    test('a two-node lineage keeps one root and no isolation', () {
      final tree = buildFamilyTree(
        entities: [
          person('族长', firstSection: 1),
          person('旁支', firstSection: 5),
        ],
        relations: [
          kin('族长', '旁支'),
        ],
      );

      expect(tree.roots.length, 1);
      expect(tree.isolatedCount, 0);
    });

    test('two unrelated lineages form a forest of two roots', () {
      final tree = buildFamilyTree(
        entities: [
          person('史塔克始祖', firstSection: 1),
          person('史塔克幼子', firstSection: 2),
          person('兰尼斯特始祖', firstSection: 4),
          person('兰尼斯特幼子', firstSection: 6),
        ],
        relations: [
          kin('史塔克始祖', '史塔克幼子'),
          kin('兰尼斯特始祖', '兰尼斯特幼子'),
        ],
      );

      expect(names(tree.roots), ['史塔克始祖', '兰尼斯特始祖']);
      expect(flatten(tree.roots[0]), ['史塔克始祖', '史塔克幼子']);
      expect(flatten(tree.roots[1]), ['兰尼斯特始祖', '兰尼斯特幼子']);
      expect(tree.isolatedCount, 0);
    });

    test('isolated persons with no kin edge are counted, not roots', () {
      final tree = buildFamilyTree(
        entities: [
          person('族长', firstSection: 1),
          person('过客', firstSection: 4),
          person('村民', firstSection: 6),
        ],
        relations: [
          kin('族长', '村民'),
        ],
      );

      expect(names(tree.roots), ['族长']);
      expect(tree.isolatedCount, 1); // 过客
    });

    test('kin label rides the tree edge to the child node', () {
      final tree = buildFamilyTree(
        entities: [
          person('方老先生', firstSection: 1),
          person('方鸿渐', firstSection: 2),
        ],
        relations: [
          AiGraphRelation(
            source: '方老先生',
            target: '方鸿渐',
            type: '亲属',
            kin: '父子',
            description: '父子关系。',
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '父子'),
            ],
            weight: 1,
          ),
        ],
      );

      expect(tree.roots.single.kin, isEmpty); // root has no parent edge
      expect(tree.roots.single.children.single.kin, '父子');
    });

    test('affinal kin (夫妻) never enters the blood-line tree', () {
      // The model emits 万历 -[亲属 kin=夫妻]-> 王皇后 alongside the real
      // 婚配 edge; the spouse is not a member of the lineage.
      final tree = buildFamilyTree(
        entities: [
          person('万历皇帝', firstSection: 1),
          person('王皇后', firstSection: 1),
          person('朱常洛', firstSection: 1),
        ],
        relations: [
          AiGraphRelation(
            source: '万历皇帝',
            target: '王皇后',
            type: '亲属',
            kin: '夫妻',
            description: '',
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '万历与王皇后为夫妻'),
            ],
            weight: 1,
          ),
          kin('万历皇帝', '朱常洛'),
        ],
      );

      // 王皇后 is isolated (her 婚配 edge is not a tree edge either); the
      // emperor keeps only his real children in the lineage.
      expect(tree.isolatedNames, contains('王皇后'));
      final wl = flatten(tree.roots.single);
      expect(wl, contains('万历皇帝'));
      expect(wl, contains('朱常洛'));
      expect(wl, isNot(contains('王皇后')));
    });

    test('marriage attaches spouses; maternal link becomes an extra edge',
        () {
      final tree = buildFamilyTree(
        entities: [
          person('万历皇帝', firstSection: 1),
          person('王皇后', firstSection: 1),
          person('恭妃王氏', firstSection: 1),
          person('朱常洛', firstSection: 2),
          person('常洵', firstSection: 3),
        ],
        relations: [
          AiGraphRelation(
            source: '万历皇帝',
            target: '王皇后',
            type: '婚配',
            kin: '皇后',
            description: '',
            evidence: [AiGraphEvidence(sectionIndex: 1, quote: '成婚')],
            weight: 1,
          ),
          AiGraphRelation(
            source: '万历皇帝',
            target: '恭妃王氏',
            type: '婚配',
            kin: '妃嫔',
            description: '',
            evidence: [AiGraphEvidence(sectionIndex: 1, quote: '册封')],
            weight: 1,
          ),
          kin('万历皇帝', '朱常洛', evidenceCount: 3),
          kin('万历皇帝', '常洵'),
          // 恭妃 is 朱常洛's birth mother; the father wins the single-parent
          // race, so her 母子 edge surfaces as a dashed extra link.
          AiGraphRelation(
            source: '恭妃王氏',
            target: '朱常洛',
            type: '亲属',
            kin: '母子',
            description: '',
            evidence: [AiGraphEvidence(sectionIndex: 2, quote: '所生')],
            weight: 1,
          ),
        ],
      );

      // Spouses attach to the node card instead of being lineage children.
      final wanli = tree.roots
          .expand((r) => _flattenNodes(r))
          .firstWhere((n) => n.name == '万历皇帝');
      expect(wanli.spouses.map((s) => '${s.kin}:${s.name}'),
          containsAll(['皇后:王皇后', '妃嫔:恭妃王氏']));

      // 王皇后 has no lineage edge → no tree card (folded as isolated); she
      // is visible only on 万历's card. 恭妃 participates as 朱常洛's mother
      // and joins the tree.
      expect(tree.isolatedNames, contains('王皇后'));
      expect(tree.isolatedNames, isNot(contains('恭妃王氏')));
      final wang = wanli.spouses.firstWhere((s) => s.name == '王皇后');
      expect(wang.kin, '皇后');

      // The maternal link survives as an extra edge; 恭妃 is not "complex".
      expect(tree.extraEdges, hasLength(1));
      final extra = tree.extraEdges.single;
      expect(extra.source, '恭妃王氏');
      expect(extra.target, '朱常洛');
      expect(extra.kin, '母子');
      expect(tree.complexNames, isNot(contains('恭妃王氏')));

      // The lineage spine still shows 万历 → 朱常洛 (father wins).
      final zhu = tree.roots
          .expand((r) => _flattenNodes(r))
          .firstWhere((n) => n.name == '朱常洛');
      expect(zhu.kin, '父子');
    });

    test('lost maternal edge with no marriage edge falls back to complex', () {
      final tree = buildFamilyTree(
        entities: [
          person('万历皇帝', firstSection: 1),
          person('恭妃王氏', firstSection: 1),
          person('朱常洛', firstSection: 2),
        ],
        relations: [
          kin('万历皇帝', '朱常洛', evidenceCount: 3),
          AiGraphRelation(
            source: '恭妃王氏',
            target: '朱常洛',
            type: '亲属',
            kin: '母子',
            description: '',
            evidence: [AiGraphEvidence(sectionIndex: 2, quote: '所生')],
            weight: 1,
          ),
        ],
      );

      // The mother has no tree seat (no marriage edge, lost the parent race):
      // the extra line cannot be drawn — she surfaces as complex instead of
      // silently vanishing.
      expect(tree.extraEdges, isEmpty);
      expect(tree.complexNames, contains('恭妃王氏'));
    });

    test('kin-less 亲属 edge never draws a child (恭妃≠万历之子)', () {
      // The model emitted 万历 -[亲属 kin=空]-> 恭妃王氏 alongside the real
      // 婚配 edge; the kin-less edge must not make the consort a child.
      final tree = buildFamilyTree(
        entities: [
          person('万历皇帝', firstSection: 1),
          person('恭妃王氏', firstSection: 1),
          person('朱常洛', firstSection: 1),
        ],
        relations: [
          AiGraphRelation(
            source: '万历皇帝',
            target: '恭妃王氏',
            type: '亲属',
            kin: '',
            description: '',
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '万历与恭妃'),
            ],
            weight: 1,
          ),
          kin('万历皇帝', '朱常洛'),
        ],
      );

      // 恭妃王氏 is isolated (her 婚配 edge is not a 亲属 tree edge), the
      // emperor keeps only his real children.
      expect(tree.isolatedCount, 1);
      expect(tree.isolatedNames, contains('恭妃王氏'));
      final wl = flatten(tree.roots.single);
      expect(wl, contains('万历皇帝'));
      expect(wl, contains('朱常洛'));
      expect(wl, isNot(contains('恭妃王氏')));
    });

    test('reference people and non-kin relations never enter the tree', () {
      final tree = buildFamilyTree(
        entities: [
          person('族长', firstSection: 1),
          person('村民', firstSection: 2),
          person('罗素', firstSection: 3, scope: AiGraphEntityScope.reference),
        ],
        relations: [
          kin('族长', '村民'),
          // A non-kin relation between two setting people must not create a
          // tree edge (spec: tree edges = 亲属 only).
          AiGraphRelation(
            source: '族长',
            target: '村民',
            type: '婚配',
            description: '',
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '族长与村民成婚'),
            ],
            weight: 1,
          ),
        ],
      );

      expect(names(tree.roots), ['族长']);
      expect(tree.isolatedCount, 0);
    });

    test('caller-side spoiler gate drops unread-evidence edges before build',
        () {
      // Simulates _buildFamilyTreeView's evidence-based filter: edges whose
      // evidence is entirely in unread chapters must not pull an otherwise-
      // isolated person into the tree or leak a late-plot kinship.
      final entities = [
        person('甲', firstSection: 1),
        person('乙', firstSection: 1),
      ];
      final unreadOnlyEdge = AiGraphRelation(
        source: '甲',
        target: '乙',
        type: '亲属',
        kin: '父子',
        description: '',
        evidence: [
          AiGraphEvidence(sectionIndex: 99, quote: '第99章才揭晓的父子关系'),
        ],
        weight: 1,
      );

      const readThrough = 5;
      final visible = unreadOnlyEdge.evidence
          .any((e) => e.sectionIndex <= readThrough);
      expect(visible, isFalse);

      final tree = buildFamilyTree(
        entities: entities,
        relations: visible ? [unreadOnlyEdge] : const [],
      );
      // With the spoiler edge dropped, neither person has a tree edge: both
      // fall into the isolated fold rather than forming a fake parent/child.
      expect(tree.roots, isEmpty);
      expect(tree.isolatedCount, 2);
      expect(tree.isolatedNames, containsAll(['甲', '乙']));
    });
  });
}

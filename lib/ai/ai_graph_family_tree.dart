/// Family-tree build (spec: docs/specs/ai-graph-narration.md §5).
///
/// Turns person entities + directed 亲属 edges (source = elder, target =
/// younger, per the step-0 direction convention) into a forest of hierarchy
/// nodes. Purely deterministic graph work — the model only produced the
/// entities and relations; roots, levels, ring breaks and isolation are all
/// computed here.
library;

import 'ai_graph.dart';

/// Affinal (姻亲) kinship labels that never enter the blood-line family tree.
/// The model occasionally emits 夫妻 as 亲属/夫妻 (alongside the correct 婚配
/// edge); a spouse is not a member of the lineage, so such edges are skipped
/// at tree build time. Kin-less 亲属 edges are filtered separately (empty kin
/// is an unconfirmed relation).
const _affinalKinTerms = {
  '夫妻', '妻', '妾', '夫', '丈夫', '妻子', '配偶', '正妻', '继室',
  '侧室', '偏房', '后妃', '妃', '嫔', '皇后', '贵妃', '夫人', '娘子',
  '翁婿', '婆媳', '妯娌', '连襟', '亲家',
};

/// One family-tree node. [children] are kept in book order (firstSection).
class AiFamilyTreeNode {
  AiFamilyTreeNode({
    required this.name,
    required this.firstSection,
    this.kin = '',
  });

  final String name;
  final int firstSection;

  /// Kinship label of the edge to its parent (父子/夫妻…), empty for roots.
  final String kin;
  final List<AiFamilyTreeNode> children = [];
}

/// Result of [buildFamilyTree].
class AiFamilyTree {
  AiFamilyTree({
    required this.roots,
    required this.isolatedCount,
    required this.isolatedNames,
    required this.complexNames,
  });

  /// Forest roots, book order. Every root is part of at least one 亲属 edge
  /// (nodes with no tree edge at all are folded into [isolatedCount]).
  final List<AiFamilyTreeNode> roots;

  /// Person entities that participate in no 亲属 edge — the「未入树 N 人」fold.
  final int isolatedCount;

  /// Names of the isolated persons, book order (for the expandable fold).
  final List<String> isolatedNames;

  /// People whose tree edge was dropped (multi-parent runner-ups, ring
  /// members). Sorted by first appearance.
  final List<String> complexNames;
}

/// Builds the family forest from a graph.
///
/// Rules (spec §5.2):
/// 1. nodes = setting persons; edges = 亲属 with source=elder, target=younger
/// 2. one parent per node: the strongest candidate edge wins (evidence
///    count, then earlier firstSection); losers are marked complex
/// 3. rings: the single-parent graph may still cycle; Kahn's algorithm on
///    the child→parent map finds the residual, each ring member drops its
///    parent edge (becomes a root) and is marked complex
/// 4. isolated = setting persons with no 亲属 edge at all
AiFamilyTree buildFamilyTree({
  required List<AiGraphEntity> entities,
  required List<AiGraphRelation> relations,
}) {
  final persons = <String, AiGraphEntity>{
    for (final e in entities)
      if (e.type == AiGraphEntityType.person &&
          e.scope == AiGraphEntityScope.setting)
        e.name: e,
  };

  // child -> candidate parent edges (strength-descending order preserved by
  // the sort below). Only 亲属 edges with a concrete KIN-SHIP label
  // participate — and affinal (姻亲) labels never enter the blood-line tree:
  // the model sometimes emits 夫妻 as 亲属/夫妻 (alongside the real 婚配 edge),
  // which would draw the consort as a member of the lineage.
  final incoming = <String, List<AiGraphRelation>>{};
  for (final r in relations) {
    if (r.type != '亲属' || r.kin.isEmpty) continue;
    if (_affinalKinTerms.contains(r.kin)) continue;
    final parent = r.source;
    final child = r.target;
    if (parent == child) continue;
    if (!persons.containsKey(parent) || !persons.containsKey(child)) continue;
    incoming.putIfAbsent(child, () => []).add(r);
  }

  final parentOf = <String, String>{};
  final kinOf = <String, String>{};
  final complex = <String>{};
  for (final entry in incoming.entries) {
    final child = entry.key;
    final candidates = entry.value;
    candidates.sort((a, b) {
      final byStrength = _edgeStrength(b).compareTo(_edgeStrength(a));
      if (byStrength != 0) return byStrength;
      return persons[a.source]!.firstSection
          .compareTo(persons[b.source]!.firstSection);
    });
    parentOf[child] = candidates.first.source;
    kinOf[child] = candidates.first.kin;
    for (final runnerUp in candidates.skip(1)) {
      complex.add(runnerUp.source);
    }
  }

  // Ring detection: Kahn on child→parent. Nodes never removed are on rings;
  // keep the strongest ring edge, drop the rest — dropped children become
  // roots, both endpoints are marked complex.
  final indegree = <String, int>{
    for (final name in persons.keys) name: 0,
  };
  for (final parent in parentOf.values) {
    indegree[parent] = (indegree[parent] ?? 0) + 1;
  }
  final queue = [
    for (final entry in indegree.entries)
      if (entry.value == 0) entry.key,
  ];
  while (queue.isNotEmpty) {
    final node = queue.removeLast();
    final parent = parentOf[node];
    if (parent == null) continue;
    final next = indegree[parent]! - 1;
    indegree[parent] = next;
    if (next == 0) queue.add(parent);
  }
  final ringMembers = <String>[
    for (final name in persons.keys)
      if (parentOf[name] != null && indegree[name]! > 0) name,
  ];
  if (ringMembers.isNotEmpty) {
    var bestStrength = -1;
    String? bestChild;
    for (final child in ringMembers) {
      final strength = _kinEdgeStrength(relations, parentOf[child]!, child);
      if (strength > bestStrength) {
        bestStrength = strength;
        bestChild = child;
      }
    }
    for (final child in ringMembers) {
      if (child == bestChild) continue;
      parentOf.remove(child);
      kinOf.remove(child);
      complex.add(child);
    }
  }

  final nodes = <String, AiFamilyTreeNode>{
    for (final name in persons.keys)
      name: AiFamilyTreeNode(
        name: name,
        firstSection: persons[name]!.firstSection,
        kin: kinOf[name] ?? '',
      ),
  };
  // Participating = everyone touched by a candidate 亲属 edge (multi-parent
  // runner-ups included — they are "complex", not isolated). Isolated =
  // setting persons with no kin edge at all.
  final treeMembers = <String>{...parentOf.keys, ...parentOf.values};
  final roots = <AiFamilyTreeNode>[
    for (final name in treeMembers)
      if (!parentOf.containsKey(name)) nodes[name]!,
  ]..sort((a, b) => a.firstSection.compareTo(b.firstSection));
  for (final entry in parentOf.entries) {
    nodes[entry.value]!.children.add(nodes[entry.key]!);
  }
  for (final node in nodes.values) {
    node.children.sort((a, b) => a.firstSection.compareTo(b.firstSection));
  }

  final participating = <String>{
    ...incoming.keys,
    for (final edges in incoming.values)
      for (final edge in edges) ...[edge.source, edge.target],
  };
  final isolatedCount = persons.length - participating.length;
  final isolatedNames = <String>[
    for (final name in persons.keys)
      if (!participating.contains(name)) name,
  ]..sort((a, b) => persons[a]!.firstSection
      .compareTo(persons[b]!.firstSection));
  final complexNames = complex.toList()
    ..sort((a, b) => persons[a]!.firstSection.compareTo(persons[b]!.firstSection));

  return AiFamilyTree(
    roots: roots,
    isolatedCount: isolatedCount,
    isolatedNames: isolatedNames,
    complexNames: complexNames,
  );
}

/// Edge strength = evidence count (more chapters corroborate → stronger).
int _edgeStrength(AiGraphRelation relation) => relation.evidence.length;

/// Strength of the 亲属 edge parent→child in the raw relation list.
int _kinEdgeStrength(
  List<AiGraphRelation> relations,
  String parent,
  String child,
) {
  for (final r in relations) {
    if (r.type == '亲属' && r.source == parent && r.target == child) {
      return r.evidence.length;
    }
  }
  return 0;
}

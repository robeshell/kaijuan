/// Family-tree build (spec: docs/specs/ai-graph.md §7.4).
///
/// Turns person entities + directed 亲属 edges (source = elder, target =
/// younger, per the step-0 direction convention) into a forest of hierarchy
/// nodes. Purely deterministic graph work — the model only produced the
/// entities and relations; roots, levels, ring breaks and isolation are all
/// computed here.
library;

import 'ai_graph.dart';

/// Only generational lineage terms can form a top-down family tree. Sibling,
/// collateral and affinal relations remain valid graph edges, but interpreting
/// them as parent→child creates a false hierarchy.
bool isLineageKin(String kin) {
  final value = kin.trim();
  if (value.isEmpty) return false;
  if (const {
    '父子',
    '父女',
    '母子',
    '母女',
    '亲子',
    '父母',
    '养父子',
    '养父女',
    '养母子',
    '养母女',
    '继父子',
    '继父女',
    '继母子',
    '继母女',
    '祖孙',
    '外祖孙',
  }.contains(value)) {
    return true;
  }
  final parentChild =
      (value.contains('父') || value.contains('母')) &&
      (value.endsWith('子') || value.endsWith('女'));
  final grandChild =
      (value.contains('祖父') || value.contains('祖母')) && value.contains('孙');
  return parentChild || grandChild;
}

/// One family-tree node. [children] are kept in book order (firstSection).
class AiFamilyTreeNode {
  AiFamilyTreeNode({
    required this.entityId,
    required this.name,
    required this.firstSection,
    this.kin = '',
    this.spouses = const [],
  });

  final String entityId;
  final String name;
  final int firstSection;

  /// Kinship label of the edge to its parent (父子/夫妻…), empty for roots.
  final String kin;

  /// Spouses from 婚配 edges (旁挂配偶), e.g. 王皇后/皇后, 恭妃王氏/妃嫔.
  final List<AiFamilySpouse> spouses;
  final List<AiFamilyTreeNode> children = [];
}

/// A spouse attached to a tree node (婚配 edge, 旁挂显示).
class AiFamilySpouse {
  const AiFamilySpouse({
    required this.entityId,
    required this.name,
    required this.kin,
  });
  final String entityId;
  final String name;
  final String kin;
}

/// An extra lineage edge drawn alongside the parent spine: the maternal
/// (母子/母女) edge a child's single-parent selection dropped — the consort
/// node then visibly links to her child (恭妃王氏 → 朱常洛 母子).
class AiFamilyExtraEdge {
  const AiFamilyExtraEdge({
    required this.sourceId,
    required this.targetId,
    required this.kin,
  });
  final String sourceId;
  final String targetId;
  final String kin;
}

/// Result of [buildFamilyTree].
class AiFamilyTree {
  AiFamilyTree({
    required this.roots,
    required this.isolatedCount,
    required this.isolatedNames,
    required this.isolatedEntityIds,
    required this.complexNames,
    required this.complexEntityIds,
    required this.extraEdges,
  });

  /// Forest roots, book order. Every root is part of at least one 亲属 edge
  /// (nodes with no tree edge at all are folded into [isolatedCount]).
  final List<AiFamilyTreeNode> roots;

  /// Person entities that participate in no 亲属 edge — the「未入树 N 人」fold.
  final int isolatedCount;

  /// Names of the isolated persons, book order (for the expandable fold).
  final List<String> isolatedNames;
  final List<String> isolatedEntityIds;

  /// People whose tree edge was dropped (multi-parent runner-ups, ring
  /// members). Sorted by first appearance.
  final List<String> complexNames;
  final List<String> complexEntityIds;

  /// Maternal links a single-parent selection dropped (母子/母女 runner-ups),
  /// drawn as dashed lines from the consort/mother node to the child.
  final List<AiFamilyExtraEdge> extraEdges;
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
        e.id: e,
  };
  final personIdsByName = <String, Set<String>>{};
  for (final person in persons.values) {
    personIdsByName.putIfAbsent(person.name, () => {}).add(person.id);
    for (final alias in person.aliases) {
      personIdsByName.putIfAbsent(alias, () => {}).add(person.id);
    }
  }

  String? endpointId(String explicitId, String name) {
    if (explicitId.isNotEmpty && persons.containsKey(explicitId)) {
      return explicitId;
    }
    final ids = personIdsByName[name];
    return ids != null && ids.length == 1 ? ids.single : null;
  }

  // child -> candidate parent edges (strength-descending order preserved by
  // the sort below). Only generational lineage edges participate; siblings,
  // aunts/uncles, cousins, generic 家人 and marriage remain graph relations.
  final incoming =
      <
        String,
        List<({AiGraphRelation relation, String parentId, String childId})>
      >{};
  for (final r in relations) {
    if (r.type != '亲属' || !isLineageKin(r.kin)) continue;
    final parentId = endpointId(r.sourceId, r.source);
    final childId = endpointId(r.targetId, r.target);
    if (parentId == null || childId == null || parentId == childId) continue;
    incoming.putIfAbsent(childId, () => []).add((
      relation: r,
      parentId: parentId,
      childId: childId,
    ));
  }

  // 婚配 edges attach spouses (旁挂) instead of lineage parents. Only
  // spouses who also participate in a 亲属 edge join the tree (恭妃王氏 as
  // 朱常洛's mother); a spouse with no lineage edge (王皇后) shows only on
  // the partner's card — no lone root card at the top.
  final spouses = <String, List<AiFamilySpouse>>{};
  final spouseMembers = <String>{};
  final kinParticipants = <String>{
    for (final edges in incoming.values)
      for (final edge in edges) ...[edge.parentId, edge.childId],
  };
  for (final r in relations) {
    if (r.type != '婚配') continue;
    final sourceId = endpointId(r.sourceId, r.source);
    final targetId = endpointId(r.targetId, r.target);
    if (sourceId == null || targetId == null || sourceId == targetId) continue;
    final forwardKin = r.kin.isEmpty ? '配偶' : r.kin;
    spouses
        .putIfAbsent(sourceId, () => [])
        .add(
          AiFamilySpouse(
            entityId: targetId,
            name: persons[targetId]!.name,
            kin: forwardKin,
          ),
        );
    // Reverse end labels the partner as plain 配偶 (王皇后 is 万历's 皇后,
    // not the other way round).
    spouses
        .putIfAbsent(targetId, () => [])
        .add(
          AiFamilySpouse(
            entityId: sourceId,
            name: persons[sourceId]!.name,
            kin: '配偶',
          ),
        );
    if (kinParticipants.contains(sourceId)) spouseMembers.add(sourceId);
    if (kinParticipants.contains(targetId)) spouseMembers.add(targetId);
  }

  final parentOf = <String, String>{};
  final kinOf = <String, String>{};
  final selectedEdgeOf =
      <String, ({AiGraphRelation relation, String parentId, String childId})>{};
  final complex = <String>{};
  final extraEdges = <AiFamilyExtraEdge>[];
  for (final entry in incoming.entries) {
    final child = entry.key;
    final candidates = entry.value;
    candidates.sort((a, b) {
      final byStrength = _edgeStrength(
        b.relation,
      ).compareTo(_edgeStrength(a.relation));
      if (byStrength != 0) return byStrength;
      return persons[a.parentId]!.firstSection.compareTo(
        persons[b.parentId]!.firstSection,
      );
    });
    parentOf[child] = candidates.first.parentId;
    kinOf[child] = candidates.first.relation.kin;
    selectedEdgeOf[child] = candidates.first;
    for (final runnerUp in candidates.skip(1)) {
      if (_maternalKin.contains(runnerUp.relation.kin)) {
        // The mother's edge lost the single-parent race to the father, but
        // she is a real parent — keep it as a visible extra link (dashed).
        extraEdges.add(
          AiFamilyExtraEdge(
            sourceId: runnerUp.parentId,
            targetId: child,
            kin: runnerUp.relation.kin,
          ),
        );
      } else {
        complex.add(runnerUp.parentId);
      }
    }
  }

  // A functional child→parent graph can contain disjoint cycles. Break each
  // cycle by dropping exactly its weakest edge; removing every edge except
  // the strongest destroys otherwise valid lineage chains.
  final globallyDone = <String>{};
  for (final start in persons.keys) {
    if (globallyDone.contains(start)) continue;
    final path = <String>[];
    final at = <String, int>{};
    var cursor = start;
    while (!globallyDone.contains(cursor) && parentOf[cursor] != null) {
      final cycleStart = at[cursor];
      if (cycleStart != null) {
        final cycle = path.sublist(cycleStart);
        var weakestChild = cycle.first;
        var weakestStrength = _edgeStrength(
          selectedEdgeOf[weakestChild]!.relation,
        );
        for (final child in cycle.skip(1)) {
          final strength = _edgeStrength(selectedEdgeOf[child]!.relation);
          if (strength < weakestStrength) {
            weakestChild = child;
            weakestStrength = strength;
          }
        }
        final formerParent = parentOf.remove(weakestChild);
        kinOf.remove(weakestChild);
        selectedEdgeOf.remove(weakestChild);
        complex.add(weakestChild);
        if (formerParent != null) complex.add(formerParent);
        break;
      }
      at[cursor] = path.length;
      path.add(cursor);
      cursor = parentOf[cursor]!;
    }
    globallyDone.addAll(path);
  }

  final nodes = <String, AiFamilyTreeNode>{
    for (final id in persons.keys)
      id: AiFamilyTreeNode(
        entityId: id,
        name: persons[id]!.name,
        firstSection: persons[id]!.firstSection,
        kin: kinOf[id] ?? '',
        spouses: spouses[id] ?? const [],
      ),
  };
  // Participating = everyone touched by a candidate 亲属 edge (multi-parent
  // runner-ups included — they are "complex", not isolated) plus 婚配
  // spouses who also hold a lineage edge. Isolated = setting persons with no
  // 亲属 edge at all — a marriage-only spouse (王皇后) has no tree seat and
  // is folded too, visible only on the partner's card.
  final treeMembers = <String>{
    ...parentOf.keys,
    ...parentOf.values,
    ...spouseMembers,
  };

  // The child always sits in the tree (parentOf key); the mother may not — a
  // consort with only a lost maternal edge and no marriage edge would leave
  // the extra line with no source node. Fall back to complex so she is not
  // silently invisible.
  final finalExtraEdges = <AiFamilyExtraEdge>[];
  for (final extra in extraEdges) {
    if (treeMembers.contains(extra.sourceId) &&
        treeMembers.contains(extra.targetId)) {
      finalExtraEdges.add(extra);
    } else {
      complex.add(extra.sourceId);
    }
  }
  final roots = <AiFamilyTreeNode>[
    for (final id in treeMembers)
      if (!parentOf.containsKey(id)) nodes[id]!,
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
      for (final edge in edges) ...[edge.parentId, edge.childId],
    ...spouseMembers,
  };
  final isolatedEntityIds =
      <String>[
        for (final id in persons.keys)
          if (!participating.contains(id)) id,
      ]..sort(
        (a, b) => persons[a]!.firstSection.compareTo(persons[b]!.firstSection),
      );
  final complexEntityIds = complex.toList()
    ..sort(
      (a, b) => persons[a]!.firstSection.compareTo(persons[b]!.firstSection),
    );

  return AiFamilyTree(
    roots: roots,
    isolatedCount: isolatedEntityIds.length,
    isolatedNames: [for (final id in isolatedEntityIds) persons[id]!.name],
    isolatedEntityIds: isolatedEntityIds,
    complexNames: [for (final id in complexEntityIds) persons[id]!.name],
    complexEntityIds: complexEntityIds,
    extraEdges: finalExtraEdges,
  );
}

/// Maternal kinship labels kept as visible extra links when the father won
/// the single-parent race (母子/母女).
const _maternalKin = {'母子', '母女'};

/// Edge strength = evidence count (more chapters corroborate → stronger).
int _edgeStrength(AiGraphRelation relation) => relation.evidence.length;

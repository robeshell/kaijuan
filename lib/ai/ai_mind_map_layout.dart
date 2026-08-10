import 'dart:math' as math;
import 'dart:ui';

import 'ai_mind_map.dart';

class AiMindMapLayoutResult {
  const AiMindMapLayoutResult({
    required this.size,
    required this.nodeRects,
    required this.edges,
  });

  final Size size;
  final Map<String, Rect> nodeRects;
  final List<({String parentId, String childId})> edges;
}

abstract final class AiMindMapLayoutEngine {
  static const nodeSize = Size(224, 108);
  static const horizontalGap = 80.0;
  static const verticalGap = 28.0;
  static const canvasPadding = 80.0;

  static AiMindMapLayoutResult layout(
    AiBookMindMap map, {
    Set<String> collapsedNodeIds = const {},
  }) {
    final visible = _visibleNodes(map.nodes, collapsedNodeIds);
    return switch (map.layout) {
      AiMindMapLayout.radial => _radial(visible),
      AiMindMapLayout.rightFacing => _rightFacing(visible),
      AiMindMapLayout.bidirectional => _bidirectional(visible),
    };
  }

  static List<AiBookMindMapNode> _visibleNodes(
    List<AiBookMindMapNode> nodes,
    Set<String> collapsed,
  ) {
    final byId = {for (final node in nodes) node.nodeId: node};
    bool hidden(AiBookMindMapNode node) {
      var parentId = node.parentId;
      while (parentId != null) {
        if (collapsed.contains(parentId)) return true;
        parentId = byId[parentId]?.parentId;
      }
      return false;
    }

    return nodes.where((node) => !hidden(node)).toList(growable: false);
  }

  static Map<String, List<AiBookMindMapNode>> _children(
    List<AiBookMindMapNode> nodes,
  ) {
    final result = <String, List<AiBookMindMapNode>>{};
    for (final node in nodes.where((node) => node.parentId != null)) {
      result.putIfAbsent(node.parentId!, () => []).add(node);
    }
    for (final siblings in result.values) {
      siblings.sort(
        (a, b) => a.order != b.order
            ? a.order.compareTo(b.order)
            : a.nodeId.compareTo(b.nodeId),
      );
    }
    return result;
  }

  static AiMindMapLayoutResult _rightFacing(List<AiBookMindMapNode> nodes) {
    final children = _children(nodes);
    final root = nodes.singleWhere((node) => node.parentId == null);
    final centers = <String, Offset>{};
    var nextY = canvasPadding + nodeSize.height / 2;

    double place(AiBookMindMapNode node) {
      final kids = children[node.nodeId] ?? const [];
      final y = kids.isEmpty
          ? nextY
          : kids.map(place).reduce((a, b) => a + b) / kids.length;
      if (kids.isEmpty) nextY += nodeSize.height + verticalGap;
      centers[node.nodeId] = Offset(
        canvasPadding +
            nodeSize.width / 2 +
            node.level * (nodeSize.width + horizontalGap),
        y,
      );
      return y;
    }

    place(root);
    final maxLevel = nodes.fold<int>(
      0,
      (value, node) => math.max(value, node.level),
    );
    final size = Size(
      canvasPadding * 2 +
          nodeSize.width +
          maxLevel * (nodeSize.width + horizontalGap),
      math.max(
        nextY - verticalGap + canvasPadding,
        nodeSize.height + canvasPadding * 2,
      ),
    );
    return _result(nodes, centers, size);
  }

  static AiMindMapLayoutResult _bidirectional(List<AiBookMindMapNode> nodes) {
    final children = _children(nodes);
    final root = nodes.singleWhere((node) => node.parentId == null);
    final branches = [...?children[root.nodeId]];
    final subtreeSizes = <String, int>{};
    int sizeOf(AiBookMindMapNode node) => subtreeSizes.putIfAbsent(
      node.nodeId,
      () =>
          1 +
          (children[node.nodeId] ?? const []).fold<int>(
            0,
            (sum, child) => sum + sizeOf(child),
          ),
    );
    branches.sort((a, b) {
      final sizeOrder = sizeOf(b).compareTo(sizeOf(a));
      if (sizeOrder != 0) return sizeOrder;
      final siblingOrder = a.order.compareTo(b.order);
      return siblingOrder != 0 ? siblingOrder : a.nodeId.compareTo(b.nodeId);
    });
    final left = <AiBookMindMapNode>[];
    final right = <AiBookMindMapNode>[];
    var leftWeight = 0;
    var rightWeight = 0;
    for (final branch in branches) {
      final weight = sizeOf(branch);
      if (leftWeight <= rightWeight) {
        left.add(branch);
        leftWeight += weight;
      } else {
        right.add(branch);
        rightWeight += weight;
      }
    }
    final centers = <String, Offset>{};
    final maxLevel = nodes.fold<int>(
      0,
      (value, node) => math.max(value, node.level),
    );
    final width =
        canvasPadding * 2 +
        nodeSize.width +
        maxLevel * 2 * (nodeSize.width + horizontalGap);
    var leftY = canvasPadding + nodeSize.height / 2;
    var rightY = canvasPadding + nodeSize.height / 2;

    double place(AiBookMindMapNode node, bool isLeft) {
      final kids = children[node.nodeId] ?? const [];
      final y = kids.isEmpty
          ? (isLeft ? leftY : rightY)
          : kids.map((child) => place(child, isLeft)).reduce((a, b) => a + b) /
                kids.length;
      if (kids.isEmpty) {
        if (isLeft) {
          leftY += nodeSize.height + verticalGap;
        } else {
          rightY += nodeSize.height + verticalGap;
        }
      }
      final direction = isLeft ? -1.0 : 1.0;
      centers[node.nodeId] = Offset(
        width / 2 + direction * node.level * (nodeSize.width + horizontalGap),
        y,
      );
      return y;
    }

    final leftCenters = [for (final branch in left) place(branch, true)];
    final rightCenters = [for (final branch in right) place(branch, false)];
    final allBranchCenters = [...leftCenters, ...rightCenters];
    final height = math.max(leftY, rightY) - verticalGap + canvasPadding;
    centers[root.nodeId] = Offset(
      width / 2,
      allBranchCenters.isEmpty
          ? height / 2
          : allBranchCenters.reduce((a, b) => a + b) / allBranchCenters.length,
    );
    return _result(nodes, centers, Size(width, math.max(height, 240)));
  }

  static AiMindMapLayoutResult _radial(List<AiBookMindMapNode> nodes) {
    final children = _children(nodes);
    final root = nodes.singleWhere((node) => node.parentId == null);
    final leafCount = <String, int>{};
    int leaves(AiBookMindMapNode node) =>
        leafCount.putIfAbsent(node.nodeId, () {
          final kids = children[node.nodeId] ?? const [];
          return kids.isEmpty
              ? 1
              : kids.fold<int>(0, (sum, child) => sum + leaves(child));
        });
    final totalLeaves = math.max(1, leaves(root));
    final maxLevel = nodes.fold<int>(
      0,
      (value, node) => math.max(value, node.level),
    );
    final radiusStep = math.max(210.0, nodeSize.width + 54);
    final outerRadius = math.max(radiusStep, maxLevel * radiusStep);
    final extent = outerRadius * 2 + nodeSize.width + canvasPadding * 2;
    final origin = Offset(extent / 2, extent / 2);
    final centers = <String, Offset>{root.nodeId: origin};

    double place(AiBookMindMapNode node, double start, double sweep) {
      final kids = children[node.nodeId] ?? const [];
      var cursor = start;
      final childAngles = <double>[];
      for (final child in kids) {
        final childSweep =
            sweep *
            leaves(child) /
            totalLeaves *
            (node == root
                ? totalLeaves / leaves(root)
                : leaves(root) / leaves(node));
        final angle = place(child, cursor, childSweep);
        childAngles.add(angle);
        cursor += childSweep;
      }
      final angle = childAngles.isEmpty
          ? start + sweep / 2
          : _circularAverage(childAngles);
      if (node != root) {
        final radius = node.level * radiusStep;
        centers[node.nodeId] = Offset(
          origin.dx + math.cos(angle) * radius,
          origin.dy + math.sin(angle) * radius,
        );
      }
      return angle;
    }

    place(root, -math.pi / 2, math.pi * 2);
    return _result(nodes, centers, Size.square(extent));
  }

  static double _circularAverage(List<double> values) {
    final x = values.fold<double>(0, (sum, value) => sum + math.cos(value));
    final y = values.fold<double>(0, (sum, value) => sum + math.sin(value));
    return math.atan2(y, x);
  }

  static AiMindMapLayoutResult _result(
    List<AiBookMindMapNode> nodes,
    Map<String, Offset> centers,
    Size size,
  ) {
    final rects = <String, Rect>{
      for (final entry in centers.entries)
        entry.key: Rect.fromCenter(
          center: entry.value,
          width: nodeSize.width,
          height: nodeSize.height,
        ),
    };
    final edges = <({String parentId, String childId})>[
      for (final node in nodes)
        if (node.parentId != null &&
            rects.containsKey(node.nodeId) &&
            rects.containsKey(node.parentId))
          (parentId: node.parentId!, childId: node.nodeId),
    ];
    return AiMindMapLayoutResult(
      size: size,
      nodeRects: Map.unmodifiable(rects),
      edges: List.unmodifiable(edges),
    );
  }
}

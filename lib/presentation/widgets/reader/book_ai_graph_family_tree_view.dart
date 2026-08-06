import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ai/ai_graph_family_tree.dart';

/// Line-connected organization-chart family tree (spec:
/// docs/specs/ai-graph-narration.md §5.3): top-down, siblings spread evenly,
/// parents connected to children with elbow lines.
///
/// Interaction — picked by the user after hand-rolled scroll layouts and the
/// graphview package both failed interaction checks (scroll nests stole
/// gestures; graphview's RenderCustomLayoutBox swallowed node taps):
/// - **InteractiveViewer** with `constrained: false` + `boundaryMargin:
///   infinity`: drag pans, wheel / pinch zooms, nothing is ever clipped out
///   of reach. Funded by Flutter's own gesture arena — node taps always win
///   because the cards are real Stack children (Positioned), not buried in a
///   third-party render object.
/// - **auto-fit on open**: a post-frame transform shows the whole tree
///   centered and magnified to fill the viewport (sparse trees are never a
///   shrunk thumbnail). The user's pan/zoom then takes over.
/// - Card tap → entity card (no gesture competition).
///
/// Trade-off: no edge labels (父子/夫妻…) — the line direction already
/// communicates parent → child.
class BookAiGraphFamilyTreeView extends StatefulWidget {
  const BookAiGraphFamilyTreeView({
    super.key,
    required this.tree,
    required this.onVertexTap,
    this.leafStep = 176,
    this.levelHeight = 96,
    this.viewportHeight = 380,
  });

  final AiFamilyTree tree;

  /// Tapped a node's canonical name (opens the entity card).
  final ValueChanged<String> onVertexTap;

  /// Minimum horizontal distance between sibling leaves. At least
  /// `nodeWidth * 2` so the parent card (centered over its children) sits in
  /// the gap and never overlaps the middle children.
  final double leafStep;

  /// Vertical distance between levels.
  final double levelHeight;

  /// Fixed viewport height; the tree fit-scaling is computed against it.
  final double viewportHeight;

  static const double nodeWidth = 88;
  static const double nodeHeight = 44;
  static const double horizontalPadding = 24;

  /// Edge kinship-label chip size (父子/夫妻…). Fixed so Positioned math
  /// stays simple; the label clips with ellipsis if longer.
  static const double _edgeLabelWidth = 34;
  static const double _edgeLabelHeight = 16;

  /// Cap on stretched sibling spacing: a sparse tree fills the panel but a
  /// two-node tree must not spread across an 800px panel.
  static const double maxSiblingStep = 264;

  static const double minScale = 0.1;
  static const double maxScale = 4;

  @override
  State<BookAiGraphFamilyTreeView> createState() =>
      _BookAiGraphFamilyTreeViewState();
}

class _BookAiGraphFamilyTreeViewState
    extends State<BookAiGraphFamilyTreeView> {
  final TransformationController _controller = TransformationController();
  bool _fitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Refit when the tree identity changes (new book / regenerated graph).
  @override
  void didUpdateWidget(covariant BookAiGraphFamilyTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tree != widget.tree) {
      _fitted = false;
    }
  }

  void _fitToViewport(Size viewport, double canvasWidth, double canvasHeight) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        canvasWidth <= 0 ||
        canvasHeight <= 0) {
      return;
    }
    final fit = math.min(
      viewport.width / canvasWidth,
      viewport.height / canvasHeight,
    );
    // autoZoomToFit magnifies a small tree to fill the panel (never below
    // minScale), never above 1:1 so a wide tree isn't blown past the panel
    // (it's panned instead).
    final scale = fit.clamp(
      BookAiGraphFamilyTreeView.minScale,
      1.0,
    );
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, (viewport.width - canvasWidth * scale) / 2)
      ..setEntry(1, 3, (viewport.height - canvasHeight * scale) / 2);
  }

  _LayoutNode _toLayoutNode(
    AiFamilyTreeNode node,
    int depth,
    Set<String> complex,
  ) {
    final layout = _LayoutNode(
      name: node.name,
      depth: depth,
      complex: complex.contains(node.name),
      kin: node.kin,
    );
    for (final child in node.children) {
      layout.children.add(_toLayoutNode(child, depth + 1, complex));
    }
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final complex = widget.tree.complexNames.toSet();
    final roots = [
      for (final root in widget.tree.roots)
        _toLayoutNode(root, 0, complex),
    ];
    if (roots.isEmpty) return const SizedBox.shrink();

    var leafCount = 0;
    void countLeaves(_LayoutNode node) {
      if (node.children.isEmpty) {
        leafCount += 1;
      } else {
        for (final child in node.children) {
          countLeaves(child);
        }
      }
    }

    for (final root in roots) {
      countLeaves(root);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final side =
            BookAiGraphFamilyTreeView.horizontalPadding +
            BookAiGraphFamilyTreeView.nodeWidth / 2;
        // Sparse trees stretch to use the panel width (capped), wide trees
        // keep the minimum step and are panned into view. The canvas always
        // fills the panel horizontally — never a shrunk thumbnail.
        final spread = (maxWidth - side * 2) / math.max(leafCount - 1, 1);
        final step = math.max(
          widget.leafStep,
          math.min(spread, BookAiGraphFamilyTreeView.maxSiblingStep),
        );

        var leafCursor = 0.0;
        double place(_LayoutNode node) {
          if (node.children.isEmpty) {
            node.x = side + leafCursor * step;
            leafCursor += 1;
            return node.x;
          }
          var sum = 0.0;
          for (final child in node.children) {
            sum += place(child);
          }
          node.x = sum / node.children.length;
          return node.x;
        }

        var maxDepth = 0;
        void depthOf(_LayoutNode node, int depth) {
          if (depth > maxDepth) maxDepth = depth;
          for (final child in node.children) {
            depthOf(child, depth + 1);
          }
        }

        for (final root in roots) {
          place(root);
        }
        for (final root in roots) {
          depthOf(root, 0);
        }

        final contentWidth =
            side * 2 + math.max(leafCount - 1, 0) * step;
        final canvasWidth = math.max(contentWidth, maxWidth);
        final canvasHeight = (maxDepth + 1) * widget.levelHeight;
        // Center a narrow tree; a wide tree starts flush and is panned.
        final offsetX = math.max(0.0, (canvasWidth - contentWidth) / 2);

        final nodes = <_LayoutNode>[];
        final edges = <_LayoutEdge>[];
        void collect(_LayoutNode node) {
          node.x += offsetX;
          nodes.add(node);
          for (final child in node.children) {
            edges.add(_LayoutEdge(
              parentCenterX: node.x,
              parentBottomY:
                  node.depth * widget.levelHeight +
                  BookAiGraphFamilyTreeView.nodeHeight,
              childCenterX: child.x + offsetX,
              childTopY: child.depth * widget.levelHeight,
              label: child.kin,
            ));
            collect(child);
          }
        }

        for (final root in roots) {
          collect(root);
        }

        if (!_fitted) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fitToViewport(
                Size(maxWidth, widget.viewportHeight),
                canvasWidth,
                canvasHeight,
              );
            }
          });
        }

        return SizedBox(
          width: double.infinity,
          height: widget.viewportHeight,
          child: InteractiveViewer(
            transformationController: _controller,
            // Keep the canvas at its real size so a wide tree isn't squashed
            // into the viewport — wheel/drag pan reveals the rest.
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: BookAiGraphFamilyTreeView.minScale,
            maxScale: BookAiGraphFamilyTreeView.maxScale,
            child: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FamilyTreeEdgePainter(
                        edges: edges,
                        color: colors.outlineVariant,
                      ),
                    ),
                  ),
                  for (final edge in edges)
                    if (edge.label.isNotEmpty)
                      Positioned(
                        left: (edge.parentCenterX + edge.childCenterX) / 2 -
                            BookAiGraphFamilyTreeView._edgeLabelWidth / 2,
                        top: (edge.parentBottomY + edge.childTopY) / 2 -
                            BookAiGraphFamilyTreeView._edgeLabelHeight / 2,
                        child: _EdgeLabel(
                          text: edge.label,
                          background: colors.surfaceContainerHighest,
                          foreground: colors.onSurfaceVariant,
                        ),
                      ),
                  for (final node in nodes)
                    Positioned(
                      left: node.x -
                          BookAiGraphFamilyTreeView.nodeWidth / 2,
                      top: node.depth * widget.levelHeight,
                      child: _TreeNodeCard(
                        name: node.name,
                        width: BookAiGraphFamilyTreeView.nodeWidth,
                        height: BookAiGraphFamilyTreeView.nodeHeight,
                        complex: node.complex,
                        onTap: () => widget.onVertexTap(node.name),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EdgeLabel extends StatelessWidget {
  const _EdgeLabel({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: BookAiGraphFamilyTreeView._edgeLabelWidth,
      height: BookAiGraphFamilyTreeView._edgeLabelHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9,
          color: foreground,
          height: 1.2,
        ),
      ),
    );
  }
}

class _TreeNodeCard extends StatelessWidget {
  const _TreeNodeCard({
    required this.name,
    required this.width,
    required this.height,
    required this.complex,
    required this.onTap,
  });

  final String name;
  final double width;
  final double height;
  final bool complex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final card = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: complex ? colors.error : colors.primary,
          width: complex ? 1.6 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: card,
      ),
    );
  }
}

class _LayoutNode {
  _LayoutNode({
    required this.name,
    required this.depth,
    required this.complex,
    this.kin = '',
  });

  final String name;
  final int depth;
  final bool complex;

  /// Kinship label of the edge to its parent (父子/夫妻…), empty for roots.
  final String kin;
  double x = 0;
  final List<_LayoutNode> children = [];
}

class _LayoutEdge {
  const _LayoutEdge({
    required this.parentCenterX,
    required this.parentBottomY,
    required this.childCenterX,
    required this.childTopY,
    this.label = '',
  });

  final double parentCenterX;
  final double parentBottomY;
  final double childCenterX;
  final double childTopY;

  /// Kinship label shown on the edge midpoint (父子/夫妻…), empty hides it.
  final String label;
}

class _FamilyTreeEdgePainter extends CustomPainter {
  _FamilyTreeEdgePainter({required this.edges, required this.color});

  final List<_LayoutEdge> edges;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final midY = (edge.parentBottomY + edge.childTopY) / 2;
      final path = Path()
        ..moveTo(edge.parentCenterX, edge.parentBottomY)
        ..lineTo(edge.parentCenterX, midY)
        ..lineTo(edge.childCenterX, midY)
        ..lineTo(edge.childCenterX, edge.childTopY);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_FamilyTreeEdgePainter oldDelegate) =>
      oldDelegate.edges != edges || oldDelegate.color != color;
}
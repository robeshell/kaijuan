import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ai/ai_graph_family_tree.dart';
import '../ai_typography.dart';

/// Line-connected organization-chart family tree (spec:
/// docs/specs/ai-graph.md §7.4): top-down, siblings spread evenly,
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
    this.minScale = 0.1,
    this.maxScale = 4,
  });

  final AiFamilyTree tree;

  /// Tapped a node's stable entity ID (opens the entity card).
  final ValueChanged<String> onVertexTap;

  /// Minimum horizontal distance between sibling leaves. At least
  /// `nodeWidth * 2` so the parent card (centered over its children) sits in
  /// the gap and never overlaps the middle children.
  final double leafStep;

  /// Vertical distance between levels.
  final double levelHeight;

  /// Fixed viewport height; the tree fit-scaling is computed against it.
  /// Null fills the parent's height constraint (fullscreen); an unbounded
  /// parent falls back to 380.
  final double? viewportHeight;

  /// Zoom limits. The fullscreen view passes a much deeper range than the
  /// panel defaults (a big tree opens fitted way below 1:1, so reading one
  /// branch needs generous magnification). Wheel zoom is native to
  /// InteractiveViewer on desktop — no custom handling needed.
  final double minScale;
  final double maxScale;

  static const double nodeWidth = 88;
  static const double nodeHeight = 44;
  static const double _spouseRowHeight = 18;
  static const double horizontalPadding = 24;

  /// Edge kinship-label chip size (父子/夫妻…). Fixed so Positioned math
  /// stays simple; the label clips with ellipsis if longer.
  static const double _edgeLabelWidth = 44;
  static const double _edgeLabelHeight = 20;

  /// Cap on stretched sibling spacing: a sparse tree fills the panel but a
  /// two-node tree must not spread across an 800px panel.
  static const double maxSiblingStep = 264;

  @override
  State<BookAiGraphFamilyTreeView> createState() =>
      _BookAiGraphFamilyTreeViewState();
}

class _BookAiGraphFamilyTreeViewState extends State<BookAiGraphFamilyTreeView> {
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
    final scale = fit.clamp(widget.minScale, 1.0);
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
      entityId: node.entityId,
      name: node.name,
      depth: depth,
      complex: complex.contains(node.entityId),
      kin: node.kin,
      spouses: node.spouses,
    );
    for (final child in node.children) {
      layout.children.add(_toLayoutNode(child, depth + 1, complex));
    }
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final complex = widget.tree.complexEntityIds.toSet();
    final roots = [
      for (final root in widget.tree.roots) _toLayoutNode(root, 0, complex),
    ];
    if (roots.isEmpty) return const SizedBox.shrink();

    // 旁挂：a consort root (恭妃王氏) parks as the partner's first child
    // instead of a distant top-level root — her maternal link to the child
    // then spans one sibling step instead of crossing the whole canvas.
    // Only forward spouse entries attach (kin ≠ '配偶'; the reverse side is
    // always plain 配偶); a marriage-only spouse (王皇后) has no tree seat
    // and is untouched. The spouse entry's forward kin is the 婚配 kin —
    // empty-kin 婚配 edges (kin='配偶' both ways) are left alone.
    final parkedIds = <String>{};
    {
      final all = <_LayoutNode>[];
      void walk(_LayoutNode n) {
        all.add(n);
        for (final c in n.children) {
          walk(c);
        }
      }

      for (final r in roots) {
        walk(r);
      }
      for (final r in [...roots]) {
        _LayoutNode? anchor;
        for (final n in all) {
          if (n.spouses.any((s) => s.entityId == r.entityId && s.kin != '配偶') &&
              !parkedIds.contains(n.entityId)) {
            anchor = n;
            break;
          }
        }
        if (anchor == null || identical(anchor, r)) continue;
        if (parkedIds.contains(r.entityId)) continue;
        roots.remove(r);
        final parked = _LayoutNode(
          entityId: r.entityId,
          name: r.name,
          depth: anchor.depth + 1,
          complex: r.complex,
          kin: r.kin,
          spouses: r.spouses,
          spouseAnchor: true,
        )..children.addAll(r.children);
        // Shift the carried subtree so depths stay consistent after the move.
        void shiftDepth(_LayoutNode n, int delta) {
          for (final c in n.children) {
            c.depth += delta;
            shiftDepth(c, delta);
          }
        }

        shiftDepth(parked, anchor.depth + 1);
        parkedIds.add(r.entityId);
        anchor.children.insert(0, parked);
        // Re-walk for the next candidate (the anchor set may have grown).
        all.clear();
        for (final r2 in roots) {
          walk(r2);
        }
      }
    }

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
        // Fullscreen passes viewportHeight: null → fill the parent; a
        // scrollable parent (unbounded height) falls back to the panel
        // default so the widget never collapses to zero.
        final viewportH =
            widget.viewportHeight ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 380);
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

        final contentWidth = side * 2 + math.max(leafCount - 1, 0) * step;
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
            if (child.spouseAnchor) {
              // 婚配 doesn't draw a parent edge (the spouse row + the
              // maternal link already show the relationship).
              collect(child);
              continue;
            }
            edges.add(
              _LayoutEdge(
                parentCenterX: node.x,
                parentBottomY:
                    node.depth * widget.levelHeight +
                    BookAiGraphFamilyTreeView.nodeHeight +
                    (node.spouses.isNotEmpty
                        ? BookAiGraphFamilyTreeView._spouseRowHeight
                        : 0),
                childCenterX: child.x + offsetX,
                childTopY: child.depth * widget.levelHeight,
                label: child.kin,
              ),
            );
            collect(child);
          }
        }

        for (final root in roots) {
          collect(root);
        }

        // Maternal extra links (母子/母女) the single-parent selection dropped:
        // dashed lines from the consort/mother node to her child.
        final nodeById = {for (final n in nodes) n.entityId: n};
        final extraEdges = <_LayoutEdge>[];
        for (final extra in widget.tree.extraEdges) {
          final source = nodeById[extra.sourceId];
          final target = nodeById[extra.targetId];
          if (source == null || target == null) continue;
          final bottomY =
              source.depth * widget.levelHeight +
              BookAiGraphFamilyTreeView.nodeHeight +
              (source.spouses.isNotEmpty
                  ? BookAiGraphFamilyTreeView._spouseRowHeight
                  : 0);
          if (source.depth == target.depth) {
            // Same layer (the parked consort next to her child): a short
            // horizontal dashed link between the two cards instead of a
            // long fold spanning the canvas.
            final left = math.min(source.x, target.x);
            final right = math.max(source.x, target.x);
            extraEdges.add(
              _LayoutEdge(
                parentCenterX: left + BookAiGraphFamilyTreeView.nodeWidth / 2,
                parentBottomY: bottomY,
                childCenterX: right - BookAiGraphFamilyTreeView.nodeWidth / 2,
                childTopY: bottomY,
                label: extra.kin,
              ),
            );
          } else {
            extraEdges.add(
              _LayoutEdge(
                parentCenterX: source.x,
                parentBottomY: bottomY,
                childCenterX: target.x,
                childTopY: target.depth * widget.levelHeight,
                label: extra.kin,
              ),
            );
          }
        }

        if (!_fitted) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fitToViewport(
                Size(maxWidth, viewportH),
                canvasWidth,
                canvasHeight,
              );
            }
          });
        }

        return SizedBox(
          width: double.infinity,
          height: viewportH,
          child: InteractiveViewer(
            transformationController: _controller,
            // Keep the canvas at its real size so a wide tree isn't squashed
            // into the viewport — wheel/drag pan reveals the rest.
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: widget.minScale,
            maxScale: widget.maxScale,
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
                        extraEdges: extraEdges,
                        color: colors.outlineVariant,
                      ),
                    ),
                  ),
                  for (final edge in [...edges, ...extraEdges])
                    if (edge.label.isNotEmpty)
                      Positioned(
                        left:
                            (edge.parentCenterX + edge.childCenterX) / 2 -
                            BookAiGraphFamilyTreeView._edgeLabelWidth / 2,
                        top:
                            (edge.parentBottomY + edge.childTopY) / 2 -
                            BookAiGraphFamilyTreeView._edgeLabelHeight / 2,
                        child: _EdgeLabel(
                          text: edge.label,
                          background: colors.surfaceContainerHighest,
                          foreground: colors.onSurfaceVariant,
                        ),
                      ),
                  for (final node in nodes)
                    Positioned(
                      left: node.x - BookAiGraphFamilyTreeView.nodeWidth / 2,
                      top: node.depth * widget.levelHeight,
                      child: _TreeNodeCard(
                        name: node.name,
                        width: BookAiGraphFamilyTreeView.nodeWidth,
                        complex: node.complex,
                        spouses: node.spouses,
                        onTap: () => widget.onVertexTap(node.entityId),
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
        style: TextStyle(fontSize: 12, color: foreground, height: 1.2),
      ),
    );
  }
}

class _TreeNodeCard extends StatelessWidget {
  const _TreeNodeCard({
    required this.name,
    required this.width,
    required this.complex,
    required this.spouses,
    required this.onTap,
  });

  final String name;
  final double width;
  final bool complex;

  /// 旁挂配偶 rows (皇后：王皇后 / 妃嫔：恭妃王氏), empty hides the row.
  final List<AiFamilySpouse> spouses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasSpouses = spouses.isNotEmpty;
    final card = Container(
      width: width,
      height: hasSpouses
          ? BookAiGraphFamilyTreeView.nodeHeight +
                BookAiGraphFamilyTreeView._spouseRowHeight
          : BookAiGraphFamilyTreeView.nodeHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: complex ? colors.error : colors.primary,
          width: complex ? 1.6 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: context.aiCaptionSize,
                height: 1.2,
                color: colors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (hasSpouses)
            Flexible(
              child: Text(
                spouses.map((s) => '${s.kin}：${s.name}').join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
    final spouseDescription = spouses
        .map((spouse) => '${spouse.kin}：${spouse.name}')
        .join('，');
    return Semantics(
      button: true,
      label: spouseDescription.isEmpty ? name : '$name，$spouseDescription',
      hint: '打开实体详情',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: card,
          ),
        ),
      ),
    );
  }
}

class _LayoutNode {
  _LayoutNode({
    required this.entityId,
    required this.name,
    required this.depth,
    required this.complex,
    this.kin = '',
    this.spouses = const [],
    this.spouseAnchor = false,
  });

  final String entityId;
  final String name;
  int depth;
  final bool complex;

  /// Kinship label of the edge to its parent (父子/夫妻…), empty for roots.
  final String kin;

  /// 旁挂配偶 (婚配 edges), shown as a small row on the card.
  final List<AiFamilySpouse> spouses;

  /// The node is a consort parked right below her partner (万历 → 恭妃王氏)
  /// so her maternal link stays short; no parent edge is drawn for it.
  final bool spouseAnchor;
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
  _FamilyTreeEdgePainter({
    required this.edges,
    required this.extraEdges,
    required this.color,
  });

  final List<_LayoutEdge> edges;

  /// Maternal links drawn dashed, slightly weaker than the parent spine.
  final List<_LayoutEdge> extraEdges;
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
    if (extraEdges.isNotEmpty) {
      final extraPaint = Paint()
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      for (final edge in extraEdges) {
        final midY = (edge.parentBottomY + edge.childTopY) / 2;
        final path = Path()
          ..moveTo(edge.parentCenterX, edge.parentBottomY)
          ..lineTo(edge.parentCenterX, midY)
          ..lineTo(edge.childCenterX, midY)
          ..lineTo(edge.childCenterX, edge.childTopY);
        canvas.drawPath(path, extraPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_FamilyTreeEdgePainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.extraEdges != extraEdges ||
      oldDelegate.color != color;
}

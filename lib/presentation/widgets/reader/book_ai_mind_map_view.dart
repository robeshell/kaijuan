import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ai/ai_mind_map.dart';
import '../../../ai/ai_mind_map_layout.dart';
import '../../../core/theme.dart';

class BookAiMindMapView extends StatefulWidget {
  const BookAiMindMapView({
    super.key,
    required this.map,
    required this.onLayoutChanged,
    required this.onOpenEvidence,
    this.onOpenFullscreen,
  });

  final AiBookMindMap map;
  final ValueChanged<AiMindMapLayout> onLayoutChanged;
  final ValueChanged<AiMindMapEvidence> onOpenEvidence;
  final VoidCallback? onOpenFullscreen;

  @override
  State<BookAiMindMapView> createState() => _BookAiMindMapViewState();
}

class _BookAiMindMapViewState extends State<BookAiMindMapView> {
  final _transformation = TransformationController();
  final _collapsed = <String>{};
  final _viewportKey = GlobalKey();
  late AiMindMapLayout _layout;
  bool _fitAfterLayoutChange = false;

  @override
  void initState() {
    super.initState();
    _layout = widget.map.layout;
    _applyLargeMapDefaults();
  }

  @override
  void didUpdateWidget(BookAiMindMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update from restored/persisted conversation state, but do not make the
    // visual switch wait for the parent session write. The card is allowed to
    // be reused by its stable message key, so relying on widget.map.layout
    // alone makes its segmented buttons appear inert for a frame or longer.
    if (oldWidget.map.layout != widget.map.layout) {
      _layout = widget.map.layout;
      _fitAfterLayoutChange = true;
    }
    if (oldWidget.map.scopeFingerprint != widget.map.scopeFingerprint ||
        oldWidget.map.createdAt != widget.map.createdAt ||
        oldWidget.map.nodes.length != widget.map.nodes.length) {
      _applyLargeMapDefaults();
      _transformation.value = Matrix4.identity();
    }
  }

  void _applyLargeMapDefaults() {
    _collapsed.clear();
    if (widget.map.nodes.length <= 80) return;
    final parentIds = widget.map.nodes
        .where((node) => node.parentId != null)
        .map((node) => node.parentId!)
        .toSet();
    _collapsed.addAll(
      widget.map.nodes
          .where((node) => node.level >= 2 && parentIds.contains(node.nodeId))
          .map((node) => node.nodeId),
    );
  }

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayMap = _layout == widget.map.layout
        ? widget.map
        : widget.map.copyWith(layout: _layout);
    final layout = AiMindMapLayoutEngine.layout(
      displayMap,
      collapsedNodeIds: _collapsed,
    );
    final children = <String, int>{};
    for (final node in widget.map.nodes.where(
      (node) => node.parentId != null,
    )) {
      children.update(node.parentId!, (value) => value + 1, ifAbsent: () => 1);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<AiMindMapLayout>(
                    segments: const [
                      ButtonSegment(
                        value: AiMindMapLayout.radial,
                        label: Text('放射'),
                      ),
                      ButtonSegment(
                        value: AiMindMapLayout.rightFacing,
                        label: Text('向右'),
                      ),
                      ButtonSegment(
                        value: AiMindMapLayout.bidirectional,
                        label: Text('双向'),
                      ),
                    ],
                    selected: {_layout},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty || selection.first == _layout) {
                        return;
                      }
                      final next = selection.first;
                      setState(() {
                        _layout = next;
                        // The embedded card has a much smaller viewport than
                        // the fullscreen route. Reusing the prior layout's
                        // transform can leave the new tree looking unchanged
                        // or outside its visible area.
                        _fitAfterLayoutChange = true;
                      });
                      widget.onLayoutChanged(next);
                    },
                  ),
                ),
              ),
              IconButton(
                tooltip: '层级列表',
                onPressed: _showAccessibleList,
                icon: const Icon(Icons.account_tree_outlined, size: 20),
              ),
              IconButton(
                tooltip: '重新居中',
                onPressed: () => _fit(layout.size),
                icon: const Icon(Icons.center_focus_strong_outlined, size: 20),
              ),
              if (widget.onOpenFullscreen != null)
                IconButton(
                  tooltip: '全屏查看',
                  onPressed: widget.onOpenFullscreen,
                  icon: const Icon(Icons.fullscreen, size: 20),
                ),
            ],
          ),
        ),
        if (widget.map.nodes.length > 80)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '大图已默认折叠深层，可逐支展开',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_fitAfterLayoutChange) {
                  _fitAfterLayoutChange = false;
                  _fit(layout.size);
                } else if (_transformation.value.isIdentity()) {
                  _fit(layout.size);
                }
              });
              return ClipRect(
                child: InteractiveViewer(
                  key: _viewportKey,
                  transformationController: _transformation,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(240),
                  minScale: 0.2,
                  maxScale: 3,
                  child: SizedBox.fromSize(
                    size: layout.size,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MindMapEdgePainter(
                              layout: layout,
                              color: context.appColors.outline,
                            ),
                          ),
                        ),
                        for (final node in widget.map.nodes)
                          if (layout.nodeRects[node.nodeId] case final rect?)
                            Positioned.fromRect(
                              rect: rect,
                              child: _MindMapNodeCard(
                                node: node,
                                childCount: children[node.nodeId] ?? 0,
                                collapsed: _collapsed.contains(node.nodeId),
                                onToggleCollapsed: () => setState(() {
                                  if (!_collapsed.add(node.nodeId)) {
                                    _collapsed.remove(node.nodeId);
                                  }
                                }),
                                onTap: () => _showNode(node),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _fit(Size canvas) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || canvas.isEmpty || box.size.isEmpty) return;
    final scale = math
        .min(box.size.width / canvas.width, box.size.height / canvas.height)
        .clamp(0.2, 1.15);
    final dx = (box.size.width - canvas.width * scale) / 2;
    final dy = (box.size.height - canvas.height * scale) / 2;
    _transformation.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setTranslationRaw(dx, dy, 0);
  }

  Future<void> _showAccessibleList() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            const ListTile(title: Text('思维导图层级')),
            for (final node in widget.map.nodes)
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: 12 + node.level * 18,
                  right: 8,
                ),
                leading: Icon(
                  node.level == 0 ? Icons.hub_outlined : Icons.circle,
                  size: node.level == 0 ? 20 : 8,
                ),
                title: Text(node.title),
                subtitle: node.summary.isEmpty
                    ? null
                    : Text(
                        node.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showNode(node);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNode(AiBookMindMapNode node) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(node.title, style: Theme.of(context).textTheme.titleMedium),
              if (node.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(node.summary),
              ],
              if (node.evidence.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('原文依据', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                for (final evidence in node.evidence)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      evidence.spanResolved
                          ? Icons.menu_book_outlined
                          : Icons.location_searching_outlined,
                    ),
                    title: Text('第 ${evidence.sectionIndex} 节'),
                    subtitle: Text(
                      evidence.quote,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    enabled: evidence.spanResolved,
                    onTap: evidence.spanResolved
                        ? () {
                            Navigator.of(context).pop();
                            widget.onOpenEvidence(evidence);
                          }
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MindMapNodeCard extends StatelessWidget {
  const _MindMapNodeCard({
    required this.node,
    required this.childCount,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onTap,
  });

  final AiBookMindMapNode node;
  final int childCount;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final root = node.level == 0;
    return Semantics(
      button: true,
      label: '${node.title}，第 ${node.level + 1} 层',
      child: Material(
        color: root
            ? colors.primary
            : colors.surfaceContainerHighest.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: root ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    node.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: root ? FontWeight.w700 : FontWeight.w600,
                      color: root ? colors.onPrimary : context.appPrimaryText,
                    ),
                  ),
                ),
                if (childCount > 0)
                  Semantics(
                    button: true,
                    toggled: !collapsed,
                    label: collapsed ? '展开分支' : '折叠分支',
                    child: IconButton(
                      tooltip: collapsed ? '展开分支' : '折叠分支',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 44,
                      ),
                      onPressed: onToggleCollapsed,
                      icon: Icon(
                        collapsed
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        size: 18,
                        color: root
                            ? colors.onPrimary
                            : context.appSecondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MindMapEdgePainter extends CustomPainter {
  const _MindMapEdgePainter({required this.layout, required this.color});

  final AiMindMapLayoutResult layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final edge in layout.edges) {
      final parent = layout.nodeRects[edge.parentId];
      final child = layout.nodeRects[edge.childId];
      if (parent == null || child == null) continue;
      final start = parent.center;
      final end = child.center;
      final control = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, start.dy, control.dx, control.dy)
        ..quadraticBezierTo(control.dx, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MindMapEdgePainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.color != color;
}

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
    this.revealOnMount = false,
    this.onRevealed,
    this.onPointerHoverChanged,
  });

  final AiBookMindMap map;
  final ValueChanged<AiMindMapLayout> onLayoutChanged;
  final ValueChanged<AiMindMapEvidence> onOpenEvidence;
  final VoidCallback? onOpenFullscreen;
  final bool revealOnMount;
  final VoidCallback? onRevealed;
  final ValueChanged<bool>? onPointerHoverChanged;

  @override
  State<BookAiMindMapView> createState() => _BookAiMindMapViewState();
}

class _BookAiMindMapViewState extends State<BookAiMindMapView> {
  final _transformation = TransformationController();
  final _collapsed = <String>{};
  final _viewportKey = GlobalKey();
  late AiMindMapLayout _layout;
  bool _fitAfterLayoutChange = false;
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    _layout = widget.map.layout;
    _applyLargeMapDefaults();
    _scheduleReveal();
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
    if (!oldWidget.revealOnMount && widget.revealOnMount) {
      _scheduleReveal();
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

  void _scheduleReveal() {
    if (!widget.revealOnMount || _revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Scrollable.ensureVisible(
        context,
        alignment: 0.02,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      if (mounted) widget.onRevealed?.call();
    });
  }

  void _claimCanvasPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // InteractiveViewer applies wheel zoom synchronously but does not claim
    // PointerSignalResolver. Claim it at the canvas boundary so an enclosing
    // conversation ListView cannot scroll from the same event.
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      if (resolvedEvent is PointerScrollEvent) {
        resolvedEvent.respond(allowPlatformDefault: false);
      }
    });
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
    final branchAccents = _resolveBranchAccents(
      widget.map.nodes,
      context.appColors,
    );
    final nodeLevels = <String, int>{
      for (final node in widget.map.nodes) node.nodeId: node.level,
    };
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
                child: MouseRegion(
                  onEnter: (_) => widget.onPointerHoverChanged?.call(true),
                  onExit: (_) => widget.onPointerHoverChanged?.call(false),
                  child: Listener(
                    onPointerSignal: _claimCanvasPointerSignal,
                    child: InteractiveViewer(
                      key: _viewportKey,
                      transformationController: _transformation,
                      constrained: false,
                      // Mind-map canvases should feel spatially unbounded. A
                      // finite margin creates an invisible wall close to the
                      // outermost nodes and prevents bringing an edge branch to
                      // the center for reading.
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.2,
                      maxScale: 6,
                      // Flutter treats PointerDeviceKind.trackpad scroll as pan
                      // unless this is explicit. Enabling it uses the framework's
                      // focal-point-preserving zoom path for both the embedded
                      // card and fullscreen explorer on desktop.
                      trackpadScrollCausesScale: true,
                      child: SizedBox.fromSize(
                        size: layout.size,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MindMapEdgePainter(
                                  layout: layout,
                                  branchAccents: branchAccents,
                                  nodeLevels: nodeLevels,
                                  fallbackColor: context.appColors.primary,
                                  dark:
                                      Theme.of(context).brightness ==
                                      Brightness.dark,
                                ),
                              ),
                            ),
                            for (final node in widget.map.nodes)
                              if (layout.nodeRects[node.nodeId]
                                  case final rect?)
                                Positioned.fromRect(
                                  rect: rect,
                                  child: _MindMapNodeCard(
                                    node: node,
                                    accent:
                                        branchAccents[node.nodeId] ??
                                        context.appColors.primary,
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
                    title: Text(_evidenceLocationLabel(evidence)),
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

  String _evidenceLocationLabel(AiMindMapEvidence evidence) {
    final scope = widget.map.scopeSectionIndices.length == 1
        ? '本章'
        : '第 ${evidence.sectionIndex} 节';
    if (!evidence.spanResolved) return '$scope · 位置未解析';
    final percent = (evidence.progressInSection.clamp(0, 1) * 100).round();
    return '$scope · 约 $percent% 处';
  }
}

class _MindMapNodeCard extends StatelessWidget {
  const _MindMapNodeCard({
    required this.node,
    required this.accent,
    required this.childCount,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onTap,
  });

  final AiBookMindMapNode node;
  final Color accent;
  final int childCount;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final root = node.level == 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(16);
    final baseSurface = root
        ? colors.surfaceContainerHighest
        : node.level <= 1
        ? colors.surfaceContainerHigh
        : colors.surfaceContainer;
    final tintOpacity = dark
        ? (node.level <= 1 ? 0.18 : 0.10)
        : (node.level <= 1 ? 0.10 : 0.055);
    final surface = root
        ? baseSurface
        : Color.alphaBlend(accent.withValues(alpha: tintOpacity), baseSurface);
    final shadowScale = context.appSkinEffects.shadowScale;
    final shadow = context.appGlass.shadow;
    final boxShadows = shadowScale <= 0
        ? const <BoxShadow>[]
        : <BoxShadow>[
            BoxShadow(
              color: shadow.withValues(alpha: shadow.a * (root ? 0.62 : 0.45)),
              blurRadius: (root ? 18 : 12) * shadowScale,
              offset: Offset(0, (root ? 5 : 3) * shadowScale),
            ),
          ];
    return Semantics(
      button: true,
      label:
          '${node.title}，第 ${node.level + 1} 层${node.summary.isEmpty ? '' : '，${node.summary}'}',
      child: DecoratedBox(
        key: ValueKey('mind-map-node-surface-${node.nodeId}'),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: radius,
          border: Border.all(
            color: root
                ? colors.primary.withValues(alpha: dark ? 0.68 : 0.46)
                : accent.withValues(alpha: dark ? 0.48 : 0.32),
            width: root ? 1.4 : 1,
          ),
          boxShadow: boxShadows,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: radius,
            mouseCursor: SystemMouseCursors.click,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return accent.withValues(alpha: 0.13);
              }
              if (states.contains(WidgetState.hovered)) {
                return accent.withValues(alpha: 0.075);
              }
              return null;
            }),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 7, 6, 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: context.appLabelSize,
                            height: 1.18,
                            fontWeight: root
                                ? FontWeight.w700
                                : FontWeight.w600,
                            letterSpacing: -0.1,
                            color: context.appPrimaryText,
                          ),
                        ),
                        if (node.summary.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            node.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: context.appCaptionSize,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                              color: context.appSecondaryText,
                            ),
                          ),
                        ],
                      ],
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
                          width: 44,
                          height: 44,
                        ),
                        onPressed: onToggleCollapsed,
                        icon: Icon(
                          collapsed
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          size: 18,
                          color: root ? colors.primary : accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MindMapEdgePainter extends CustomPainter {
  const _MindMapEdgePainter({
    required this.layout,
    required this.branchAccents,
    required this.nodeLevels,
    required this.fallbackColor,
    required this.dark,
  });

  final AiMindMapLayoutResult layout;
  final Map<String, Color> branchAccents;
  final Map<String, int> nodeLevels;
  final Color fallbackColor;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final edge in layout.edges) {
      final parent = layout.nodeRects[edge.parentId];
      final child = layout.nodeRects[edge.childId];
      if (parent == null || child == null) continue;
      final childLevel = nodeLevels[edge.childId] ?? 1;
      paint
        ..color = (branchAccents[edge.childId] ?? fallbackColor).withValues(
          alpha: dark
              ? (childLevel == 1 ? 0.62 : 0.43)
              : (childLevel == 1 ? 0.50 : 0.34),
        )
        ..strokeWidth = childLevel == 1 ? 2.2 : 1.55;
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
      oldDelegate.layout != layout ||
      oldDelegate.branchAccents != branchAccents ||
      oldDelegate.nodeLevels != nodeLevels ||
      oldDelegate.fallbackColor != fallbackColor ||
      oldDelegate.dark != dark;
}

Map<String, Color> _resolveBranchAccents(
  List<AiBookMindMapNode> nodes,
  ColorScheme colors,
) {
  if (nodes.isEmpty) return const {};
  AiBookMindMapNode? root;
  for (final node in nodes) {
    if (node.parentId == null) {
      root = node;
      break;
    }
  }
  if (root == null) return const {};
  final children = <String, List<AiBookMindMapNode>>{};
  for (final node in nodes) {
    final parentId = node.parentId;
    if (parentId == null) continue;
    children.putIfAbsent(parentId, () => []).add(node);
  }
  for (final siblings in children.values) {
    siblings.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.nodeId.compareTo(b.nodeId);
    });
  }
  final palette = <Color>[
    colors.primary,
    colors.tertiary,
    colors.secondary,
    Color.lerp(colors.primary, colors.tertiary, 0.33)!,
    Color.lerp(colors.tertiary, colors.secondary, 0.33)!,
    Color.lerp(colors.secondary, colors.primary, 0.33)!,
    Color.lerp(colors.primary, colors.tertiary, 0.67)!,
    Color.lerp(colors.tertiary, colors.secondary, 0.67)!,
    Color.lerp(colors.secondary, colors.primary, 0.67)!,
    Color.lerp(colors.primary, colors.tertiary, 0.50)!,
    Color.lerp(colors.tertiary, colors.secondary, 0.50)!,
    Color.lerp(colors.secondary, colors.primary, 0.50)!,
  ];
  final result = <String, Color>{root.nodeId: colors.primary};
  final visited = <String>{root.nodeId};

  void colorSubtree(AiBookMindMapNode node, Color accent) {
    if (!visited.add(node.nodeId)) return;
    result[node.nodeId] = accent;
    for (final child in children[node.nodeId] ?? const []) {
      colorSubtree(child, accent);
    }
  }

  final branches = children[root.nodeId] ?? const [];
  for (var index = 0; index < branches.length; index++) {
    colorSubtree(branches[index], palette[index % palette.length]);
  }
  for (final node in nodes) {
    result.putIfAbsent(node.nodeId, () => colors.primary);
  }
  return Map.unmodifiable(result);
}

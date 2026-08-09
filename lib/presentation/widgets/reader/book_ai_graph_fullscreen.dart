import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/theme.dart';
import 'book_ai_entity_sheet.dart';
import 'book_ai_graph_view.dart';

/// Fullscreen knowledge-graph explorer: a large force-directed view with the
/// same data as the tab, plus a per-vertex detail sheet on tap.
class BookAiGraphFullscreen extends StatefulWidget {
  const BookAiGraphFullscreen({
    super.key,
    required this.entities,
    required this.relations,
    required this.graph,
    required this.gateByProgress,
    required this.readThrough,
    this.title = '知识图谱',
    this.onJumpToEvidence,
  });

  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;

  /// The full graph the (already gated) [entities]/[relations] slices came
  /// from — the entity detail sheet re-derives its own relation/evidence
  /// lists from it, so the vertex card matches the panel's card exactly.
  final AiBookGraph graph;
  final bool gateByProgress;
  final int readThrough;
  final String title;

  /// Called when the user taps an evidence row: jump the reader to the
  /// quoted section (the caller owns the pop of this route).
  final void Function(AiGraphEvidence evidence)? onJumpToEvidence;

  @override
  State<BookAiGraphFullscreen> createState() => _BookAiGraphFullscreenState();
}

class _BookAiGraphFullscreenState extends State<BookAiGraphFullscreen> {
  int _viewEpoch = 0;
  bool _showGestureHint = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '重置视图',
            onPressed: () => setState(() => _viewEpoch++),
            icon: const Icon(Icons.center_focus_strong_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: BookAiGraphView(
                        key: ValueKey(_viewEpoch),
                        entities: widget.entities,
                        relations: widget.relations,
                        onVertexTap: (entityId) =>
                            _showVertexCard(context, entityId),
                        scrollZoomEnabled: true,
                      ),
                    ),
                    if (_showGestureHint)
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: Material(
                          color: context.appColors.surfaceContainerHighest
                              .withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 12,
                                ),
                                child: Text(
                                  context.appIsCompact
                                      ? '缩放与拖动浏览'
                                      : '双指或滚轮缩放 · 拖动平移',
                                  style: TextStyle(
                                    fontSize: context.appCaptionSize,
                                    color: context.appSecondaryText,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '隐藏操作提示',
                                onPressed: () =>
                                    setState(() => _showGestureHint = false),
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              BookAiGraphEntityNavigator(
                entities: widget.entities,
                onEntityTap: (entityId) => _showVertexCard(context, entityId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVertexCard(BuildContext context, String entityId) {
    // Same card as the graph tab's entity sheet (the sheet pops itself
    // before invoking the evidence callback; the callback's owner then
    // closes this route after the jump, as the hand-rolled card did).
    showBookAiEntitySheetById(
      context,
      entityId,
      graph: widget.graph,
      gateByProgress: widget.gateByProgress,
      readThrough: widget.readThrough,
      onJumpToEvidence: widget.onJumpToEvidence,
    );
  }
}

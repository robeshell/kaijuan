import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../ai/ai_graph_family_tree.dart';
import '../../../core/theme.dart';
import 'book_ai_entity_sheet.dart';
import 'book_ai_graph_family_tree_view.dart';

/// Fullscreen family-tree explorer: the same tree as the tab, but filling
/// the window with a deep zoom range and desktop wheel zoom (the panel's
/// fixed 380px viewport and the sheet's scroll ownership make deep zoom
/// awkward there).
class BookAiGraphFamilyTreeFullscreen extends StatefulWidget {
  const BookAiGraphFamilyTreeFullscreen({
    super.key,
    required this.tree,
    required this.graph,
    required this.gateByProgress,
    required this.readThrough,
    this.title = '家族树',
    this.onJumpToEvidence,
  });

  /// The already progress-gated tree built by the panel (same instance, so
  /// both views agree on parking/isolation).
  final AiFamilyTree tree;

  /// Full graph the tree was derived from — the entity detail sheet
  /// re-derives its own relation/evidence lists from it.
  final AiBookGraph graph;
  final bool gateByProgress;
  final int readThrough;
  final String title;

  /// Called when the user taps an evidence row: jump the reader to the
  /// quoted section (the caller owns the pop of this route).
  final void Function(AiGraphEvidence evidence)? onJumpToEvidence;

  @override
  State<BookAiGraphFamilyTreeFullscreen> createState() =>
      _BookAiGraphFamilyTreeFullscreenState();
}

class _BookAiGraphFamilyTreeFullscreenState
    extends State<BookAiGraphFamilyTreeFullscreen> {
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
          // Big trees open fitted far below 1:1, so the zoom ceiling is
          // generous (a single branch readable at half-window size) and the
          // floor low enough to see the whole forest at once.
          child: Stack(
            children: [
              Positioned.fill(
                child: BookAiGraphFamilyTreeView(
                  key: ValueKey(_viewEpoch),
                  tree: widget.tree,
                  onVertexTap: (entityId) => showBookAiEntitySheetById(
                    context,
                    entityId,
                    graph: widget.graph,
                    gateByProgress: widget.gateByProgress,
                    readThrough: widget.readThrough,
                    onJumpToEvidence: widget.onJumpToEvidence,
                  ),
                  viewportHeight: null,
                  minScale: 0.05,
                  maxScale: 12,
                ),
              ),
              if (_showGestureHint)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: Material(
                    color: context.appColors.surfaceContainerHighest.withValues(
                      alpha: 0.94,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 12),
                          child: Text(
                            context.appIsCompact ? '缩放与拖动浏览' : '双指或滚轮缩放 · 拖动平移',
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
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import 'book_ai_graph_components.dart';
import 'book_ai_graph_sort.dart';
import 'book_ai_graph_view.dart';

/// Pure graph-detail projection.
///
/// Scope selection, generation, persistence, dialogs and navigation remain in
/// the workspace controller/sheet. This widget only renders a frozen graph
/// projection and reports user intent through callbacks.
class BookAiGraphContentView extends StatelessWidget {
  const BookAiGraphContentView({
    required this.graph,
    required this.listEpoch,
    required this.scrollController,
    required this.activeWorkTitle,
    required this.busy,
    required this.error,
    required this.viewMode,
    required this.connectedEntities,
    required this.visibleEntities,
    required this.orderedMain,
    required this.orderedIsolated,
    required this.foldIsolated,
    required this.queryController,
    required this.query,
    required this.sortOrder,
    required this.listKind,
    required this.titleSize,
    required this.bodySize,
    required this.onCloseWork,
    required this.onRegenerate,
    required this.onDelete,
    this.hiddenEntityCount = 0,
    this.onShowHidden,
    required this.onViewModeChanged,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onSortChanged,
    required this.onGraphVertexTap,
    required this.onOpenGraphFullscreen,
    required this.buildFamilyTree,
    required this.buildLocationChain,
    required this.buildMainEntities,
    required this.buildIsolatedEntities,
    super.key,
  });

  final AiBookGraph graph;
  final int listEpoch;
  final ScrollController scrollController;
  final String? activeWorkTitle;
  final bool busy;
  final String? error;
  final BookAiGraphViewMode viewMode;
  final List<AiGraphEntity> connectedEntities;
  final List<AiGraphEntity> visibleEntities;
  final List<AiGraphEntity> orderedMain;
  final List<AiGraphEntity> orderedIsolated;
  final bool foldIsolated;
  final TextEditingController queryController;
  final String query;
  final GraphEntitySortOrder sortOrder;
  final GraphEntityListKind listKind;
  final double titleSize;
  final double bodySize;
  final VoidCallback onCloseWork;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;
  final int hiddenEntityCount;
  final VoidCallback? onShowHidden;
  final ValueChanged<BookAiGraphViewMode> onViewModeChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<GraphEntitySortOrder> onSortChanged;
  final ValueChanged<String> onGraphVertexTap;
  final VoidCallback onOpenGraphFullscreen;
  final Widget Function() buildFamilyTree;
  final Widget Function() buildLocationChain;
  final Widget Function(List<AiGraphEntity>) buildMainEntities;
  final Widget Function(List<AiGraphEntity>) buildIsolatedEntities;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListView(
      key: ValueKey<int>(listEpoch),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          children: [
            if (activeWorkTitle != null)
              IconButton(
                tooltip: '全部作品',
                onPressed: busy ? null : onCloseWork,
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
            Expanded(
              child: Text(
                activeWorkTitle != null
                    ? '《$activeWorkTitle》图谱'
                    : (graph.includesUnread ? '全书图谱' : '已读章节图谱'),
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                  color: context.appPrimaryText,
                ),
              ),
            ),
            IconButton(
              tooltip: '重新生成图谱',
              onPressed: busy ? null : onRegenerate,
              icon: const Icon(KaijuanIcons.refresh, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              enabled: !busy,
              onSelected: (value) {
                switch (value) {
                  case 'hidden':
                    onShowHidden?.call();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                if (hiddenEntityCount > 0)
                  PopupMenuItem(
                    value: 'hidden',
                    child: Text('已隐藏的实体（$hiddenEntityCount）'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('删除图谱')),
              ],
            ),
          ],
        ),
        if (shouldShowGraphViewNavigation(graph: graph, generating: busy)) ...[
          const SizedBox(height: 10),
          BookAiGraphViewNavigation(
            graph: graph,
            selected: viewMode,
            onSelected: onViewModeChanged,
          ),
        ],
        if (!busy && error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: colors.error,
            ),
          ),
        ],
        if (!busy && viewMode == BookAiGraphViewMode.graph) ...[
          const SizedBox(height: 12),
          if (graph.relations.isEmpty)
            Text(
              '本书暂无可展示的实体关系。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: bodySize,
                color: context.appSecondaryText,
              ),
            )
          else ...[
            Semantics(
              label: '关系图说明：连线文字是关系类型，单箭头表示关系方向，双向符号表示对等关系。点击节点查看关系和出处。',
              child: Text(
                '连线文字为关系类型 · 箭头为方向 · 点击节点查看出处',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                BookAiGraphView(
                  entities: connectedEntities,
                  relations: graph.relations,
                  onVertexTap: onGraphVertexTap,
                  height: 300,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.9,
                    ),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: '全屏查看',
                      iconSize: 18,
                      icon: const Icon(KaijuanIcons.maximize),
                      onPressed: onOpenGraphFullscreen,
                    ),
                  ),
                ),
              ],
            ),
            BookAiGraphEntityNavigator(
              entities: connectedEntities,
              onEntityTap: onGraphVertexTap,
            ),
          ],
          const SizedBox(height: 10),
        ],
        if (!busy && viewMode == BookAiGraphViewMode.familyTree) ...[
          const SizedBox(height: 12),
          buildFamilyTree(),
          const SizedBox(height: 10),
        ],
        if (viewMode != BookAiGraphViewMode.graph &&
            viewMode != BookAiGraphViewMode.familyTree) ...[
          const SizedBox(height: 12),
          Row(
            key: const ValueKey<String>('graphEntitySearch'),
            children: [
              Expanded(
                child: TextField(
                  controller: queryController,
                  onChanged: onQueryChanged,
                  style: context.appInputTextStyle.copyWith(
                    color: context.appPrimaryText,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索',
                    hintStyle: context.appInputTextStyle.copyWith(
                      color: context.appMutedText,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    constraints: BoxConstraints(
                      minHeight: context.appIsCompact ? 44 : 40,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    prefixIcon: const Icon(KaijuanIcons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<GraphEntitySortOrder>(
                tooltip: '排序',
                initialValue: sortOrder,
                onSelected: onSortChanged,
                itemBuilder: (_) => [
                  for (final order in graphSortOrdersFor(listKind))
                    PopupMenuItem(
                      value: order,
                      child: Text(graphSortOrderLabel(order, listKind)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        KaijuanIcons.sort,
                        size: 18,
                        color: context.appSecondaryText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        graphSortOrderLabel(sortOrder, listKind),
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: context.appSecondaryText,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        KaijuanIcons.chevronDown,
                        size: 16,
                        color: context.appMutedText,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (viewMode == BookAiGraphViewMode.locations &&
              (graph.narration?.feature('geography') ?? 0) >= 0.5)
            buildLocationChain(),
          if (visibleEntities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    query.trim().isEmpty
                        ? '本书暂无${bookAiGraphViewLabel(viewMode)}实体。'
                        : '没有匹配“${query.trim()}”的实体。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: bodySize,
                      color: context.appSecondaryText,
                    ),
                  ),
                  if (query.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: onClearQuery,
                      child: const Text('清除搜索'),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            buildMainEntities(orderedMain),
            buildIsolatedEntities(orderedIsolated),
          ],
        ],
      ],
    );
  }
}

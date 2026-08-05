import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import 'ai_relation_row.dart';
import 'book_ai_graph_view.dart';

/// Fullscreen knowledge-graph explorer: a large force-directed view with the
/// same data as the tab, plus a per-vertex detail sheet on tap.
class BookAiGraphFullscreen extends StatelessWidget {
  const BookAiGraphFullscreen({
    super.key,
    required this.entities,
    required this.relations,
    this.title = '知识图谱',
    this.onJumpToEvidence,
  });

  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;
  final String title;

  /// Called when the user taps an evidence row: jump the reader to the
  /// quoted section (the caller owns the pop of this route).
  final void Function(AiGraphEvidence evidence)? onJumpToEvidence;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '滚轮缩放 · 拖动平移',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: BookAiGraphView(
            entities: entities,
            relations: relations,
            onVertexTap: (name) => _showVertexCard(context, name),
            scrollZoomEnabled: true,
          ),
        ),
      ),
    );
  }

  void _showVertexCard(BuildContext context, String name) {
    final colors = Theme.of(context).colorScheme;
    final entity = entities
        .where((e) => e.name == name || e.aliases.contains(name))
        .firstOrNull;
    if (entity == null) return;
    final occurrences = entity.chapterFreq.values.fold<int>(
      0,
      (sum, v) => sum + v,
    );
    final relations = this.relations
        .where((r) => r.source == entity.name || r.target == entity.name)
        .toList(growable: false);
    final evidence = entity.evidence;
    Widget sectionBadge(int count) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entity.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$occurrences 次',
                  style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            if (entity.aliases.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '别名：${entity.aliases.join('、')}',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ],
            if (entity.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  entity.description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
            if (relations.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '关系',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  sectionBadge(relations.length),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in relations)
                AiRelationRow(
                  relation: r,
                  selfName: entity.name,
                ),
            ],
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '出处',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  sectionBadge(evidence.length),
                ],
              ),
              const SizedBox(height: 8),
              for (final item in evidence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onJumpToEvidence == null
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              onJumpToEvidence!(item);
                            },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '§${item.sectionIndex}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.quote,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: item.spanResolved
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Icon(
                                KaijuanIcons.forward,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            if (relations.isEmpty && evidence.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '该实体暂无可见内容。',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

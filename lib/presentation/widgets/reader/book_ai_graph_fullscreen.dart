import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import 'book_ai_graph_view.dart';

/// Fullscreen knowledge-graph explorer: a large force-directed view with the
/// same data as the tab, plus a per-vertex detail sheet on tap.
class BookAiGraphFullscreen extends StatelessWidget {
  const BookAiGraphFullscreen({
    super.key,
    required this.entities,
    required this.relations,
    this.title = '知识图谱',
  });

  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;
  final String title;

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
                  '出现 $occurrences 次',
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
              const SizedBox(height: 10),
              Text(
                entity.description,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.onSurface,
                ),
              ),
            ],
            if (relations.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '关系（${relations.length}）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              for (final r in relations.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${r.source} —${r.type}→ ${r.target}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (relations.length > 12)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '… 另有 ${relations.length - 12} 条关系',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

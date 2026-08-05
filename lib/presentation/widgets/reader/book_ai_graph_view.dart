import 'package:flutter/material.dart';
import 'package:flutter_graph_view/flutter_graph_view.dart';

import '../../../ai/ai_graph.dart';

/// Force-directed view of the book knowledge graph.
///
/// Entities become type-colored vertices (person / location / event), typed
/// relations become edges. Hover shows the entity card summary; tapping a
/// vertex bubbles its name up so the list below can scroll and highlight it.
///
/// Density guard: beyond [_maxVertices] the most frequent entities win, so
/// the graph never degenerates into a hairball. 60 keeps labels legible
/// while still showing the core cast; the rest stay in the list below.
class BookAiGraphView extends StatelessWidget {
  const BookAiGraphView({
    super.key,
    required this.entities,
    required this.relations,
    required this.onVertexTap,
    this.height,
  });

  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;

  /// Called with the tapped entity's canonical name.
  final ValueChanged<String> onVertexTap;

  /// Fixed graph area height; null lets the parent constrain it (fullscreen).
  final double? height;

  static const int _maxVertices = 60;

  List<AiGraphEntity> _topEntities() {
    final sorted = [...entities]..sort(_byFrequencyThenName);
    return sorted.take(_maxVertices).toList(growable: false);
  }

  static int _byFrequencyThenName(AiGraphEntity a, AiGraphEntity b) {
    final fa = a.chapterFreq.values.fold<int>(0, (sum, v) => sum + v);
    final fb = b.chapterFreq.values.fold<int>(0, (sum, v) => sum + v);
    if (fa != fb) return fb.compareTo(fa);
    return a.name.compareTo(b.name);
  }

  String _typeLabel(AiGraphEntityType type) => switch (type) {
    AiGraphEntityType.person => '人物',
    AiGraphEntityType.location => '地点',
    AiGraphEntityType.event => '事件',
  };

  @override
  Widget build(BuildContext context) {
    if (entities.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;

    final selected = _topEntities();
    final selectedIds = {for (final e in selected) e.name};
    final relationCount = <String, int>{for (final e in selected) e.name: 0};
    final selectedRels = relations
        .where(
          (r) =>
              selectedIds.contains(r.source) && selectedIds.contains(r.target),
        )
        .toList(growable: false);
    for (final r in selectedRels) {
      relationCount[r.source] = (relationCount[r.source] ?? 0) + 1;
      relationCount[r.target] = (relationCount[r.target] ?? 0) + 1;
    }

    final data = <String, Object?>{
      'vertexes': [
        for (final e in selected)
          {
            'id': e.name,
            'tag': _typeLabel(e.type),
            'tags': [_typeLabel(e.type)],
            'freq': e.chapterFreq.values.fold<int>(0, (sum, v) => sum + v),
            'relations': relationCount[e.name] ?? 0,
            'description': e.description,
          },
      ],
      'edges': [
        for (final r in selectedRels)
          {
            'srcId': r.source,
            'dstId': r.target,
            'edgeName': r.type,
            'ranking': r.weight.toInt(),
          },
      ],
    };

    final options = Options()
      ..enableHit = true
      ..panelDelay = const Duration(milliseconds: 250)
      ..graphStyle = (GraphStyle()
        ..tagColorByIndex = [
          colors.primary.withValues(alpha: 0.85),
          Colors.teal,
          Colors.amber.shade700,
        ]
        ..vertexTextStyleGetter = (vertex, shape) => TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colors.onSurface,
        ))
      ..vertexShape = VertexCircleShape()
      ..edgeShape = EdgeLineShape()
      ..vertexPanelBuilder = (hoverVertex) {
        final c = hoverVertex.g!.options!.localToGlobal(hoverVertex.position);
        final data = Map<String, Object?>.from(hoverVertex.data as Map);
        return Stack(
          children: [
            Positioned(
              left: c.x + hoverVertex.radius + 6,
              top: c.y - 26,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 190,
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${data['id']}（${data['tag']}）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '出现 ${data['freq']} 次 · 关系 ${data['relations']}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }
      ..onVertexTapDown = (vertex, _) => onVertexTap(vertex.id as String);

    final graphArea = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: FlutterGraphWidget(
          data: data,
          convertor: MapConvertor(),
          algorithm: RandomAlgorithm(
            decorators: [
              CoulombDecorator(k: 14),
              HookeDecorator(length: 150),
              CoulombCenterDecorator(),
              HookeCenterDecorator(),
              ForceDecorator(),
              ForceMotionDecorator(),
              TimeCounterDecorator(),
            ],
          ),
          options: options,
        ),
      ),
    );
    if (height == null) {
      return SizedBox(width: double.infinity, child: graphArea);
    }
    return SizedBox(height: height, width: double.infinity, child: graphArea);
  }
}

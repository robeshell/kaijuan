import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
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
    this.scrollZoomEnabled = false,
  });

  final List<AiGraphEntity> entities;
  final List<AiGraphRelation> relations;

  /// Called with the tapped entity's canonical name.
  final ValueChanged<String> onVertexTap;

  /// Fixed graph area height; null lets the parent constrain it (fullscreen).
  final double? height;

  /// When false (tab embed), the wheel is left to the surrounding list:
  /// flutter_graph_view's default scroll-to-zoom consumes the pointer event
  /// and mutates scale inside pointer dispatch, tripping Flutter's
  /// MouseTracker debug assertion on macOS. Fullscreen enables it.
  final bool scrollZoomEnabled;

  static const int _maxVertices = 60;

  List<AiGraphEntity> _topEntities() {
    // Reference entities (cited outsiders like 罗素 in an essay) never make
    // it into the force-directed core, even if they are frequent.
    final core = entities
        .where((e) => e.scope == AiGraphEntityScope.setting)
        .toList(growable: false);
    final sorted = [...core]..sort(_byFrequencyThenName);
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
      ..backgroundBuilder = (context) {
        return _DotGridBackground(color: colors.outlineVariant);
      }
      ..graphStyle = (GraphStyle()
        ..tagColorByIndex = [
          colors.primary.withValues(alpha: 0.85),
          Colors.teal,
          Colors.amber.shade700,
        ]
        // 1.0 disables the hover dim-out: moving the mouse flips
        // hoverVertex between nodes and the opacity jump reads as flicker.
        // Vertex state stays tracked (tap detection needs hoverVertex).
        ..hoverOpacity = 1.0
        ..vertexTextStyleGetter = (vertex, shape) => TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
          // Soft halo around the label so it stays readable over edges and
          // other nodes (flutter_graph_view draws labels on the canvas with
          // no background of their own).
          shadows: [
            Shadow(
              color: colors.surfaceContainerLow.withValues(alpha: 0.95),
              blurRadius: 8,
            ),
            Shadow(
              color: colors.surfaceContainerLow.withValues(alpha: 0.9),
              blurRadius: 2,
            ),
          ],
        ))
      ..vertexShape =
          _RingVertexShape(ringColor: colors.surfaceContainerLow)
      ..edgeShape = _FadedEdgeLineShape()
      ..onVertexTapUp = (vertex, _) {
        // Deferred: mutating state inside the pointer-event dispatch trips
        // Flutter's MouseTracker debug assertion on macOS (and onVertexTapDown
        // is never invoked by this package — TapUp is the live callback).
        final name = vertex.id as String;
        Future.microtask(() => onVertexTap(name));
      };

    // Set outside the cascade: the handler needs to read options.scale/offset,
    // and Dart forbids referencing the cascade target inside its own chain.
    options.onPointerSignal = (event) {
      if (!scrollZoomEnabled) return;
      if (event is! PointerScrollEvent) return;
      // 4x the package default (0.05/notch): one wheel notch is now a
      // visible step instead of an imperceptible 5%.
      final zoomDelta =
          event.scrollDelta.dy.sign * options.zoomPerScrollUnit * 4;
      if (options.scale.value + zoomDelta <= 0) return;
      // Deferred: mutating scale inside the pointer dispatch re-enters
      // setState through the scale listener and trips Flutter's
      // MouseTracker debug assertion (same trap as onVertexTapUp).
      Future.microtask(() {
        final oz = options.scale.value;
        options.scale.value += zoomDelta;
        options.keepCenter(
          oz,
          options.scale.value,
          options.size.value,
          event.localPosition,
          options.offset,
        );
      });
    };

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
              // ForceMotionDecorator/TimeCounterDecorator dropped: their
              // per-frame rebuild races pointer dispatch and trips
              // MouseTracker._debugDuringDeviceUpdate on macOS debug.
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

/// Circle vertex with a crisp surface-colored ring: at graph density the
/// fill-only circles melt into each other, the ring keeps them separated
/// (and doubles as a soft shadow edge against the dot grid).
class _RingVertexShape extends VertexCircleShape {
  _RingVertexShape({required this.ringColor});

  final Color ringColor;

  @override
  void render(
    Vertex vertex,
    ui.Canvas canvas,
    Paint paint,
    List<Paint> paintLayers,
  ) {
    super.render(vertex, canvas, paint, paintLayers);
    canvas.drawCircle(
      ui.Offset.zero,
      vertex.radiusZoom,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / vertex.zoom
        ..color = ringColor,
    );
  }
}

/// Thinner, translucent edges so the vertices carry the visual weight.
/// Hover still thickens the hovered edge (the only hover feedback left
/// after the flicker fix).
class _FadedEdgeLineShape extends EdgeLineShape {
  @override
  Paint getPaint(Edge edge) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (edge.isHovered ? 3 : 1) / edge.zoom;
    final from = edge.start.colors.lastOrNull ?? Colors.grey;
    final to = edge.end?.colors.lastOrNull ?? from;
    paint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(len(edge), 0),
      [
        from.withValues(alpha: 0.45),
        to.withValues(alpha: 0.45),
      ],
    );
    return paint;
  }
}

/// Sparse dot grid behind the graph — reads as "map" instead of "floating
/// circles on a blank panel".
class _DotGridBackground extends StatelessWidget {
  const _DotGridBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(color: color.withValues(alpha: 0.6)),
      child: const SizedBox.expand(),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;

  static const double _step = 28;
  static const double _dotRadius = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = _step / 2; y < size.height; y += _step) {
      for (var x = _step / 2; x < size.width; x += _step) {
        canvas.drawCircle(Offset(x, y), _dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

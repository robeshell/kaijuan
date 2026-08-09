import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_graph_view/flutter_graph_view.dart';

import '../../../ai/ai_graph.dart';
import 'book_ai_graph_tiles.dart';

/// Force-directed view of the book knowledge graph.
///
/// Entities become type-colored vertices (person / location / event), typed
/// relations become edges. Tapping a vertex bubbles its name up so the list
/// below can scroll and highlight it.
///
/// Layout & performance — the package's stock setup fights us three ways
/// (verified against flutter_graph_view 2.1.0 sources):
/// - `FlutterGraphWidget` mints a new `Graph` (used as its ValueKey) per
///   instance, so every parent setState used to rebuild the whole canvas and
///   re-randomize positions. Everything heavy is therefore hoisted into this
///   State and only rebuilt when the content signature or theme changes.
/// - The stock `RandomAlgorithm` + force decorators computes O(n²) forces
///   every frame that nothing consumes (ForceMotionDecorator was removed for
///   a macOS MouseTracker assertion) — positions were random and frozen. We
///   replace it with [_ForceLayoutAlgorithm]: a deterministic Fruchterman-
///   Reingold pass computed once in `onGraphLoad`, then injected as fixed
///   positions. Real clustering, zero per-frame simulation.
/// - The package's ticker repaints forever (`GraphPainter.shouldRepaint` is
///   unconditionally true). After layout we set `options.pause`; any pointer
///   activity wakes the ticker and a 600ms debounce puts it back to sleep,
///   so hover/drag/tap behave exactly as before while idle CPU drops to 0.
///
/// Density guard: beyond [_maxVertices] the most frequent entities win, so
/// the graph never degenerates into a hairball. 60 keeps labels legible
/// while still showing the core cast; the rest stay in the list below.
class BookAiGraphView extends StatefulWidget {
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

  /// Called with the tapped entity's stable ID.
  final ValueChanged<String> onVertexTap;

  /// Fixed graph area height; null lets the parent constrain it (fullscreen).
  final double? height;

  /// When false (tab embed), the wheel is left to the surrounding list:
  /// flutter_graph_view's default scroll-to-zoom consumes the pointer event
  /// and mutates scale inside pointer dispatch, tripping Flutter's
  /// MouseTracker debug assertion on macOS. Fullscreen enables it.
  final bool scrollZoomEnabled;

  static const int _maxVertices = 60;

  @override
  State<BookAiGraphView> createState() => _BookAiGraphViewState();
}

class _BookAiGraphViewState extends State<BookAiGraphView> {
  late Options _options;
  late Widget _graphWidget;
  Timer? _sleepTimer;
  bool _initialized = false;
  Object? _themeKey;
  String _signature = '';

  List<AiGraphEntity> _topEntities() {
    // Reference entities (cited outsiders like 罗素 in an essay) never make
    // it into the force-directed core, even if they are frequent.
    final core = widget.entities
        .where((e) => e.scope == AiGraphEntityScope.setting)
        .toList(growable: false);
    final sorted = [...core]..sort(_byFrequencyThenName);
    if (sorted.length <= BookAiGraphView._maxVertices) return sorted;

    // Reserve room for connector endpoints. A frequency-only top-N can drop
    // a low-frequency bridge and visually split one real cluster into two.
    final byId = {for (final entity in core) entity.id: entity};
    final byUniqueName = <String, AiGraphEntity>{};
    final duplicateNames = <String>{};
    for (final entity in core) {
      if (byUniqueName.containsKey(entity.name)) {
        duplicateNames.add(entity.name);
      }
      byUniqueName[entity.name] = entity;
    }
    for (final name in duplicateNames) {
      byUniqueName.remove(name);
    }
    AiGraphEntity? endpoint(AiGraphRelation relation, bool source) {
      final id = source ? relation.sourceId : relation.targetId;
      if (id.isNotEmpty) return byId[id];
      return byUniqueName[source ? relation.source : relation.target];
    }

    final selected = <String, AiGraphEntity>{
      for (final entity in sorted.take(45)) entity.id: entity,
    };
    final edges = [...widget.relations]
      ..sort((left, right) => right.weight.compareTo(left.weight));
    var changed = true;
    while (changed && selected.length < BookAiGraphView._maxVertices) {
      changed = false;
      for (final relation in edges) {
        final source = endpoint(relation, true);
        final target = endpoint(relation, false);
        if (source == null || target == null) continue;
        final sourceIn = selected.containsKey(source.id);
        final targetIn = selected.containsKey(target.id);
        if (sourceIn == targetIn) continue;
        final bridge = sourceIn ? target : source;
        selected[bridge.id] = bridge;
        changed = true;
        if (selected.length >= BookAiGraphView._maxVertices) break;
      }
    }
    for (final entity in sorted) {
      selected.putIfAbsent(entity.id, () => entity);
      if (selected.length >= BookAiGraphView._maxVertices) break;
    }
    return selected.values.toList(growable: false);
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
    AiGraphEntityType.organization => '组织',
    AiGraphEntityType.item => '物件',
    AiGraphEntityType.concept => '概念',
    AiGraphEntityType.creature => '非人角色',
  };

  /// Content fingerprint: parent rebuilds mint fresh entity/relation lists
  /// on every setState, so identity comparison is useless. The graph widget
  /// is only rebuilt when the actual content changes (regeneration, progress
  /// gate toggle) — otherwise positions, zoom and pan survive untouched.
  String _computeSignature() {
    final b = StringBuffer();
    for (final e in widget.entities) {
      b
        ..write(e.id)
        ..write('');
    }
    b.write('');
    for (final r in widget.relations) {
      b
        ..write(r.sourceId)
        ..write('>')
        ..write(r.targetId)
        ..write(':')
        ..write(r.type)
        ..write(':')
        ..write(r.weight)
        ..write('');
    }
    return b.toString();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    final themeKey = Object.hash(
      colors.brightness,
      colors.primary,
      colors.onSurface,
      colors.surfaceContainerLow,
    );
    if (!_initialized) {
      _initialized = true;
      _themeKey = themeKey;
      _signature = _computeSignature();
      _buildGraphObjects();
      _wake();
      return;
    }
    if (themeKey != _themeKey) {
      _themeKey = themeKey;
      _rebuildGraphObjects();
    }
  }

  @override
  void didUpdateWidget(covariant BookAiGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _computeSignature();
    if (signature != _signature) {
      _signature = signature;
      _rebuildGraphObjects();
    }
  }

  void _rebuildGraphObjects() {
    _sleepTimer?.cancel();
    setState(_buildGraphObjects);
    _wake();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  /// Wake the package's ticker for interaction, then re-sleep after 600ms
  /// idle. While awake everything (hover tracking, drag, tap) repaints at
  /// vsync exactly like the stock setup; while asleep the canvas only
  /// repaints on zoom/pan (scale/offset listeners bump the timestamp).
  void _wake() {
    final active = _sleepTimer?.isActive ?? false;
    _sleepTimer?.cancel();
    if (!active && _options.pause.value) {
      _options.pause.value = false;
    }
    _sleepTimer = Timer(const Duration(milliseconds: 600), () {
      _options.pause.value = true;
    });
  }

  void _buildGraphObjects() {
    final colors = Theme.of(context).colorScheme;

    final selected = _topEntities();
    final selectedIds = {for (final e in selected) e.id};
    final uniqueNames = <String, String>{};
    final duplicateNames = <String>{};
    for (final entity in selected) {
      if (uniqueNames.containsKey(entity.name)) duplicateNames.add(entity.name);
      uniqueNames[entity.name] = entity.id;
    }
    for (final name in duplicateNames) {
      uniqueNames.remove(name);
    }
    String? endpointId(AiGraphRelation relation, bool source) {
      final id = source ? relation.sourceId : relation.targetId;
      if (id.isNotEmpty) return id;
      return uniqueNames[source ? relation.source : relation.target];
    }

    final relationCount = <String, int>{for (final e in selected) e.id: 0};
    final selectedRels = widget.relations
        .where(
          (r) =>
              selectedIds.contains(endpointId(r, true)) &&
              selectedIds.contains(endpointId(r, false)),
        )
        .toList(growable: false);
    for (final r in selectedRels) {
      final sourceId = endpointId(r, true)!;
      final targetId = endpointId(r, false)!;
      relationCount[sourceId] = (relationCount[sourceId] ?? 0) + 1;
      relationCount[targetId] = (relationCount[targetId] ?? 0) + 1;
    }
    final labels = {for (final entity in selected) entity.id: entity.name};

    final data = <String, Object?>{
      'vertexes': [
        for (final e in selected)
          {
            'id': e.id,
            'tag': _typeLabel(e.type),
            'tags': [_typeLabel(e.type)],
            'freq': e.chapterFreq.values.fold<int>(0, (sum, v) => sum + v),
            'relations': relationCount[e.id] ?? 0,
            'description': e.description,
          },
      ],
      'edges': [
        for (final r in selectedRels)
          {
            'srcId': endpointId(r, true),
            'dstId': endpointId(r, false),
            'edgeName': r.type,
            'ranking': r.weight.toInt(),
          },
      ],
    };

    _options = Options()
      ..enableHit = true
      ..backgroundBuilder = (context) {
        return _DotGridBackground(
          color: Theme.of(context).colorScheme.outlineVariant,
        );
      }
      ..graphStyle = (GraphStyle()
        // Vertex colors keyed by the exact _typeLabel strings, from the
        // same source as the list tiles' type dots (tagColor takes
        // priority over tagColorByIndex, so 势力 no longer falls back to
        // the package's random palette).
        ..tagColor = {
          for (final type in AiGraphEntityType.values)
            _typeLabel(type): graphEntityTypeColor(context, type),
        }
        ..edgeTextStyleGetter = (_, _) {
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
            backgroundColor: colors.surfaceContainerLow.withValues(alpha: 0.86),
          );
        }
        // 1.0 disables the hover dim-out: moving the mouse flips hoverVertex
        // between nodes; the opacity jump otherwise reads as flicker.
        ..hoverOpacity = 1.0)
      ..vertexShape = _RingVertexShape(
        ringColor: colors.surfaceContainerLow,
        textRenderer: _CachedHaloTextRenderer(
          labelForId: (id) => labels[id] ?? id,
          styleBuilder: () => TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            // Soft halo around the label so it stays readable over edges
            // and other nodes (labels are drawn on the canvas with no
            // background of their own). The stock text renderer strips
            // shadows — this is the renderer that actually honors them.
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
          ),
        ),
      )
      ..edgeShape = _FadedEdgeLineShape(textRenderer: EdgeTextRendererImpl())
      ..onVertexTapUp = (vertex, _) {
        // Deferred: mutating state inside the pointer-event dispatch trips
        // Flutter's MouseTracker debug assertion on macOS (and onVertexTapDown
        // is never invoked by this package — TapUp is the live callback).
        final id = vertex.id as String;
        Future.microtask(() => widget.onVertexTap(id));
      };

    // Wrap the package's default pointer handlers so any activity wakes the
    // ticker (getters return the defaults until a setter replaces them).
    final defaultHover = _options.onPointerHover;
    _options.onPointerHover = (event) {
      _wake();
      defaultHover(event);
    };
    final defaultDown = _options.onPointerDown;
    _options.onPointerDown = (event) {
      _wake();
      defaultDown(event);
    };
    final defaultUp = _options.onPointerUp;
    _options.onPointerUp = (event) {
      _wake();
      defaultUp(event);
    };
    final defaultScaleStart = _options.onScaleStart;
    _options.onScaleStart = (details) {
      _wake();
      defaultScaleStart(details);
    };
    final defaultScaleUpdate = _options.onScaleUpdate;
    _options.onScaleUpdate = (details) {
      _wake();
      defaultScaleUpdate(details);
    };

    // Set outside the cascade: the handler needs to read options.scale/offset,
    // and Dart forbids referencing the cascade target inside its own chain.
    _options.onPointerSignal = (event) {
      _wake();
      if (!widget.scrollZoomEnabled) return;
      if (event is! PointerScrollEvent) return;
      // 4x the package default (0.05/notch): one wheel notch is now a
      // visible step instead of an imperceptible 5%.
      final zoomDelta =
          event.scrollDelta.dy.sign * _options.zoomPerScrollUnit * 4;
      if (_options.scale.value + zoomDelta <= 0) return;
      // Deferred: mutating scale inside the pointer dispatch re-enters
      // setState through the scale listener and trips Flutter's
      // MouseTracker debug assertion (same trap as onVertexTapUp).
      Future.microtask(() {
        final oz = _options.scale.value;
        _options.scale.value += zoomDelta;
        _options.keepCenter(
          oz,
          _options.scale.value,
          _options.size.value,
          event.localPosition,
          _options.offset,
        );
      });
    };

    // The whole package object graph is built once and pinned in the State:
    // FlutterGraphWidget mints a new Graph (its ValueKey) per instance, so
    // rebuilding it on every parent setState would restart the ticker and
    // wipe positions/zoom. _rebuildGraphObjects swaps it deliberately.
    _graphWidget = FlutterGraphWidget(
      data: data,
      convertor: MapConvertor(),
      algorithm: _ForceLayoutAlgorithm(),
      options: _options,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entities.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final graphArea = Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label:
          '知识关系图，共 ${widget.entities.length} 个实体、${widget.relations.length} 条关系',
      hint: '空间关系示意图。使用实体列表打开详情；也可拖动平移并缩放画布。',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: _graphWidget,
        ),
      ),
    );
    if (widget.height == null) {
      return SizedBox(width: double.infinity, child: graphArea);
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: graphArea,
    );
  }
}

/// Keyboard- and screen-reader-operable equivalent to the painted graph.
///
/// The force-directed canvas remains useful for spatial exploration, while
/// this disclosure gives every entity a real focusable control.
class BookAiGraphEntityNavigator extends StatelessWidget {
  const BookAiGraphEntityNavigator({
    super.key,
    required this.entities,
    required this.onEntityTap,
  });

  final List<AiGraphEntity> entities;
  final ValueChanged<String> onEntityTap;

  @override
  Widget build(BuildContext context) {
    final byId = <String, AiGraphEntity>{};
    for (final entity in entities) {
      byId.putIfAbsent(entity.id, () => entity);
    }
    final items = byId.values.toList(growable: false)
      ..sort((a, b) {
        final byType = a.type.index.compareTo(b.type.index);
        if (byType != 0) return byType;
        return a.name.compareTo(b.name);
      });
    if (items.isEmpty) return const SizedBox.shrink();
    final listHeight = math.min(240.0, items.length * 46.0);
    return Semantics(
      container: true,
      label: '关系图实体列表',
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.only(bottom: 6),
        title: Text('实体列表 ${items.length}'),
        subtitle: const Text('可使用键盘或读屏打开实体详情'),
        children: [
          SizedBox(
            height: listHeight,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final entity = items[index];
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: graphEntityTypeColor(context, entity.type),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(entity.name),
                  subtitle: Text(graphEntityTypeLabel(entity.type)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => onEntityTap(entity.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Deterministic one-shot Fruchterman-Reingold layout.
///
/// Runs once in `onGraphLoad` (all vertices/edges exist by then and
/// `options.size` is the real canvas), writes fixed positions into both the
/// vertices and [positionStorage]. No decorators: the stock force decorators
/// compute O(n²) forces per frame whose only consumer (ForceMotionDecorator)
/// was removed — pure dead work. Determinism (sorted ids + golden-angle
/// spiral seed, no Random) keeps the layout stable across widget rebuilds.
class _ForceLayoutAlgorithm extends RandomOrPersistenceAlgorithm {
  static const int _iterations = 250;

  @override
  void onGraphLoad(Graph graph) {
    final vertexes = graph.vertexes;
    final n = vertexes.length;
    if (n == 0) return;
    final rect =
        graph.options?.visibleWorldRect ??
        const Rect.fromLTWH(0, 0, 1920, 1080);
    final cx = rect.left + rect.width / 2;
    final cy = rect.top + rect.height / 2;
    // Ideal pairwise spacing; clamped so tiny panels still spread and huge
    // fullscreen canvases don't fling clusters apart.
    final k = (math.sqrt(rect.width * rect.height / n)).clamp(36.0, 160.0);

    final sorted = [...vertexes]
      ..sort((a, b) => '${a.id}'.compareTo('${b.id}'));
    final pos = <dynamic, Vector2>{};
    const goldenAngle = 2.399963229728653; // π(3 − √5)
    for (var i = 0; i < n; i++) {
      final r = k * 0.6 * math.sqrt(i + 0.5);
      final a = i * goldenAngle;
      pos[sorted[i].id] = Vector2(cx + r * math.cos(a), cy + r * math.sin(a));
    }

    var temperature = k * 2;
    final cooling = temperature / _iterations;
    for (var iter = 0; iter < _iterations; iter++) {
      final disp = <dynamic, Vector2>{
        for (final v in vertexes) v.id: Vector2.zero(),
      };
      // Repulsion between every pair.
      for (var i = 0; i < n; i++) {
        final pi = pos[vertexes[i].id]!;
        for (var j = i + 1; j < n; j++) {
          final pj = pos[vertexes[j].id]!;
          var delta = pi - pj;
          var dist = delta.length;
          if (dist < 0.01) {
            delta = Vector2(0.01, 0.01);
            dist = delta.length;
          }
          final force = k * k / dist;
          final step = delta / dist * force;
          disp[vertexes[i].id] = disp[vertexes[i].id]! + step;
          disp[vertexes[j].id] = disp[vertexes[j].id]! - step;
        }
      }
      // Attraction along edges (uniform weight: type/ranking proved too
      // noisy to matter at this density).
      for (final edge in graph.edges) {
        final end = edge.end;
        if (end == null || identical(edge.start, end)) continue;
        if (!pos.containsKey(edge.start.id) || !pos.containsKey(end.id)) {
          continue;
        }
        final delta = pos[edge.start.id]! - pos[end.id]!;
        final dist = math.max(delta.length, 0.01);
        final force = dist * dist / k;
        final step = delta / dist * force;
        disp[edge.start.id] = disp[edge.start.id]! - step;
        disp[end.id] = disp[end.id]! + step;
      }
      // Weak gravity keeps the forest centered instead of drifting apart.
      for (final v in vertexes) {
        final p = pos[v.id]!;
        disp[v.id] = disp[v.id]! + (Vector2(cx, cy) - p) * 0.02;
      }
      // Apply, clamped by the cooling temperature, and confine to the rect.
      for (final v in vertexes) {
        final d = disp[v.id]!;
        final len = d.length;
        if (len > 0.01) {
          final p = pos[v.id]! + d / len * math.min(len, temperature);
          pos[v.id] = Vector2(
            p.x.clamp(rect.left + 24, rect.right - 24),
            p.y.clamp(rect.top + 24, rect.bottom - 24),
          );
        }
      }
      temperature = math.max(temperature - cooling, k * 0.02);
    }

    for (final v in vertexes) {
      v.position = pos[v.id]!;
      positionStorage[v.id] = v.position;
    }
  }
}

/// Label renderer with a per-(vertex, zoom-bucket) TextPainter cache.
///
/// The stock `VertexTextRendererImpl` rebuilds a `ui.Paragraph` AND a full
/// TextPainter layout per vertex per frame, and its `textStyleGetter`
/// silently drops `TextStyle.shadows` — so the readability halo never
/// rendered. Here the TextPainter (shadows included) is laid out once and
/// replayed; zoom is quantized to 0.1 so a zoom gesture only re-layouts per
/// bucket, and the cache is bounded (cleared past 600 entries).
class _CachedHaloTextRenderer extends VertexTextRenderer {
  _CachedHaloTextRenderer({
    required this.styleBuilder,
    required this.labelForId,
  });

  /// Full label style at zoom 1.0, halo shadows included.
  final TextStyle Function() styleBuilder;
  final String Function(String id) labelForId;

  final Map<String, ({TextPainter painter, double fontSize})> _cache = {};

  @override
  void render(Vertex vertex, ui.Canvas canvas, ui.Paint paint) {
    final zoom = vertex.zoom;
    if (zoom <= 0) return;
    final label = labelForId('${vertex.id}');
    if (label.isEmpty) return;
    final key = '${vertex.id}@${(zoom * 10).round()}';
    var entry = _cache[key];
    if (entry == null) {
      if (_cache.length > 600) _cache.clear();
      final base = styleBuilder();
      // Matches the stock renderer's 1/zoom counter-scaling: the canvas is
      // already zoomed, so the font shrinks to keep screen size constant.
      final fontSize = (base.fontSize ?? 12.5) / zoom;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: base.copyWith(fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      entry = (painter: painter, fontSize: fontSize);
      _cache[key] = entry;
    }
    final vw = vertex.radiusZoom;
    // Same anchor as the stock impl: centered above the vertex circle.
    entry.painter.paint(
      canvas,
      ui.Offset(-entry.painter.width / 2, -vw - entry.fontSize / 0.7),
    );
  }
}

/// Circle vertex with a crisp surface-colored ring: at graph density the
/// fill-only circles melt into each other, the ring keeps them separated
/// (and doubles as a soft shadow edge against the dot grid).
class _RingVertexShape extends VertexCircleShape {
  _RingVertexShape({required this.ringColor, super.textRenderer});

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
  _FadedEdgeLineShape({super.textRenderer});

  static const _symmetricTypes = {'同盟', '敌对', '婚配', '同事', '朋友', '同学', '相识'};

  @override
  void vertexDifferent(Edge edge, ui.Canvas canvas, ui.Paint paint) {
    super.vertexDifferent(edge, canvas, paint);
    if (_symmetricTypes.contains(edge.edgeName)) return;
    final endRadius = edge.end?.radiusZoom ?? 0;
    final tipX = (len(edge) - endRadius - 2 / edge.zoom).clamp(0.0, len(edge));
    final size = 5 / edge.zoom;
    final arrow = ui.Path()
      ..moveTo(tipX, 0)
      ..lineTo(tipX - size * 1.7, -size)
      ..lineTo(tipX - size * 1.7, size)
      ..close();
    canvas.drawPath(
      arrow,
      ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..color = (edge.end?.colors.lastOrNull ?? Colors.grey).withValues(
          alpha: 0.72,
        ),
    );
  }

  @override
  Paint getPaint(Edge edge) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (edge.isHovered ? 3 : 1) / edge.zoom;
    final from = edge.start.colors.lastOrNull ?? Colors.grey;
    final to = edge.end?.colors.lastOrNull ?? from;
    paint.shader = ui.Gradient.linear(Offset.zero, Offset(len(edge), 0), [
      from.withValues(alpha: 0.45),
      to.withValues(alpha: 0.45),
    ]);
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
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}

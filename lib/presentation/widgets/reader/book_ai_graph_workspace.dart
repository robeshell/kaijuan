import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../ai/ai_graph_family_tree.dart';
import '../../../ai/ai_graph_service.dart';
import '../../../ai/ai_user_error.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../ai_typography.dart';
import '../app_components.dart';
import '../app_overlays.dart';
import 'book_ai_entity_sheet.dart';
import 'book_ai_graph_components.dart';
import 'book_ai_graph_content_view.dart';
import 'book_ai_graph_family_tree_fullscreen.dart';
import 'book_ai_graph_family_tree_view.dart';
import 'book_ai_graph_sort.dart';
import 'book_ai_graph_tiles.dart';
import 'book_ai_graph_fullscreen.dart';
import 'book_ai_narration_dialog.dart';

typedef _NarrationConfirmation = ({
  AiNarrationPlan? plan,
  AiNarrationPlanMode mode,
  Set<int> excludedSections,
});

/// Owns the complete knowledge-graph tab presentation and route coordination.
class BookAiGraphWorkspace extends StatefulWidget {
  const BookAiGraphWorkspace({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final BookReaderController controller;
  final Future<void> Function() onOpenSettings;

  @override
  State<BookAiGraphWorkspace> createState() => _BookAiGraphWorkspaceState();
}

class _BookAiGraphWorkspaceState extends State<BookAiGraphWorkspace> {
  final _graphQueryController = TextEditingController();
  final _graphScrollController = ScrollController();
  BookAiGraphViewMode _graphViewMode = BookAiGraphViewMode.persons;
  AiBookGraph? _appliedNarrationGraph;
  bool _familyTreeDetailExpanded = false;
  final _graphSortOrders = <BookAiGraphViewMode, GraphEntitySortOrder>{};
  bool _graphIsolatedExpanded = false;
  bool _graphWorksLoading = false;
  bool _graphPreparing = false;
  String? _graphPreparingWorkId;
  String _graphQuery = '';
  String? _graphHighlighted;
  Timer? _graphHighlightTimer;
  final _graphEntityKeys = <String, GlobalKey>{};
  int _graphListEpoch = 0;

  BookReaderController get _c => widget.controller;
  bool get _ready => _c.canUseAiChat;
  bool get _graphBusy => _graphPreparing || _c.isGeneratingBookGraph;

  GraphEntitySortOrder get _graphSortOrder =>
      _graphSortOrders[_graphViewMode] ?? defaultGraphSortOrder(_graphListKind);

  double _panelTitleSize(BuildContext context) => context.aiTitleSize;
  double _panelBodySize(BuildContext context) => context.aiBodySize;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
    unawaited(_ensureGraphWorks());
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final storedGraph = _c.bookGraph;
    final visibleGraph = _c.visibleBookGraph;
    if (storedGraph != null &&
        !identical(storedGraph, _appliedNarrationGraph)) {
      _appliedNarrationGraph = storedGraph;
      final wanted = _viewModeFor(
        resolveGraphInitialView(
          visibleGraph ?? storedGraph,
          storedGraph.narration?.defaultView,
        ),
      );
      if (wanted != null) _graphViewMode = wanted;
      _graphQueryController.clear();
      _graphQuery = '';
      _graphListEpoch++;
    }
    setState(() {});
  }

  /// Which entity types the current list view shows; empty on the graph
  /// view (no list rendered there). The persons view also folds in
  /// `organization` has its own index; it must not inflate the person list.
  Set<AiGraphEntityType> get _graphListEntityTypes => switch (_graphViewMode) {
    BookAiGraphViewMode.persons => {AiGraphEntityType.person},
    BookAiGraphViewMode.locations => {AiGraphEntityType.location},
    BookAiGraphViewMode.events => {AiGraphEntityType.event},
    BookAiGraphViewMode.organizations => {AiGraphEntityType.organization},
    BookAiGraphViewMode.things => {
      AiGraphEntityType.item,
      AiGraphEntityType.concept,
      AiGraphEntityType.creature,
    },
    BookAiGraphViewMode.graph => const {},
    BookAiGraphViewMode.familyTree => const {},
  };

  GraphEntityListKind get _graphListKind => switch (_graphViewMode) {
    BookAiGraphViewMode.persons => GraphEntityListKind.persons,
    BookAiGraphViewMode.locations => GraphEntityListKind.locations,
    BookAiGraphViewMode.events => GraphEntityListKind.events,
    BookAiGraphViewMode.organizations => GraphEntityListKind.organizations,
    BookAiGraphViewMode.things => GraphEntityListKind.things,
    // Sorting controls are not rendered for exploration views. This fallback
    // only keeps the shared build path total while those views are active.
    BookAiGraphViewMode.graph ||
    BookAiGraphViewMode.familyTree => GraphEntityListKind.persons,
  };

  BookAiGraphViewMode? _viewModeFor(String view) => switch (view) {
    'persons' => BookAiGraphViewMode.persons,
    'locations' => BookAiGraphViewMode.locations,
    'events' => BookAiGraphViewMode.events,
    'organizations' || 'org_tree' => BookAiGraphViewMode.organizations,
    'things' => BookAiGraphViewMode.things,
    'graph' => BookAiGraphViewMode.graph,
    'family_tree' => BookAiGraphViewMode.familyTree,
    _ => null,
  };

  Widget _buildGraphTab(BuildContext context) {
    if (_c.hasCollectionWorks && !_c.hasActiveWorkGraph) {
      return _buildGraphWorkList(context);
    }
    return _buildGraphContent(context);
  }

  Widget _buildGraphWorkList(BuildContext context) {
    if (!_ready) {
      return _GraphUnavailable(
        message: '添加 API Key 后，就可以生成本书的人物、地点与事件图谱。',
        onOpenSettings: () => unawaited(widget.onOpenSettings()),
        icon: KaijuanIcons.graph,
      );
    }
    final works = _c.resolvedGraphWorks ?? const <AiGraphWorkCandidate>[];
    final reading = _c.currentReadingWork;
    final generatingWork = _c.generatingGraphWork;
    final progress = _c.bookGraphProgress;
    final error = _c.bookGraphError;
    return BookAiGraphWorkList(
      works: works,
      readingWork: reading,
      generatingWork: generatingWork,
      preparing: _graphPreparing,
      preparingWorkId: _graphPreparingWorkId,
      busy: _graphBusy,
      error: error,
      progressLabel: progress?.label,
      titleSize: _panelTitleSize(context),
      isReady: _c.hasWorkGraph,
      onCancelGeneration: _c.cancelBookGraphGeneration,
      onSelect: (work) {
        if (_c.hasWorkGraph(work)) {
          _c.openWorkGraph(work);
        } else {
          unawaited(_generateGraph(work: work));
        }
      },
    );
  }

  Widget _buildGraphContent(BuildContext context) {
    final colors = context.appColors;
    final graph = _c.visibleBookGraph;
    final hadEmptySnapshot = graph == null && _c.bookGraph != null;
    final generating = _c.isGeneratingBookGraph;
    final preparing = _graphPreparing && !generating;
    final busy = preparing || generating;
    final error = _c.bookGraphError;
    if (!_ready) {
      return _GraphUnavailable(
        message: '添加 API Key 后，就可以生成本书的人物、地点与事件图谱。',
        onOpenSettings: () => unawaited(widget.onOpenSettings()),
        icon: KaijuanIcons.graph,
      );
    }
    if (graph == null) {
      // Collection detection is async (outline → work candidates). Until the
      // works are known, there is no valid range to generate — show a
      // loading state instead of the actionable empty-state button, or a
      // tap would start a whole-book dialog against a half-loaded book.
      // Only a recognition IN PROGRESS shows the loading state; once it
      // fails (or this is a plain book that will never have works), fall
      // through to the actionable empty state — otherwise the tab would be
      // stuck on「正在识别著作范围…」forever.
      final works = _c.resolvedGraphWorks;
      if (works == null && _graphWorksLoading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 12),
                Text(
                  '正在识别著作范围…',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: context.appSecondaryText,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                KaijuanIcons.graph,
                size: 34,
                color: context.appSecondaryText,
              ),
              const SizedBox(height: 14),
              if (!busy)
                Text(
                  hadEmptySnapshot ? '尚无有效图谱数据' : '知识图谱',
                  style: TextStyle(
                    fontSize: _panelTitleSize(context),
                    fontWeight: FontWeight.w600,
                    color: context.appPrimaryText,
                  ),
                ),
              if (busy) ...[
                const SizedBox(height: 10),
                Text(
                  '生成完成后，实体、关系与索引会显示在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: context.appSecondaryText,
                  ),
                ),
              ] else ...[
                if (hadEmptySnapshot) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上一次没有得到可展示的实体或关系。再次生成会重新读取正文，不会沿用空的完成记录。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      height: 1.4,
                      color: context.appSecondaryText,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => unawaited(
                    _generateGraph(
                      // Retry the range being retried: after a cancelled /
                      // failed generation the active work is still set, and
                      // the dialog must open scoped to it (not the whole
                      // collection).
                      work: _c.activeGraphWork,
                    ),
                  ),
                  icon: const Icon(KaijuanIcons.graph, size: 18),
                  label: Text(hadEmptySnapshot ? '重新生成图谱' : '生成图谱'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final readThrough = _c.sectionIndex + 1;
    // [visibleBookGraph] has already removed ungrounded evidence. Its saved
    // generation scope is authoritative, so child widgets must not invent a
    // device-local progress projection.
    const gateByProgress = false;
    // Entities with at least one relation form the readable core; zero-edge
    // entities (mere mentions) collapse into one foldable row and are left
    // off the force-directed view where they would float as orphan dots.
    final connectedIds = <String>{
      for (final r in graph.relations) ...[
        if (r.sourceId.isNotEmpty) r.sourceId,
        if (r.targetId.isNotEmpty) r.targetId,
      ],
    };
    // Structural gates below (view-mode switcher, graph/family-tree blocks)
    // must NOT depend on the search query: when a query matches nothing,
    // hiding a block above the search box shifts the ListView's children,
    // recreates the field's element and breaks IME composition (the next
    // keystroke garbles). baseEntities = progress/type gated, no query.
    // The model/store layers enforce unique stable IDs, but keep the render
    // boundary defensive: a legacy or in-memory graph must never mount one
    // GlobalKey twice and take down the whole AI panel.
    final renderedEntityIds = <String>{};
    final baseEntities = graph.entities
        .where((entity) {
          if (!renderedEntityIds.add(entity.id)) return false;
          final listTypes = _graphListEntityTypes;
          if (listTypes.isNotEmpty && !listTypes.contains(entity.type)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final visibleEntities = _graphQuery.trim().isEmpty
        ? baseEntities
        : baseEntities
              .where((entity) {
                final query = _graphQuery.trim();
                final hit =
                    entity.name.contains(query) ||
                    entity.aliases.any((alias) => alias.contains(query));
                return hit;
              })
              .toList(growable: false);
    // Main list = everything the book itself is about (setting), connected
    // or not. Only referenced outsiders (罗素 etc.) fold away — in essay
    // collections relations are sparse, so "connected only" would empty the
    // list.
    final isolatedEntities = <AiGraphEntity>[
      for (final entity in visibleEntities)
        if (entity.scope != AiGraphEntityScope.setting) entity,
    ];
    final mainEntities = <AiGraphEntity>[
      for (final entity in visibleEntities)
        if (entity.scope == AiGraphEntityScope.setting) entity,
    ];
    // Search is allowed to surface mere mentions without the fold.
    final foldIsolated =
        isolatedEntities.isNotEmpty && _graphQuery.trim().isEmpty;
    final relationCounts = graphEntityRelationCounts(
      graph.entities,
      graph.relations,
    );
    // Sort the visible snapshot explicitly. Cached graphs, repaired graphs
    // and newly generated graphs may all arrive in different array orders;
    // presentation order must never depend on that incidental storage order.
    List<AiGraphEntity> ordered(List<AiGraphEntity> source) {
      return sortGraphEntities(
        source,
        order: _graphSortOrder,
        relationCounts: relationCounts,
      );
    }

    final orderedMain = ordered(mainEntities);
    final orderedIsolated = ordered(isolatedEntities);

    return BookAiGraphContentView(
      graph: graph,
      listEpoch: _graphListEpoch,
      scrollController: _graphScrollController,
      activeWorkTitle: _c.activeGraphWork?.title,
      busy: busy,
      error: error,
      viewMode: _graphViewMode,
      connectedEntities: graph.entities
          .where((entity) => connectedIds.contains(entity.id))
          .toList(growable: false),
      visibleEntities: visibleEntities,
      orderedMain: orderedMain,
      orderedIsolated: orderedIsolated,
      foldIsolated: foldIsolated,
      queryController: _graphQueryController,
      query: _graphQuery,
      sortOrder: _graphSortOrder,
      listKind: _graphListKind,
      titleSize: _panelTitleSize(context),
      bodySize: _panelBodySize(context),
      onCloseWork: _c.closeActiveWorkGraph,
      onRegenerate: () =>
          unawaited(_generateGraph(force: true, work: _c.activeGraphWork)),
      onDelete: () => unawaited(_deleteGraph()),
      onViewModeChanged: (mode) => setState(() => _graphViewMode = mode),
      onQueryChanged: (value) => setState(() => _graphQuery = value),
      onClearQuery: () {
        _graphQueryController.clear();
        setState(() => _graphQuery = '');
      },
      onSortChanged: (order) =>
          setState(() => _graphSortOrders[_graphViewMode] = order),
      onGraphVertexTap: _onGraphVertexTap,
      onOpenGraphFullscreen: _openGraphFullscreen,
      buildFamilyTree: () =>
          _buildFamilyTreeView(context, graph, gateByProgress, readThrough),
      buildLocationChain: () =>
          _buildLocationChain(context, graph, gateByProgress, readThrough),
      buildMainEntities: (entities) {
        if (_graphViewMode == BookAiGraphViewMode.events) {
          return _buildGraphEventTimeline(
            context,
            entities,
            gateByProgress,
            readThrough,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entity in entities)
              KeyedSubtree(
                key: _graphEntityKeys.putIfAbsent(entity.id, () => GlobalKey()),
                child: _buildGraphEntityTile(
                  context,
                  entity,
                  gateByProgress,
                  readThrough,
                ),
              ),
          ],
        );
      },
      buildIsolatedEntities: (entities) {
        if (foldIsolated) {
          return _buildIsolatedRow(
            context,
            entities,
            gateByProgress,
            readThrough,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entity in entities)
              KeyedSubtree(
                key: _graphEntityKeys.putIfAbsent(entity.id, () => GlobalKey()),
                child: _buildGraphEntityTile(
                  context,
                  entity,
                  gateByProgress,
                  readThrough,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Events view: chapter-ordered flat list of event cards. Chapter headers
  /// were dropped — section labels from the graph pipeline are too unreliable
  /// to show as headers, and the chapter order is already implied by the
  /// sort (出场顺序).
  Widget _buildGraphEventTimeline(
    BuildContext context,
    List<AiGraphEntity> events,
    bool gateByProgress,
    int readThrough,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in events)
          KeyedSubtree(
            key: _graphEntityKeys.putIfAbsent(event.id, () => GlobalKey()),
            child: _buildGraphEventTile(
              context,
              event,
              gateByProgress,
              readThrough,
            ),
          ),
      ],
    );
  }

  Widget _buildGraphEventTile(
    BuildContext context,
    AiGraphEntity entity,
    bool gateByProgress,
    int readThrough,
  ) {
    return GraphEventTile(
      entity: entity,
      bodySize: _panelBodySize(context),
      trailingLabel: switch (_graphSortOrder) {
        GraphEntitySortOrder.importance => '重要度 ${entity.importance}',
        GraphEntitySortOrder.chapters => '${graphEntityChapterCount(entity)} 章',
        _ => '第 ${entity.firstSection} 节',
      },
      highlighted: _graphHighlighted == entity.id,
      onTap: () => _showEntityDetails(entity),
    );
  }

  /// Family-tree view: the line-connected chart plus the foldable
  /// 「未入树 N 人 · 关系复杂 N 人」rows (each name opens the entity card).
  /// Degrades to a hint when the book has no kin data at all.
  Widget _buildFamilyTreeView(
    BuildContext context,
    AiBookGraph graph,
    bool gateByProgress,
    int readThrough,
  ) {
    final treeEntities = graph.entities
        .where((e) => !gateByProgress || e.firstSection <= readThrough)
        .toList(growable: false);
    // Spoiler gate (mirrors _buildGraphEntityTile's relation count): a 亲属
    // edge whose evidence is entirely in unread chapters reveals a late-plot
    // kinship between two already-introduced characters, so it must not
    // enter the tree (or the isolated/complex counts).
    final treeRelations = graph.relations
        .where(
          (r) =>
              !gateByProgress ||
              r.evidence.any((e) => e.sectionIndex <= readThrough),
        )
        .toList(growable: false);
    final familyTree = buildFamilyTree(
      entities: treeEntities,
      relations: treeRelations,
    );
    if (familyTree.roots.isEmpty && familyTree.isolatedCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '本书暂无血缘关系数据',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
      );
    }
    final detailEntities = <({String id, String name})>[
      for (var i = 0; i < familyTree.complexEntityIds.length; i++)
        (id: familyTree.complexEntityIds[i], name: familyTree.complexNames[i]),
      for (var i = 0; i < familyTree.isolatedEntityIds.length; i++)
        (
          id: familyTree.isolatedEntityIds[i],
          name: familyTree.isolatedNames[i],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '家族树图例：从上到下表示长辈到晚辈，虚线表示额外母系关系，标记为复杂表示关系存在冲突或成环。',
          child: Text(
            '上→下：长辈到晚辈 · 虚线：额外母系 · 复杂：关系冲突',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            BookAiGraphFamilyTreeView(
              tree: familyTree,
              onVertexTap: _onGraphVertexTap,
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: Material(
                color: context.appColors.surfaceContainerHighest.withValues(
                  alpha: 0.9,
                ),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: '全屏查看',
                  iconSize: 18,
                  icon: const Icon(KaijuanIcons.maximize),
                  onPressed: () => _openFamilyTreeFullscreen(
                    familyTree,
                    graph,
                    gateByProgress,
                    readThrough,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (familyTree.isolatedCount > 0 ||
            familyTree.complexNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(
              () => _familyTreeDetailExpanded = !_familyTreeDetailExpanded,
            ),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Icon(
                  _familyTreeDetailExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: context.appSecondaryText,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '未入树 ${familyTree.isolatedCount} 人'
                    ' · 关系复杂 ${familyTree.complexNames.length} 人',
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: context.appSecondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_familyTreeDetailExpanded) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entity in detailEntities)
                  ActionChip(
                    label: Text(entity.name),
                    visualDensity: VisualDensity.compact,
                    // Tree mode renders no entity list rows, so the
                    // scroll-and-highlight path in _onGraphVertexTap has
                    // nothing to scroll to — go straight to the detail card
                    // (same as tapping a tree node).
                    onPressed: () => _onGraphVertexTap(entity.id),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildLocationChain(
    BuildContext context,
    AiBookGraph graph,
    bool gateByProgress,
    int readThrough,
  ) {
    return GraphLocationChain(
      locations: graph.entities
          .where(
            (e) =>
                e.type == AiGraphEntityType.location &&
                e.scope == AiGraphEntityScope.setting,
          )
          .toList(growable: false),
      gateByProgress: gateByProgress,
      readThrough: readThrough,
      onPillTap: _onGraphVertexTap,
    );
  }

  Widget _buildIsolatedRow(
    BuildContext context,
    List<AiGraphEntity> isolated,
    bool gateByProgress,
    int readThrough,
  ) {
    final expanded = _graphIsolatedExpanded;
    return GraphIsolatedRow(
      count: isolated.length,
      expanded: expanded,
      onToggle: () => setState(() => _graphIsolatedExpanded = !expanded),
      expandedChildren: [
        for (final entity in isolated)
          KeyedSubtree(
            key: _graphEntityKeys.putIfAbsent(entity.id, () => GlobalKey()),
            child: _buildGraphEntityTile(
              context,
              entity,
              gateByProgress,
              readThrough,
            ),
          ),
      ],
    );
  }

  void _onGraphVertexTap(String entityId) {
    final graph = _c.visibleBookGraph;
    final entity = graph?.entityById(entityId);
    if (entity == null) return;
    if (_graphViewMode == BookAiGraphViewMode.graph ||
        _graphViewMode == BookAiGraphViewMode.familyTree) {
      _showEntityDetails(entity);
      return;
    }
    setState(() => _graphHighlighted = entityId);
    _graphHighlightTimer?.cancel();
    _graphHighlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _graphHighlighted = null);
    });
    final ctx = _graphEntityKeys[entityId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.2,
      );
    }
  }

  void _openFamilyTreeFullscreen(
    AiFamilyTree familyTree,
    AiBookGraph graph,
    bool gateByProgress,
    int readThrough,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiGraphFamilyTreeFullscreen(
          title: _c.activeGraphWork != null
              ? '《${_c.activeGraphWork!.title}》家族树'
              : '家族树',
          tree: familyTree,
          graph: graph,
          gateByProgress: gateByProgress,
          readThrough: readThrough,
          onJumpToEvidence: _goToGraphEvidence,
        ),
      ),
    );
  }

  void _openGraphFullscreen() {
    final graph = _c.visibleBookGraph;
    if (graph == null) return;
    final readThrough = _c.sectionIndex + 1;
    const gateByProgress = false;
    final connectedIds = <String>{
      for (final r in graph.relations) ...[
        if (r.sourceId.isNotEmpty) r.sourceId,
        if (r.targetId.isNotEmpty) r.targetId,
      ],
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookAiGraphFullscreen(
          title: _c.activeGraphWork != null
              ? '《${_c.activeGraphWork!.title}》图谱'
              : '知识图谱',
          graph: graph,
          gateByProgress: gateByProgress,
          readThrough: readThrough,
          entities: graph.entities
              .where((entity) => connectedIds.contains(entity.id))
              .toList(growable: false),
          relations: graph.relations,
          onJumpToEvidence: _goToGraphEvidence,
        ),
      ),
    );
  }

  Widget _buildGraphEntityTile(
    BuildContext context,
    AiGraphEntity entity,
    bool gateByProgress,
    int readThrough,
  ) {
    final graph = _c.visibleBookGraph;
    final relationCount = graph == null
        ? 0
        : graph.relations
              .where(
                (r) =>
                    ((r.sourceId.isNotEmpty &&
                            (r.sourceId == entity.id ||
                                r.targetId == entity.id)) ||
                        (r.sourceId.isEmpty &&
                            (r.source == entity.name ||
                                r.target == entity.name))) &&
                    (!gateByProgress ||
                        r.evidence.any((e) => e.sectionIndex <= readThrough)),
              )
              .length;
    return GraphEntityTile(
      entity: entity,
      metadata: switch (_graphSortOrder) {
        GraphEntitySortOrder.appearance =>
          '首次：第 ${entity.firstSection} 节 · '
              '${graphEntityChapterCount(entity)} 章',
        GraphEntitySortOrder.evidence =>
          '${graphEntityEvidenceCount(entity)} 条出处 · '
              '${graphEntityChapterCount(entity)} 章',
        GraphEntitySortOrder.relations =>
          '$relationCount 关系 · ${graphEntityChapterCount(entity)} 章',
        GraphEntitySortOrder.type =>
          '${_graphEntityTypeLabel(entity.type)} · '
              '${graphEntityChapterCount(entity)} 章',
        _ => '${graphEntityChapterCount(entity)} 章 · $relationCount 关系',
      },
      typeColor: graphEntityTypeColor(context, entity.type),
      highlighted: _graphHighlighted == entity.id,
      bodySize: _panelBodySize(context),
      onTap: () => _showEntityDetails(entity),
    );
  }

  String _graphEntityTypeLabel(AiGraphEntityType type) => switch (type) {
    AiGraphEntityType.person => '人物',
    AiGraphEntityType.location => '地点',
    AiGraphEntityType.event => '事件',
    AiGraphEntityType.organization => '组织',
    AiGraphEntityType.item => '物件',
    AiGraphEntityType.concept => '概念',
    AiGraphEntityType.creature => '非人角色',
  };

  void _showEntityDetails(AiGraphEntity entity) {
    final graph = _c.visibleBookGraph;
    if (graph == null) return;
    final readThrough = _c.sectionIndex + 1;
    const gateByProgress = false;
    showAppBottomSheet<void>(
      context,
      useRootNavigator: true,
      anchorPoint: appTrailingBottomOverlayAnchor(context),
      builder: (_) => BookAiEntitySheet(
        entity: entity,
        graph: graph,
        gateByProgress: gateByProgress,
        readThrough: readThrough,
        titleSize: _panelTitleSize(context),
        bodySize: _panelBodySize(context),
        onOpenEvidence: _goToGraphEvidence,
        onHideEntity: () => unawaited(_c.hideBookGraphEntity(entity.id)),
      ),
    );
  }

  void _goToGraphEvidence(AiGraphEvidence evidence) {
    final index = evidence.sectionIndex - 1;
    if (index < 0 || index >= _c.sectionCount) return;
    _c.goToSection(index, progressInSection: evidence.progressInSection ?? 0);
    // The evidence row already popped its modal; wait for that route's exit
    // animation to finish, then close the side panel itself so the reader
    // sees the quoted section. Popping immediately would hit the modal
    // (still animating out) and leave the panel open.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });
  }

  Future<void> _ensureGraphWorks() async {
    if (_c.bookStructureManifest != null) return;
    if (_graphWorksLoading || !mounted) return;
    _graphWorksLoading = true;
    await _c.resolveGraphWorkCandidates();
    if (!mounted) return;
    _graphWorksLoading = false;
    setState(() {});
  }

  Future<void> _generateGraph({
    bool force = false,
    AiGraphWorkCandidate? work,
  }) async {
    if (!_ready || _graphBusy) return;
    setState(() {
      _graphPreparing = true;
      _graphPreparingWorkId = work?.id;
    });
    try {
      if (force && _c.bookGraph != null) {
        final confirmed = await showAppConfirmDialog(
          context,
          title: '重新生成图谱？',
          message: '将重新请求 AI，并替换当前保存的图谱。',
          confirmLabel: '重新生成',
        );
        if (confirmed != true || !mounted) return;
      }
      // Step-0 display plan, confirmed before extraction: a fresh generation
      // (no narration yet) and every regeneration get the confirm dialog;
      // incremental runs keep their existing plan untouched. Judged against
      // the TARGET work's graph — the picker page shows the whole-book legacy
      // graph, whose plan must not suppress a fresh per-work dialog.
      final hasPlan = work == null
          ? _c.bookGraph?.narration != null
          : _c.workGraphHasNarration(work);
      if (force || !hasPlan) {
        final confirmed = await _confirmNarrationPlan(work);
        if (confirmed == null || !mounted) return;
        final generation = _c.generateBookGraph(
          only: work,
          force: force,
          narrationOverride: confirmed.plan,
          narrationMode: confirmed.mode,
          excludedGraphSectionIndices: confirmed.excludedSections,
        );
        _clearGraphPreparing();
        await generation;
        return;
      }
      final generation = _c.generateBookGraph(only: work, force: force);
      _clearGraphPreparing();
      await generation;
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          aiUserErrorMessage(error, operation: AiUserOperation.graph),
        );
      }
    } finally {
      _clearGraphPreparing();
    }
  }

  void _clearGraphPreparing() {
    if (!mounted || !_graphPreparing) return;
    setState(() {
      _graphPreparing = false;
      _graphPreparingWorkId = null;
    });
  }

  /// Pre-generation confirm dialog: runs the step-0 display plan (features +
  /// recommended view, user may pick another default view) **and** the
  /// auto-filtered graph corpus with a manual section chooser (uncheck to
  /// exclude a chapter). Returns the confirmed plan (null = keep the default
  /// view) + excluded section indices. Null = cancelled.
  Future<_NarrationConfirmation?> _confirmNarrationPlan(
    AiGraphWorkCandidate? work,
  ) async {
    final existing = work == null ? _c.bookGraph : _c.workGraphFor(work);
    return _showNarrationChooser(
      work: work,
      initialExcluded: existing?.excludedGraphSections.toSet() ?? const {},
      useRecommendedSelection: existing == null,
    );
  }

  Future<_NarrationConfirmation?> _showNarrationChooser({
    AiGraphWorkCandidate? work,
    Set<int> initialExcluded = const {},
    bool useRecommendedSelection = true,
    bool scopeOnly = false,
    String? dialogTitle,
    String? confirmLabel,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    final anchorPoint = appTrailingBottomOverlayAnchor(context);
    Widget chooser(BuildContext _) => NarrationPlanDialog(
      controller: _c,
      work: work,
      initialExcluded: initialExcluded,
      useRecommendedSelection: useRecommendedSelection,
      scopeOnly: scopeOnly,
      dialogTitle: dialogTitle,
      confirmLabel: confirmLabel,
      sheetLayout: context.appIsCompact,
    );
    if (context.appIsCompact) {
      return showAppBottomSheet<_NarrationConfirmation>(
        context,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
        showHandle: false,
        maxWidth: 640,
        anchorPoint: anchorPoint,
        builder: chooser,
      );
    }
    return showDialog<_NarrationConfirmation>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      anchorPoint: anchorPoint,
      builder: chooser,
    );
  }

  Future<void> _deleteGraph() async {
    if (_c.bookGraph == null || _c.isGeneratingBookGraph) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除图谱？',
      message: '只删除这本书保存的 AI 图谱，不影响对话与大纲。',
      confirmLabel: '删除图谱',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _c.deleteBookGraph();
  }

  Widget _buildGraphOperationStatus(BuildContext context) {
    final progress = _c.bookGraphProgress;
    final generating = _c.isGeneratingBookGraph;
    final label = _graphPreparing
        ? '正在准备知识图谱…'
        : progress?.label ?? '正在生成知识图谱…';
    return BookAiGraphOperationStatus(
      label: label,
      completed: progress?.completed ?? 0,
      total: progress?.total ?? 0,
      generating: generating,
      onCancel: _c.cancelBookGraphGeneration,
    );
  }

  Widget _withLiveStatus({
    required Widget child,
    required String label,
    bool announce = true,
  }) {
    if (!announce) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Semantics(
          container: true,
          liveRegion: true,
          label: label,
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final graphLiveStatus = _graphPreparing
        ? '正在准备知识图谱'
        : _c.isGeneratingBookGraph
        ? _c.bookGraphProgress?.label ?? '正在生成知识图谱'
        : _c.bookGraphError ??
              (_c.visibleBookGraph != null
                  ? '知识图谱已生成'
                  : _c.bookGraph != null
                  ? '知识图谱没有有效数据'
                  : '尚未生成知识图谱');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_graphBusy) _buildGraphOperationStatus(context),
        Expanded(
          child: _withLiveStatus(
            child: _buildGraphTab(context),
            label: graphLiveStatus,
            announce: !_graphBusy,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _graphQueryController.dispose();
    _graphScrollController.dispose();
    _graphHighlightTimer?.cancel();
    super.dispose();
  }
}

class _GraphUnavailable extends StatelessWidget {
  const _GraphUnavailable({
    required this.message,
    required this.onOpenSettings,
    required this.icon,
  });

  final String message;
  final VoidCallback onOpenSettings;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: context.appSecondaryText),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: context.aiBodySize,
                height: 1.45,
                color: context.appPrimaryText,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onOpenSettings, child: const Text('去设置')),
          ],
        ),
      ),
    );
  }
}

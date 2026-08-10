import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_mind_map_fullscreen.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_mind_map_view.dart';

void main() {
  final map = AiBookMindMap(
    contentHash: 'a' * 64,
    workKey: null,
    createdAt: DateTime.utc(2026, 8, 10),
    model: 'test',
    scopeSectionIndices: const [1],
    scopeFingerprint: 'scope',
    contentKind: AiMindMapContentKind.narrative,
    layout: AiMindMapLayout.rightFacing,
    nodes: const [
      AiBookMindMapNode(
        nodeId: 'mm001',
        parentId: null,
        order: 0,
        level: 0,
        title: '全书',
        summary: '总览',
      ),
      AiBookMindMapNode(
        nodeId: 'mm002',
        parentId: 'mm001',
        order: 0,
        level: 1,
        title: '主题甲',
        summary: '主题说明',
        evidence: [
          AiMindMapEvidence(
            sectionIndex: 1,
            quote: '原文证据',
            progressInSection: 0.25,
            spanResolved: true,
          ),
        ],
      ),
    ],
  );

  final styledMap = AiBookMindMap(
    contentHash: 'c' * 64,
    workKey: null,
    createdAt: DateTime.utc(2026, 8, 10),
    model: 'test',
    scopeSectionIndices: const [1],
    scopeFingerprint: 'styled-scope',
    contentKind: AiMindMapContentKind.argumentative,
    layout: AiMindMapLayout.bidirectional,
    nodes: const [
      AiBookMindMapNode(
        nodeId: 'root',
        parentId: null,
        order: 0,
        level: 0,
        title: '全书主题',
        summary: '整本书的中心结论',
      ),
      AiBookMindMapNode(
        nodeId: 'branch-a',
        parentId: 'root',
        order: 0,
        level: 1,
        title: '论点一',
        summary: '第一条主要论证',
      ),
      AiBookMindMapNode(
        nodeId: 'detail-a',
        parentId: 'branch-a',
        order: 0,
        level: 2,
        title: '事实依据',
        summary: '支撑第一条论证的正文事实',
      ),
      AiBookMindMapNode(
        nodeId: 'branch-b',
        parentId: 'root',
        order: 1,
        level: 1,
        title: '论点二',
        summary: '第二条主要论证',
      ),
    ],
  );

  final multiSectionMap = AiBookMindMap(
    contentHash: map.contentHash,
    workKey: map.workKey,
    createdAt: map.createdAt,
    model: map.model,
    scopeSectionIndices: const [1, 2],
    scopeFingerprint: 'multi-section-scope',
    contentKind: map.contentKind,
    layout: map.layout,
    nodes: map.nodes,
  );

  testWidgets('native view exposes layout, hierarchy list and node details', (
    tester,
  ) async {
    AiMindMapLayout? selected;
    AiMindMapEvidence? opened;
    var openedFullscreen = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BookAiMindMapView(
              map: map,
              onLayoutChanged: (value) => selected = value,
              onOpenEvidence: (value) => opened = value,
              onOpenFullscreen: () => openedFullscreen = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('向右'), findsOneWidget);
    expect(find.text('主题甲'), findsOneWidget);
    expect(find.text('主题说明'), findsOneWidget);

    await tester.tap(find.byTooltip('全屏查看'));
    expect(openedFullscreen, isTrue);

    final transformBefore = List<double>.from(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .storage,
    );
    await tester.tap(find.text('双向'));
    await tester.pump();
    await tester.pump();
    expect(selected, AiMindMapLayout.bidirectional);
    expect(
      tester
          .widget<SegmentedButton<AiMindMapLayout>>(
            find.byType(SegmentedButton<AiMindMapLayout>),
          )
          .selected,
      {AiMindMapLayout.bidirectional},
    );
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .storage,
      isNot(transformBefore),
    );

    await tester.tap(find.byTooltip('层级列表'));
    await tester.pumpAndSettle();
    expect(find.text('思维导图层级'), findsOneWidget);
    await tester.tap(find.text('主题甲').last);
    await tester.pumpAndSettle();
    expect(find.text('原文依据'), findsOneWidget);
    expect(find.text('本章 · 约 25% 处'), findsOneWidget);
    await tester.tap(find.text('本章 · 约 25% 处'));
    await tester.pumpAndSettle();
    expect(opened?.progressInSection, 0.25);
  });

  testWidgets(
    'fullscreen explorer fills its route and writes layout changes back',
    (tester) async {
      AiMindMapLayout? savedLayout;
      await tester.pumpWidget(
        MaterialApp(
          home: BookAiMindMapFullscreen(
            map: map,
            onLayoutChanged: (value) => savedLayout = value,
            onOpenEvidence: (_) {},
          ),
        ),
      );

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('思维导图'), findsOneWidget);
      expect(find.byTooltip('全屏查看'), findsNothing);

      await tester.tap(find.text('双向'));
      await tester.pump();
      expect(savedLayout, AiMindMapLayout.bidirectional);
    },
  );

  testWidgets('fullscreen evidence closes the explorer before navigation', (
    tester,
  ) async {
    AiMindMapEvidence? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookAiMindMapFullscreen(
                    map: map,
                    onLayoutChanged: (_) {},
                    onOpenEvidence: (value) => opened = value,
                  ),
                ),
              ),
              child: const Text('打开全屏'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本章 · 约 25% 处'));
    await tester.pumpAndSettle();

    expect(opened?.progressInSection, 0.25);
    expect(find.text('打开全屏'), findsOneWidget);
    expect(find.text('思维导图'), findsNothing);
  });

  testWidgets('multi-section evidence shows section and in-section progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BookAiMindMapView(
              map: multiSectionMap,
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('主题甲'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 节 · 约 25% 处'), findsOneWidget);
  });

  testWidgets('branch colors are distinct, inherited and theme-derived', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 650,
            child: BookAiMindMapView(
              map: styledMap,
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Color borderColorOf(String nodeId) {
      final surface = tester.widget<DecoratedBox>(
        find.byKey(ValueKey('mind-map-node-surface-$nodeId')),
      );
      final border = (surface.decoration as BoxDecoration).border! as Border;
      return border.top.color;
    }

    expect(borderColorOf('branch-a'), isNot(borderColorOf('branch-b')));
    expect(borderColorOf('detail-a'), borderColorOf('branch-a'));
    expect(
      find.byKey(const ValueKey('mind-map-branch-accent-branch-a')),
      findsNothing,
    );

    final rootSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mind-map-node-surface-root')),
    );
    final rootDecoration = rootSurface.decoration as BoxDecoration;
    expect(rootDecoration.gradient, isNull);
    expect(
      rootDecoration.color,
      isNot(AppTheme.light(AppColors.defaultAccent).colorScheme.primary),
    );
    expect(rootDecoration.boxShadow, isNotEmpty);

    final branchSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mind-map-node-surface-branch-a')),
    );
    final branchDecoration = branchSurface.decoration as BoxDecoration;
    expect(branchDecoration.color, isNotNull);
    expect(branchDecoration.border, isNotNull);
    final lightBranchSurface = branchDecoration.color;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppColors.defaultAccent),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 650,
            child: BookAiMindMapView(
              map: styledMap,
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(borderColorOf('branch-a'), isNot(borderColorOf('branch-b')));
    final darkBranchSurface =
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(
                        const ValueKey('mind-map-node-surface-branch-a'),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .color;
    expect(darkBranchSurface, isNot(lightBranchSurface));
  });

  testWidgets('trackpad scroll zoom keeps the scene point under the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BookAiMindMapView(
              map: map,
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewerFinder = find.byType(InteractiveViewer);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.trackpadScrollCausesScale, isTrue);
    final controller = viewer.transformationController!;
    final pointerLocal = const Offset(610, 250);
    final pointerGlobal = tester.getTopLeft(viewerFinder) + pointerLocal;
    final sceneBefore = controller.toScene(pointerLocal);
    final scaleBefore = controller.value.getMaxScaleOnAxis();

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: pointerGlobal,
        scrollDelta: const Offset(0, -20),
        kind: PointerDeviceKind.trackpad,
      ),
    );
    await tester.pump();

    final sceneAfter = controller.toScene(pointerLocal);
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(scaleBefore));
    expect((sceneAfter - sceneBefore).distance, lessThan(0.01));
  });

  testWidgets('collapsing a branch keeps the toggled node in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BookAiMindMapView(
              map: styledMap,
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final branch = find.byKey(const ValueKey('mind-map-node-surface-branch-a'));
    final collapse = find.descendant(
      of: branch,
      matching: find.byTooltip('折叠分支'),
    );
    final before = tester.getCenter(branch);

    await tester.tap(collapse);
    await tester.pump();
    await tester.pump();

    expect(find.text('事实依据'), findsNothing);
    expect((tester.getCenter(branch) - before).distance, lessThan(0.5));

    final expand = find.descendant(
      of: branch,
      matching: find.byTooltip('展开分支'),
    );
    await tester.tap(expand);
    await tester.pump();
    await tester.pump();

    expect(find.text('事实依据'), findsOneWidget);
    expect((tester.getCenter(branch) - before).distance, lessThan(0.5));
  });

  testWidgets('canvas has no nearby pan wall and supports wide zoom range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BookAiMindMapView(
              map: map,
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewerFinder = find.byType(InteractiveViewer);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.boundaryMargin.left, double.infinity);
    expect(viewer.minScale, 0.2);
    expect(viewer.maxScale, 6);

    final controller = viewer.transformationController!;
    final translationBefore = controller.value.getTranslation().x;
    final rect = tester.getRect(viewerFinder);
    final gesture = await tester.startGesture(
      Offset(rect.left + 20, rect.bottom - 20),
    );
    await gesture.moveBy(const Offset(600, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      controller.value.getTranslation().x - translationBefore,
      greaterThan(500),
    );
  });

  testWidgets('large maps start with deep branches collapsed', (tester) async {
    final nodes = <AiBookMindMapNode>[
      const AiBookMindMapNode(
        nodeId: 'root',
        parentId: null,
        order: 0,
        level: 0,
        title: '全书',
        summary: '总览',
      ),
      const AiBookMindMapNode(
        nodeId: 'branch',
        parentId: 'root',
        order: 0,
        level: 1,
        title: '主题',
        summary: '主题摘要',
      ),
      const AiBookMindMapNode(
        nodeId: 'deep',
        parentId: 'branch',
        order: 0,
        level: 2,
        title: '深层分支',
        summary: '深层摘要',
      ),
      for (var index = 0; index < 79; index++)
        AiBookMindMapNode(
          nodeId: 'leaf$index',
          parentId: 'deep',
          order: index,
          level: 3,
          title: '叶节点$index',
          summary: '叶节点摘要',
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BookAiMindMapView(
              map: AiBookMindMap(
                contentHash: 'b' * 64,
                workKey: null,
                createdAt: DateTime.utc(2026, 8, 10),
                model: 'test',
                scopeSectionIndices: const [1],
                scopeFingerprint: 'large-scope',
                contentKind: AiMindMapContentKind.reference,
                layout: AiMindMapLayout.rightFacing,
                nodes: nodes,
              ),
              onLayoutChanged: (_) {},
              onOpenEvidence: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('大图已默认折叠深层，可逐支展开'), findsOneWidget);
    expect(find.text('深层分支'), findsOneWidget);
    expect(find.text('叶节点0'), findsNothing);
  });
}

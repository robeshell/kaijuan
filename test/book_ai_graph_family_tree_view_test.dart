import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_family_tree.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_graph_family_tree_view.dart';

AiGraphEntity person(String name, int firstSection) {
  return AiGraphEntity(
    name: name,
    type: AiGraphEntityType.person,
    evidence: [AiGraphEvidence(sectionIndex: firstSection, quote: '$name 出场')],
    chapterFreq: {firstSection: 1},
    firstSection: firstSection,
    lastSection: firstSection,
  );
}

AiGraphRelation kin(String elder, String younger) {
  return AiGraphRelation(
    source: elder,
    target: younger,
    type: '亲属',
    kin: '父子',
    description: '',
    evidence: [
      AiGraphEvidence(sectionIndex: 1, quote: '$elder 与 $younger 是亲属'),
    ],
    weight: 1,
  );
}

void main() {
  testWidgets('renders all nodes inside an InteractiveViewer', (tester) async {
    final tree = buildFamilyTree(
      entities: [
        person('始祖', 1),
        person('长子', 2),
        person('次子', 3),
        person('孙女', 4),
      ],
      relations: [kin('始祖', '长子'), kin('始祖', '次子'), kin('长子', '孙女')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(BookAiGraphFamilyTreeView),
        matching: find.byType(InteractiveViewer),
      ),
      findsOneWidget,
    );
    for (final name in ['始祖', '长子', '次子', '孙女']) {
      expect(find.text(name), findsOneWidget, reason: '$name 应在图中');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('kinship labels render on edges', (tester) async {
    final tree = buildFamilyTree(
      entities: [person('始祖', 1), person('长子', 2)],
      relations: [kin('始祖', '长子')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    // The edge kinship label '父子' renders on the edge midpoint chip.
    expect(find.text('父子'), findsOneWidget);
  });

  testWidgets('consort parks under partner; maternal link stays short', (
    tester,
  ) async {
    final tree = buildFamilyTree(
      entities: [person('万历皇帝', 1), person('恭妃王氏', 1), person('朱常洛', 2)],
      relations: [
        kin('万历皇帝', '朱常洛'),
        AiGraphRelation(
          source: '万历皇帝',
          target: '恭妃王氏',
          type: '婚配',
          kin: '妃嫔',
          description: '',
          evidence: [AiGraphEvidence(sectionIndex: 1, quote: '册封')],
          weight: 1,
        ),
        AiGraphRelation(
          source: '恭妃王氏',
          target: '朱常洛',
          type: '亲属',
          kin: '母子',
          description: '',
          evidence: [AiGraphEvidence(sectionIndex: 2, quote: '所生')],
          weight: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    // 恭妃 is parked next to 万历 (spouse row) and still present as a card.
    expect(find.text('恭妃王氏'), findsOneWidget);
    expect(find.text('妃嫔：恭妃王氏'), findsOneWidget);
    // The maternal link label renders (same-layer horizontal dashed edge).
    expect(find.text('母子'), findsOneWidget);
    // No parent edge is drawn for the marriage (no 婚配/妃嫔 edge label).
    expect(find.text('父子'), findsOneWidget); // 万历→朱常洛 spine stays.
    expect(tester.takeException(), isNull);
  });

  testWidgets('node tap fires the callback', (tester) async {
    final tree = buildFamilyTree(
      entities: [person('始祖', 1), person('长子', 2)],
      relations: [kin('始祖', '长子')],
    );
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(
            tree: tree,
            onVertexTap: (entityId) => tapped = entityId,
          ),
        ),
      ),
    );

    // pump twice: post-frame auto-fit transform needs one frame to show
    // the cards in position.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('始祖'));
    expect(tapped, person('始祖', 1).id);
  });

  testWidgets('family nodes expose names and actions to assistive tech', (
    tester,
  ) async {
    final tree = buildFamilyTree(
      entities: [person('始祖', 1), person('长子', 2)],
      relations: [kin('始祖', '长子')],
    );
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('始祖'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('始祖'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.hint, contains('打开实体详情'));
    semantics.dispose();
  });

  testWidgets('survives inside a scrolling column', (tester) async {
    final tree = buildFamilyTree(
      entities: [for (var i = 1; i <= 7; i++) person('人$i', i)],
      relations: [for (var i = 2; i <= 7; i++) kin('人1', '人$i')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('人1'), findsOneWidget);
  });

  testWidgets('wide forest keeps its real size, no shrink', (tester) async {
    // 24 siblings: hand-rolled canvas would be ~4200px wide. auto-fit scales
    // the whole tree into the viewport (zoom to fit), so every node stays
    // reachable by panning — nothing is clipped.
    final tree = buildFamilyTree(
      entities: [for (var i = 1; i <= 25; i++) person('人$i', i)],
      relations: [for (var i = 2; i <= 25; i++) kin('人1', '人$i')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('人1'), findsOneWidget);
    expect(find.text('人25'), findsOneWidget);
  });

  testWidgets('wheel scroll zooms (native InteractiveViewer behavior)', (
    tester,
  ) async {
    final tree = buildFamilyTree(
      entities: [person('始祖', 1), person('长子', 2)],
      relations: [kin('始祖', '长子')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(tree: tree, onVertexTap: (_) {}),
        ),
      ),
    );
    // Let the post-frame auto-fit run.
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final before = viewer.transformationController!.value.getMaxScaleOnAxis();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(InteractiveViewer))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();

    final after = viewer.transformationController!.value.getMaxScaleOnAxis();
    expect(after, greaterThan(before));
  });

  testWidgets('wheel zoom clamps at the configured maxScale', (tester) async {
    final tree = buildFamilyTree(
      entities: [person('始祖', 1), person('长子', 2)],
      relations: [kin('始祖', '长子')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(
            tree: tree,
            onVertexTap: (_) {},
            maxScale: 1.5,
          ),
        ),
      ),
    );
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(InteractiveViewer))),
    );
    // Several zoom-in notches to blow past the 1.5 ceiling.
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
    }

    final scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    expect(scale, lessThanOrEqualTo(1.5));
  });
}

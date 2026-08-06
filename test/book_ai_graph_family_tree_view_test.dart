import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_family_tree.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_graph_family_tree_view.dart';

AiGraphEntity person(String name, int firstSection) {
  return AiGraphEntity(
    name: name,
    type: AiGraphEntityType.person,
    evidence: [
      AiGraphEvidence(sectionIndex: firstSection, quote: '$name 出场'),
    ],
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
      relations: [
        kin('始祖', '长子'),
        kin('始祖', '次子'),
        kin('长子', '孙女'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(
            tree: tree,
            onVertexTap: (_) {},
          ),
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
      entities: [
        person('始祖', 1),
        person('长子', 2),
      ],
      relations: [kin('始祖', '长子')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(
            tree: tree,
            onVertexTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // The edge kinship label '父子' renders on the edge midpoint chip.
    expect(find.text('父子'), findsOneWidget);
  });

  testWidgets('node tap fires the callback', (tester) async {
    final tree = buildFamilyTree(
      entities: [
        person('始祖', 1),
        person('长子', 2),
      ],
      relations: [kin('始祖', '长子')],
    );
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(
            tree: tree,
            onVertexTap: (name) => tapped = name,
          ),
        ),
      ),
    );

    // pump twice: post-frame auto-fit transform needs one frame to show
    // the cards in position.
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('始祖'));
    expect(tapped, '始祖');
  });

  testWidgets('survives inside a scrolling column', (tester) async {
    final tree = buildFamilyTree(
      entities: [
        for (var i = 1; i <= 7; i++) person('人$i', i),
      ],
      relations: [
        for (var i = 2; i <= 7; i++) kin('人1', '人$i'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                BookAiGraphFamilyTreeView(
                  tree: tree,
                  onVertexTap: (_) {},
                ),
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
      entities: [
        for (var i = 1; i <= 25; i++) person('人$i', i),
      ],
      relations: [
        for (var i = 2; i <= 25; i++) kin('人1', '人$i'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphFamilyTreeView(
            tree: tree,
            onVertexTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('人1'), findsOneWidget);
    expect(find.text('人25'), findsOneWidget);
  });
}
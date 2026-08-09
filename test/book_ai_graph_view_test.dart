import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_graph_view.dart';

AiGraphEntity _entity(String name, AiGraphEntityType type) {
  return AiGraphEntity(
    name: name,
    type: type,
    evidence: [AiGraphEvidence(sectionIndex: 1, quote: '$name 出场')],
    chapterFreq: const {1: 1},
    firstSection: 1,
    lastSection: 1,
  );
}

void main() {
  testWidgets('entity navigator is a real operable alternative to the canvas', (
    tester,
  ) async {
    String? tapped;
    final entities = [
      _entity('哈利', AiGraphEntityType.person),
      _entity('霍格沃茨', AiGraphEntityType.location),
    ];
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphEntityNavigator(
            entities: entities,
            onEntityTap: (id) => tapped = id,
          ),
        ),
      ),
    );

    expect(find.text('实体列表 2'), findsOneWidget);
    expect(find.bySemanticsLabel('关系图实体列表'), findsOneWidget);
    await tester.tap(find.text('实体列表 2'));
    await tester.pumpAndSettle();

    expect(find.text('哈利'), findsOneWidget);
    expect(find.text('霍格沃茨'), findsOneWidget);
    await tester.tap(find.text('哈利'));
    expect(tapped, entities.first.id);
    semantics.dispose();
  });

  testWidgets('entity navigator remains usable on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphEntityNavigator(
            entities: [_entity('一个名字很长的角色实体', AiGraphEntityType.person)],
            onEntityTap: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('实体列表 1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('一个名字很长的角色实体'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/reader/ai_relation_row.dart';

void main() {
  testWidgets('relation row exposes endpoint navigation and evidence', (
    tester,
  ) async {
    String? openedEntity;
    AiGraphEvidence? openedEvidence;
    const evidence = AiGraphEvidence(
      sectionIndex: 3,
      quote: '张三拜李四为师',
      spanResolved: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: SizedBox(
            width: 520,
            child: AiRelationRow(
              relation: const AiGraphRelation(
                source: '李四',
                target: '张三',
                sourceId: 'teacher',
                targetId: 'student',
                type: '师徒',
                evidence: [evidence],
              ),
              selfId: 'student',
              onEntityTap: (id) => openedEntity = id,
              onEvidenceTap: (item) => openedEvidence = item,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('李四'));
    expect(openedEntity, 'teacher');

    await tester.tap(find.textContaining('1 条出处'));
    await tester.pumpAndSettle();
    expect(find.text('张三拜李四为师'), findsOneWidget);

    await tester.tap(find.text('张三拜李四为师'));
    expect(openedEvidence, evidence);
    expect(tester.takeException(), isNull);
  });
}

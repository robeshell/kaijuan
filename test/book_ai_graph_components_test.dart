import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_graph_components.dart';

AiGraphEntity _entity(String name, AiGraphEntityType type) => AiGraphEntity(
  name: name,
  type: type,
  evidence: [AiGraphEvidence(sectionIndex: 1, quote: '$name 出场')],
  chapterFreq: const {1: 1},
  firstSection: 1,
  lastSection: 1,
);

void main() {
  testWidgets('graph navigation reports counts and changes product view', (
    tester,
  ) async {
    BookAiGraphViewMode? selected;
    final graph = AiBookGraph(
      contentHash: 'hash',
      entities: [
        _entity('人物甲', AiGraphEntityType.person),
        _entity('地点乙', AiGraphEntityType.location),
      ],
      relations: const [
        AiGraphRelation(source: '人物甲', target: '地点乙', type: 'visits'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphViewNavigation(
            graph: graph,
            selected: BookAiGraphViewMode.persons,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('人物 1'), findsOneWidget);
    expect(find.text('地点 1'), findsOneWidget);
    expect(find.text('关系图 1'), findsOneWidget);
    await tester.tap(find.text('地点 1'));
    expect(selected, BookAiGraphViewMode.locations);
  });

  testWidgets('work list delegates existing and missing work selection', (
    tester,
  ) async {
    const works = [
      AiBookWork(
        id: 'a',
        title: '第一部',
        startSection: 1,
        endSectionExclusive: 3,
      ),
      AiBookWork(
        id: 'b',
        title: '第二部',
        startSection: 3,
        endSectionExclusive: 5,
      ),
    ];
    AiBookWork? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphWorkList(
            works: works,
            readingWork: works.first,
            generatingWork: null,
            preparing: false,
            preparingWorkId: null,
            busy: false,
            error: null,
            progressLabel: null,
            titleSize: 16,
            isReady: (work) => work.id == 'a',
            onSelect: (work) => selected = work,
            onCancelGeneration: () {},
          ),
        ),
      ),
    );

    expect(find.text('本书包含 2 部作品'), findsNothing);
    expect(find.textContaining('这份文件包含 2 部作品'), findsOneWidget);
    expect(find.text('已生成 · 正在阅读'), findsOneWidget);
    expect(find.text('未生成'), findsOneWidget);
    await tester.tap(find.text('第二部'));
    expect(selected?.id, 'b');
  });

  testWidgets('operation status exposes progress and cancellation', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiGraphOperationStatus(
            label: '正在抽取实体与关系…',
            completed: 2,
            total: 5,
            generating: true,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );

    expect(find.text('正在抽取实体与关系…  2 / 5'), findsOneWidget);
    await tester.tap(find.text('停止'));
    expect(cancelled, isTrue);
  });
}

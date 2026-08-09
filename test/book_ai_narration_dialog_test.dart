import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_scope.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/book_reader_controller.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_narration_dialog.dart';

class _NarrationDialogController extends BookReaderController {
  _NarrationDialogController({
    required super.database,
    required super.item,
    required this.sections,
  });

  final List<AiBookSectionSlice> sections;
  int analyzeCalls = 0;

  @override
  bool get allowUnreadGraphContext => true;

  @override
  Future<AiNarrationPlan?> analyzeActiveGraphNarration({
    AiGraphWorkCandidate? work,
  }) async {
    analyzeCalls++;
    return const AiNarrationPlan(
      features: {
        'eventDriven': 0.8,
        'characterEnsemble': 0.7,
        'organization': 0.2,
        'geography': 0.1,
        'essay': 0.0,
      },
      defaultView: 'persons',
      viewOrder: ['persons', 'events', 'graph'],
    );
  }

  @override
  Future<AiGraphScopePlan> graphScopePlan(AiGraphWorkCandidate? work) async =>
      AiGraphScopePlanner.build(
        sections: sections,
        work: work,
        isSuggestedSupplement: (title) => title.contains('前言'),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'range chooser is flat, scrollable, and supports bulk selection',
    (tester) async {
      // Small-phone portrait also exercises the dialog's constrained width,
      // wrapped bulk actions and independently scrollable long scope list.
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 8);
      await database.upsertReadingItem(
        ReadingItemsCompanion.insert(
          id: 'narration-dialog',
          kind: ReaderKind.book.storageValue,
          format: ReaderFormat.epub.storageValue,
          title: '测试书',
          filePath: '/tmp/narration-dialog.epub',
          contentHash: 'hash-narration-dialog',
          pageCount: const Value(19),
          addedAt: now,
          updatedAt: now,
        ),
      );
      final item = (await database.readingItemById('narration-dialog'))!;
      final controller = _NarrationDialogController(
        database: database,
        item: item,
        sections: [
          for (var i = 1; i <= 19; i++)
            AiBookSectionSlice(index: i, label: '第 $i 章', text: '正文 $i'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          NarrationPlanDialog(controller: controller),
                    ),
                    child: const Text('打开'),
                  ),
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => NarrationPlanDialog(
                        controller: controller,
                        scopeOnly: true,
                        dialogTitle: '选择大纲范围',
                        confirmLabel: '生成大纲',
                      ),
                    ),
                    child: const Text('打开大纲范围'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('已选 19 / 19 节'), findsOneWidget);
      expect(find.text('选择内容范围'), findsNothing);
      expect(find.text('内容单元'), findsNothing);
      expect(find.textContaining('程序仅提供建议'), findsNothing);
      expect(find.byTooltip('批量选择'), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(tester.widget<Text>(find.text('生成知识图谱')).style?.fontSize, 16);
      expect(tester.widget<Text>(find.text('第 1 章')).style?.fontSize, 15);
      expect(
        tester.getSize(find.byKey(const ValueKey('ai-scope-toolbar'))).height,
        // The test uses 1.3× system text; keep the toolbar to one compact row
        // while allowing accessible text scaling instead of clipping it.
        lessThanOrEqualTo(52),
      );
      await tester.ensureVisible(find.text('第 19 章'));
      final layoutException = tester.takeException();
      expect(
        layoutException,
        isNull,
        reason: layoutException is FlutterError
            ? layoutException.toStringDeep()
            : '$layoutException',
      );

      await tester.ensureVisible(find.byTooltip('批量选择'));
      await tester.tap(find.byTooltip('批量选择'));
      await tester.pumpAndSettle();
      expect(find.text('选择推荐'), findsOneWidget);
      expect(find.text('全选可读项'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 / 19 节'), findsOneWidget);
      expect(find.text('请至少选择一节可读取内容'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '生成图谱'))
            .onPressed,
        isNull,
      );

      await tester.ensureVisible(find.text('第 1 章'));
      await tester.tap(find.text('第 1 章'));
      await tester.pump();
      expect(find.text('已选 1 / 19 节'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '生成图谱'))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.analyzeCalls, 1);
      await tester.tap(find.text('打开大纲范围'));
      await tester.pumpAndSettle();
      expect(find.text('选择大纲范围'), findsOneWidget);
      expect(find.text('生成大纲'), findsOneWidget);
      expect(find.text('首次展示'), findsNothing);
      expect(controller.analyzeCalls, 1);
    },
  );
}

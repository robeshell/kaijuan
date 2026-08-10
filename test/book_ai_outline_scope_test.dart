import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_scope.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_outline.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_search.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/book_reader_controller.dart';
import 'package:kaijuan/presentation/widgets/app_components.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_chat_sheet.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_language_sheet.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_mind_map_view.dart';
import 'package:kaijuan/readers/book/book_language_actions.dart';

class _AmbiguousOutlineController extends BookReaderController {
  _AmbiguousOutlineController({required super.database, required super.item});

  @override
  bool get canUseAiChat => true;

  @override
  bool get supportsDeepThinking => true;

  @override
  bool get defaultDeepThinkingEnabled => true;

  @override
  bool get hasAmbiguousInternalWorks => true;

  @override
  bool get hasCollectionWorks => false;

  @override
  bool get allowUnreadGraphContext => true;

  @override
  Future<List<AiGraphWorkCandidate>?> resolveGraphWorkCandidates({
    CancelToken? cancel,
  }) async => null;

  @override
  Future<AiBookOutline?> loadBookOutline({AiChatSession? session}) async =>
      null;

  @override
  Future<void> loadBookGraph() async {}

  @override
  Future<AiGraphScopePlan> graphScopePlan(AiGraphWorkCandidate? work) async {
    return AiGraphScopePlanner.build(
      sections: const [
        AiBookSectionSlice(index: 1, label: '第一篇', text: '正文一'),
        AiBookSectionSlice(index: 2, label: '第二篇', text: '正文二'),
      ],
      isSuggestedSupplement: (_) => false,
    );
  }

  final graphGate = Completer<void>();
  final chatCancelGates = <Completer<void>>[];
  final chatStreams = <StreamController<AiRunEvent>>[];
  AiBookGraph? graphOverride;
  bool _generatingGraph = false;
  bool? lastDeepThinkingEnabled;
  int? lastMindMapSourceSectionIndex;

  @override
  Future<AiBookSectionSlice?> captureCurrentBookMindMapChapter() async {
    return const AiBookSectionSlice(
      index: 1,
      sourceSectionIndex: 1,
      label: '当前章',
      text: '当前章正文',
    );
  }

  @override
  Future<AiBookMindMap?> generateBookMindMap({
    Set<int> excludedSectionIndices = const {},
    AiGraphWorkCandidate? work,
    AiBookSectionSlice? frozenCurrentChapter,
    bool useFrozenWork = false,
  }) async {
    lastMindMapSourceSectionIndex = frozenCurrentChapter?.originSectionIndex;
    return AiBookMindMap(
      contentHash: item.contentHash,
      workKey: null,
      createdAt: DateTime.utc(2026, 8, 10),
      model: 'test',
      scopeSectionIndices: [
        frozenCurrentChapter?.originSectionIndex ?? 1,
        if (frozenCurrentChapter == null) 2,
      ],
      scopeFingerprint: frozenCurrentChapter == null ? 'whole-book' : 'chapter',
      contentKind: AiMindMapContentKind.narrative,
      layout: AiMindMapLayout.radial,
      nodes: const [
        AiBookMindMapNode(
          nodeId: 'mm001',
          parentId: null,
          order: 0,
          level: 0,
          title: '主题',
          summary: '结构总览',
        ),
        AiBookMindMapNode(
          nodeId: 'mm002',
          parentId: 'mm001',
          order: 0,
          level: 1,
          title: '分支',
          summary: '分支说明',
          evidence: [
            AiMindMapEvidence(
              sectionIndex: 1,
              quote: '正文一',
              progressInSection: 0,
              spanResolved: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Stream<AiRunEvent>? streamBookChat({
    required String userText,
    required List<AiChatMessage> history,
    required AiChatContextBundle context,
    required AiGraphWorkCandidate? workScope,
    List<AiWebSearchHit>? webHits,
    bool? reasoningEnabled,
    CancelToken? cancelToken,
    String? runId,
  }) {
    lastDeepThinkingEnabled = reasoningEnabled;
    final gate = Completer<void>();
    chatCancelGates.add(gate);
    final descriptor = AiRunDescriptor(
      runId: runId ?? 'test-chat-${chatCancelGates.length}',
      task: AiRunTask.bookChat,
      scope: AiRunScope(contentHash: item.contentHash),
    );
    late final StreamController<AiRunEvent> stream;
    stream = StreamController<AiRunEvent>(
      onListen: () {
        scheduleMicrotask(() {
          if (stream.isClosed) return;
          final now = DateTime.now();
          stream
            ..add(
              AiRunStarted(
                descriptor: descriptor,
                sequence: 0,
                occurredAt: now,
              ),
            )
            ..add(
              AiRunModelStarted(
                runId: descriptor.runId,
                sequence: 1,
                occurredAt: now,
                purpose: AiRunModelPurpose.answer,
                callIndex: 1,
              ),
            )
            ..add(
              AiRunReasoningSnapshot(
                runId: descriptor.runId,
                sequence: 2,
                occurredAt: now,
                text: '先分析问题。',
                kind: AiReasoningContentKind.process,
              ),
            )
            ..add(
              AiRunTextSnapshot(
                runId: descriptor.runId,
                sequence: 3,
                occurredAt: now,
                text: '已经生成一部分',
              ),
            );
        });
      },
      onCancel: () => gate.future,
    );
    chatStreams.add(stream);
    return stream.stream;
  }

  void releaseChatCancellations() {
    for (final gate in chatCancelGates) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final stream in chatStreams) {
      if (!stream.isClosed) unawaited(stream.close());
    }
  }

  @override
  AiBookGraph? get bookGraph => graphOverride;

  @override
  AiBookGraph? get visibleBookGraph {
    final graph = graphOverride;
    if (graph == null) return null;
    final display = graph.verifiedForDisplay();
    return display.entities.isEmpty && display.relations.isEmpty
        ? null
        : display;
  }

  @override
  bool get isGeneratingBookGraph => _generatingGraph;

  @override
  AiGraphProgress? get bookGraphProgress => _generatingGraph
      ? const AiGraphProgress(completed: 0, total: 2, label: '正在抽取实体与关系…')
      : null;

  @override
  Future<AiNarrationPlan?> analyzeActiveGraphNarration({
    AiGraphWorkCandidate? work,
  }) async => const AiNarrationPlan(
    features: {
      'eventDriven': 0.8,
      'characterEnsemble': 0.7,
      'organization': 0.1,
      'geography': 0.1,
      'essay': 0,
    },
    defaultView: 'persons',
    viewOrder: ['persons', 'events', 'graph'],
  );

  @override
  Future<void> generateBookGraph({
    AiGraphWorkCandidate? only,
    bool force = false,
    AiNarrationPlan? narrationOverride,
    AiNarrationPlanMode narrationMode = AiNarrationPlanMode.autoAnalyze,
    Set<int>? excludedGraphSectionIndices,
  }) {
    _generatingGraph = true;
    notifyListeners();
    return graphGate.future.whenComplete(() {
      _generatingGraph = false;
      notifyListeners();
    });
  }

  @override
  void cancelBookGraphGeneration() {
    if (!graphGate.isCompleted) graphGate.complete();
  }
}

class _CompletedChatController extends _AmbiguousOutlineController {
  _CompletedChatController({required super.database, required super.item});

  @override
  Stream<AiRunEvent>? streamBookChat({
    required String userText,
    required List<AiChatMessage> history,
    required AiChatContextBundle context,
    required AiGraphWorkCandidate? workScope,
    List<AiWebSearchHit>? webHits,
    bool? reasoningEnabled,
    CancelToken? cancelToken,
    String? runId,
  }) async* {
    final descriptor = AiRunDescriptor(
      runId: runId ?? 'completed-chat',
      task: AiRunTask.bookChat,
      scope: AiRunScope(contentHash: item.contentHash),
    );
    final now = DateTime.now();
    yield AiRunStarted(descriptor: descriptor, sequence: 0, occurredAt: now);
    yield AiRunModelStarted(
      runId: descriptor.runId,
      sequence: 1,
      occurredAt: now,
      purpose: AiRunModelPurpose.answer,
      callIndex: 1,
    );
    yield AiRunTextSnapshot(
      runId: descriptor.runId,
      sequence: 2,
      occurredAt: now,
      text: List.filled(18, '这是一段用于撑高回答区域的测试内容。').join('\n\n'),
    );
  }

  @override
  Future<List<String>> suggestBookChatFollowUps({
    required String userText,
    required String answer,
    required AiChatContextBundle context,
    CancelToken? cancelToken,
  }) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ambiguous publication offers outline as a chat shortcut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 9);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'ambiguous-outline',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '测试合订本',
        filePath: '/tmp/ambiguous-outline.epub',
        contentHash: 'hash-ambiguous-outline',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('ambiguous-outline'))!;
    final controller = _AmbiguousOutlineController(
      database: database,
      item: item,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showBookAiChatSheet(context, controller: controller),
              child: const Text('打开 AI'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    final composer = find.byKey(const ValueKey<String>('ai-chat-composer'));
    expect(composer, findsOneWidget);
    expect(tester.getSize(composer).height, 44);
    expect(tester.getSize(find.byTooltip('发送')), const Size.square(44));
    final chatField = tester.widget<TextField>(find.byType(TextField).last);
    expect(chatField.style?.fontSize, 16);
    expect(chatField.enabled, isNot(equals(false)));
    expect(chatField.decoration?.hintText, '问这本书…');
    expect(find.byTooltip('深度思考已开启'), findsOneWidget);

    expect(find.widgetWithText(Tab, '大纲'), findsNothing);
    expect(find.widgetWithText(Tab, '思维导图'), findsNothing);
    expect(find.text('生成本书大纲'), findsOneWidget);
    expect(find.text('生成本章思维导图'), findsOneWidget);
    expect(find.text('选择范围生成大纲'), findsNothing);
    expect(find.text('选择范围并生成'), findsNothing);
  });

  testWidgets('mind maps route by chat intent and render inside conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 10);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'mind-map-chat',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '思维导图测试',
        filePath: '/tmp/mind-map-chat.epub',
        contentHash: 'hash-mind-map-chat',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('mind-map-chat'))!;
    final controller = _AmbiguousOutlineController(
      database: database,
      item: item,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showBookAiChatSheet(context, controller: controller),
              child: const Text('打开 AI'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成本章思维导图'));
    await tester.pumpAndSettle();
    expect(controller.lastMindMapSourceSectionIndex, 1);
    expect(find.byType(BookAiMindMapView), findsOneWidget);
    expect(find.text('已根据当前章生成思维导图。'), findsOneWidget);
    expect(find.widgetWithText(Tab, '思维导图'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '为这本书生成思维导图');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(controller.lastMindMapSourceSectionIndex, isNull);
    // The conversation ListView lazily builds only the visible artifact card.
    expect(find.byType(BookAiMindMapView), findsWidgets);
    expect(find.text('已根据这本书生成思维导图。'), findsOneWidget);
  });

  testWidgets('chat stop and close react on the first tap', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 9);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'chat-one-tap-cancel',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '停止测试',
        filePath: '/tmp/chat-one-tap-cancel.epub',
        contentHash: 'hash-chat-one-tap-cancel',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('chat-one-tap-cancel'))!;
    final controller = _AmbiguousOutlineController(
      database: database,
      item: item,
    );
    addTearDown(() {
      controller.releaseChatCancellations();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showBookAiChatSheet(context, controller: controller),
              child: const Text('打开 AI'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('ai-chat-deep-thinking-toggle')),
    );
    await tester.pump();
    expect(find.byTooltip('开启深度思考'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '第一次问题');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();
    expect(controller.lastDeepThinkingEnabled, isFalse);
    expect(find.text('正在思考'), findsOneWidget);
    expect(find.text('先分析问题。'), findsOneWidget);
    expect(find.textContaining('已经生成一部分'), findsOneWidget);

    await tester.tap(find.byTooltip('停止'));
    await tester.pump();
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.text('回答已停止'), findsOneWidget);
    expect(find.text('思考过程'), findsOneWidget);
    expect(find.text('先分析问题。'), findsNothing);
    await tester.tap(find.text('思考过程'));
    await tester.pump();
    expect(find.text('先分析问题。'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '第二次问题');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('停止'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.text('打开 AI'), findsOneWidget);

    controller.releaseChatCancellations();
  });

  testWidgets(
    'fallback follow-up shortcuts scroll into view after completion',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 10);
      await database.upsertReadingItem(
        ReadingItemsCompanion.insert(
          id: 'chat-fallback-scroll',
          kind: ReaderKind.book.storageValue,
          format: ReaderFormat.epub.storageValue,
          title: '快捷追问滚动测试',
          filePath: '/tmp/chat-fallback-scroll.epub',
          contentHash: 'hash-chat-fallback-scroll',
          pageCount: const Value(2),
          addedAt: now,
          updatedAt: now,
        ),
      );
      final item = (await database.readingItemById('chat-fallback-scroll'))!;
      final controller = _CompletedChatController(
        database: database,
        item: item,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () =>
                    showBookAiChatSheet(context, controller: controller),
                child: const Text('打开 AI'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开 AI'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '请介绍这本书');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(find.text('结合书中内容再展开'), findsOneWidget);
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey<String>('ai-chat-message-list')),
      );
      expect(list.controller!.position.extentAfter, lessThan(1));
    },
  );

  testWidgets('phone graph generation keeps visible feedback across routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 9);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'mobile-graph-flow',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '测试图谱',
        filePath: '/tmp/mobile-graph-flow.epub',
        contentHash: 'hash-mobile-graph-flow',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('mobile-graph-flow'))!;
    final controller = _AmbiguousOutlineController(
      database: database,
      item: item,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showBookAiChatSheet(context, controller: controller),
              child: const Text('打开 AI'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知识图谱'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '生成图谱'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('graph-operation-status')),
      findsOneWidget,
    );
    expect(find.text('正在准备知识图谱…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey<String>('narration-plan-sheet')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('正在读取内容范围…'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '生成图谱').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey<String>('graph-operation-status')),
      findsOneWidget,
    );
    expect(find.textContaining('正在抽取实体与关系…'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);

    controller.graphGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('知识图谱'), findsWidgets);
  });

  testWidgets('phone empty graph shows recovery instead of five zero tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 9);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'mobile-empty-graph',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '空图谱测试',
        filePath: '/tmp/mobile-empty-graph.epub',
        contentHash: 'hash-mobile-empty-graph',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('mobile-empty-graph'))!;
    final controller =
        _AmbiguousOutlineController(database: database, item: item)
          ..graphOverride = const AiBookGraph(
            contentHash: 'hash-mobile-empty-graph',
            coveredSections: [1, 2],
          );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showBookAiChatSheet(context, controller: controller),
              child: const Text('打开 AI'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知识图谱'));
    await tester.pumpAndSettle();

    expect(find.text('尚无有效图谱数据'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重新生成图谱'), findsOneWidget);
    for (final zeroTab in ['人物 0', '地点 0', '事件 0', '组织 0', '事物 0']) {
      expect(find.text(zeroTab), findsNothing);
    }
  });

  testWidgets('open fold keeps all AI tabs in the trailing pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 9);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'fold-ai-tabs',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '折叠屏测试书',
        filePath: '/tmp/fold-ai-tabs.epub',
        contentHash: 'hash-fold-ai-tabs',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('fold-ai-tabs'))!;
    final controller = _AmbiguousOutlineController(
      database: database,
      item: item,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            displayFeatures: const [
              DisplayFeature(
                bounds: Rect.fromLTWH(395, 0, 10, 600),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                FilledButton(
                  onPressed: () =>
                      showBookAiChatSheet(context, controller: controller),
                  child: const Text('打开 AI'),
                ),
                FilledButton(
                  onPressed: () => showBookAiLanguageSheet(
                    context,
                    controller: controller,
                    operation: BookLanguageOperation.dictionary,
                    text: 'magic',
                  ),
                  child: const Text('打开词典'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    expect(find.byType(AppSideSheet), findsOneWidget);
    final panelRect = tester.getRect(find.byType(AppSideSheet));
    expect(panelRect.right, 800);
    expect(panelRect.left, greaterThanOrEqualTo(405));
    for (final tab in ['对话', '知识图谱']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.widgetWithText(Tab, '大纲'), findsNothing);
    expect(find.text('生成本书大纲'), findsOneWidget);
    await tester.tap(find.text('知识图谱'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '生成图谱'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '生成图谱'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.getRect(find.byType(AlertDialog)).left,
      greaterThanOrEqualTo(405),
    );
    expect(
      find.byKey(const ValueKey<String>('narration-plan-sheet')),
      findsNothing,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开词典'));
    await tester.pumpAndSettle();
    final quickSheetRect = tester.getRect(find.byType(AppBottomSheet));
    expect(quickSheetRect.left, greaterThanOrEqualTo(405));
    expect(find.text('AI 未启用或未配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

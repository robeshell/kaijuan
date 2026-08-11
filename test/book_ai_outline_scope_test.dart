import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_store.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_scope.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_outline.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
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
  }) async {
    structureResolveCalls++;
    return null;
  }

  @override
  Future<List<AiGraphWorkCandidate>?> resolveBookStructure({
    CancelToken? cancel,
  }) async {
    structureResolveCalls++;
    return null;
  }

  @override
  Future<List<AiBookSectionSlice>> bookMindMapSections({
    AiGraphWorkCandidate? work,
    bool useFrozenWork = false,
  }) async {
    mindMapSectionCalls++;
    await mindMapSectionsGate?.future;
    return work == null
        ? const [
            AiBookSectionSlice(index: 1, label: '第一章', text: '正文一'),
            AiBookSectionSlice(index: 2, label: '第二章', text: '正文二'),
          ]
        : [
            AiBookSectionSlice(
              index: work.startSection,
              sourceSectionIndex: work.startSection,
              label: '${work.title}第一章',
              text: '${work.title}正文',
            ),
          ];
  }

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
  AiBookStructureManifest? manifestOverride;
  bool _generatingGraph = false;
  bool? lastDeepThinkingEnabled;
  String? lastChatRunId;
  int? lastMindMapSourceSectionIndex;
  AiGraphWorkCandidate? lastMindMapWork;
  bool? lastMindMapUseFrozenWork;
  int structureResolveCalls = 0;
  int mindMapFailuresRemaining = 0;
  Completer<void>? mindMapGate;
  Completer<void>? mindMapSectionsGate;
  int mindMapSectionCalls = 0;
  AiBookWork? currentWorkOverride;
  AiBookMindMap? lastExistingMindMap;
  final generatedMindMapScopes = <String>[];
  AiProductActionRequest? productActionOverride;
  int productActionRequests = 0;

  @override
  AiBookStructureManifest? get bookStructureManifest => manifestOverride;

  @override
  AiBookWork? get currentReadingWork => currentWorkOverride;

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
    AiGraphWorkCandidate? work,
    AiBookSectionSlice? frozenCurrentChapter,
    List<AiBookSectionSlice>? frozenSections,
    AiBookMindMap? existingMindMap,
    bool useFrozenWork = false,
    required String userInstruction,
    String? scopeLabel,
    String? progressLabel,
  }) async {
    generatedMindMapScopes.add(scopeLabel ?? '');
    lastExistingMindMap = existingMindMap;
    lastMindMapWork = work;
    lastMindMapUseFrozenWork = useFrozenWork;
    lastMindMapSourceSectionIndex =
        frozenCurrentChapter?.originSectionIndex ??
        (frozenSections?.length == 1
            ? frozenSections!.single.originSectionIndex
            : null);
    await mindMapGate?.future;
    if (mindMapFailuresRemaining > 0) {
      mindMapFailuresRemaining--;
      return null;
    }
    return AiBookMindMap(
      contentHash: item.contentHash,
      workKey: null,
      createdAt: DateTime.utc(2026, 8, 10),
      model: 'test',
      scopeSectionIndices: [
        for (final section
            in frozenSections ??
                (frozenCurrentChapter == null
                    ? const [
                        AiBookSectionSlice(index: 1, label: '第一章', text: '正文一'),
                        AiBookSectionSlice(index: 2, label: '第二章', text: '正文二'),
                      ]
                    : [frozenCurrentChapter]))
          section.originSectionIndex,
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
    required AiBookWork? workScope,
    List<AiWebSearchHit>? webHits,
    AiChatProductContext productContext = const AiChatProductContext(),
    bool? reasoningEnabled,
    CancelToken? cancelToken,
    String? runId,
  }) {
    final requestedAction =
        productActionOverride ??
        _defaultProductAction(userText, productContext);
    if (requestedAction != null) {
      productActionRequests++;
      final descriptor = AiRunDescriptor(
        runId: runId ?? 'test-product-action-$productActionRequests',
        task: AiRunTask.bookChat,
        scope: AiRunScope(contentHash: item.contentHash),
      );
      return Stream<AiRunEvent>.fromIterable([
        AiRunStarted(
          descriptor: descriptor,
          sequence: 0,
          occurredAt: DateTime.now(),
        ),
        AiRunProductActionRequested(
          runId: descriptor.runId,
          sequence: 1,
          occurredAt: DateTime.now(),
          request: requestedAction,
        ),
      ]);
    }
    lastDeepThinkingEnabled = reasoningEnabled;
    final gate = Completer<void>();
    chatCancelGates.add(gate);
    final descriptor = AiRunDescriptor(
      runId: runId ?? 'test-chat-${chatCancelGates.length}',
      task: AiRunTask.bookChat,
      scope: AiRunScope(contentHash: item.contentHash),
    );
    lastChatRunId = descriptor.runId;
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

  AiProductActionRequest? _defaultProductAction(
    String text,
    AiChatProductContext context,
  ) {
    if (text.contains('思维导图') && (text.contains('生成') || text.contains('需要'))) {
      return AiCreateBookMindMapAction(
        instruction: text,
        scope: text.contains('本章') || text.contains('当前章')
            ? AiBookMindMapActionScope.currentChapter
            : text.contains('这本书') ||
                  text.contains('整本书') ||
                  text.contains('全书')
            ? AiBookMindMapActionScope.wholePublication
            : AiBookMindMapActionScope.unspecified,
      );
    }
    if (text.contains('再丰富') ||
        text.contains('增加更多') ||
        text.contains('修改上一张')) {
      final artifacts = context.artifacts;
      if (artifacts.isEmpty) return null;
      final target =
          artifacts.where((artifact) => artifact.isPreferred).firstOrNull ??
          artifacts.where((artifact) => artifact.isAdjacent).firstOrNull ??
          artifacts.last;
      return AiReviseBookMindMapAction(
        instruction: text,
        artifactAlias: target.alias,
        artifactId: target.artifactId,
      );
    }
    return null;
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
    required AiBookWork? workScope,
    List<AiWebSearchHit>? webHits,
    AiChatProductContext productContext = const AiChatProductContext(),
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
    expect(controller.structureResolveCalls, 0);

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

    controller.mindMapFailuresRemaining = 1;
    await tester.tap(find.text('生成本章思维导图'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(controller.lastMindMapSourceSectionIndex, 1);
    expect(find.byType(BookAiMindMapView), findsOneWidget);
    expect(find.text('已根据《当前章》的 1 章内容生成思维导图。'), findsOneWidget);
    final retryMessageList = tester.widget<ListView>(
      find.byKey(const ValueKey<String>('ai-chat-message-list')),
    );
    retryMessageList.controller!.jumpTo(0);
    await tester.pump();
    expect(find.text('请为当前章生成思维导图'), findsOneWidget);
    expect(find.widgetWithText(Tab, '思维导图'), findsNothing);

    final chapterMap = find.byType(BookAiMindMapView).first;
    final messageList = tester.widget<ListView>(
      find.byKey(const ValueKey<String>('ai-chat-message-list')),
    );
    final listController = messageList.controller!;
    final listOffsetBeforeZoom = listController.offset;
    final viewerFinder = find.descendant(
      of: chapterMap,
      matching: find.byType(InteractiveViewer),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(viewerFinder));
    await tester.pump();
    expect(
      tester
          .widget<ListView>(
            find.byKey(const ValueKey<String>('ai-chat-message-list')),
          )
          .physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final scaleBeforeZoom = viewer.transformationController!.value
        .getMaxScaleOnAxis();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewerFinder),
        scrollDelta: const Offset(0, -20),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(scaleBeforeZoom),
    );
    expect(listController.offset, closeTo(listOffsetBeforeZoom, 0.01));
    await mouse.moveTo(tester.getCenter(find.text('对话')));
    await tester.pump();
    expect(
      tester
          .widget<ListView>(
            find.byKey(const ValueKey<String>('ai-chat-message-list')),
          )
          .physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
    );
    await mouse.removePointer();

    await tester.tap(
      find.descendant(of: chapterMap, matching: find.text('向右')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<AiMindMapLayout>>(
            find
                .descendant(
                  of: find.byType(BookAiMindMapView).first,
                  matching: find.byType(SegmentedButton<AiMindMapLayout>),
                )
                .first,
          )
          .selected,
      {AiMindMapLayout.rightFacing},
    );
    expect(
      tester
          .widget<BookAiMindMapView>(find.byType(BookAiMindMapView).first)
          .map
          .layout,
      AiMindMapLayout.rightFacing,
    );

    final structureCallsBeforeWholeBook = controller.structureResolveCalls;
    await tester.enterText(find.byType(TextField).last, '为这本书生成思维导图');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.structureResolveCalls, structureCallsBeforeWholeBook + 2);
    expect(controller.lastMindMapSourceSectionIndex, isNull);
    expect(controller.lastMindMapWork, isNull);
    expect(controller.lastMindMapUseFrozenWork, isTrue);
    // The conversation ListView lazily builds only the visible artifact card.
    expect(find.byType(BookAiMindMapView), findsWidgets);
    expect(find.text('已根据《思维导图测试》的 2 章内容生成思维导图。'), findsOneWidget);
    final editButton = tester.widget<TextButton>(
      find
          .ancestor(
            of: find.text('继续修改').last,
            matching: find.byType(TextButton),
          )
          .last,
    );
    editButton.onPressed!();
    await tester.pump();
    expect(find.textContaining('正在修改：'), findsOneWidget);
    final actionCallsBeforeDiscussion = controller.productActionRequests;
    await tester.enterText(find.byType(TextField).last, '我还是觉得不对');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(controller.productActionRequests, actionCallsBeforeDiscussion);
    expect(controller.chatStreams, hasLength(1));
    expect(find.textContaining('正在修改：'), findsOneWidget);
  });

  testWidgets('a follow-up to a Mermaid map remains ordinary rich conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 11);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'legacy-mermaid-map',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '旧导图迁移测试',
        filePath: '/tmp/legacy-mermaid-map.epub',
        contentHash: 'hash-legacy-mermaid-map',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final store = MemoryAiChatHistoryStore();
    await store.write(
      const AiChatSession(
        contentHash: 'hash-legacy-mermaid-map',
        itemId: 'legacy-mermaid-map',
        messages: [
          AiChatMessage(
            role: AiMessageRole.user,
            content: '我需要这本书的思维导图',
            turnId: 'legacy-turn',
          ),
          AiChatMessage(
            role: AiMessageRole.assistant,
            content:
                '''好的。\n```mermaid\n%%{init: {'theme': 'base'}}%%\nmindmap\n  root((全书))\n    主题\n```''',
            turnId: 'legacy-turn',
          ),
        ],
      ),
    );
    final controller = _AmbiguousOutlineController(
      database: database,
      item: (await database.readingItemById('legacy-mermaid-map'))!,
    )..attachChatHistoryStore(store);
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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).last, '再丰富点内容');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(controller.generatedMindMapScopes, isEmpty);
    expect(controller.productActionRequests, 0);
    expect(controller.chatStreams, hasLength(1));
    expect(find.byType(BookAiMindMapView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a concise follow-up edits the adjacent native map without edit mode',
    (tester) async {
      tester.view.physicalSize = const Size(820, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 11);
      await database.upsertReadingItem(
        ReadingItemsCompanion.insert(
          id: 'adjacent-native-map',
          kind: ReaderKind.book.storageValue,
          format: ReaderFormat.epub.storageValue,
          title: '相邻导图测试',
          filePath: '/tmp/adjacent-native-map.epub',
          contentHash: 'hash-adjacent-native-map',
          pageCount: const Value(2),
          addedAt: now,
          updatedAt: now,
        ),
      );
      final store = MemoryAiChatHistoryStore();
      await store.write(
        AiChatSession(
          contentHash: 'hash-adjacent-native-map',
          itemId: 'adjacent-native-map',
          messages: [
            AiChatMessage(
              role: AiMessageRole.assistant,
              content: '已生成思维导图。',
              turnId: 'native-turn',
              mindMap: AiBookMindMap(
                contentHash: 'hash-adjacent-native-map',
                workKey: null,
                createdAt: now,
                model: 'test',
                artifactId: 'native-map',
                scopeSectionIndices: const [1, 2],
                scopeFingerprint: 'whole-book',
                contentKind: AiMindMapContentKind.narrative,
                layout: AiMindMapLayout.bidirectional,
                nodes: const [
                  AiBookMindMapNode(
                    nodeId: 'mm001',
                    parentId: null,
                    order: 0,
                    level: 0,
                    title: '原始主题',
                    summary: '原始摘要',
                  ),
                  AiBookMindMapNode(
                    nodeId: 'mm002',
                    parentId: 'mm001',
                    order: 0,
                    level: 1,
                    title: '原始分支',
                    summary: '原始分支摘要',
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
              ),
            ),
          ],
        ),
      );
      final controller = _AmbiguousOutlineController(
        database: database,
        item: (await database.readingItemById('adjacent-native-map'))!,
      )..attachChatHistoryStore(store);
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
      expect(find.textContaining('正在修改：'), findsNothing);

      await tester.enterText(find.byType(TextField).last, '再丰富点');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(controller.generatedMindMapScopes, ['原始主题']);
      expect(controller.lastExistingMindMap?.artifactId, 'native-map');
      expect(controller.productActionRequests, 1);
      expect(controller.chatStreams, isEmpty);
      expect(find.byType(BookAiMindMapView), findsWidgets);

      await tester.enterText(find.byType(TextField).last, '为什么这样整理？');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(controller.generatedMindMapScopes, hasLength(1));
      expect(controller.productActionRequests, 1);
      expect(controller.chatStreams, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mind map revision locks preflight and restores the artifact scope exactly',
    (tester) async {
      tester.view.physicalSize = const Size(820, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 11);
      await database.upsertReadingItem(
        ReadingItemsCompanion.insert(
          id: 'mind-map-revision',
          kind: ReaderKind.book.storageValue,
          format: ReaderFormat.epub.storageValue,
          title: '导图修订测试',
          filePath: '/tmp/mind-map-revision.epub',
          contentHash: 'hash-mind-map-revision',
          pageCount: const Value(2),
          addedAt: now,
          updatedAt: now,
        ),
      );
      const work = AiBookWork(
        id: 'work-1',
        title: '当前作品',
        startSection: 1,
        endSectionExclusive: 3,
      );
      AiBookMindMap map({required String artifactId, String? workKey}) =>
          AiBookMindMap(
            contentHash: 'hash-mind-map-revision',
            workKey: workKey,
            createdAt: now,
            model: 'test',
            artifactId: artifactId,
            scopeSectionIndices: const [1],
            scopeFingerprint: '$artifactId-scope',
            contentKind: AiMindMapContentKind.narrative,
            layout: AiMindMapLayout.bidirectional,
            nodes: const [
              AiBookMindMapNode(
                nodeId: 'mm001',
                parentId: null,
                order: 0,
                level: 0,
                title: '原始主题',
                summary: '原始摘要',
              ),
            ],
          );

      final store = MemoryAiChatHistoryStore();
      await store.write(
        AiChatSession(
          contentHash: 'hash-mind-map-revision',
          itemId: 'mind-map-revision',
          workMessages: {
            work.id: [
              AiChatMessage(
                role: AiMessageRole.assistant,
                content: '整本范围导图',
                turnId: 'turn-whole',
                mindMap: map(artifactId: 'map-whole'),
              ),
              AiChatMessage(
                role: AiMessageRole.assistant,
                content: '失效作品导图',
                turnId: 'turn-missing',
                mindMap: map(
                  artifactId: 'map-missing',
                  workKey: 'missing-work',
                ),
              ),
            ],
          },
        ),
      );
      final sectionsGate = Completer<void>();
      final controller =
          _AmbiguousOutlineController(
              database: database,
              item: (await database.readingItemById('mind-map-revision'))!,
            )
            ..attachChatHistoryStore(store)
            ..currentWorkOverride = work
            ..manifestOverride = const AiBookStructureManifest(
              kind: AiBookStructureKind.multiWorkOmnibus,
              source: AiBookStructureSource.navigationHierarchy,
              confidence: 0.9,
              reason: 'test',
              works: [work],
            )
            ..mindMapSectionsGate = sectionsGate;
      addTearDown(() {
        if (!sectionsGate.isCompleted) sectionsGate.complete();
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

      controller.productActionOverride = const AiReviseBookMindMapAction(
        instruction: '修改这张思维导图',
        artifactAlias: 'artifact_2',
        artifactId: 'map-missing',
      );
      await tester.enterText(find.byType(TextField).last, '修改这张思维导图');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.textContaining('作品范围已经变化'), findsOneWidget);
      expect(controller.mindMapSectionCalls, 0);
      expect(controller.generatedMindMapScopes, isEmpty);

      controller.productActionOverride = const AiReviseBookMindMapAction(
        instruction: '修改上一张思维导图',
        artifactAlias: 'artifact_1',
        artifactId: 'map-whole',
      );
      await tester.enterText(find.byType(TextField).last, '修改上一张思维导图');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(controller.mindMapSectionCalls, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).enabled,
        isFalse,
      );

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(controller.mindMapSectionCalls, 1);

      sectionsGate.complete();
      await tester.pumpAndSettle();
      expect(controller.generatedMindMapScopes, hasLength(1));
      expect(controller.lastMindMapWork, isNull);
      expect(find.text('已根据《原始主题》的 1 章内容生成思维导图。'), findsOneWidget);
      expect(find.textContaining('正在修改：'), findsNothing);
      final revisedMapId = controller.lastExistingMindMap?.artifactId;
      controller.productActionOverride = AiReviseBookMindMapAction(
        instruction: '增加更多事实细节',
        artifactAlias: 'artifact_3',
        artifactId: revisedMapId ?? 'map-whole',
      );
      await tester.enterText(find.byType(TextField).last, '增加更多事实细节');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(controller.generatedMindMapScopes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('omnibus mind map explains scope and waits for a work choice', (
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
        id: 'mind-map-omnibus',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '测试合集',
        filePath: '/tmp/mind-map-omnibus.epub',
        contentHash: 'hash-mind-map-omnibus',
        pageCount: const Value(4),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final controller =
        _AmbiguousOutlineController(
            database: database,
            item: (await database.readingItemById('mind-map-omnibus'))!,
          )
          ..manifestOverride = const AiBookStructureManifest(
            kind: AiBookStructureKind.multiWorkOmnibus,
            source: AiBookStructureSource.navigationHierarchy,
            confidence: 0.95,
            reason: 'test omnibus',
            works: [
              AiBookWork(
                id: 'work-a',
                title: '作品甲',
                startSection: 1,
                endSectionExclusive: 3,
              ),
              AiBookWork(
                id: 'work-b',
                title: '作品乙',
                startSection: 3,
                endSectionExclusive: 5,
              ),
            ],
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
    await tester.enterText(find.byType(TextField).last, '生成整本书思维导图');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('本书包含 2 部作品，共 4 章'), findsOneWidget);
    expect(find.text('全部作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('ai-mind-map-scope-choice-card')),
      findsOneWidget,
    );
    expect(find.byType(AppDialog), findsNothing);
    final allChoice = find.byKey(
      const ValueKey<String>('ai-mind-map-scope--1'),
    );
    final firstChoice = find.byKey(
      const ValueKey<String>('ai-mind-map-scope-0'),
    );
    final secondChoice = find.byKey(
      const ValueKey<String>('ai-mind-map-scope-1'),
    );
    expect(allChoice, findsOneWidget);
    expect(firstChoice, findsOneWidget);
    expect(secondChoice, findsOneWidget);
    expect(
      tester.getTopLeft(allChoice).dy,
      lessThan(tester.getTopLeft(firstChoice).dy),
    );
    expect(
      tester.getTopLeft(firstChoice).dy,
      lessThan(tester.getTopLeft(secondChoice).dy),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).enabled,
      isFalse,
    );
    expect(controller.generatedMindMapScopes, isEmpty);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('ai-mind-map-scope-choice-card')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      '生成整本书思维导图',
    );
    expect(controller.generatedMindMapScopes, isEmpty);

    await tester.tap(find.byTooltip('发送').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('ai-mind-map-scope-0')));
    await tester.pumpAndSettle();
    expect(controller.generatedMindMapScopes, ['作品甲']);
    expect(find.text('已根据《作品甲》的 1 章内容生成思维导图。'), findsOneWidget);
  });

  testWidgets('long mind map progress wraps inside a narrow conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 11);
    const longTitle = '火星崛起2：黄金之子（年度科幻小说，同名电影即将开拍，环球影业出品）全球顶级畅销小说文库';
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'mind-map-long-progress',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: longTitle,
        filePath: '/tmp/mind-map-long-progress.epub',
        contentHash: 'hash-mind-map-long-progress',
        pageCount: const Value(45),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final gate = Completer<void>();
    final controller = _AmbiguousOutlineController(
      database: database,
      item: (await database.readingItemById('mind-map-long-progress'))!,
    )..mindMapGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
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
    await tester.enterText(find.byType(TextField).last, '生成整本书思维导图');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('停止'), findsOneWidget);
    expect(find.textContaining(longTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    expect(controller.structureResolveCalls, 1);
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

  testWidgets('streaming follow pauses when the user scrolls up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 10);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'chat-stream-scroll',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: '流式滚动测试',
        filePath: '/tmp/chat-stream-scroll.epub',
        contentHash: 'hash-chat-stream-scroll',
        pageCount: const Value(2),
        addedAt: now,
        updatedAt: now,
      ),
    );
    final item = (await database.readingItemById('chat-stream-scroll'))!;
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

    await tester.enterText(find.byType(TextField).last, '生成长回答');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    final stream = controller.chatStreams.single;
    final firstBody = List.filled(80, '这是一段持续增长的流式回答内容。').join('\n\n');
    stream.add(
      AiRunTextSnapshot(
        runId: controller.lastChatRunId!,
        sequence: 4,
        occurredAt: DateTime.now(),
        text: firstBody,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final listFinder = find.byKey(
      const ValueKey<String>('ai-chat-message-list'),
    );
    final scroll = tester.widget<ListView>(listFinder).controller!;
    expect(scroll.position.extentAfter, lessThan(1));

    await tester.drag(listFinder, const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(50));
    final userOffset = scroll.offset;

    stream.add(
      AiRunTextSnapshot(
        runId: controller.lastChatRunId!,
        sequence: 5,
        occurredAt: DateTime.now(),
        text: '$firstBody\n\n${List.filled(20, '新增流式内容。').join('\n\n')}',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(scroll.offset, closeTo(userOffset, 1));
    expect(scroll.position.extentAfter, greaterThan(50));
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

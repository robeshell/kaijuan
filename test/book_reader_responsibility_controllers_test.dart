import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/app/book_reading_preferences.dart';
import 'package:kaijuan/presentation/controllers/book_ai_conversation_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_mind_map_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_mind_map_coordinator.dart';
import 'package:kaijuan/presentation/controllers/book_reader_bridge.dart';
import 'package:kaijuan/presentation/controllers/book_reader_preferences_controller.dart';
import 'package:kaijuan/presentation/controllers/book_search_controller.dart';
import 'package:kaijuan/presentation/widgets/reader/book_ai_mind_map_scope_card.dart';
import 'package:kaijuan/readers/book/foliate_js_bridge.dart';

void main() {
  group('BookReaderPreferencesController', () {
    test('clamps values and freezes locator before mode change', () async {
      var freezes = 0;
      final controller = BookReaderPreferencesController(
        scrollModeEnabled: true,
        onReadingModeWillChange: () => freezes++,
      );

      await controller.setFontSize(999);
      await controller.setReadingMode(BookReadingMode.scroll);

      expect(controller.fontSize, BookReadingPreferences.maxFontSize);
      expect(controller.readingMode, BookReadingMode.scroll);
      expect(freezes, 1);
      controller.dispose();
    });

    test('rejects scroll mode when renderer capability is disabled', () async {
      final controller = BookReaderPreferencesController(
        scrollModeEnabled: false,
        onReadingModeWillChange: () => fail('must not freeze'),
      );

      await controller.setReadingMode(BookReadingMode.scroll);

      expect(controller.readingMode, BookReadingMode.page);
      controller.dispose();
    });
  });

  test(
    'BookReaderBridge owns adapter callbacks and clears content cache',
    () async {
      var next = 0;
      var seek = 0.0;
      var detached = 0;
      final bridge = BookReaderBridge(onContentDetached: () => detached++);
      bridge.attachPageNavigation(nextPage: () => next++, previousPage: () {});
      bridge.attachSeek((value) => seek = value);
      bridge.attachContent(
        getChapterText: () async => 'chapter',
        getSelectionContext: (before, after) async =>
            (before: '$before', after: '$after'),
      );

      bridge.nextPage();
      bridge.seek(0.4);

      expect(next, 1);
      expect(seek, 0.4);
      expect(await bridge.loadChapterText(), 'chapter');
      expect(await bridge.loadSelectionContext(before: 2, after: 3), (
        before: '2',
        after: '3',
      ));

      bridge.detachContent();
      expect(await bridge.loadChapterText(), isEmpty);
      expect(detached, 1);
    },
  );

  test('BookSearchController isolates search and image overlay state', () {
    var overlays = 0;
    var cleared = 0;
    String? submitted;
    FoliateSearchHit? selected;
    final controller =
        BookSearchController(
          beforeOpenOverlay: () => overlays++,
          onSearchHitSelected: (hit) => selected = hit,
        )..attachBridge(
          runSearch: (query) => submitted = query,
          clearSearch: () => cleared++,
        );
    const hit = FoliateSearchHit(
      cfi: 'epubcfi(/6/4)',
      chapterLabel: '第一章',
      excerptPre: '前',
      excerptMatch: '中',
      excerptPost: '后',
    );

    controller.openSearch(initialQuery: '  关键词  ');
    controller.report(
      const FoliateSearchChapterHits(label: '第一章', hits: [hit]),
    );
    controller.report(const FoliateSearchDone());
    controller.selectHit(hit);
    controller.openImage('https://invalid.example/image.png');
    controller.openImage('data:image/png;base64,AA==');

    expect(submitted, '关键词');
    expect(controller.hits, [hit]);
    expect(controller.running, isFalse);
    expect(selected, same(hit));
    expect(controller.imageOpen, isTrue);
    expect(overlays, 2);
    expect(cleared, 1);
    controller.dispose();
  });

  group('BookAiMindMapCoordinator', () {
    late BookAiConversationController conversation;
    late BookAiMindMapController mindMapConversation;
    late BookAiMindMapCoordinator coordinator;
    late AiChatMessage message;
    var persisted = 0;

    setUp(() {
      persisted = 0;
      conversation = BookAiConversationController((_) async => persisted++);
      mindMapConversation = BookAiMindMapController(conversation);
      final map = AiBookMindMap(
        contentHash: 'hash',
        workKey: null,
        createdAt: DateTime.utc(2026),
        model: 'test',
        scopeSectionIndices: const [1],
        scopeFingerprint: 'scope',
        contentKind: AiMindMapContentKind.narrative,
        layout: AiMindMapLayout.radial,
        artifactId: 'artifact-1',
        nodes: const [
          AiBookMindMapNode(
            nodeId: 'root',
            parentId: null,
            order: 0,
            level: 0,
            title: '主题',
            summary: '摘要',
          ),
        ],
      );
      message = AiChatMessage(
        role: AiMessageRole.assistant,
        content: '已生成',
        turnId: 'turn-1',
        mindMap: map,
      );
      conversation.hydrate(
        AiChatSession(contentHash: 'hash', itemId: 'item', messages: [message]),
      );
      coordinator = BookAiMindMapCoordinator(
        conversation: conversation,
        mindMapConversation: mindMapConversation,
        currentWorkKey: () => null,
        persist: conversation.persist,
      );
    });

    tearDown(() {
      coordinator.dispose();
      mindMapConversation.dispose();
      conversation.dispose();
    });

    test('owns artifact attachment and persists native layout', () async {
      expect(coordinator.beginEditing(message, enabled: true), isTrue);
      expect(coordinator.activeMindMap?.artifactId, 'artifact-1');

      coordinator.updateLayout(message, AiMindMapLayout.rightFacing);
      await pumpEventQueue();

      expect(
        conversation.session.messages.single.mindMap?.layout,
        AiMindMapLayout.rightFacing,
      );
      expect(persisted, 1);
    });

    test('scope request has one owner and completes once', () async {
      final result = coordinator.requestScope(
        title: '选择作品',
        choices: const [(value: 7, label: '第一部', subtitle: '3 章')],
      );

      expect(coordinator.scopePrompt, isNotNull);
      coordinator.selectScope(7);

      expect(await result, 7);
      expect(coordinator.scopePrompt, isNull);
    });
  });

  testWidgets('mind-map scope card delegates the selected value', (
    tester,
  ) async {
    final prompt = BookAiMindMapScopePrompt(
      title: '选择作品',
      choices: const [(value: 3, label: '第一部', subtitle: '3 章')],
    );
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookAiMindMapScopeChoiceCard(
            prompt: prompt,
            onSelected: (value) => selected = value,
            onCancel: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('第一部'));

    expect(selected, 3);
  });
}

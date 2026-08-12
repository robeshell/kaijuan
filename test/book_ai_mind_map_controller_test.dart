import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/presentation/controllers/book_ai_conversation_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_mind_map_controller.dart';

void main() {
  const firstWork = AiBookWork(
    id: 'work-1',
    title: '第一部',
    startSection: 1,
    endSectionExclusive: 2,
  );
  const secondWork = AiBookWork(
    id: 'work-2',
    title: '第二部',
    startSection: 2,
    endSectionExclusive: 3,
  );
  const firstUnit = (
    work: firstWork,
    label: '第一部',
    frozenSections: <AiBookSectionSlice>[
      AiBookSectionSlice(
        index: 1,
        sourceSectionIndex: 1,
        label: '第一章',
        text: '正文一',
      ),
    ],
    estimatedSections: 1,
  );
  const secondUnit = (
    work: secondWork,
    label: '第二部',
    frozenSections: <AiBookSectionSlice>[
      AiBookSectionSlice(
        index: 2,
        sourceSectionIndex: 2,
        label: '第二章',
        text: '正文二',
      ),
    ],
    estimatedSections: 1,
  );

  AiBookMindMap mapFor(BookAiMindMapGenerationUnit unit) => AiBookMindMap(
    contentHash: 'hash',
    workKey: unit.work?.id,
    createdAt: DateTime.utc(2026, 8, 11),
    model: 'test',
    scopeSectionIndices: [unit.frozenSections!.single.index],
    scopeFingerprint: unit.label,
    contentKind: AiMindMapContentKind.narrative,
    layout: AiMindMapLayout.bidirectional,
    nodes: [
      AiBookMindMapNode(
        nodeId: 'root',
        parentId: null,
        order: 0,
        level: 0,
        title: unit.label,
        summary: '摘要',
      ),
    ],
  );

  test(
    'owns a multi-unit product turn and persists native artifacts',
    () async {
      final writes = <AiChatSession>[];
      final conversation = BookAiConversationController(
        (session) async => writes.add(session),
      )..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
      final controller = BookAiMindMapController(conversation);
      final revealed = <AiBookMindMap>[];

      final outcome = await controller.generate(
        turnId: 'turn-1',
        workKey: null,
        text: '生成整本书思维导图',
        publicationTitle: '合集',
        units: const [firstUnit, secondUnit],
        segmentedPublication: true,
        isCancelled: () => false,
        loadSections: (_) => throw StateError('frozen sections must be used'),
        generateMap: (unit, _, _) async => mapFor(unit),
        onArtifact: revealed.add,
      );

      expect(outcome.succeeded, isTrue);
      expect(revealed, hasLength(2));
      final messages = conversation.messagesFor(null);
      expect(messages, hasLength(3));
      expect(messages.first.status, AiChatTurnStatus.completed);
      expect(
        messages.skip(1).every((message) => message.mindMap != null),
        isTrue,
      );
      expect(messages[1].mindMap?.artifactId, 'turn-1-mind-map-1');
      expect(messages[2].mindMap?.artifactId, 'turn-1-mind-map-2');
      expect(writes, isNotEmpty);
      expect(controller.isRunning, isFalse);
      controller.dispose();
      conversation.dispose();
    },
  );

  test(
    'partial failure preserves completed artifacts without retrying batch',
    () async {
      final conversation = BookAiConversationController((_) async {})
        ..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
      final controller = BookAiMindMapController(conversation);
      var calls = 0;

      final outcome = await controller.generate(
        turnId: 'turn-1',
        workKey: null,
        text: '生成全部',
        publicationTitle: '合集',
        units: const [firstUnit, secondUnit],
        isCancelled: () => false,
        generationError: () => '第二部失败',
        loadSections: (_) => throw StateError('frozen sections must be used'),
        generateMap: (unit, _, _) async {
          calls++;
          return calls == 1 ? mapFor(unit) : null;
        },
      );

      expect(outcome.completed, 1);
      expect(outcome.failedUnit?.label, '第二部');
      expect(outcome.succeeded, isFalse);
      expect(conversation.messagesFor(null), hasLength(2));
      expect(
        conversation.messagesFor(null).first.status,
        AiChatTurnStatus.failed,
      );
      expect(conversation.retryTurnId, isNull);
      controller.dispose();
      conversation.dispose();
    },
  );

  test(
    'cancelled generation closes the product turn without an artifact',
    () async {
      final conversation = BookAiConversationController((_) async {})
        ..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
      final controller = BookAiMindMapController(conversation);
      var cancelled = false;

      final outcome = await controller.generate(
        turnId: 'turn-1',
        workKey: null,
        text: '生成第一部',
        publicationTitle: '合集',
        units: const [firstUnit],
        isCancelled: () => cancelled,
        loadSections: (_) => throw StateError('frozen sections must be used'),
        generateMap: (unit, _, _) async {
          cancelled = true;
          return mapFor(unit);
        },
      );

      expect(outcome.cancelled, isTrue);
      expect(outcome.completed, 0);
      final messages = conversation.messagesFor(null);
      expect(messages, hasLength(1));
      expect(messages.single.status, AiChatTurnStatus.cancelled);
      expect(conversation.retryTurnId, isNull);
      controller.dispose();
      conversation.dispose();
    },
  );

  test('persist failure marks turn failed and rolls back memory', () async {
    // Fail any durable write that includes a mind-map (projection).
    final written = <AiChatSession>[];
    final conversation = BookAiConversationController((session) async {
      final hasMap =
          session.messages.any((m) => m.mindMap != null) ||
          session.workMessages.values.any(
            (list) => list.any((m) => m.mindMap != null),
          );
      if (hasMap) throw StateError('disk full');
      written.add(session);
    })..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
    final controller = BookAiMindMapController(conversation);

    final outcome = await controller.generate(
      turnId: 'turn-1',
      workKey: null,
      text: '生成第一部',
      publicationTitle: '合集',
      units: const [firstUnit],
      isCancelled: () => false,
      loadSections: (_) => throw StateError('frozen sections must be used'),
      generateMap: (unit, _, _) async => mapFor(unit),
    );

    expect(outcome.succeeded, isFalse);
    expect(outcome.completed, 0);
    expect(outcome.error, isNotNull);
    expect(conversation.messagesFor(null).first.status, AiChatTurnStatus.failed);
    // Failed projection must not leave a native map in memory (or later saves).
    expect(
      conversation.messagesFor(null).any((m) => m.mindMap != null),
      isFalse,
    );
    expect(
      written.any(
        (s) =>
            s.messages.any((m) => m.mindMap != null) ||
            s.workMessages.values.any(
              (list) => list.any((m) => m.mindMap != null),
            ),
      ),
      isFalse,
    );
    controller.dispose();
    conversation.dispose();
  });

  test(
    'persist failure unstages only the projection, keeps concurrent edits',
    () async {
      late BookAiConversationController conversation;
      conversation = BookAiConversationController((session) async {
        final hasMap =
            session.messages.any((m) => m.mindMap != null) ||
            session.workMessages.values.any(
              (list) => list.any((m) => m.mindMap != null),
            );
        if (!hasMap) return;
        // Simulate cancel / other turn landing while disk write is in flight.
        conversation.appendMessage(
          const AiChatMessage(
            role: AiMessageRole.user,
            content: '先停一下',
            turnId: 'concurrent-user',
            status: AiChatTurnStatus.completed,
          ),
        );
        conversation.replaceMessages(null, [
          ...conversation.messagesFor(null).map((message) {
            if (message.turnId == 'turn-1') {
              return message.copyWith(status: AiChatTurnStatus.cancelled);
            }
            return message;
          }),
        ]);
        throw StateError('disk full');
      })..hydrate(
        AiChatSession(
          contentHash: 'hash',
          itemId: 'item',
          messages: [
            AiChatMessage(
              role: AiMessageRole.user,
              content: '生成',
              turnId: 'turn-1',
              status: AiChatTurnStatus.pending,
            ),
          ],
        ),
      );
      final controller = BookAiMindMapController(conversation);

      await expectLater(
        controller.projectArtifact(
          turnId: 'turn-1',
          workKey: null,
          unitLabel: '第一部',
          sectionCount: 1,
          artifact: mapFor(firstUnit).copyWith(artifactId: 'turn-1-mind-map-1'),
        ),
        throwsStateError,
      );

      final messages = conversation.messagesFor(null);
      expect(messages.any((m) => m.mindMap != null), isFalse);
      expect(
        messages.singleWhere((m) => m.turnId == 'turn-1').status,
        AiChatTurnStatus.cancelled,
      );
      expect(messages.any((m) => m.turnId == 'concurrent-user'), isTrue);
      controller.dispose();
      conversation.dispose();
    },
  );

  test('retry removes prior mind-map projections for the same turn', () async {
    final conversation = BookAiConversationController((_) async {})
      ..hydrate(
        AiChatSession(
          contentHash: 'hash',
          itemId: 'item',
          messages: [
            AiChatMessage(
              role: AiMessageRole.user,
              content: '生成',
              turnId: 'turn-1',
              status: AiChatTurnStatus.failed,
            ),
            AiChatMessage(
              role: AiMessageRole.assistant,
              content: '已根据《第一部》的 1 章内容生成思维导图。',
              turnId: 'turn-1-mind-map-1',
              status: AiChatTurnStatus.completed,
              mindMap: mapFor(firstUnit).copyWith(artifactId: 'turn-1-mind-map-1'),
            ),
          ],
        ),
      );
    // Retry beginTurn is owned by conversation; assert cleanup contract.
    conversation.beginTurn(
      turnId: 'turn-2',
      workKey: null,
      text: '生成',
      wantsWebSearch: false,
      retryTurnId: 'turn-1',
    );
    final messages = conversation.messagesFor(null);
    expect(messages.any((m) => m.turnId == 'turn-1'), isFalse);
    expect(messages.any((m) => m.turnId == 'turn-1-mind-map-1'), isFalse);
    expect(messages.single.turnId, 'turn-2');
    conversation.dispose();
  });
}

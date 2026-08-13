import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_search.dart';
import 'package:kaijuan/presentation/controllers/book_ai_conversation_controller.dart';

void main() {
  const descriptor = AiRunDescriptor(
    runId: 'turn-1',
    task: AiRunTask.bookChat,
    scope: AiRunScope(contentHash: 'book-hash', workKey: 'work-1'),
  );
  final now = DateTime.utc(2026, 8, 11, 12);

  test('owns bounded turn lifecycle and persists complete snapshots', () async {
    final writes = <AiChatSession>[];
    final controller = BookAiConversationController(
      (session) async => writes.add(session),
      now: () => now,
    );
    controller.hydrate(
      const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
    );

    final start = controller.beginTurn(
      turnId: 'turn-1',
      workKey: 'work-1',
      text: '解释本章',
      wantsWebSearch: true,
    );
    controller.completeWebSearch(3);
    controller.applyRunEvent(
      AiRunStarted(descriptor: descriptor, sequence: 0, occurredAt: now),
    );
    controller.applyRunEvent(
      AiRunTextSnapshot(
        runId: 'turn-1',
        sequence: 1,
        occurredAt: now,
        text: '本章围绕制度冲突展开。',
      ),
    );
    final completion = controller.completeActiveTurn();

    expect(start.history, isEmpty);
    expect(completion.body, '本章围绕制度冲突展开。');
    expect(completion.assistantIndex, 1);
    final messages = controller.messagesFor('work-1');
    expect(messages, hasLength(2));
    expect(messages.first.webHitCount, 3);
    expect(messages.first.status, AiChatTurnStatus.completed);
    expect(messages.last.role, AiMessageRole.assistant);
    expect(messages.last.status, AiChatTurnStatus.completed);
    expect(controller.sending, isFalse);
    expect(
      writes.any(
        (session) => session
            .messagesFor('work-1')
            .any(
              (message) =>
                  message.role == AiMessageRole.assistant &&
                  message.status == AiChatTurnStatus.pending,
            ),
      ),
      isTrue,
      reason: 'first streamed snapshot is checkpointed immediately',
    );
    controller.dispose();
  });

  test('beginTurn stores a short display label without changing model text', () {
    final controller = BookAiConversationController((_) async {}, now: () => now)
      ..hydrate(
        const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
      );
    controller.beginTurn(
      turnId: 'turn-label',
      workKey: 'work-1',
      text: kAiChatBookDigestPrompt,
      displayText: '本书书摘',
      wantsWebSearch: false,
    );
    final user = controller.messagesFor('work-1').single;
    expect(user.content, kAiChatBookDigestPrompt);
    expect(user.visibleContent, '本书书摘');
    controller.dispose();
  });

  test('failure keeps partial answer and retry identity in one work', () {
    final controller = BookAiConversationController(
      (_) async {},
      now: () => now,
    );
    controller.hydrate(
      const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
    );
    controller.beginTurn(
      turnId: 'turn-1',
      workKey: 'work-1',
      text: '继续解释',
      wantsWebSearch: false,
    );
    controller.applyRunEvent(
      AiRunStarted(descriptor: descriptor, sequence: 0, occurredAt: now),
    );
    controller.applyRunEvent(
      AiRunReasoningSnapshot(
        runId: 'turn-1',
        sequence: 1,
        occurredAt: now,
        text: '先梳理因果',
        kind: AiReasoningContentKind.process,
      ),
    );
    controller.applyRunEvent(
      AiRunTextSnapshot(
        runId: 'turn-1',
        sequence: 2,
        occurredAt: now,
        text: '已经生成的部分',
      ),
    );

    controller.failActiveTurn(StateError('transport failed'));

    final messages = controller.messagesFor('work-1');
    expect(messages, hasLength(2));
    expect(
      messages.every((message) => message.status == AiChatTurnStatus.failed),
      isTrue,
    );
    expect(messages.last.content, '已经生成的部分');
    expect(messages.last.reasoningContent, '先梳理因果');
    expect(controller.retryText, '继续解释');
    expect(controller.retryTurnId, 'turn-1');
    expect(controller.failure, isA<StateError>());
    controller.dispose();
  });

  test('product action removes the provisional model turn', () {
    final controller = BookAiConversationController((_) async {});
    controller.hydrate(
      const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
    );
    controller.beginTurn(
      turnId: 'turn-1',
      workKey: null,
      text: '生成本书思维导图',
      wantsWebSearch: false,
    );

    controller.finishWithProductAction();

    expect(controller.messagesFor(null), isEmpty);
    expect(controller.sending, isFalse);
    expect(controller.activeTurnId, isNull);
    controller.dispose();
  });

  test('consumes a run stream and publishes one terminal outcome', () async {
    final controller = BookAiConversationController((_) async {});
    controller.hydrate(
      const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
    );
    controller.beginTurn(
      turnId: 'turn-1',
      workKey: 'work-1',
      text: '解释本章',
      wantsWebSearch: false,
    );
    var snapshots = 0;

    final outcome = await controller.consumeRun(
      Stream.fromIterable([
        AiRunStarted(descriptor: descriptor, sequence: 0, occurredAt: now),
        AiRunTextSnapshot(
          runId: 'turn-1',
          sequence: 1,
          occurredAt: now,
          text: '完整回答',
        ),
        AiRunCompleted(
          runId: 'turn-1',
          sequence: 2,
          occurredAt: now,
          text: '完整回答',
        ),
      ]),
      onSnapshot: () => snapshots++,
    );

    expect(outcome, isA<BookAiRunCompletedOutcome>());
    expect((outcome as BookAiRunCompletedOutcome).completion.body, '完整回答');
    expect(snapshots, 1);
    expect(controller.messagesFor('work-1'), hasLength(2));
    expect(controller.sending, isFalse);
    controller.dispose();
  });

  test('runTurn owns search, runtime start and final persistence', () async {
    final controller = BookAiConversationController((_) async {});
    controller.hydrate(
      const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
    );
    List<AiChatMessage>? frozenHistory;
    List<AiWebSearchHit>? frozenHits;

    final outcome = await controller.runTurn(
      turnId: 'turn-1',
      workKey: 'work-1',
      text: '结合资料解释本章',
      wantsWebSearch: true,
      searchWeb: () async => const [
        AiWebSearchHit(title: '资料', url: 'https://example.com'),
      ],
      startRuntime: (turn, webHits) {
        frozenHistory = turn.history;
        frozenHits = webHits;
        return Stream.fromIterable([
          AiRunStarted(descriptor: descriptor, sequence: 0, occurredAt: now),
          AiRunTextSnapshot(
            runId: 'turn-1',
            sequence: 1,
            occurredAt: now,
            text: '联网后的回答',
          ),
          AiRunCompleted(
            runId: 'turn-1',
            sequence: 2,
            occurredAt: now,
            text: '联网后的回答',
          ),
        ]);
      },
    );

    expect(outcome, isA<BookAiRunCompletedOutcome>());
    expect(frozenHistory, isEmpty);
    expect(frozenHits, hasLength(1));
    final messages = controller.messagesFor('work-1');
    expect(messages.first.webHitCount, 1);
    expect(messages.last.content, '联网后的回答');
    controller.dispose();
  });

  test('runTurn exposes search failure phase and retry identity', () async {
    final controller = BookAiConversationController((_) async {});
    controller.hydrate(
      const AiChatSession(contentHash: 'book-hash', itemId: 'book-id'),
    );

    final outcome = await controller.runTurn(
      turnId: 'turn-1',
      workKey: null,
      text: '联网解释',
      wantsWebSearch: true,
      searchWeb: () async => throw StateError('search failed'),
      startRuntime: (_, _) => throw StateError('must not start'),
    );

    expect(outcome, isA<BookAiRunFailedOutcome>());
    expect(
      (outcome as BookAiRunFailedOutcome).phase,
      BookAiRunFailurePhase.webSearch,
    );
    expect(controller.retryTurnId, 'turn-1');
    expect(controller.retryText, '联网解释');
    expect(controller.sending, isFalse);
    controller.dispose();
  });

  test('retry removes the previous failed turn before freezing history', () {
    final controller = BookAiConversationController((_) async {});
    controller.hydrate(
      AiChatSession(
        contentHash: 'book-hash',
        itemId: 'book-id',
        messages: [
          AiChatMessage(
            role: AiMessageRole.user,
            content: '旧问题',
            turnId: 'old-turn',
            status: AiChatTurnStatus.failed,
          ),
          AiChatMessage(
            role: AiMessageRole.assistant,
            content: '旧的部分回答',
            turnId: 'old-turn',
            status: AiChatTurnStatus.failed,
          ),
          const AiChatMessage(role: AiMessageRole.user, content: '稳定历史'),
        ],
      ),
    );

    final start = controller.beginTurn(
      turnId: 'new-turn',
      workKey: null,
      text: '旧问题',
      wantsWebSearch: false,
      retryTurnId: 'old-turn',
    );

    expect(start.history.map((message) => message.content), ['稳定历史']);
    expect(controller.messagesFor(null).map((message) => message.turnId), [
      null,
      'new-turn',
    ]);
    controller.dispose();
  });
}

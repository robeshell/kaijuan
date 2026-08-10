import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_session_ops.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';

void main() {
  const base = AiChatSession(contentHash: 'hash', itemId: 'book');

  test('recovery cancels pending turns in whole-book and work scopes', () {
    const pending = AiChatMessage(
      role: AiMessageRole.user,
      content: '问题',
      turnId: 'turn',
      status: AiChatTurnStatus.pending,
    );
    const partial = AiChatMessage(
      role: AiMessageRole.assistant,
      content: '已保存的部分回答',
      turnId: 'turn',
      status: AiChatTurnStatus.pending,
    );
    final session = base.copyWith(
      messages: const [pending, partial],
      workMessages: const {
        'work': [pending, partial],
      },
    );

    final recovered = AiChatSessionOps.recoverInterruptedTurns(session);

    expect(
      recovered.messages.every(
        (message) => message.status == AiChatTurnStatus.cancelled,
      ),
      isTrue,
    );
    expect(recovered.messages.last.content, '已保存的部分回答');
    expect(
      recovered.workMessages['work']!.every(
        (message) => message.status == AiChatTurnStatus.cancelled,
      ),
      isTrue,
    );
  });

  test('bounded append and status updates stay inside frozen work scope', () {
    var session = base;
    for (var i = 0; i < 4; i++) {
      session = AiChatSessionOps.appendBounded(
        session,
        AiChatMessage(
          role: AiMessageRole.user,
          content: '$i',
          turnId: 'turn-$i',
          status: AiChatTurnStatus.pending,
        ),
        workKey: 'work',
        maxMessages: 3,
      );
    }
    session = AiChatSessionOps.setTurnStatus(
      session,
      'turn-3',
      AiChatTurnStatus.completed,
      workKey: 'work',
    );

    expect(session.messages, isEmpty);
    expect(session.workMessages['work']!.map((message) => message.content), [
      '1',
      '2',
      '3',
    ]);
    expect(
      session.workMessages['work']!.last.status,
      AiChatTurnStatus.completed,
    );
  });

  test('mind map intent freezes chapter or whole-book scope', () {
    expect(
      resolveAiMindMapRequestScope('给当前章生成一个思维导图'),
      AiMindMapRequestScope.currentChapter,
    );
    expect(
      resolveAiMindMapRequestScope('我想看看这本书的思维导图'),
      AiMindMapRequestScope.wholeBook,
    );
    expect(
      resolveAiMindMapRequestScope('生成思维导图'),
      AiMindMapRequestScope.currentChapter,
    );
    expect(resolveAiMindMapRequestScope('用 Mermaid 画这本书的思维导图'), isNull);
    expect(resolveAiMindMapRequestScope('总结这一章'), isNull);
  });

  test('structured mind map survives chat message JSON round-trip', () {
    final map = AiBookMindMap(
      contentHash: 'hash',
      workKey: null,
      createdAt: DateTime.utc(2026, 8, 10),
      model: 'test',
      scopeSectionIndices: const [3],
      scopeFingerprint: 'chapter-3',
      contentKind: AiMindMapContentKind.narrative,
      layout: AiMindMapLayout.radial,
      nodes: const [
        AiBookMindMapNode(
          nodeId: 'mm001',
          parentId: null,
          order: 0,
          level: 0,
          title: '本章',
          summary: '本章结构',
        ),
        AiBookMindMapNode(
          nodeId: 'mm002',
          parentId: 'mm001',
          order: 0,
          level: 1,
          title: '主题',
          summary: '主题说明',
          evidence: [
            AiMindMapEvidence(
              sectionIndex: 3,
              quote: '原文证据',
              progressInSection: 0.2,
              spanResolved: true,
            ),
          ],
        ),
      ],
    );
    final source = AiChatMessage(
      role: AiMessageRole.assistant,
      content: '已生成。',
      mindMap: map,
    );

    final restored = AiChatMessage.fromJson(source.toJson());

    expect(restored.mindMap, isNotNull);
    expect(restored.mindMap!.scopeSectionIndices, const [3]);
    expect(restored.mindMap!.nodes[1].evidence.single.quote, '原文证据');
  });
}

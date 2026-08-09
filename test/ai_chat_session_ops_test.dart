import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_session_ops.dart';
import 'package:kaijuan/ai/ai_models.dart';

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
}

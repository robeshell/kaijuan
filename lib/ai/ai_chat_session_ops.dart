import 'ai_chat.dart';

/// Pure conversation-state transitions shared by presentation controllers.
abstract final class AiChatSessionOps {
  /// Pending turns cannot resume after an app/panel restart. Preserve their
  /// bubbles for the reader, but exclude them from future model history.
  static AiChatSession recoverInterruptedTurns(AiChatSession session) {
    List<AiChatMessage> recover(List<AiChatMessage> messages) => [
      for (final message in messages)
        if (message.status == AiChatTurnStatus.pending)
          message.copyWith(status: AiChatTurnStatus.cancelled)
        else
          message,
    ];

    final messages = recover(session.messages);
    final workMessages = {
      for (final entry in session.workMessages.entries)
        entry.key: recover(entry.value),
    };
    final changed =
        !_identicalMessageLists(messages, session.messages) ||
        session.workMessages.entries.any(
          (entry) =>
              !_identicalMessageLists(workMessages[entry.key]!, entry.value),
        );
    return changed
        ? session.copyWith(messages: messages, workMessages: workMessages)
        : session;
  }

  /// Adds a message to its frozen work scope and bounds persisted history.
  static AiChatSession appendBounded(
    AiChatSession session,
    AiChatMessage message, {
    String? workKey,
    int maxMessages = 100,
  }) {
    final limit = maxMessages < 1 ? 1 : maxMessages;
    final messages = <AiChatMessage>[...session.messagesFor(workKey), message];
    final kept = messages.length > limit
        ? messages.sublist(messages.length - limit)
        : messages;
    return session.withMessagesFor(workKey, kept);
  }

  /// Updates both bubbles of one turn without re-reading the active work.
  static AiChatSession setTurnStatus(
    AiChatSession session,
    String turnId,
    AiChatTurnStatus status, {
    String? workKey,
  }) {
    final messages = session.messagesFor(workKey);
    if (!messages.any((message) => message.turnId == turnId)) return session;
    return session.withMessagesFor(workKey, [
      for (final message in messages)
        message.turnId == turnId ? message.copyWith(status: status) : message,
    ]);
  }

  /// Visible thread for the AI panel given an optional resolved work key.
  ///
  /// Collection history lives in [AiChatSession.workMessages]. Before structure
  /// resolves, [workKey] is null; prefer the sole non-empty work thread over
  /// the empty whole-book list so reopen does not look blank.
  static List<AiChatMessage> visibleMessages(
    AiChatSession session, {
    String? workKey,
  }) {
    if (workKey != null) return session.messagesFor(workKey);
    final whole = session.messages;
    if (whole.isNotEmpty) return whole;
    final nonEmpty = [
      for (final entry in session.workMessages.entries)
        if (entry.value.isNotEmpty) entry.value,
    ];
    if (nonEmpty.length == 1) return nonEmpty.single;
    return whole;
  }

  static bool _identicalMessageLists(
    List<AiChatMessage> left,
    List<AiChatMessage> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!identical(left[i], right[i])) return false;
    }
    return true;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/presentation/controllers/book_ai_conversation_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_mind_map_controller.dart';

void main() {
  AiAuthorizedCommand commandFor(List<BookAiMindMapGenerationUnit> units) {
    final indices = [
      for (final unit in units)
        for (final section
            in unit.frozenSections ?? const <AiBookSectionSlice>[])
          section.index,
    ];
    return AiAuthorizedCommand(
      protocolVersion: 1,
      commandId: 'command-test',
      proposalId: 'proposal-test',
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      commandSchemaVersion: 1,
      workflowVersion: 1,
      authorizationSource: AiActionProposalSource.explicitUi,
      authorizationSubmissionId: 'submission-test',
      authorizationEvidence: 'test',
      authorizedAt: DateTime.utc(2026, 8, 12),
      idempotencyKey: 'idem-test',
      arguments: const {},
      originalUserText: '生成思维导图',
      scopeSectionIndices: indices,
      scopeFingerprint: 'sections:${indices.join(',')}',
    );
  }

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
        actionCommand: commandFor(const [firstUnit, secondUnit]),
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
        actionCommand: commandFor(const [firstUnit, secondUnit]),
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
        actionCommand: commandFor(const [firstUnit]),
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

  test('rejects missing frozen scope or wrong action kind on command', () {
    final conversation = BookAiConversationController((_) async {})
      ..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
    final controller = BookAiMindMapController(conversation);
    final wrongKind = commandFor(const [firstUnit]);
    final emptyScope = AiAuthorizedCommand(
      protocolVersion: wrongKind.protocolVersion,
      commandId: wrongKind.commandId,
      proposalId: wrongKind.proposalId,
      actionKind: wrongKind.actionKind,
      definitionVersion: wrongKind.definitionVersion,
      commandSchemaVersion: wrongKind.commandSchemaVersion,
      workflowVersion: wrongKind.workflowVersion,
      authorizationSource: wrongKind.authorizationSource,
      authorizationSubmissionId: wrongKind.authorizationSubmissionId,
      authorizationEvidence: wrongKind.authorizationEvidence,
      authorizedAt: wrongKind.authorizedAt,
      idempotencyKey: wrongKind.idempotencyKey,
      arguments: wrongKind.arguments,
      originalUserText: wrongKind.originalUserText,
      scopeSectionIndices: const [],
    );
    expect(
      () => controller.validateActionCommand(
        actionCommand: emptyScope,
        units: const [firstUnit],
      ),
      throwsStateError,
    );
    expect(
      () => controller.validateActionCommand(
        actionCommand: AiAuthorizedCommand(
          protocolVersion: wrongKind.protocolVersion,
          commandId: wrongKind.commandId,
          proposalId: wrongKind.proposalId,
          actionKind: 'create_book_presentation',
          definitionVersion: wrongKind.definitionVersion,
          commandSchemaVersion: wrongKind.commandSchemaVersion,
          workflowVersion: wrongKind.workflowVersion,
          authorizationSource: wrongKind.authorizationSource,
          authorizationSubmissionId: wrongKind.authorizationSubmissionId,
          authorizationEvidence: wrongKind.authorizationEvidence,
          authorizedAt: wrongKind.authorizedAt,
          idempotencyKey: wrongKind.idempotencyKey,
          arguments: wrongKind.arguments,
          originalUserText: wrongKind.originalUserText,
          scopeSectionIndices: wrongKind.scopeSectionIndices,
        ),
        units: const [firstUnit],
      ),
      throwsStateError,
    );
    controller.dispose();
    conversation.dispose();
  });
}

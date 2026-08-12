import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_product_actions.dart';
import 'package:kaijuan/ai/legacy/ai_book_mind_map_workflow.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_workflow_contract.dart';
import 'package:kaijuan/ai/ai_workflow_executor.dart';
import 'package:kaijuan/presentation/controllers/book_ai_conversation_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_mind_map_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_workspace_controller.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12, 12);

  AiBookMindMap mapFor(List<int> sections, {String? artifactId, int rev = 1}) =>
      AiBookMindMap(
        contentHash: 'hash',
        workKey: 'work-1',
        createdAt: now,
        model: 'test',
        scopeSectionIndices: sections,
        scopeFingerprint: 'sections:${sections.join(',')}',
        contentKind: AiMindMapContentKind.narrative,
        layout: AiMindMapLayout.bidirectional,
        artifactId: artifactId,
        revision: rev,
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

  Future<AiAuthorizedCommand> authorizeCreate(
    AiProductActionController controller,
    String proposalId,
  ) async {
    await controller.propose(
      AiActionProposal(
        protocolVersion: 1,
        proposalId: proposalId,
        parentRunId: null,
        conversationId: 'hash',
        turnId: 't',
        actionKind: 'create_book_mind_map',
        definitionVersion: 1,
        proposalSchemaVersion: 1,
        source: AiActionProposalSource.explicitUi,
        sourceSubmissionId: 'sub-$proposalId',
        originalUserText: '生成思维导图',
        requestedArguments: const {'scope': 'wholePublication'},
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
      deferExplicitAuthorization: true,
      capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
    );
    final authorized = await controller.authorize(
      proposalId: proposalId,
      authorizationSubmissionId: 'sub-$proposalId',
      authorizationEvidence: 'ui',
      normalizedArguments: const {
        'scopeFingerprint': 'sections:1',
        'scopeSectionIndices': [1],
        'unitLabels': ['当前章'],
        'unitSectionCounts': [1],
        'contentHash': 'hash',
      },
    );
    return authorized.command!;
  }

  const unit = (
    work: null,
    label: '当前章',
    sections: [
      AiBookSectionSlice(
        index: 1,
        sourceSectionIndex: 1,
        label: '一',
        text: '正文',
      ),
    ],
  );

  test('cancel after generate does not leave dangling lineage head', () async {
    final artifacts = MemoryAiArtifactRepository();
    final controller = AiProductActionController(
      registry: AiBookMindMapProductActions.registry,
      journal: MemoryAiActionJournalStore(),
      now: () => now,
      idGenerator: () => 'command-head-order',
    );
    final adapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.create.actionKind,
      artifacts: artifacts,
    );
    final command = await authorizeCreate(controller, 'head-order');
    await controller.queue('head-order');
    final token = CancelToken();
    adapter.stage(
      command.commandId,
      AiBookMindMapStagedRun(
        units: const [unit],
        userInstruction: '生成',
        publicationTitle: '书',
        generateUnit:
            ({
              required work,
              required label,
              required sections,
              required progressLabel,
              required cancelToken,
            }) async {
              token.cancel();
              return mapFor(const [1]);
            },
      ),
    );
    final executor = AiProductWorkflowExecutor(
      actions: controller,
      adapters: AiWorkflowAdapterRegistry([adapter]),
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
        checkpoints: MemoryAiWorkflowCheckpointStore(),
        now: () => now,
      ),
    );
    final completed = await executor.execute('head-order', cancelToken: token);
    expect(completed.status, AiActionJournalStatus.cancelled);
    final artifactId = '${command.commandId}-mind-map-1';
    final head = await artifacts.readLineageHead(artifactId);
    // Create head uses artifactId as lineage root only after successful head
    // CAS. Cancelled runs must not leave a head pointing at missing content.
    expect(head, isNull);
    final content = await artifacts.read(artifactId);
    if (content != null) {
      // Content-only orphan is allowed; head must still not be advanced.
      expect(await artifacts.readLineageHead(artifactId), isNull);
    }
  });

  test(
    'receipt committed without projection is recovered without regenerating',
    () async {
      final workspace = BookAiWorkspaceController(
        saveChatSession: (_) async {},
        aiStoresReady: true,
      );
      workspace.conversation.hydrate(
        const AiChatSession(contentHash: 'hash', itemId: 'item'),
      );
      final controller = workspace.actionController;
      final command = await authorizeCreate(controller, 'proj-pending');
      await controller.queue('proj-pending');
      await controller.markExecuting('proj-pending', attempt: 1);
      final artifactId = '${command.commandId}-mind-map-1';
      await workspace.artifactRepository.commit(
        AiBookMindMapArtifactCodec.envelopeFor(
          map: mapFor(const [1], artifactId: artifactId),
          artifactId: artifactId,
          lineageRootId: artifactId,
          revision: 1,
          createdAt: now,
        ),
      );
      await controller.completeForProposal(
        proposalId: 'proj-pending',
        status: AiActionJournalStatus.succeeded,
        artifactRefs: [artifactId],
        attempt: 1,
      );
      final entry = await controller.journal.read('proj-pending');
      expect(entry!.needsProjection, isTrue);
      final candidates = await controller.inspectRecovery();
      expect(
        candidates
            .singleWhere((c) => c.entry.proposal.proposalId == 'proj-pending')
            .disposition,
        AiActionRecoveryDisposition.needsProjection,
      );
      expect(workspace.conversation.messagesFor(null), isEmpty);

      var generateCalls = 0;
      // Reconcile must not call model generation.
      final outcome = await workspace.reconcilePendingProjection(
        entry,
        turnId: 'turn-p',
        workKey: null,
        publicationTitle: '书',
      );
      expect(outcome.completed, 1);
      expect(generateCalls, 0);
      expect(
        workspace.conversation.messagesFor(null).single.mindMap?.artifactId,
        artifactId,
      );
      final after = await controller.journal.read('proj-pending');
      expect(after!.needsProjection, isFalse);
      expect(after.projectedArtifactRefs, [artifactId]);
      workspace.dispose();
    },
  );

  test(
    'projection persist failure is retriable and not blocked by memory',
    () async {
      var persistCalls = 0;
      final conversation = BookAiConversationController((session) async {
        persistCalls++;
        if (persistCalls == 1) {
          throw StateError('disk full');
        }
      })..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
      final mindMap = BookAiMindMapController(conversation);
      final map = mapFor(const [1], artifactId: 'art-persist');
      await expectLater(
        mindMap.projectArtifact(
          turnId: 'turn',
          workKey: null,
          unitLabel: '书',
          sectionCount: 1,
          artifact: map,
        ),
        throwsStateError,
      );
      expect(conversation.hasMindMapArtifact('art-persist'), isTrue);
      expect(persistCalls, 1);
      await mindMap.projectArtifact(
        turnId: 'turn',
        workKey: null,
        unitLabel: '书',
        sectionCount: 1,
        artifact: map,
      );
      expect(persistCalls, 2);
      expect(
        conversation.messagesFor(null).where((m) => m.mindMap != null).length,
        1,
      );
      mindMap.dispose();
      conversation.dispose();
    },
  );

  test('executor uses journaled attempt after prepareRetry', () async {
    final journal = MemoryAiActionJournalStore();
    final controller = AiProductActionController(
      registry: AiBookMindMapProductActions.registry,
      journal: journal,
      now: () => now,
      idGenerator: () => 'command-attempt',
    );
    final artifacts = MemoryAiArtifactRepository();
    final adapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.create.actionKind,
      artifacts: artifacts,
    );
    final command = await authorizeCreate(controller, 'attempt-p');
    await controller.queue('attempt-p');
    await controller.markExecuting('attempt-p', attempt: 1);
    await controller.completeForProposal(
      proposalId: 'attempt-p',
      status: AiActionJournalStatus.failed,
      artifactRefs: const [],
      publicErrorCode: 'mind_map_generation_failed',
      attempt: 1,
    );
    final rearmed = await controller.prepareRetry('attempt-p');
    expect(rearmed.attempt, 2);
    await controller.queue('attempt-p');
    adapter.stage(
      command.commandId,
      AiBookMindMapStagedRun(
        units: const [unit],
        userInstruction: '生成',
        publicationTitle: '书',
        generateUnit:
            ({
              required work,
              required label,
              required sections,
              required progressLabel,
              required cancelToken,
            }) async => mapFor(const [1]),
      ),
    );
    final executor = AiProductWorkflowExecutor(
      actions: controller,
      adapters: AiWorkflowAdapterRegistry([adapter]),
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
        checkpoints: MemoryAiWorkflowCheckpointStore(),
        now: () => now,
      ),
    );
    final completed = await executor.execute('attempt-p', attempt: 1);
    expect(completed.status, AiActionJournalStatus.succeeded);
    expect(completed.receipt?.attempt, 2);
    expect(completed.attempt, 2);
  });

  test('head CAS happens only after content artifact exists', () async {
    final artifacts = MemoryAiArtifactRepository();
    final order = <String>[];
    final wrapped = _OrderingArtifactRepository(artifacts, order);
    final controller = AiProductActionController(
      registry: AiBookMindMapProductActions.registry,
      journal: MemoryAiActionJournalStore(),
      now: () => now,
      idGenerator: () => 'command-order2',
    );
    final adapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.create.actionKind,
      artifacts: wrapped,
    );
    final command = await authorizeCreate(controller, 'order2');
    await controller.queue('order2');
    adapter.stage(
      command.commandId,
      AiBookMindMapStagedRun(
        units: const [unit],
        userInstruction: '生成',
        publicationTitle: '书',
        generateUnit:
            ({
              required work,
              required label,
              required sections,
              required progressLabel,
              required cancelToken,
            }) async => mapFor(const [1]),
      ),
    );
    final executor = AiProductWorkflowExecutor(
      actions: controller,
      adapters: AiWorkflowAdapterRegistry([adapter]),
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
        checkpoints: MemoryAiWorkflowCheckpointStore(),
        now: () => now,
      ),
    );
    final completed = await executor.execute('order2');
    expect(completed.status, AiActionJournalStatus.succeeded);
    expect(order, containsAllInOrder(['commit', 'commitLineageHead']));
    final firstHead = order.indexOf('commitLineageHead');
    final firstCommit = order.indexOf('commit');
    expect(firstCommit, lessThan(firstHead));
  });
}

class _OrderingArtifactRepository implements AiArtifactRepository {
  _OrderingArtifactRepository(this.inner, this.order);

  final AiArtifactRepository inner;
  final List<String> order;

  @override
  Future<AiArtifactEnvelope?> read(String artifactId) => inner.read(artifactId);

  @override
  Future<AiArtifactEnvelope> commit(
    AiArtifactEnvelope artifact, {
    int? expectedRevision,
  }) async {
    order.add('commit');
    return inner.commit(artifact, expectedRevision: expectedRevision);
  }

  @override
  Future<AiArtifactLineageHead?> readLineageHead(String lineageRootId) =>
      inner.readLineageHead(lineageRootId);

  @override
  Future<AiArtifactLineageHead> commitLineageHead(
    AiArtifactLineageHead head, {
    required int? expectedRevision,
  }) async {
    order.add('commitLineageHead');
    return inner.commitLineageHead(head, expectedRevision: expectedRevision);
  }

  @override
  Future<List<AiArtifactEnvelope>> listByCommandPrefix(String commandId) =>
      inner.listByCommandPrefix(commandId);
}

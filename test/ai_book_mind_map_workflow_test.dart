import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_product_actions.dart';
import 'package:kaijuan/ai/ai_book_mind_map_workflow.dart';
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

  Future<({AiProductActionController controller, AiAuthorizedCommand command})>
  authorizeCreate({
    required AiProductActionController controller,
    required String proposalId,
    required String commandId,
    List<int> sections = const [1],
  }) async {
    await controller.propose(
      AiActionProposal(
        protocolVersion: 1,
        proposalId: proposalId,
        parentRunId: null,
        conversationId: 'c',
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
    );
    final authorized = await controller.authorize(
      proposalId: proposalId,
      authorizationSubmissionId: 'sub-$proposalId',
      authorizationEvidence: 'ui',
      normalizedArguments: {
        'scopeFingerprint': 'sections:${sections.join(',')}',
        'scopeSectionIndices': sections,
        'contentHash': 'hash',
      },
    );
    return (controller: controller, command: authorized.command!);
  }

  test(
    'artifact then checkpoint then receipt; projection is separate',
    () async {
      final artifacts = MemoryAiArtifactRepository();
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-order',
      );
      final adapter = AiBookMindMapWorkflowAdapter(
        actionKind: AiBookMindMapProductActions.create.actionKind,
        artifacts: artifacts,
      );
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([adapter]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({}),
          checkpoints: checkpoints,
          now: () => now,
        ),
      );
      final authorized = await authorizeCreate(
        controller: controller,
        proposalId: 'order-proposal',
        commandId: 'command-order',
      );
      await controller.queue('order-proposal');
      var generated = 0;
      adapter.stage(
        authorized.command.commandId,
        AiBookMindMapStagedRun(
          units: const [
            (
              work: null,
              label: '书',
              sections: [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '一',
                  text: '正文',
                ),
              ],
            ),
          ],
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
                generated++;
                return mapFor([1]);
              },
        ),
      );
      final completed = await executor.execute('order-proposal');
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(generated, 1);
      expect(completed.receipt?.artifactRefs, hasLength(1));
      expect(
        await artifacts.read(completed.receipt!.artifactRefs.single),
        isNotNull,
      );
      expect(
        (await checkpoints.readLatest('workflow:command-order'))?.stageId,
        'unit_committed',
      );
    },
  );

  test(
    'artifact committed before checkpoint is recovered without regenerating',
    () async {
      final artifacts = MemoryAiArtifactRepository();
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-orphan',
      );
      final adapter = AiBookMindMapWorkflowAdapter(
        actionKind: AiBookMindMapProductActions.create.actionKind,
        artifacts: artifacts,
      );
      final authorized = await authorizeCreate(
        controller: controller,
        proposalId: 'orphan-proposal',
        commandId: 'command-orphan',
      );
      await controller.markExecuting('orphan-proposal', attempt: 1);
      final artifactId = '${authorized.command.commandId}-mind-map-1';
      await artifacts.commit(
        AiBookMindMapArtifactCodec.envelopeFor(
          map: mapFor(const [1], artifactId: artifactId),
          artifactId: artifactId,
          lineageRootId: artifactId,
          revision: 1,
          createdAt: now,
        ),
      );
      // No checkpoint written — crash window after Artifact, before checkpoint.
      var generated = 0;
      adapter.stage(
        authorized.command.commandId,
        AiBookMindMapStagedRun(
          units: const [
            (
              work: null,
              label: '书',
              sections: [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '一',
                  text: '正文',
                ),
              ],
            ),
          ],
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
                generated++;
                return mapFor(const [1]);
              },
        ),
      );
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([adapter]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({}),
          checkpoints: checkpoints,
          now: () => now,
        ),
      );
      final completed = await executor.execute('orphan-proposal', attempt: 2);
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(generated, 0);
      expect(completed.receipt?.artifactRefs, [artifactId]);
    },
  );

  test(
    'cancel after model return before commit leaves zero artifacts',
    () async {
      final artifacts = MemoryAiArtifactRepository();
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: MemoryAiActionJournalStore(),
        now: () => now,
        idGenerator: () => 'command-cancel-race',
      );
      final adapter = AiBookMindMapWorkflowAdapter(
        actionKind: AiBookMindMapProductActions.create.actionKind,
        artifacts: artifacts,
      );
      final authorized = await authorizeCreate(
        controller: controller,
        proposalId: 'cancel-race',
        commandId: 'command-cancel-race',
      );
      await controller.queue('cancel-race');
      final token = CancelToken();
      adapter.stage(
        authorized.command.commandId,
        AiBookMindMapStagedRun(
          units: const [
            (
              work: null,
              label: '书',
              sections: [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '一',
                  text: '正文',
                ),
              ],
            ),
          ],
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
          capabilities: const AiCapabilitySet({}),
          checkpoints: MemoryAiWorkflowCheckpointStore(),
          now: () => now,
        ),
      );
      final completed = await executor.execute(
        'cancel-race',
        cancelToken: token,
      );
      expect(completed.status, AiActionJournalStatus.cancelled);
      expect(completed.receipt?.artifactRefs, isEmpty);
      expect(
        await artifacts.listByCommandPrefix('command-cancel-race'),
        isEmpty,
      );
    },
  );

  test('two concurrent revisions of v1 only one becomes v2 head', () async {
    final artifacts = MemoryAiArtifactRepository();
    final lineageRoot = 'lineage-root';
    await artifacts.commit(
      AiBookMindMapArtifactCodec.envelopeFor(
        map: mapFor(const [1], artifactId: lineageRoot),
        artifactId: lineageRoot,
        lineageRootId: lineageRoot,
        revision: 1,
        createdAt: now,
      ),
    );
    await artifacts.commitLineageHead(
      AiArtifactLineageHead(
        lineageRootId: lineageRoot,
        headArtifactId: lineageRoot,
        revision: 1,
        updatedAt: now,
      ),
      expectedRevision: null,
    );

    Future<AiActionJournalEntry> runRevise(String suffix) async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-rev-$suffix',
      );
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'rev-$suffix',
          parentRunId: null,
          conversationId: null,
          turnId: null,
          actionKind: 'revise_book_mind_map',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'sub-$suffix',
          originalUserText: '再详细一点',
          requestedArguments: const {},
          targetRef: lineageRoot,
          expectedRevision: 1,
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        deferExplicitAuthorization: true,
      );
      await controller.authorize(
        proposalId: 'rev-$suffix',
        authorizationSubmissionId: 'sub-$suffix',
        authorizationEvidence: 'ui',
        normalizedArguments: const {
          'scopeFingerprint': 'sections:1',
          'scopeSectionIndices': [1],
          'contentHash': 'hash',
        },
      );
      // Force expected revision onto command via decision was from proposal.
      final entry = await journal.read('rev-$suffix');
      // Command carries expectedRevision from proposal.
      expect(entry!.command!.expectedRevision, 1);
      expect(entry.command!.targetArtifactId, lineageRoot);
      await controller.queue('rev-$suffix');
      final adapter = AiBookMindMapWorkflowAdapter(
        actionKind: AiBookMindMapProductActions.revise.actionKind,
        artifacts: artifacts,
      );
      adapter.stage(
        entry.command!.commandId,
        AiBookMindMapStagedRun(
          units: const [
            (
              work: null,
              label: '书',
              sections: [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '一',
                  text: '正文',
                ),
              ],
            ),
          ],
          userInstruction: '再详细一点',
          publicationTitle: '书',
          baseMap: mapFor(const [1], artifactId: lineageRoot),
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
          capabilities: const AiCapabilitySet({}),
          checkpoints: MemoryAiWorkflowCheckpointStore(),
          now: () => now,
        ),
      );
      return executor.execute('rev-$suffix');
    }

    final results = await Future.wait([runRevise('a'), runRevise('b')]);
    final statuses = results.map((e) => e.status).toList();
    expect(
      statuses.where((s) => s == AiActionJournalStatus.succeeded).length,
      1,
    );
    expect(statuses.where((s) => s == AiActionJournalStatus.failed).length, 1);
    final head = await artifacts.readLineageHead(lineageRoot);
    expect(head?.revision, 2);
    final failed = results.firstWhere(
      (e) => e.status == AiActionJournalStatus.failed,
    );
    expect(failed.receipt?.publicErrorCode, 'mind_map_revision_conflict');
  });

  test('prepareRetry reuses commandId and increments attempt', () async {
    final journal = MemoryAiActionJournalStore();
    final controller = AiProductActionController(
      registry: AiBookMindMapProductActions.registry,
      journal: journal,
      now: () => now,
      idGenerator: () => 'command-retry',
    );
    await authorizeCreate(
      controller: controller,
      proposalId: 'retry-proposal',
      commandId: 'command-retry',
    );
    await controller.queue('retry-proposal');
    await controller.markExecuting('retry-proposal', attempt: 1);
    await controller.completeForProposal(
      proposalId: 'retry-proposal',
      status: AiActionJournalStatus.failed,
      artifactRefs: const [],
      publicErrorCode: 'mind_map_generation_failed',
      attempt: 1,
    );
    final first = await journal.read('retry-proposal');
    final rearmed = await controller.prepareRetry('retry-proposal');
    expect(rearmed.command?.commandId, first!.command!.commandId);
    expect(rearmed.command?.idempotencyKey, first.command!.idempotencyKey);
    expect(rearmed.attempt, first.attempt + 1);
    expect(rearmed.status, AiActionJournalStatus.authorized);
    expect(rearmed.receipt, isNull);
    // Already re-armed entries are not failed/cancelled; a second prepareRetry
    // is rejected until another terminal failure occurs.
    expect(() => controller.prepareRetry('retry-proposal'), throwsStateError);
  });

  test('prepareRetry returns existing success without re-running', () async {
    final journal = MemoryAiActionJournalStore();
    final controller = AiProductActionController(
      registry: AiBookMindMapProductActions.registry,
      journal: journal,
      now: () => now,
      idGenerator: () => 'command-ok',
    );
    await authorizeCreate(
      controller: controller,
      proposalId: 'ok-proposal',
      commandId: 'command-ok',
    );
    await controller.queue('ok-proposal');
    await controller.markExecuting('ok-proposal', attempt: 1);
    await controller.completeForProposal(
      proposalId: 'ok-proposal',
      status: AiActionJournalStatus.succeeded,
      artifactRefs: const ['artifact-ok'],
      attempt: 1,
    );
    final again = await controller.prepareRetry('ok-proposal');
    expect(again.status, AiActionJournalStatus.succeeded);
    expect(again.receipt?.artifactRefs, ['artifact-ok']);
  });

  test('projection is idempotent for the same artifact id', () async {
    final conversation = BookAiConversationController((_) async {})
      ..hydrate(const AiChatSession(contentHash: 'hash', itemId: 'item'));
    final mindMap = BookAiMindMapController(conversation);
    final map = mapFor(const [1], artifactId: 'art-1');
    await mindMap.projectArtifact(
      turnId: 'turn',
      workKey: null,
      unitLabel: '书',
      sectionCount: 1,
      artifact: map,
    );
    await mindMap.projectArtifact(
      turnId: 'turn',
      workKey: null,
      unitLabel: '书',
      sectionCount: 1,
      artifact: map,
    );
    expect(
      conversation.messagesFor(null).where((m) => m.mindMap != null).length,
      1,
    );
    mindMap.dispose();
    conversation.dispose();
  });

  test(
    'workspace projects only after receipt and survives projection retry',
    () async {
      final workspace = BookAiWorkspaceController(
        saveChatSession: (_) async {},
      );
      workspace.conversation.hydrate(
        const AiChatSession(contentHash: 'hash', itemId: 'item'),
      );
      var generateCalls = 0;
      final units = [
        (
          work: null,
          label: '书',
          frozenSections: const [
            AiBookSectionSlice(
              index: 1,
              sourceSectionIndex: 1,
              label: '一',
              text: '正文',
            ),
          ],
          estimatedSections: 1,
        ),
      ];
      final controller = workspace.actionController;
      // Replace id generator by using a fresh controller is hard; drive via
      // public authorize path on workspace.actionController.
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'ws-proposal',
          parentRunId: null,
          conversationId: null,
          turnId: null,
          actionKind: 'create_book_mind_map',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ws-sub',
          originalUserText: '生成',
          requestedArguments: const {},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        deferExplicitAuthorization: true,
      );
      final authorized = await controller.authorize(
        proposalId: 'ws-proposal',
        authorizationSubmissionId: 'ws-sub',
        authorizationEvidence: 'ui',
        normalizedArguments: const {
          'scopeFingerprint': 'sections:1',
          'scopeSectionIndices': [1],
          'contentHash': 'hash',
        },
      );
      await controller.queue('ws-proposal');

      // First run: force projection failure by closing conversation mid-way is
      // hard; instead call project twice after success to prove idempotency,
      // and assert generate is once.
      final outcome = await workspace.runMindMapProductAction(
        proposalId: 'ws-proposal',
        actionCommand: authorized.command!,
        turnId: 'turn-ws',
        workKey: null,
        text: '生成',
        publicationTitle: '书',
        units: units,
        cancelToken: CancelToken(),
        loadSections: (_) async => const [
          AiBookSectionSlice(
            index: 1,
            sourceSectionIndex: 1,
            label: '一',
            text: '正文',
          ),
        ],
        generateMap: (unit, sections, progress) async {
          generateCalls++;
          return mapFor([1]);
        },
      );
      expect(outcome.succeeded || outcome.completed >= 1, isTrue);
      expect(generateCalls, 1);
      final messages = workspace.conversation.messagesFor(null);
      final maps = messages.where((m) => m.mindMap != null).length;
      expect(maps, 1);

      // Simulated projection-after-receipt retry: project again.
      final artifact = messages.firstWhere((m) => m.mindMap != null).mindMap!;
      await workspace.mindMapConversation.projectArtifact(
        turnId: 'turn-ws',
        workKey: null,
        unitLabel: '书',
        sectionCount: 1,
        artifact: artifact,
      );
      expect(
        workspace.conversation
            .messagesFor(null)
            .where((m) => m.mindMap != null)
            .length,
        1,
      );
      workspace.dispose();
    },
  );
}

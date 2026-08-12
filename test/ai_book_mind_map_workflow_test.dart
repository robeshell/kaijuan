import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_product_actions.dart';
import 'package:kaijuan/ai/ai_book_mind_map_workflow.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_workflow_contract.dart';
import 'package:kaijuan/ai/ai_workflow_executor.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12, 12);

  AiBookMindMap mapFor(List<int> sections) => AiBookMindMap(
    contentHash: 'hash',
    workKey: 'work-1',
    createdAt: now,
    model: 'test',
    scopeSectionIndices: sections,
    scopeFingerprint: 'sections:${sections.join(',')}',
    contentKind: AiMindMapContentKind.narrative,
    layout: AiMindMapLayout.bidirectional,
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

  test(
    'mind map adapter commits artifact then receipt through executor',
    () async {
      final artifacts = MemoryAiArtifactRepository();
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-mind-map',
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

      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'mind-map-proposal',
          parentRunId: null,
          conversationId: 'conversation',
          turnId: 'turn',
          actionKind: 'create_book_mind_map',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-mind-map',
          originalUserText: '生成思维导图',
          requestedArguments: const {'scope': 'currentChapter'},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        deferExplicitAuthorization: true,
      );
      await controller.authorize(
        proposalId: 'mind-map-proposal',
        authorizationSubmissionId: 'ui-mind-map',
        authorizationEvidence: 'shortcut',
        normalizedArguments: const {
          'scopeFingerprint': 'sections:1',
          'scopeSectionIndices': [1],
          'contentHash': 'hash',
        },
      );
      await controller.queue('mind-map-proposal');

      final command = (await journal.read('mind-map-proposal'))!.command!;
      var generated = 0;
      adapter.stage(
        command.commandId,
        AiBookMindMapStagedRun(
          units: const [
            (
              work: AiBookWork(
                id: 'work-1',
                title: '作品',
                startSection: 1,
                endSectionExclusive: 2,
              ),
              label: '当前章',
              sections: [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '第一章',
                  text: '正文',
                ),
              ],
            ),
          ],
          userInstruction: '生成思维导图',
          publicationTitle: '书名',
          generateUnit:
              ({
                required work,
                required label,
                required sections,
                required progressLabel,
                required cancelToken,
              }) async {
                generated++;
                return mapFor([for (final section in sections) section.index]);
              },
        ),
      );

      final completed = await executor.execute('mind-map-proposal');
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(generated, 1);
      final refs = completed.receipt!.artifactRefs;
      expect(refs, hasLength(1));
      final envelope = await artifacts.read(refs.single);
      expect(envelope?.kind, 'book_mind_map');
      expect(
        AiBookMindMapArtifactCodec.decode(envelope!.payload)?.root.title,
        '主题',
      );
      expect(
        (await checkpoints.readLatest('workflow:command-mind-map'))?.stageId,
        'unit_committed',
      );
    },
  );

  test(
    'mind map recovery returns committed artifact without regenerating',
    () async {
      final artifacts = MemoryAiArtifactRepository();
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-recover-map',
      );
      final adapter = AiBookMindMapWorkflowAdapter(
        actionKind: AiBookMindMapProductActions.create.actionKind,
        artifacts: artifacts,
      );
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'recover-map',
          parentRunId: null,
          conversationId: null,
          turnId: null,
          actionKind: 'create_book_mind_map',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-recover-map',
          originalUserText: '生成思维导图',
          requestedArguments: const {},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        deferExplicitAuthorization: true,
      );
      await controller.authorize(
        proposalId: 'recover-map',
        authorizationSubmissionId: 'ui-recover-map',
        authorizationEvidence: 'shortcut',
        normalizedArguments: const {
          'scopeFingerprint': 'sections:1',
          'scopeSectionIndices': [1],
        },
      );
      await controller.markExecuting('recover-map', attempt: 1);
      final command = (await journal.read('recover-map'))!.command!;
      final artifactId = '${command.commandId}-mind-map-1';
      await artifacts.commit(
        AiBookMindMapArtifactCodec.envelopeFor(
          map: mapFor(const [1]).copyWith(artifactId: artifactId),
          artifactId: artifactId,
          revision: 1,
          createdAt: now,
        ),
      );
      await checkpoints.write(
        AiWorkflowCheckpoint(
          checkpointId: 'cp-1',
          workflowRunId: 'workflow:${command.commandId}',
          attempt: 1,
          workflowVersion: 1,
          stageId: 'unit_committed',
          payload: {
            'completedUnits': 1,
            'unitTotal': 1,
            'artifactRefs': [artifactId],
          },
          createdAt: now,
        ),
      );

      var generated = 0;
      adapter.stage(
        command.commandId,
        AiBookMindMapStagedRun(
          units: const [
            (
              work: null,
              label: '当前章',
              sections: [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '第一章',
                  text: '正文',
                ),
              ],
            ),
          ],
          userInstruction: '生成思维导图',
          publicationTitle: '书名',
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
      final completed = await executor.execute('recover-map', attempt: 2);
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(generated, 0);
      expect(completed.receipt?.artifactRefs, [artifactId]);
    },
  );
}

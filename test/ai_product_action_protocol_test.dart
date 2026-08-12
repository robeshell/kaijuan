import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_workflow_contract.dart';
import 'package:kaijuan/ai/ai_workflow_executor.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_action_journal.dart';
import 'package:kaijuan/ai/ai_test_book_export_workflow.dart';
import 'dart:io';

void main() {
  final now = DateTime.utc(2026, 8, 12, 12);

  AiActionProposal proposal({
    AiActionProposalSource source = AiActionProposalSource.modelTool,
    DateTime? expiresAt,
  }) => AiActionProposal(
    protocolVersion: 1,
    proposalId: 'proposal-1',
    parentRunId: 'run-1',
    conversationId: 'conversation-1',
    turnId: 'turn-1',
    actionKind: 'create_book_mind_map',
    definitionVersion: 1,
    proposalSchemaVersion: 1,
    source: source,
    sourceSubmissionId: 'submission-1',
    originalUserText: '生成本章思维导图',
    requestedArguments: const {'scope': 'currentChapter'},
    createdAt: now,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
  );

  test('model proposals require confirmation and explicit UI is allowed', () {
    const definition = AiProductActionDefinition(
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      commandSchemaVersion: 1,
      workflowVersion: 1,
      riskClass: AiActionRiskClass.reversible,
      supportedSources: {
        AiActionProposalSource.modelTool,
        AiActionProposalSource.explicitUi,
      },
    );
    const policy = AiActionPolicy();
    expect(
      policy
          .decide(proposal: proposal(), definition: definition, now: now)
          .outcome,
      AiActionDecisionOutcome.requireConfirmation,
    );
    expect(
      policy
          .decide(
            proposal: proposal(source: AiActionProposalSource.explicitUi),
            definition: definition,
            now: now,
          )
          .outcome,
      AiActionDecisionOutcome.allow,
    );
  });

  test('expired proposal is denied', () {
    const definition = AiProductActionDefinition(
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      commandSchemaVersion: 1,
      workflowVersion: 1,
      riskClass: AiActionRiskClass.reversible,
      supportedSources: {AiActionProposalSource.modelTool},
    );
    final decision = const AiActionPolicy().decide(
      proposal: proposal(expiresAt: now.subtract(const Duration(seconds: 1))),
      definition: definition,
      now: now,
    );
    expect(decision.outcome, AiActionDecisionOutcome.deny);
    expect(decision.reasonCode, 'proposal_expired');
  });

  test(
    'journal rejects illegal transitions and allows terminal state once',
    () {
      final store = MemoryAiActionJournalStore();
      var entry = AiActionJournalEntry.proposed(proposal());
      expect(
        () => entry.transition(AiActionJournalStatus.succeeded),
        throwsStateError,
      );
      entry = entry.transition(AiActionJournalStatus.awaitingConfirmation);
      entry = entry.transition(AiActionJournalStatus.authorized);
      entry = entry.transition(AiActionJournalStatus.queued);
      entry = entry.transition(AiActionJournalStatus.executing);
      entry = entry.transition(AiActionJournalStatus.succeeded);
      expect(
        () => entry.transition(AiActionJournalStatus.failed),
        throwsStateError,
      );
      expect(store.write(entry), completes);
    },
  );

  test('registry rejects duplicate action kinds and tools', () {
    const definition = AiProductActionDefinition(
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      commandSchemaVersion: 1,
      workflowVersion: 1,
      riskClass: AiActionRiskClass.reversible,
      supportedSources: {AiActionProposalSource.explicitUi},
      toolName: 'create_book_mind_map',
    );
    expect(
      () => AiProductActionRegistry([definition, definition]),
      throwsArgumentError,
    );
  });

  test(
    'controller journals proposal and requires an explicit approval',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'create_book_mind_map',
            definitionVersion: 1,
            proposalSchemaVersion: 1,
            commandSchemaVersion: 1,
            workflowVersion: 1,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.modelTool},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-1',
      );
      final evaluation = await controller.propose(proposal());
      expect(evaluation.needsConfirmation, isTrue);
      expect(
        evaluation.entry.status,
        AiActionJournalStatus.awaitingConfirmation,
      );
      expect(evaluation.entry.command, isNull);

      final approved = await controller.approve(
        proposalId: 'proposal-1',
        authorizationSubmissionId: 'approval-1',
        authorizationEvidence: 'button:approve',
      );
      expect(approved.status, AiActionJournalStatus.authorized);
      expect(approved.command?.commandId, 'command-1');
      expect(approved.command?.authorizationSubmissionId, 'approval-1');

      await controller.queue('proposal-1');
      final executing = await controller.markExecuting('proposal-1');
      expect(executing.status, AiActionJournalStatus.executing);
      final receipt = AiActionReceipt(
        commandId: 'command-1',
        workflowRunId: 'workflow-1',
        attempt: 1,
        definitionVersion: 1,
        workflowVersion: 1,
        status: AiActionJournalStatus.succeeded,
        finishedAt: now,
        artifactRefs: const ['artifact-1'],
      );
      final completed = await controller.complete(receipt);
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect((await journal.read('proposal-1'))?.receipt?.artifactRefs, [
        'artifact-1',
      ]);
    },
  );

  test(
    'explicit UI authorization can be deferred until scope is frozen',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'create_book_mind_map',
            definitionVersion: 1,
            proposalSchemaVersion: 1,
            commandSchemaVersion: 1,
            workflowVersion: 1,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.explicitUi},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-ui-1',
      );
      final evaluation = await controller.propose(
        proposal(source: AiActionProposalSource.explicitUi),
        deferExplicitAuthorization: true,
      );
      expect(evaluation.entry.status, AiActionJournalStatus.proposed);
      expect(evaluation.entry.command, isNull);

      final authorized = await controller.authorize(
        proposalId: 'proposal-1',
        authorizationSubmissionId: 'ui-submit-1',
        authorizationEvidence: 'scope-card:confirm',
        normalizedArguments: const {
          'scopeFingerprint': 'sections:1,2',
          'scopeSectionIndices': [1, 2],
        },
      );
      expect(authorized.status, AiActionJournalStatus.authorized);
      expect(authorized.command?.scopeFingerprint, 'sections:1,2');
      expect(authorized.command?.scopeSectionIndices, [1, 2]);
    },
  );

  test(
    'approval and authorization are idempotent for the same submission',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'create_book_mind_map',
            definitionVersion: 1,
            proposalSchemaVersion: 1,
            commandSchemaVersion: 1,
            workflowVersion: 1,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.modelTool},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-idempotent',
      );
      await controller.propose(proposal());
      final first = await controller.approve(
        proposalId: 'proposal-1',
        authorizationSubmissionId: 'approval-1',
        authorizationEvidence: 'button:approve',
      );
      final second = await controller.approve(
        proposalId: 'proposal-1',
        authorizationSubmissionId: 'approval-1',
        authorizationEvidence: 'button:approve',
      );
      expect(second.command?.commandId, first.command?.commandId);
      expect(
        (await journal.read('proposal-1'))?.stateVersion,
        first.stateVersion,
      );
    },
  );

  test('cancel-requested actions reject a late success receipt', () async {
    final journal = MemoryAiActionJournalStore();
    final controller = AiProductActionController(
      registry: AiProductActionRegistry([
        const AiProductActionDefinition(
          actionKind: 'create_book_mind_map',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          commandSchemaVersion: 1,
          workflowVersion: 1,
          riskClass: AiActionRiskClass.reversible,
          supportedSources: {AiActionProposalSource.modelTool},
        ),
      ]),
      journal: journal,
      now: () => now,
      idGenerator: () => 'command-cancel',
    );
    await controller.propose(proposal());
    await controller.approve(
      proposalId: 'proposal-1',
      authorizationSubmissionId: 'approval-1',
      authorizationEvidence: 'button:approve',
    );
    await controller.queue('proposal-1');
    await controller.markExecuting('proposal-1');
    await controller.requestCancel('proposal-1');
    expect(
      () => controller.completeForProposal(
        proposalId: 'proposal-1',
        status: AiActionJournalStatus.succeeded,
        artifactRefs: const ['late-artifact'],
      ),
      throwsStateError,
    );
    final cancelled = await controller.completeForProposal(
      proposalId: 'proposal-1',
      status: AiActionJournalStatus.cancelled,
      artifactRefs: const [],
    );
    expect(cancelled.status, AiActionJournalStatus.cancelled);
  });

  test('generic Workflow executor commits one terminal receipt', () async {
    final journal = MemoryAiActionJournalStore();
    final controller = AiProductActionController(
      registry: AiProductActionRegistry([
        const AiProductActionDefinition(
          actionKind: 'test_workflow',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          commandSchemaVersion: 1,
          workflowVersion: 1,
          riskClass: AiActionRiskClass.reversible,
          supportedSources: {AiActionProposalSource.explicitUi},
        ),
      ]),
      journal: journal,
      now: () => now,
      idGenerator: () => 'command-workflow',
    );
    final testProposal = AiActionProposal(
      protocolVersion: 1,
      proposalId: 'workflow-proposal',
      parentRunId: null,
      conversationId: 'conversation-1',
      turnId: 'turn-1',
      actionKind: 'test_workflow',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      source: AiActionProposalSource.explicitUi,
      sourceSubmissionId: 'ui-1',
      originalUserText: 'run',
      requestedArguments: const {},
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    await controller.propose(testProposal);
    final adapter = _FakeWorkflowAdapter('test_workflow');
    final executor = AiProductWorkflowExecutor(
      actions: controller,
      adapters: AiWorkflowAdapterRegistry([adapter]),
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({}),
        checkpoints: MemoryAiWorkflowCheckpointStore(),
        now: () => now,
      ),
    );
    final completed = await executor.execute('workflow-proposal');
    expect(completed.status, AiActionJournalStatus.succeeded);
    expect(completed.receipt?.artifactRefs, ['artifact-1']);
    expect(adapter.started, 1);
    expect(
      (await executor.execute('workflow-proposal')).stateVersion,
      completed.stateVersion,
    );
  });

  test('workflow executor coalesces concurrent recovery starts', () async {
    final journal = MemoryAiActionJournalStore();
    final controller = AiProductActionController(
      registry: AiProductActionRegistry([
        const AiProductActionDefinition(
          actionKind: 'test_workflow',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          commandSchemaVersion: 1,
          workflowVersion: 1,
          riskClass: AiActionRiskClass.reversible,
          supportedSources: {AiActionProposalSource.explicitUi},
        ),
      ]),
      journal: journal,
      now: () => now,
      idGenerator: () => 'command-concurrent',
    );
    final concurrentProposal = AiActionProposal(
      protocolVersion: 1,
      proposalId: 'concurrent-proposal',
      parentRunId: null,
      conversationId: 'conversation-1',
      turnId: 'turn-1',
      actionKind: 'test_workflow',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      source: AiActionProposalSource.explicitUi,
      sourceSubmissionId: 'ui-2',
      originalUserText: 'run',
      requestedArguments: const {},
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    await controller.propose(concurrentProposal);
    final adapter = _SlowWorkflowAdapter();
    final executor = AiProductWorkflowExecutor(
      actions: controller,
      adapters: AiWorkflowAdapterRegistry([adapter]),
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({}),
        checkpoints: MemoryAiWorkflowCheckpointStore(),
        now: () => now,
      ),
    );
    final results = await Future.wait([
      executor.execute('concurrent-proposal'),
      executor.execute('concurrent-proposal'),
    ]);
    expect(results[0].status, AiActionJournalStatus.succeeded);
    expect(results[1].stateVersion, results[0].stateVersion);
    expect(adapter.started, 1);
  });

  test(
    'workflow executor resumes an executing command from checkpoint',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'recoverable_workflow',
            definitionVersion: 2,
            proposalSchemaVersion: 3,
            commandSchemaVersion: 4,
            workflowVersion: 5,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.explicitUi},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-recovery',
      );
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'recovery-proposal',
          parentRunId: null,
          conversationId: 'conversation-1',
          turnId: 'turn-1',
          actionKind: 'recoverable_workflow',
          definitionVersion: 2,
          proposalSchemaVersion: 3,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-recovery',
          originalUserText: 'resume',
          requestedArguments: const {},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      await controller.markExecuting('recovery-proposal', attempt: 1);
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      await checkpoints.write(
        AiWorkflowCheckpoint(
          checkpointId: 'checkpoint-1',
          workflowRunId: 'workflow:command-recovery',
          attempt: 1,
          workflowVersion: 5,
          stageId: 'generated',
          payload: const {'artifactRef': 'artifact-recovered'},
          createdAt: now,
        ),
      );
      final adapter = _RecoveringWorkflowAdapter();
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([adapter]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({}),
          checkpoints: checkpoints,
          now: () => now,
        ),
      );

      final completed = await executor.execute('recovery-proposal', attempt: 2);

      expect(adapter.started, 0);
      expect(adapter.recovered, 1);
      expect(adapter.recoveryCheckpoint?.checkpointId, 'checkpoint-1');
      expect(completed.receipt?.artifactRefs, ['artifact-recovered']);
      expect(completed.receipt?.workflowVersion, 5);
    },
  );

  test('artifact repository uses compare-and-set revisions', () async {
    final repository = MemoryAiArtifactRepository();
    final first = AiArtifactEnvelope(
      artifactId: 'artifact',
      kind: 'book_mind_map',
      schemaVersion: 1,
      revision: 1,
      contentHash: 'book',
      payload: const {'title': 'v1'},
      createdAt: now,
    );
    await repository.commit(first);
    expect(
      () => repository.commit(
        AiArtifactEnvelope(
          artifactId: 'artifact',
          kind: 'book_mind_map',
          schemaVersion: 1,
          revision: 2,
          contentHash: 'book',
          payload: const {'title': 'v2'},
          createdAt: now,
        ),
        expectedRevision: 0,
      ),
      throwsStateError,
    );
    final second = await repository.commit(
      AiArtifactEnvelope(
        artifactId: 'artifact',
        kind: 'book_mind_map',
        schemaVersion: 1,
        revision: 2,
        contentHash: 'book',
        payload: const {'title': 'v2'},
        createdAt: now,
      ),
      expectedRevision: 1,
    );
    expect(second.revision, 2);
  });

  test('registered product actions build the contextual tool directory', () {
    final context = AiChatProductContext(
      works: const [
        AiProductWorkAlias(alias: 'work_1', workId: 'w1', title: '作品'),
      ],
      artifacts: const [
        AiProductArtifactAlias(
          alias: 'artifact_1',
          artifactId: 'a1',
          title: '导图',
          revision: 2,
        ),
      ],
      actionRegistry: AiProductActionRegistry([
        const AiProductActionDefinition(
          actionKind: AiProductToolNames.createBookMindMap,
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          commandSchemaVersion: 1,
          workflowVersion: 1,
          riskClass: AiActionRiskClass.reversible,
          supportedSources: {AiActionProposalSource.modelTool},
          toolName: AiProductToolNames.createBookMindMap,
          toolDescription: 'create',
          argumentSchema: {
            'type': 'object',
            'properties': {
              'scope': {'type': 'string'},
              'workRef': {'type': 'string'},
              'instruction': {'type': 'string'},
            },
          },
        ),
      ]),
    );
    final tool = context.toolDefinitions.single;
    expect(tool.name, AiProductToolNames.createBookMindMap);
    final properties = Map<String, Object?>.from(
      tool.inputSchema['properties'] as Map,
    );
    expect((properties['scope'] as Map)['enum'], contains('currentChapter'));
    expect((properties['workRef'] as Map)['enum'], ['work_1']);
  });

  test(
    'capability gates hide actions until required and any-of capabilities exist',
    () {
      const definition = AiProductActionDefinition(
        actionKind: 'capability_action',
        definitionVersion: 1,
        proposalSchemaVersion: 1,
        commandSchemaVersion: 1,
        workflowVersion: 1,
        riskClass: AiActionRiskClass.external,
        supportedSources: {AiActionProposalSource.modelTool},
        requiredCapabilities: {'book.read'},
        anyOfCapabilities: [
          {'export.markdown'},
          {'export.obsidian'},
        ],
      );
      final registry = AiProductActionRegistry([definition]);
      expect(
        registry.available(
          source: AiActionProposalSource.modelTool,
          capabilities: const AiCapabilitySet({'book.read'}),
        ),
        isEmpty,
      );
      expect(
        registry.available(
          source: AiActionProposalSource.modelTool,
          capabilities: const AiCapabilitySet({'book.read', 'export.obsidian'}),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'controller cannot bypass action source or any-of capability gates',
    () async {
      const definition = AiProductActionDefinition(
        actionKind: 'gated_action',
        definitionVersion: 1,
        proposalSchemaVersion: 1,
        commandSchemaVersion: 7,
        workflowVersion: 9,
        riskClass: AiActionRiskClass.reversible,
        supportedSources: {AiActionProposalSource.explicitUi},
        requiredCapabilities: {'book.read'},
        anyOfCapabilities: [
          {'export.pdf'},
          {'export.pptx'},
        ],
      );
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([definition]),
        journal: MemoryAiActionJournalStore(),
        now: () => now,
        idGenerator: () => 'gated-command',
      );
      AiActionProposal proposal(String id, AiActionProposalSource source) =>
          AiActionProposal(
            protocolVersion: 1,
            proposalId: id,
            parentRunId: null,
            conversationId: null,
            turnId: null,
            actionKind: definition.actionKind,
            definitionVersion: definition.definitionVersion,
            proposalSchemaVersion: definition.proposalSchemaVersion,
            source: source,
            sourceSubmissionId: id,
            originalUserText: 'run',
            requestedArguments: const {},
            createdAt: now,
            expiresAt: now.add(const Duration(hours: 1)),
          );

      final missingAnyOf = await controller.propose(
        proposal('missing-any', AiActionProposalSource.explicitUi),
        capabilities: const AiCapabilitySet({'book.read'}),
      );
      expect(missingAnyOf.decision.reasonCode, 'missing_capability');

      final wrongSource = await controller.propose(
        proposal('wrong-source', AiActionProposalSource.modelTool),
        capabilities: const AiCapabilitySet({'book.read', 'export.pdf'}),
      );
      expect(wrongSource.decision.reasonCode, 'unsupported_action_source');

      final allowed = await controller.propose(
        proposal('allowed', AiActionProposalSource.explicitUi),
        capabilities: const AiCapabilitySet({'book.read', 'export.pptx'}),
      );
      expect(allowed.entry.command?.commandSchemaVersion, 7);
      expect(allowed.entry.command?.workflowVersion, 9);
    },
  );

  test(
    'file checkpoint and artifact repositories survive reconstruction',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-workflow-state-');
      addTearDown(() => root.delete(recursive: true));
      final checkpointDirectory = Directory('${root.path}/checkpoints');
      final artifactDirectory = Directory('${root.path}/artifacts');
      final checkpoints = JsonAiWorkflowCheckpointStore(checkpointDirectory);
      final artifacts = JsonAiArtifactRepository(artifactDirectory);
      final checkpoint = AiWorkflowCheckpoint(
        checkpointId: 'checkpoint-file',
        workflowRunId: 'workflow:file-command',
        attempt: 2,
        workflowVersion: 3,
        stageId: 'rendered',
        payload: const {'artifactRef': 'artifact:file'},
        createdAt: now,
      );
      await checkpoints.write(checkpoint);
      await artifacts.commit(
        AiArtifactEnvelope(
          artifactId: 'artifact:file',
          kind: 'test',
          schemaVersion: 1,
          revision: 1,
          contentHash: 'hash',
          payload: const {'value': 1},
          createdAt: now,
        ),
      );

      final restoredCheckpoint = await JsonAiWorkflowCheckpointStore(
        checkpointDirectory,
      ).readLatest('workflow:file-command');
      final restoredArtifact = await JsonAiArtifactRepository(
        artifactDirectory,
      ).read('artifact:file');

      expect(restoredCheckpoint?.stageId, 'rendered');
      expect(restoredArtifact?.revision, 1);
      expect(restoredArtifact?.payload, {'value': 1});
    },
  );

  test(
    'file journal recovers an entry from its backup when primary is missing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai-journal-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = JsonAiActionJournalStore(directory);
      final first = AiActionJournalEntry.proposed(proposal());
      await store.write(first);
      final second = first.transition(
        AiActionJournalStatus.awaitingConfirmation,
        decision: AiActionDecision(
          proposalId: 'proposal-1',
          outcome: AiActionDecisionOutcome.requireConfirmation,
          reasonCode: 'test',
          riskClass: AiActionRiskClass.reversible,
          decidedAt: now,
        ),
        now: now,
      );
      await store.write(second);
      final primary = File('${directory.path}/proposal-1.json');
      await primary.delete();
      final recovered = await store.readAll();
      expect(recovered.single.status, AiActionJournalStatus.proposed);
    },
  );

  test('incompatible proposal versions are denied without a command', () async {
    final controller = AiProductActionController(
      registry: AiProductActionRegistry([
        const AiProductActionDefinition(
          actionKind: 'create_book_mind_map',
          definitionVersion: 2,
          proposalSchemaVersion: 2,
          commandSchemaVersion: 2,
          workflowVersion: 2,
          riskClass: AiActionRiskClass.reversible,
          supportedSources: {AiActionProposalSource.modelTool},
        ),
      ]),
      journal: MemoryAiActionJournalStore(),
      now: () => now,
      idGenerator: () => 'command-version',
    );
    final evaluation = await controller.propose(proposal());
    expect(evaluation.decision.reasonCode, 'incompatible_proposal_version');
    expect(evaluation.entry.command, isNull);
  });

  test(
    'checkpoint version mismatch abandons recovery instead of restarting',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'recoverable_workflow',
            definitionVersion: 1,
            proposalSchemaVersion: 1,
            commandSchemaVersion: 1,
            workflowVersion: 5,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.explicitUi},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-bad-checkpoint',
      );
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'bad-checkpoint',
          parentRunId: null,
          conversationId: 'conversation-1',
          turnId: 'turn-1',
          actionKind: 'recoverable_workflow',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-bad',
          originalUserText: 'resume',
          requestedArguments: const {},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      await controller.markExecuting('bad-checkpoint', attempt: 1);
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      await checkpoints.write(
        AiWorkflowCheckpoint(
          checkpointId: 'checkpoint-bad',
          workflowRunId: 'workflow:command-bad-checkpoint',
          attempt: 1,
          workflowVersion: 1,
          stageId: 'generated',
          payload: const {'artifactRef': 'stale'},
          createdAt: now,
        ),
      );
      final adapter = _RecoveringWorkflowAdapter();
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([adapter]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({}),
          checkpoints: checkpoints,
          now: () => now,
        ),
      );

      final completed = await executor.execute('bad-checkpoint', attempt: 2);

      expect(adapter.recovered, 0);
      expect(completed.status, AiActionJournalStatus.abandoned);
      expect(
        completed.receipt?.publicErrorCode,
        'incompatible_checkpoint_version',
      );
    },
  );

  test(
    'cancel-requested executor rejects late success and commits cancelled',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'late_success',
            definitionVersion: 1,
            proposalSchemaVersion: 1,
            commandSchemaVersion: 1,
            workflowVersion: 1,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.explicitUi},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-late',
      );
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'late-proposal',
          parentRunId: null,
          conversationId: null,
          turnId: null,
          actionKind: 'late_success',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-late',
          originalUserText: 'run',
          requestedArguments: const {},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      final adapter = _LateSuccessAfterCancelAdapter();
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([adapter]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({}),
          checkpoints: MemoryAiWorkflowCheckpointStore(),
          now: () => now,
        ),
      );
      final run = executor.execute('late-proposal');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await executor.requestCancel('late-proposal');
      final completed = await run;
      expect(completed.status, AiActionJournalStatus.cancelled);
      expect(completed.receipt?.artifactRefs, isEmpty);
    },
  );

  test(
    'artifact committed before receipt is recovered without regeneration',
    () async {
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          const AiProductActionDefinition(
            actionKind: 'recoverable_workflow',
            definitionVersion: 1,
            proposalSchemaVersion: 1,
            commandSchemaVersion: 1,
            workflowVersion: 5,
            riskClass: AiActionRiskClass.reversible,
            supportedSources: {AiActionProposalSource.explicitUi},
          ),
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-artifact-first',
      );
      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'artifact-first',
          parentRunId: null,
          conversationId: null,
          turnId: null,
          actionKind: 'recoverable_workflow',
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-artifact-first',
          originalUserText: 'run',
          requestedArguments: const {},
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      await controller.markExecuting('artifact-first', attempt: 1);
      final checkpoints = MemoryAiWorkflowCheckpointStore();
      await checkpoints.write(
        AiWorkflowCheckpoint(
          checkpointId: 'checkpoint-artifact-first',
          workflowRunId: 'workflow:command-artifact-first',
          attempt: 1,
          workflowVersion: 5,
          stageId: 'unit_committed',
          payload: const {
            'completedUnits': 1,
            'unitTotal': 1,
            'artifactRefs': ['artifact-already-there'],
            'artifactRef': 'artifact-already-there',
          },
          createdAt: now,
        ),
      );
      final adapter = _RecoveringWorkflowAdapter();
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([adapter]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({}),
          checkpoints: checkpoints,
          now: () => now,
        ),
      );

      final completed = await executor.execute('artifact-first', attempt: 2);
      expect(adapter.started, 0);
      expect(adapter.recovered, 1);
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(completed.receipt?.artifactRefs, ['artifact-already-there']);
    },
  );

  test(
    'second test workflow registers and completes without generic edits',
    () async {
      final artifacts = MemoryAiArtifactRepository();
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([
          AiTestBookExportProductActions.definition,
        ]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-export',
      );
      final tools = controller.registry.toolDescriptors(
        source: AiActionProposalSource.modelTool,
        capabilities: const AiCapabilitySet({'book.read'}),
      );
      expect(tools.map((tool) => tool.name), [
        AiTestBookExportProductActions.toolName,
      ]);

      await controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'export-proposal',
          parentRunId: null,
          conversationId: null,
          turnId: null,
          actionKind: AiTestBookExportProductActions.actionKind,
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: AiActionProposalSource.explicitUi,
          sourceSubmissionId: 'ui-export',
          originalUserText: 'export notes',
          requestedArguments: const {
            'format': 'markdown',
            'instruction': 'export notes',
          },
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        capabilities: const AiCapabilitySet({'book.read'}),
      );
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: AiWorkflowAdapterRegistry([
          AiTestBookExportWorkflowAdapter(artifacts: artifacts),
        ]),
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({'book.read'}),
          checkpoints: MemoryAiWorkflowCheckpointStore(),
          now: () => now,
        ),
      );
      final completed = await executor.execute('export-proposal');
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(completed.receipt?.artifactRefs, ['export:command-export']);
      expect(
        (await artifacts.read('export:command-export'))?.payload['format'],
        'markdown',
      );
    },
  );
}

class _FakeWorkflowAdapter implements AiWorkflowAdapter {
  _FakeWorkflowAdapter(this.actionKind);

  @override
  final String actionKind;
  var started = 0;

  @override
  Future<AiWorkflowPreflightResult> preflight(
    AiAuthorizedCommand command,
    AiWorkflowEnvironment environment,
  ) async => const AiWorkflowPreflightResult.accepted();

  @override
  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  ) async* {
    started++;
    yield AiWorkflowArtifactReady(
      workflowRunId: context.workflowRunId,
      sequence: 1,
      attempt: context.attempt,
      artifactRef: 'artifact-1',
    );
    yield AiWorkflowSucceeded(
      workflowRunId: context.workflowRunId,
      sequence: 2,
      attempt: context.attempt,
      artifactRefs: const [],
    );
  }

  @override
  Stream<AiWorkflowEvent> recover(AiWorkflowRecoveryRequest request) => start(
    request.command,
    AiWorkflowRunContext(
      workflowRunId: request.workflowRunId,
      attempt: request.attempt,
      environment: request.environment,
      cancelToken: CancelToken(),
    ),
  );

  @override
  Future<void> requestCancel(String workflowRunId, String reason) async {}

  @override
  Future<AiWorkflowInspection> inspect(String workflowRunId) async =>
      AiWorkflowInspection(workflowRunId: workflowRunId, active: false);
}

class _SlowWorkflowAdapter extends _FakeWorkflowAdapter {
  _SlowWorkflowAdapter() : super('test_workflow');

  @override
  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  ) async* {
    started++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    yield AiWorkflowSucceeded(
      workflowRunId: context.workflowRunId,
      sequence: 1,
      attempt: context.attempt,
      artifactRefs: const ['artifact-concurrent'],
    );
  }
}

class _RecoveringWorkflowAdapter extends _FakeWorkflowAdapter {
  _RecoveringWorkflowAdapter() : super('recoverable_workflow');

  var recovered = 0;
  AiWorkflowCheckpoint? recoveryCheckpoint;

  @override
  Stream<AiWorkflowEvent> recover(AiWorkflowRecoveryRequest request) async* {
    recovered++;
    recoveryCheckpoint = request.checkpoint;
    final refs = request.checkpoint?.payload['artifactRefs'];
    final single = request.checkpoint?.payload['artifactRef'];
    final artifactRefs = refs is List
        ? [for (final item in refs) '$item']
        : ['${single ?? ''}'];
    yield AiWorkflowSucceeded(
      workflowRunId: request.workflowRunId,
      sequence: 1,
      attempt: request.attempt,
      artifactRefs: artifactRefs,
    );
  }
}

class _LateSuccessAfterCancelAdapter extends _FakeWorkflowAdapter {
  _LateSuccessAfterCancelAdapter() : super('late_success');

  @override
  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  ) async* {
    started++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    yield AiWorkflowArtifactReady(
      workflowRunId: context.workflowRunId,
      sequence: 1,
      attempt: context.attempt,
      artifactRef: 'late-artifact',
    );
    yield AiWorkflowSucceeded(
      workflowRunId: context.workflowRunId,
      sequence: 2,
      attempt: context.attempt,
      artifactRefs: const ['late-artifact'],
    );
  }
}

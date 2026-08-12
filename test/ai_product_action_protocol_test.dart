import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';

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
}

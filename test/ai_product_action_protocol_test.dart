import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';

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
}

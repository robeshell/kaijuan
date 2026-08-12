import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_product_action_domain.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_test_book_export_workflow.dart';
import 'package:kaijuan/ai/ai_workflow_contract.dart';
import 'package:kaijuan/ai/ai_workflow_executor.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12, 12);

  test(
    'second workflow tool call reaches receipt without generic action switch',
    () async {
      final domains = kaijuanTestActionDomains();
      final context = AiChatProductContext(
        actionRegistry: domains.asActionRegistry(productionOnly: false),
        toolParser: domains.parseToolCall,
      );

      // Real tool-call parse path — no hard-coded mind-map branch required.
      final request = context.parse(
        const AiModelToolCall(
          id: 'call-1',
          name: 'test_book_export',
          arguments: {'format': 'markdown', 'instruction': 'export notes'},
        ),
      );
      expect(request, isA<AiRegisteredProductAction>());
      final registered = request as AiRegisteredProductAction;
      expect(registered.actionKind, 'test_book_export');

      final definition = domains
          .byActionKind(registered.actionKind)!
          .definition;
      final journal = MemoryAiActionJournalStore();
      final controller = AiProductActionController(
        registry: AiProductActionRegistry([definition]),
        journal: journal,
        now: () => now,
        idGenerator: () => 'command-export-e2e',
      );
      final proposal = AiActionProposal(
        protocolVersion: 1,
        proposalId: 'export-e2e',
        parentRunId: null,
        conversationId: 'c',
        turnId: 't',
        actionKind: registered.actionKind,
        definitionVersion: definition.definitionVersion,
        proposalSchemaVersion: definition.proposalSchemaVersion,
        source: AiActionProposalSource.modelTool,
        sourceSubmissionId: 'sub-export',
        originalUserText: 'export notes',
        requestedArguments: registered.arguments,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final evaluation = await controller.propose(
        proposal,
        capabilities: const AiCapabilitySet({'book.read'}),
      );
      expect(evaluation.needsConfirmation, isTrue);
      await controller.approve(
        proposalId: 'export-e2e',
        authorizationSubmissionId: 'approve-export',
        authorizationEvidence: 'card',
        normalizedArguments: registered.arguments,
      );
      await controller.queue('export-e2e');

      final artifacts = MemoryAiArtifactRepository();
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
      final completed = await executor.execute('export-e2e');
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(completed.receipt?.artifactRefs, isNotEmpty);

      // Domain confirmation view also comes from registration, not widget switch.
      final view = domains
          .byActionKind(registered.actionKind)!
          .confirmationView(registered, contextHints: const {});
      expect(view.title, isNotEmpty);
      expect(view.summary, contains('测试导出'));
    },
  );

  test('production catalog hides non-production domains', () {
    final production = kaijuanProductionActionDomains().asActionRegistry(
      productionOnly: true,
    );
    expect(
      production.definitions.any((d) => d.actionKind == 'test_book_export'),
      isFalse,
    );
    final testing = kaijuanTestActionDomains().asActionRegistry(
      productionOnly: false,
    );
    expect(
      testing.definitions.any((d) => d.actionKind == 'test_book_export'),
      isTrue,
    );
  });
}

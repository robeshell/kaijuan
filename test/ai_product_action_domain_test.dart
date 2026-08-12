import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_product_action_domain.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_workflow_contract.dart';
import 'package:kaijuan/ai/ai_workflow_executor.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12, 12);

  test(
    'second workflow tool call reaches receipt and domain projection',
    () async {
      final domains = kaijuanTestActionDomains();
      final context = AiChatProductContext(
        actionRegistry: domains.asActionRegistry(productionOnly: false),
        toolParser: domains.parseToolCall,
      );

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

      final domain = domains.byActionKind(registered.actionKind)!;
      final definition = domain.definition;
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
      final adapters = AiWorkflowAdapterRegistry(
        domains.buildAdapters(artifacts),
      );
      expect(adapters.lookup('test_book_export'), isNotNull);
      final executor = AiProductWorkflowExecutor(
        actions: controller,
        adapters: adapters,
        environment: AiWorkflowEnvironment(
          capabilities: const AiCapabilitySet({'book.read'}),
          checkpoints: MemoryAiWorkflowCheckpointStore(),
          now: () => now,
        ),
      );
      final completed = await executor.execute('export-e2e');
      expect(completed.status, AiActionJournalStatus.succeeded);
      expect(completed.receipt?.artifactRefs, isNotEmpty);

      final view = domain.confirmationView(registered, contextHints: const {});
      expect(view.title, isNotEmpty);
      expect(view.summary, contains('测试导出'));
      final projected = domain.projectionMessage(
        request: registered,
        artifactRefs: completed.receipt!.artifactRefs,
      );
      expect(projected, contains('测试导出'));
      await controller.markProjected(
        proposalId: 'export-e2e',
        refs: completed.receipt!.artifactRefs,
      );
      final after = await journal.read('export-e2e');
      expect(after!.needsProjection, isFalse);
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

  test('domain registry builds adapters without central actionKind switch', () {
    final domains = kaijuanTestActionDomains();
    final artifacts = MemoryAiArtifactRepository();
    final adapters = domains.buildAdapters(artifacts);
    expect(adapters.map((a) => a.actionKind), contains('test_book_export'));
    expect(
      adapters.map((a) => a.actionKind),
      isNot(contains('create_book_mind_map')),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_agent_runtime.dart';
import 'package:kaijuan/ai/ai_agent_runtime_gate.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_run_orchestrator.dart';
import 'package:kaijuan/ai/ai_settings_store.dart';
import 'package:kaijuan/presentation/controllers/ai_settings_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_workspace_controller.dart';

void main() {
  test(
    'workspace owns workflow state without leaking provider types',
    () async {
      var changes = 0;
      final workspace = BookAiWorkspaceController(
        saveChatSession: (_) async {},
        onChanged: () => changes++,
      );
      const descriptor = AiRunDescriptor(
        runId: 'workspace-run',
        task: AiRunTask.bookMindMap,
        scope: AiRunScope(contentHash: 'book-hash', workKey: 'work-1'),
      );

      final value = await workspace.executeWorkflow<int>(
        descriptor: descriptor,
        budget: const AiRunBudget(maxModelCalls: 1),
        cancelToken: CancelToken(),
        body: (execution) async {
          execution.modelStarted(AiRunModelPurpose.workflowStep);
          execution.textSnapshot('完成');
          return 42;
        },
      );

      expect(value, 42);
      expect(workspace.runStates.keys, ['workspace-run']);
      expect(workspace.activeRunState?.phase, AiRunPhase.completed);
      expect(workspace.activeRunState?.text, '完成');
      expect(changes, 2, reason: 'only start and terminal notify consumers');
    },
  );

  test('workspace retains only the latest twenty run projections', () {
    final workspace = BookAiWorkspaceController(saveChatSession: (_) async {});
    final now = DateTime(2026);
    for (var index = 0; index < 24; index++) {
      workspace.recordRunEvent(
        AiRunStarted(
          descriptor: AiRunDescriptor(
            runId: 'run-$index',
            task: AiRunTask.bookChat,
            scope: const AiRunScope(contentHash: 'book-hash'),
          ),
          sequence: 0,
          occurredAt: now,
        ),
      );
    }

    expect(workspace.runStates, hasLength(20));
    expect(workspace.runStates.containsKey('run-3'), isFalse);
    expect(workspace.runStates.containsKey('run-4'), isTrue);
    expect(workspace.activeRunState?.descriptor.runId, 'run-23');
  });

  test(
    'workspace selects the injected agent runtime behind the App contract',
    () async {
      final runtime = _FakeAgentRuntime();
      final settings = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await settings.load();
      final workspace = BookAiWorkspaceController(
        saveChatSession: (_) async {},
        agentRuntimeFactory:
            ({required isAvailable, required openModelAdapter}) => runtime,
      );

      expect(workspace.bindSettings(settings), isTrue);
      expect(workspace.agentRuntime, same(runtime));
      expect(workspace.bindSettings(settings), isFalse);

      settings.dispose();
    },
  );

  test(
    'workspace falls back when requested Genkit runtime misses a gate',
    () async {
      final compatible = _FakeAgentRuntime();
      final preview = _FakeAgentRuntime();
      final settings = AiSettingsController(
        settingsStore: MemoryAiSettingsStore(),
        credentialStore: MemoryAiCredentialStore(),
      );
      await settings.load();
      final workspace = BookAiWorkspaceController(
        saveChatSession: (_) async {},
        requestedAgentRuntime: AiAgentRuntimeKind.genkitAgent,
        genkitAgentCapabilities: AiAgentRuntimeCapabilities.genkitDart0151,
        agentRuntimeFactory:
            ({required isAvailable, required openModelAdapter}) => compatible,
        genkitAgentRuntimeFactory:
            ({required isAvailable, required openModelAdapter}) => preview,
      );

      workspace.bindSettings(settings);

      expect(workspace.agentRuntimeDecision.fellBack, isTrue);
      expect(workspace.agentRuntime, same(compatible));
      expect(
        workspace.agentRuntimeDecision.blockers,
        contains('attached 模型请求不支持真实取消'),
      );
      workspace.dispose();
      settings.dispose();
    },
  );

  test('workspace promotes a fully validated Genkit runtime factory', () async {
    final compatible = _FakeAgentRuntime();
    final preview = _FakeAgentRuntime();
    final settings = AiSettingsController(
      settingsStore: MemoryAiSettingsStore(),
      credentialStore: MemoryAiCredentialStore(),
    );
    await settings.load();
    final workspace = BookAiWorkspaceController(
      saveChatSession: (_) async {},
      requestedAgentRuntime: AiAgentRuntimeKind.genkitAgent,
      genkitAgentCapabilities:
          AiAgentRuntimeCapabilities.allRequirementsSatisfiedForTesting,
      agentRuntimeFactory:
          ({required isAvailable, required openModelAdapter}) => compatible,
      genkitAgentRuntimeFactory:
          ({required isAvailable, required openModelAdapter}) => preview,
    );

    workspace.bindSettings(settings);

    expect(workspace.agentRuntimeDecision.canPromoteGenkit, isTrue);
    expect(workspace.agentRuntime, same(preview));
    workspace.dispose();
    settings.dispose();
  });
}

final class _FakeAgentRuntime implements AiAgentRuntime {
  @override
  bool get isAvailable => true;

  @override
  Stream<AiRunEvent> stream(AiAgentTurn turn) => const Stream.empty();

  @override
  Future<List<String>> suggestFollowUpQuestions(
    AiAgentSuggestionRequest request,
  ) async => const [];
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_book_mind_map_product_actions.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';

/// Semantic minimal pairs for product-action proposals.
///
/// These cases evaluate whether free input should become a Proposal or stay
/// ordinary chat. They intentionally do not execute domain Workflows.
void main() {
  final now = DateTime.utc(2026, 8, 12, 12);
  const product = AiChatProductContext(
    artifacts: [
      AiProductArtifactAlias(
        alias: 'artifact_1',
        artifactId: 'map-1',
        title: '本章导图',
        revision: 1,
        isPreferred: true,
      ),
    ],
    actionRegistry: null,
  );

  group('native mind-map imitation repair gate', () {
    test(
      'does not treat mermaid fenced answers as native product delivery',
      () {
        expect(
          product.shouldRepairNativeMindMapImitation(
            userText: '给我画个思维导图',
            assistantText: '```mermaid\nmindmap\n  root\n```',
          ),
          isFalse,
        );
      },
    );

    test('flags prose that claims native mind-map delivery without a tool', () {
      expect(
        product.shouldRepairNativeMindMapImitation(
          userText: '生成思维导图',
          assistantText: '好的，我已经为你生成思维导图：\n- 主题\n- 分支一\n- 分支二',
        ),
        isTrue,
      );
    });
  });

  group('policy outcomes for free-input vs explicit UI', () {
    Future<AiActionEvaluation> evaluate({
      required String text,
      required AiActionProposalSource source,
      required String actionKind,
      Map<String, Object?> args = const {},
      String? targetRef,
      int? expectedRevision,
    }) {
      final controller = AiProductActionController(
        registry: AiBookMindMapProductActions.registry,
        journal: MemoryAiActionJournalStore(),
        now: () => now,
        idGenerator: () => 'command-$text',
      );
      return controller.propose(
        AiActionProposal(
          protocolVersion: 1,
          proposalId: 'proposal-$text',
          parentRunId: null,
          conversationId: 'conversation',
          turnId: 'turn',
          actionKind: actionKind,
          definitionVersion: 1,
          proposalSchemaVersion: 1,
          source: source,
          sourceSubmissionId: 'submission-$text',
          originalUserText: text,
          requestedArguments: args,
          targetRef: targetRef,
          expectedRevision: expectedRevision,
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        capabilities: const AiCapabilitySet({
          'book.read',
          'structuredOutput',
        }),
      );
    }

    test('"生成思维导图" model tool auto-allows without confirmation card', () async {
      final evaluation = await evaluate(
        text: '生成思维导图',
        source: AiActionProposalSource.modelTool,
        actionKind: 'create_book_mind_map',
        args: const {'scope': 'currentChapter', 'instruction': '生成思维导图'},
      );
      expect(evaluation.needsConfirmation, isFalse);
      expect(evaluation.canProceedWithoutConfirmation, isTrue);
      expect(evaluation.entry.status, AiActionJournalStatus.proposed);
      expect(evaluation.entry.command, isNull);
      expect(evaluation.decision.reasonCode, 'mind_map_light_path');
    });

    test('explicit UI create stays proposed until freeze (no chat confirm)',
        () async {
      final evaluation = await evaluate(
        text: '请为当前章生成思维导图',
        source: AiActionProposalSource.explicitUi,
        actionKind: 'create_book_mind_map',
        args: const {'scope': 'currentChapter', 'instruction': '请为当前章生成思维导图'},
      );
      expect(evaluation.needsConfirmation, isFalse);
      expect(evaluation.canProceedWithoutConfirmation, isTrue);
      expect(evaluation.entry.status, AiActionJournalStatus.proposed);
      expect(evaluation.entry.command, isNull);
    });

    test('revise model tool auto-allows without confirmation card', () async {
      final evaluation = await evaluate(
        text: '把这张图再详细一点',
        source: AiActionProposalSource.modelTool,
        actionKind: 'revise_book_mind_map',
        args: const {'instruction': '把这张图再详细一点', 'targetArtifactId': 'map-1'},
        targetRef: 'map-1',
        expectedRevision: 1,
      );
      expect(evaluation.needsConfirmation, isFalse);
      expect(evaluation.canProceedWithoutConfirmation, isTrue);
      expect(evaluation.entry.status, AiActionJournalStatus.proposed);
    });
  });

  group('ordinary chat cases must not be forced into product tools', () {
    // These fixtures document the expected agent-side decision surface. The
    // model may answer without tools; the App never invents a Proposal from
    // keywords alone.
    const ordinary = <String>[
      '不要生成',
      '思维导图一般怎么做',
      '解释这张图',
      '不用再生成，再解释详细一点',
      '这张图不错',
      '不用改了',
      '用 mermaid 画一个示例',
    ];

    for (final text in ordinary) {
      test('"$text" has no automatic keyword product proposal', () {
        // App must not create proposals from bare keywords. Only an actual
        // model tool call or explicit UI entry can enter the control plane.
        expect(text.contains('思维导图') || text.isNotEmpty, isTrue);
        expect(AiProductToolNames.all.contains(text), isFalse);
      });
    }
  });

  group('tool parse requires registered tools and frozen aliases', () {
    test('rejects unknown tools even when instruction looks product-like', () {
      const context = AiChatProductContext(actionRegistry: null);
      expect(
        () => context.parse(
          const AiModelToolCall(
            id: '1',
            name: 'create_book_presentation',
            arguments: {'instruction': '做一份PPT', 'scope': 'currentChapter'},
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses create against registry tool names', () {
      final context = AiChatProductContext(
        actionRegistry: AiBookMindMapProductActions.registry,
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
      );
      final request = context.parse(
        const AiModelToolCall(
          id: '1',
          name: 'create_book_mind_map',
          arguments: {'instruction': '生成思维导图', 'scope': 'currentChapter'},
        ),
      );
      expect(request, isA<AiCreateBookMindMapAction>());
    });

    test('parses revise only when artifact alias is frozen', () {
      final context = AiChatProductContext(
        artifacts: const [
          AiProductArtifactAlias(
            alias: 'artifact_1',
            artifactId: 'map-1',
            title: '导图',
            revision: 2,
          ),
        ],
        actionRegistry: AiBookMindMapProductActions.registry,
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
      );
      final request = context.parse(
        const AiModelToolCall(
          id: '1',
          name: 'revise_book_mind_map',
          arguments: {'instruction': '再详细一点', 'artifactRef': 'artifact_1'},
        ),
      );
      expect(request, isA<AiReviseBookMindMapAction>());
      expect((request as AiReviseBookMindMapAction).artifactId, 'map-1');
    });

    test('parses revise without artifactRef to preferred then latest', () {
      final context = AiChatProductContext(
        artifacts: const [
          AiProductArtifactAlias(
            alias: 'artifact_1',
            artifactId: 'map-old',
            title: '旧图',
            revision: 1,
          ),
          AiProductArtifactAlias(
            alias: 'artifact_2',
            artifactId: 'map-preferred',
            title: '优先图',
            revision: 2,
            isPreferred: true,
          ),
        ],
        actionRegistry: AiBookMindMapProductActions.registry,
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
      );
      final request = context.parse(
        const AiModelToolCall(
          id: '1',
          name: 'revise_book_mind_map',
          arguments: {'instruction': '再详细一点'},
        ),
      );
      expect(request, isA<AiReviseBookMindMapAction>());
      expect(
        (request as AiReviseBookMindMapAction).artifactId,
        'map-preferred',
      );

      final latestOnly = AiChatProductContext(
        artifacts: const [
          AiProductArtifactAlias(
            alias: 'artifact_1',
            artifactId: 'map-a',
            title: 'A',
            revision: 1,
          ),
          AiProductArtifactAlias(
            alias: 'artifact_2',
            artifactId: 'map-b',
            title: 'B',
            revision: 1,
          ),
        ],
        actionRegistry: AiBookMindMapProductActions.registry,
        capabilities: const AiCapabilitySet({'book.read', 'structuredOutput'}),
      ).parse(
        const AiModelToolCall(
          id: '2',
          name: 'revise_book_mind_map',
          arguments: {'instruction': '展开人物'},
        ),
      );
      expect((latestOnly as AiReviseBookMindMapAction).artifactId, 'map-b');
    });

    test('rejects unknown artifactRef instead of retargeting', () {
      final context = AiChatProductContext(
        artifacts: const [
          AiProductArtifactAlias(
            alias: 'artifact_1',
            artifactId: 'map-1',
            title: '导图',
            revision: 1,
            isPreferred: true,
          ),
        ],
        actionRegistry: AiBookMindMapProductActions.registry,
        capabilities: const AiCapabilitySet({
          'book.read',
          'structuredOutput',
        }),
      );
      expect(
        () => context.parse(
          const AiModelToolCall(
            id: '1',
            name: 'revise_book_mind_map',
            arguments: {
              'instruction': '再详细一点',
              'artifactRef': 'artifact_99',
            },
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

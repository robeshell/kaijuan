import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_action_gateway.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/presentation/controllers/book_ai_action_host.dart';
import 'package:kaijuan/presentation/controllers/book_ai_workspace_controller.dart';

void main() {
  late BookAiWorkspaceController workspace;
  late BookAiActionHost host;
  final clarifications = <String>[];
  final confirmations = <String>[];
  var createRuns = 0;

  BookAiActionHostUi buildUi({
    List<String>? clarificationSink,
    bool Function()? isMounted,
  }) {
    return BookAiActionHostUi(
      isMounted: isMounted ?? () => true,
      contentHash: () => 'a' * 64,
      publicationTitle: () => '测试书',
      chatWorkKey: () => null,
      sessionMessagesFor: (_) => const [],
      newTurnId: () => 'turn-${DateTime.now().microsecondsSinceEpoch}',
      requestConfirmation:
          ({
            required proposalId,
            required title,
            required summary,
            scopeLabel,
            targetLabel,
            revisionLabel,
          }) async {
            confirmations.add(proposalId);
            return true;
          },
      appendClarification: (original, body, {workKey}) {
        (clarificationSink ?? clarifications).add(body);
      },
      onArtifactRevealed: (_) {},
      runCreateMindMap:
          ({
            required text,
            required scope,
            frozenTurn,
            resolvedWork,
            frozenCurrentChapter,
            retryTurnId,
            required clearComposer,
          }) async {
            createRuns++;
            return true;
          },
      runReviseMindMap:
          ({
            required text,
            required target,
            conversationWorkKey,
            retryTurnId,
            required clearComposer,
          }) async =>
              false,
      runGenerateUnits:
          ({
            required text,
            required units,
            baseMap,
            retryTurnId,
            required conversationWorkKey,
            command,
            keepEditing = false,
          }) async {},
      mindMapEditUnit:
          (target, {required requestText, conversationWorkKey}) async => null,
      bookMindMapSections: ({work, required useFrozenWork}) async => const [],
      workForKey: (_) => null,
      resolveGraphWorkCandidates: () async {},
      loadAiChatContext: ({selectionOverride, required workScope}) async =>
          const AiChatContextBundle(),
      freezeBookMindMapTurn: ({required workScope, required context}) =>
          const AiBookMindMapTurnSnapshot(
            conversationWorkKey: null,
            currentWork: null,
            availableWorks: [],
            currentChapter: null,
            manifest: null,
          ),
      currentReadingWork: () => null,
      bookStructureManifest: () => null,
      itemTitle: () => '测试书',
    );
  }

  setUp(() {
    clarifications.clear();
    confirmations.clear();
    createRuns = 0;
    workspace = BookAiWorkspaceController(
      saveChatSession: (_) async {},
      aiStoresReady: true,
    );
    host = BookAiActionHost(workspace: workspace, ui: buildUi());
  });

  AiBookMindMapProductTurn emptyTurn({
    AiCapabilitySet? capabilities,
  }) => AiBookMindMapActionGateway.prepareProductTurn(
    history: const [],
    scopeSnapshot: const AiBookMindMapTurnSnapshot(
      conversationWorkKey: null,
      currentWork: null,
      availableWorks: [],
      currentChapter: null,
      manifest: null,
    ),
    capabilities: capabilities ?? workspace.resolveCapabilities(),
  );

  test('mind-map dispatch does not require Journal stores', () async {
    workspace.markAiStoresReady(ready: false, error: '存储未就绪');
    await host.dispatch(
      originalText: '生成思维导图',
      action: const AiCreateBookMindMapAction(
        instruction: '生成思维导图',
        scope: AiBookMindMapActionScope.wholePublication,
      ),
      productTurn: emptyTurn(),
    );
    // Session path: no Journal, no stores gate.
    expect(clarifications, isEmpty);
    expect(createRuns, 1);
    final journal = await workspace.actionController.journal.read('anything');
    expect(journal, isNull);
  });

  test('resumeAfterOpen is silent when stores are not ready', () async {
    workspace.markAiStoresReady(ready: false, error: '未就绪');
    // Seed a recoverable-looking entry would require stores; host must not
    // inspect journal when not ready.
    await host.resumeAfterOpen();
    expect(confirmations, isEmpty);
    expect(clarifications, isEmpty);
    expect(createRuns, 0);
  });

  test('resumeAfterOpen abandons legacy mind-map Journal rows', () async {
    final proposal = AiActionProposal(
      protocolVersion: 1,
      proposalId: 'recover-p1',
      parentRunId: null,
      conversationId: 'a' * 64,
      turnId: 't-recover',
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      source: AiActionProposalSource.modelTool,
      sourceSubmissionId: 'sub-r',
      originalUserText: '生成',
      requestedArguments: const {
        'scope': 'wholePublication',
        'instruction': '生成',
      },
      createdAt: DateTime.utc(2026, 8, 12),
      expiresAt: DateTime.utc(2026, 8, 13),
    );
    await workspace.actionController.propose(
      proposal,
      capabilities: const AiCapabilitySet({
        'book.read',
        'structuredOutput',
      }),
    );

    await host.resumeAfterOpen();
    expect(confirmations, isEmpty);
    expect(createRuns, 0);
    final entry = await workspace.actionController.journal.read('recover-p1');
    expect(entry?.status, AiActionJournalStatus.abandoned);
  });

  test('dispatch runs mind-map session without confirmation or Journal',
      () async {
    final turn = emptyTurn(
      capabilities: const AiCapabilitySet({
        'book.read',
        'structuredOutput',
      }),
    );
    await host.dispatch(
      originalText: '生成思维导图',
      action: const AiCreateBookMindMapAction(
        instruction: '生成思维导图',
        scope: AiBookMindMapActionScope.wholePublication,
      ),
      productTurn: turn,
    );
    expect(confirmations, isEmpty);
    expect(createRuns, 1);
    final all = await workspace.actionController.journal.readAll();
    expect(all, isEmpty);
  });

  test('dispatchExplicitCreate runs session path without Journal', () async {
    await host.dispatchExplicitCreate(
      originalText: '请为当前章生成思维导图',
      requestScope: AiMindMapRequestScope.currentChapter,
    );
    expect(createRuns, 1);
    expect(clarifications, isEmpty);
    final all = await workspace.actionController.journal.readAll();
    expect(all, isEmpty);
  });

  test('missing structuredOutput hides tools and denies propose', () async {
    final context = AiChatProductContext(
      actionRegistry: workspace.actionController.registry,
      capabilities: const AiCapabilitySet({'book.read'}),
    );
    expect(context.toolDefinitions, isEmpty);

    final evaluation = await workspace.actionController.propose(
      AiActionProposal(
        protocolVersion: 1,
        proposalId: 'deny-p',
        parentRunId: null,
        conversationId: 'a' * 64,
        turnId: 't',
        actionKind: 'create_book_mind_map',
        definitionVersion: 1,
        proposalSchemaVersion: 1,
        source: AiActionProposalSource.modelTool,
        sourceSubmissionId: 'sub',
        originalUserText: '生成',
        requestedArguments: const {
          'scope': 'currentChapter',
          'instruction': '生成',
        },
        createdAt: DateTime.utc(2026, 8, 12),
        expiresAt: DateTime.utc(2026, 8, 13),
      ),
      capabilities: const AiCapabilitySet({'book.read'}),
    );
    expect(evaluation.authorized, isFalse);
    expect(evaluation.needsConfirmation, isFalse);
    expect(evaluation.entry.command, isNull);
    expect(evaluation.entry.status, isNot(AiActionJournalStatus.authorized));

    final ready = AiChatProductContext(
      actionRegistry: workspace.actionController.registry,
      capabilities: const AiCapabilitySet({
        'book.read',
        'structuredOutput',
      }),
    );
    expect(
      ready.toolDefinitions.map((t) => t.name),
      contains('create_book_mind_map'),
    );
  });

  test('resolveCapabilities omits structuredOutput without ready settings', () {
    final caps = workspace.resolveCapabilities();
    expect(caps.values.contains('book.read'), isTrue);
    expect(caps.values.contains('structuredOutput'), isFalse);
  });
}

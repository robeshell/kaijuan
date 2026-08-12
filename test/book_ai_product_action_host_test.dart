import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_action_gateway.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/presentation/controllers/book_ai_product_action_host.dart';
import 'package:kaijuan/presentation/controllers/book_ai_workspace_controller.dart';

void main() {
  late BookAiWorkspaceController workspace;
  late BookAiProductActionHost host;
  final clarifications = <String>[];
  final confirmations = <String>[];
  var createRuns = 0;

  BookAiProductActionUi buildUi({
    List<String>? clarificationSink,
    bool Function()? isMounted,
  }) {
    return BookAiProductActionUi(
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
            required actionProposalId,
            required authorizeAction,
          }) async {
            createRuns++;
            final unit = (
              work: null,
              label: '章',
              frozenSections: const [
                AiBookSectionSlice(
                  index: 1,
                  sourceSectionIndex: 1,
                  label: '章',
                  text: '正文',
                ),
              ],
              estimatedSections: 1,
            );
            final entry = await authorizeAction([unit]);
            return entry.command != null;
          },
      runReviseMindMap:
          ({
            required text,
            required target,
            conversationWorkKey,
            retryTurnId,
            required clearComposer,
            required actionProposalId,
            required authorizeAction,
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
            required actionProposalId,
            required actionCommand,
            attempt,
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
    host = BookAiProductActionHost(workspace: workspace, ui: buildUi());
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

  test('dispatch stores-not-ready is fail-closed and user-visible', () async {
    workspace.markAiStoresReady(ready: false, error: '存储未就绪');
    await host.dispatch(
      originalText: '生成思维导图',
      action: const AiCreateBookMindMapAction(
        instruction: '生成思维导图',
        scope: AiBookMindMapActionScope.currentChapter,
      ),
      productTurn: emptyTurn(),
    );
    expect(clarifications, isNotEmpty);
    expect(clarifications.single, contains('存储'));
    expect(createRuns, 0);
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

  test(
    'resumeAfterOpen recovers incomplete mind-map proposed work after reopen',
    () async {
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
      final evaluation = await workspace.actionController.propose(
        proposal,
        capabilities: const AiCapabilitySet({
          'book.read',
          'structuredOutput',
        }),
      );
      // Live light path: no chat confirmation card.
      expect(evaluation.needsConfirmation, isFalse);
      expect(evaluation.canProceedWithoutConfirmation, isTrue);
      expect(evaluation.entry.status, AiActionJournalStatus.proposed);

      await host.resumeAfterOpen();
      // Crash recovery still asks once before resuming incomplete work.
      expect(confirmations, ['recover-p1']);
      expect(createRuns, 1);
    },
  );

  test('dispatchProposed skips confirmation for mind-map light path', () async {
    final turn = emptyTurn(
      capabilities: const AiCapabilitySet({
        'book.read',
        'structuredOutput',
      }),
    );
    final proposal = AiActionProposal(
      protocolVersion: 1,
      proposalId: 'live-light-p1',
      parentRunId: null,
      conversationId: 'a' * 64,
      turnId: 't-live',
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      source: AiActionProposalSource.modelTool,
      sourceSubmissionId: 'sub-live',
      originalUserText: '生成思维导图',
      requestedArguments: const {
        'scope': 'wholePublication',
        'instruction': '生成思维导图',
      },
      createdAt: DateTime.utc(2026, 8, 12),
      expiresAt: DateTime.utc(2026, 8, 13),
    );
    // Seed journal with full caps (workspace resolveCapabilities is empty in
    // this harness without settings). dispatchProposed is idempotent on id.
    final seeded = await workspace.actionController.propose(
      proposal,
      capabilities: const AiCapabilitySet({
        'book.read',
        'structuredOutput',
      }),
    );
    expect(seeded.canProceedWithoutConfirmation, isTrue);
    expect(seeded.needsConfirmation, isFalse);

    await host.dispatchProposed(
      originalText: '生成思维导图',
      action: const AiCreateBookMindMapAction(
        instruction: '生成思维导图',
        scope: AiBookMindMapActionScope.wholePublication,
      ),
      productTurn: turn,
      proposal: proposal,
    );
    expect(confirmations, isEmpty);
    expect(createRuns, 1);
  });

  test('authorizeAfterFreeze issues one command with frozen scope', () async {
    final proposal = AiActionProposal(
      protocolVersion: 1,
      proposalId: 'p1',
      parentRunId: null,
      conversationId: 'a' * 64,
      turnId: 't1',
      actionKind: 'create_book_mind_map',
      definitionVersion: 1,
      proposalSchemaVersion: 1,
      source: AiActionProposalSource.explicitUi,
      sourceSubmissionId: 'sub',
      originalUserText: '生成',
      requestedArguments: const {
        'scope': 'currentChapter',
        'instruction': '生成',
      },
      createdAt: DateTime.utc(2026, 8, 12),
      expiresAt: DateTime.utc(2026, 8, 13),
    );
    await workspace.actionController.propose(
      proposal,
      deferExplicitAuthorization: true,
      capabilities: const AiCapabilitySet({
        'book.read',
        'structuredOutput',
      }),
    );
    final entry = await host.authorizeAfterFreeze(
      proposal,
      units: [
        (
          work: null,
          label: '当前章',
          frozenSections: const [
            AiBookSectionSlice(
              index: 3,
              sourceSectionIndex: 3,
              label: '当前章',
              text: '正文',
            ),
          ],
          estimatedSections: 1,
        ),
      ],
    );
    expect(entry.status, AiActionJournalStatus.queued);
    expect(entry.command, isNotNull);
    expect(entry.command!.scopeSectionIndices, [3]);
    expect(entry.command!.arguments['unitLabels'], ['当前章']);
  });

  test('dispatchExplicitCreate uses registry definition versions', () async {
    final def = workspace.actionController.registry.lookup(
      'create_book_mind_map',
    )!;
    // Without structuredOutput capability, Host fails closed with user message
    // (settings not bound). Registry versions still drive definition lookup.
    await host.dispatchExplicitCreate(
      originalText: '请为当前章生成思维导图',
      requestScope: AiMindMapRequestScope.currentChapter,
    );
    expect(createRuns, 0);
    expect(clarifications, isNotEmpty);
    expect(def.definitionVersion, greaterThanOrEqualTo(1));
    expect(def.proposalSchemaVersion, greaterThanOrEqualTo(1));
    expect(def.actionKind, 'create_book_mind_map');
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

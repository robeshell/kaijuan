import '../../ai/ai_book_mind_map_action_gateway.dart';
import '../../ai/ai_book_structure.dart';
import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_conversation_intent.dart';
import '../../ai/ai_mind_map.dart';
import '../../ai/ai_product_action.dart';
import '../../ai/ai_product_action_controller.dart';
import '../../ai/ai_product_action_domain.dart';
import '../../ai/ai_product_action_protocol.dart';
import '../../ai/ai_user_error.dart';
import 'book_ai_mind_map_controller.dart';
import 'book_ai_workspace_controller.dart';

/// UI bridge for mind-map session runs and (optional) heavy product actions.
class BookAiActionHostUi {
  const BookAiActionHostUi({
    required this.isMounted,
    required this.contentHash,
    required this.publicationTitle,
    required this.chatWorkKey,
    required this.sessionMessagesFor,
    required this.newTurnId,
    required this.requestConfirmation,
    required this.appendClarification,
    required this.onArtifactRevealed,
    required this.runCreateMindMap,
    required this.runReviseMindMap,
    required this.runGenerateUnits,
    required this.mindMapEditUnit,
    required this.bookMindMapSections,
    required this.workForKey,
    required this.resolveGraphWorkCandidates,
    required this.loadAiChatContext,
    required this.freezeBookMindMapTurn,
    required this.currentReadingWork,
    required this.bookStructureManifest,
    required this.itemTitle,
  });

  final bool Function() isMounted;
  final String Function() contentHash;
  final String Function() publicationTitle;
  final String? Function() chatWorkKey;
  final List<AiChatMessage> Function(String? workKey) sessionMessagesFor;
  final String Function() newTurnId;
  final Future<bool?> Function({
    required String proposalId,
    required String title,
    required String summary,
    String? scopeLabel,
    String? targetLabel,
    String? revisionLabel,
  })
  requestConfirmation;
  final void Function(
    String originalText,
    String body, {
    String? workKey,
  })
  appendClarification;
  final void Function(String artifactId) onArtifactRevealed;
  final Future<bool> Function({
    required String text,
    required AiMindMapRequestScope scope,
    AiBookMindMapTurnSnapshot? frozenTurn,
    AiBookWork? resolvedWork,
    AiBookSectionSlice? frozenCurrentChapter,
    String? retryTurnId,
    required bool clearComposer,
  })
  runCreateMindMap;
  final Future<bool> Function({
    required String text,
    required AiBookMindMap target,
    String? conversationWorkKey,
    String? retryTurnId,
    required bool clearComposer,
  })
  runReviseMindMap;
  final Future<void> Function({
    required String text,
    required List<BookAiMindMapGenerationUnit> units,
    AiBookMindMap? baseMap,
    String? retryTurnId,
    required String? conversationWorkKey,
    AiConversationCommand? command,
    bool keepEditing,
  })
  runGenerateUnits;
  final Future<BookAiMindMapGenerationUnit?> Function(
    AiBookMindMap target, {
    required String requestText,
    String? conversationWorkKey,
  })
  mindMapEditUnit;
  final Future<List<AiBookSectionSlice>> Function({
    AiBookWork? work,
    required bool useFrozenWork,
  })
  bookMindMapSections;
  final AiBookWork? Function(String workKey) workForKey;
  final Future<void> Function() resolveGraphWorkCandidates;
  final Future<AiChatContextBundle> Function({
    String? selectionOverride,
    required AiBookWork? workScope,
  })
  loadAiChatContext;
  final AiBookMindMapTurnSnapshot Function({
    required AiBookWork? workScope,
    required AiChatContextBundle context,
  })
  freezeBookMindMapTurn;
  final AiBookWork? Function() currentReadingWork;
  final AiBookStructureManifest? Function() bookStructureManifest;
  final String Function() itemTitle;
}

/// Dispatches mind-map **session** runs and heavy product actions.
///
/// Mind maps never enter Product Action Journal. Heavy domains (export, etc.)
/// still use propose → authorize → Workflow when present.
class BookAiActionHost {
  BookAiActionHost({
    required this.workspace,
    required this.ui,
  });

  final BookAiWorkspaceController workspace;
  final BookAiActionHostUi ui;

  AiProductActionDomainRegistry get domains => workspace.actionDomains;

  bool get storesReady => workspace.aiStoresReady;

  String? get storesBlocker => workspace.aiStoresError;

  Future<void> completeFailure(String proposalId) async {
    try {
      final entry = await workspace.actionController.journal.read(proposalId);
      if (entry == null) return;
      if (entry.status == AiActionJournalStatus.proposed ||
          entry.status == AiActionJournalStatus.awaitingConfirmation ||
          entry.status == AiActionJournalStatus.awaitingClarification) {
        await workspace.actionController.reject(proposalId);
        return;
      }
      if (entry.status == AiActionJournalStatus.authorized) {
        await workspace.actionController.abandon(
          proposalId,
          reasonCode: 'mind_map_action_failed_before_execution',
        );
        return;
      }
      if (entry.status == AiActionJournalStatus.cancelRequested) {
        await workspace.actionController.completeForProposal(
          proposalId: proposalId,
          status: AiActionJournalStatus.cancelled,
          artifactRefs: const [],
        );
        return;
      }
      await workspace.actionController.completeForProposal(
        proposalId: proposalId,
        status: AiActionJournalStatus.failed,
        artifactRefs: const [],
        publicErrorCode: 'mind_map_action_failed',
      );
    } catch (_) {}
  }

  Future<void> completeCancelled(String proposalId) async {
    try {
      final entry = await workspace.actionController.journal.read(proposalId);
      if (entry == null) return;
      if (entry.status == AiActionJournalStatus.proposed ||
          entry.status == AiActionJournalStatus.awaitingConfirmation ||
          entry.status == AiActionJournalStatus.awaitingClarification) {
        await workspace.actionController.reject(proposalId);
        return;
      }
      if (entry.status == AiActionJournalStatus.authorized) {
        await workspace.actionController.requestCancel(proposalId);
        await workspace.actionController.completeForProposal(
          proposalId: proposalId,
          status: AiActionJournalStatus.cancelled,
          artifactRefs: const [],
        );
        return;
      }
      await workspace.actionController.completeForProposal(
        proposalId: proposalId,
        status: AiActionJournalStatus.cancelled,
        artifactRefs: const [],
      );
    } catch (_) {
      await completeFailure(proposalId);
    }
  }

  bool _isMindMapAction(AiProductActionRequest action) =>
      action is AiCreateBookMindMapAction || action is AiReviseBookMindMapAction;

  bool _isMindMapKind(String actionKind) =>
      actionKind == 'create_book_mind_map' ||
      actionKind == 'revise_book_mind_map';

  AiActionProposal proposalForHeavy({
    required String originalText,
    required AiRegisteredProductAction action,
    required AiBookMindMapProductTurn productTurn,
    String? parentTurnId,
    AiActionProposalSource source = AiActionProposalSource.modelTool,
  }) {
    final definition = workspace.actionController.registry.lookup(
      action.actionKind,
    );
    final turnId = parentTurnId ?? ui.newTurnId();
    final workKey = productTurn.scopeSnapshot.conversationWorkKey;
    return AiActionProposal(
      protocolVersion: AiActionProposal.currentProtocolVersion,
      proposalId: 'proposal-${ui.newTurnId()}',
      parentRunId: parentTurnId,
      conversationId: ui.contentHash(),
      turnId: turnId,
      actionKind: action.actionKind,
      definitionVersion: definition?.definitionVersion ?? 1,
      proposalSchemaVersion: definition?.proposalSchemaVersion ?? 1,
      source: source,
      sourceSubmissionId: turnId,
      originalUserText: originalText,
      requestedArguments: {
        'instruction': action.instruction,
        'contentHash': ui.contentHash(),
        ...action.arguments,
        if (workKey != null && workKey.isNotEmpty) 'workKey': workKey,
      },
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  /// Cold-start: abandon legacy mind-map Journal rows; recover heavy jobs only.
  Future<void> resumeAfterOpen() async {
    if (!storesReady) return;
    final candidates = await workspace.actionController.inspectRecovery();
    final scoped = candidates.where(
      (c) => c.entry.proposal.conversationId == ui.contentHash(),
    );
    // Legacy mind-map Journal entries are no longer a product path.
    for (final candidate in scoped) {
      if (!_isMindMapKind(candidate.entry.proposal.actionKind)) continue;
      if (candidate.entry.status.isTerminal) continue;
      await workspace.actionController.abandon(
        candidate.entry.proposal.proposalId,
        reasonCode: 'mind_map_session_path',
      );
    }
    final remaining = (await workspace.actionController.inspectRecovery()).where(
      (c) =>
          c.entry.proposal.conversationId == ui.contentHash() &&
          !_isMindMapKind(c.entry.proposal.actionKind),
    );
    for (final candidate in remaining.where(
      (c) => c.disposition == AiActionRecoveryDisposition.needsProjection,
    )) {
      await reconcileProjection(candidate.entry);
    }
    final pending = remaining
        .where(
          (c) =>
              c.entry.status == AiActionJournalStatus.awaitingConfirmation ||
              c.entry.status == AiActionJournalStatus.proposed,
        )
        .lastOrNull;
    if (pending == null) {
      final recoverable = remaining
          .where(
            (c) => c.disposition == AiActionRecoveryDisposition.recoverable,
          )
          .lastOrNull;
      if (recoverable != null) {
        await resumeRecoverable(recoverable);
      }
      return;
    }
    if (!ui.isMounted()) return;
    try {
      await resumePendingProposal(pending.entry.proposal);
    } catch (error) {
      await completeFailure(pending.entry.proposal.proposalId);
      if (ui.isMounted()) {
        ui.appendClarification(
          pending.entry.proposal.originalUserText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
        );
      }
    }
  }

  Future<void> reconcileProjection(AiActionJournalEntry entry) async {
    if (!entry.needsProjection) return;
    final workKey = entry.command?.workKey;
    final turnId =
        entry.proposal.turnId ?? 'projection-${entry.proposal.proposalId}';
    try {
      final outcome = await workspace.reconcilePendingProjection(
        entry,
        turnId: turnId,
        workKey: workKey,
        publicationTitle: ui.publicationTitle(),
        onArtifact: (artifact) {
          final id = artifact.artifactId;
          if (!ui.isMounted() || id == null) return;
          ui.onArtifactRevealed(id);
        },
      );
      // outcome used only for side effects via onArtifact
      // ignore: unused_local_variable
      final _ = outcome;
    } catch (error) {
      if (ui.isMounted()) {
        ui.appendClarification(
          entry.proposal.originalUserText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
          workKey: workKey,
        );
      }
    }
  }

  Future<void> resumeRecoverable(AiActionRecoveryCandidate candidate) async {
    final proposal = candidate.entry.proposal;
    if (_isMindMapKind(proposal.actionKind)) {
      await workspace.actionController.abandon(
        proposal.proposalId,
        reasonCode: 'mind_map_session_path',
      );
      return;
    }
    if (candidate.entry.status == AiActionJournalStatus.cancelRequested) {
      await completeCancelled(proposal.proposalId);
      return;
    }
    // Heavy product recovery only; mind maps do not use Journal.
    try {
      if (candidate.entry.command == null) {
        await workspace.actionController.abandon(
          proposal.proposalId,
          reasonCode: 'authorized_command_missing',
        );
        return;
      }
      if (candidate.entry.status == AiActionJournalStatus.authorized) {
        await workspace.actionController.queue(proposal.proposalId);
      }
      final domain = domains.byActionKind(proposal.actionKind);
      if (domain == null) {
        await workspace.actionController.abandon(
          proposal.proposalId,
          reasonCode: 'unknown_action_kind',
        );
        return;
      }
      final completed = await workspace.workflowExecutor.execute(
        proposal.proposalId,
      );
      if (!ui.isMounted()) return;
      if (completed.status == AiActionJournalStatus.succeeded) {
        final message = domain.projectionMessage(
          request: null,
          artifactRefs: completed.receipt?.artifactRefs ?? const [],
        );
        ui.appendClarification(proposal.originalUserText, message);
        if (completed.receipt != null) {
          await workspace.actionController.markProjected(
            proposalId: proposal.proposalId,
            refs: completed.receipt!.artifactRefs,
          );
        }
      }
    } catch (error) {
      await completeFailure(proposal.proposalId);
      if (ui.isMounted()) {
        ui.appendClarification(
          proposal.originalUserText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
        );
      }
    }
  }

  Future<void> resumePendingProposal(AiActionProposal proposal) async {
    if (_isMindMapKind(proposal.actionKind)) {
      await workspace.actionController.abandon(
        proposal.proposalId,
        reasonCode: 'mind_map_session_path',
      );
      return;
    }
    // Heavy domains only.
    final domain = domains.byActionKind(proposal.actionKind);
    if (domain == null) {
      await workspace.actionController.abandon(
        proposal.proposalId,
        reasonCode: 'unknown_action_kind',
      );
      return;
    }
    final entry = await workspace.actionController.journal.read(
      proposal.proposalId,
    );
    if (entry == null) return;
    if (entry.status == AiActionJournalStatus.awaitingConfirmation ||
        entry.status == AiActionJournalStatus.proposed) {
      final approved = await ui.requestConfirmation(
        proposalId: proposal.proposalId,
        title: '恢复未完成的操作',
        summary: '上次的操作尚未执行完成。确认后会继续。',
      );
      if (approved != true) {
        await workspace.actionController.reject(proposal.proposalId);
        return;
      }
      await workspace.actionController.authorize(
        proposalId: proposal.proposalId,
        authorizationSubmissionId: '${proposal.proposalId}:recover',
        authorizationEvidence: 'recovery:confirm',
        normalizedArguments: {
          ...proposal.requestedArguments,
          'contentHash': ui.contentHash(),
        },
      );
    }
    await workspace.actionController.queue(proposal.proposalId);
    final completed = await workspace.workflowExecutor.execute(
      proposal.proposalId,
    );
    if (!ui.isMounted()) return;
    if (completed.status == AiActionJournalStatus.succeeded) {
      ui.appendClarification(
        proposal.originalUserText,
        domain.projectionMessage(
          request: null,
          artifactRefs: completed.receipt?.artifactRefs ?? const [],
        ),
      );
    }
  }

  void _notifyStoresBlocked(String originalText, {String? workKey}) {
    if (!ui.isMounted()) return;
    ui.appendClarification(
      originalText,
      storesBlocker ?? 'AI 本地存储未就绪，无法执行产品动作',
      workKey: workKey,
    );
  }

  /// Free-input / model tool: mind maps run as session; others may use Journal.
  Future<void> dispatch({
    required String originalText,
    required AiProductActionRequest action,
    required AiBookMindMapProductTurn productTurn,
    String? retryTurnId,
    String? parentTurnId,
  }) async {
    try {
      if (_isMindMapAction(action)) {
        await executeMindMapSession(
          originalText: originalText,
          action: action,
          productTurn: productTurn,
          retryTurnId: retryTurnId,
        );
        return;
      }
      if (!storesReady) {
        _notifyStoresBlocked(
          originalText,
          workKey: productTurn.scopeSnapshot.conversationWorkKey,
        );
        return;
      }
      if (action is! AiRegisteredProductAction) {
        ui.appendClarification(originalText, '未知的产品操作');
        return;
      }
      final proposal = proposalForHeavy(
        originalText: originalText,
        action: action,
        productTurn: productTurn,
        parentTurnId: parentTurnId,
      );
      final evaluation = await workspace.actionController.propose(
        proposal,
        capabilities: workspace.resolveCapabilities(),
      );
      if (evaluation.needsConfirmation) {
        final domain = domains.byActionKind(proposal.actionKind);
        final view =
            domain?.confirmationView(action, contextHints: const {}) ??
            const AiProductActionConfirmationView(
              title: '确认执行',
              summary: '请确认执行此产品操作。',
            );
        final approved = await ui.requestConfirmation(
          proposalId: proposal.proposalId,
          title: view.title,
          summary: view.summary,
          scopeLabel: view.scopeLabel,
          targetLabel: view.targetLabel,
          revisionLabel: view.revisionLabel,
        );
        if (approved != true) {
          await workspace.actionController.reject(proposal.proposalId);
          return;
        }
      } else if (!evaluation.canProceedWithoutConfirmation &&
          !evaluation.authorized) {
        ui.appendClarification(originalText, '这项操作目前未获授权，请重新发起。');
        return;
      }
      await _runRegistered(
        originalText,
        action,
        proposal: proposal,
        productTurn: productTurn,
        domain: domains.byActionKind(proposal.actionKind)!,
      );
    } catch (error) {
      if (ui.isMounted()) {
        ui.appendClarification(
          originalText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
          workKey: productTurn.scopeSnapshot.conversationWorkKey,
        );
      }
    }
  }

  /// Shortcut create: session path, no Journal.
  Future<void> dispatchExplicitCreate({
    required String originalText,
    required AiMindMapRequestScope requestScope,
    String? parentTurnId,
    String? conversationWorkKey,
  }) async {
    try {
      final started = await ui.runCreateMindMap(
        text: originalText,
        scope: requestScope,
        clearComposer: true,
      );
      if (!started && ui.isMounted()) {
        // Scope cancelled or empty — no error noise.
      }
    } catch (error) {
      if (ui.isMounted()) {
        ui.appendClarification(
          originalText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
          workKey: conversationWorkKey,
        );
      }
    }
  }

  Future<void> executeMindMapSession({
    required String originalText,
    required AiProductActionRequest action,
    required AiBookMindMapProductTurn productTurn,
    String? retryTurnId,
  }) async {
    switch (action) {
      case final AiCreateBookMindMapAction create:
        AiBookMindMapCreateInput input;
        try {
          input = AiBookMindMapActionGateway.resolveCreate(
            create,
            productTurn.scopeSnapshot,
          );
        } catch (error) {
          ui.appendClarification(
            originalText,
            aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
            workKey: productTurn.scopeSnapshot.conversationWorkKey,
          );
          return;
        }
        await ui.runCreateMindMap(
          text: originalText,
          scope: input.scope,
          frozenTurn: productTurn.scopeSnapshot,
          resolvedWork: input.work,
          frozenCurrentChapter: input.frozenCurrentChapter,
          retryTurnId: retryTurnId,
          clearComposer: true,
        );
      case final AiReviseBookMindMapAction revise:
        AiBookMindMap target;
        try {
          target = AiBookMindMapActionGateway.resolveRevision(
            revise,
            productTurn.artifactsById,
            preferredArtifactId: productTurn.modelContext.artifacts
                .where((a) => a.isPreferred)
                .map((a) => a.artifactId)
                .firstOrNull,
          );
        } catch (error) {
          ui.appendClarification(
            originalText,
            aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
            workKey: productTurn.scopeSnapshot.conversationWorkKey,
          );
          return;
        }
        await ui.runReviseMindMap(
          text: originalText,
          target: target,
          conversationWorkKey: productTurn.scopeSnapshot.conversationWorkKey,
          retryTurnId: retryTurnId,
          clearComposer: false,
        );
      case AiRegisteredProductAction():
        throw StateError('executeMindMapSession only accepts mind-map actions');
    }
  }

  Future<void> _runRegistered(
    String originalText,
    AiRegisteredProductAction action, {
    required AiActionProposal proposal,
    required AiBookMindMapProductTurn productTurn,
    required AiProductActionDomain domain,
  }) async {
    final adapter = domain.createAdapter(workspace.artifactRepository);
    if (adapter != null &&
        workspace.workflowAdapters.lookup(action.actionKind) == null) {
      workspace.registerExtraAdapters([adapter]);
    }
    final entry = await workspace.actionController.journal.read(
      proposal.proposalId,
    );
    if (entry == null) throw StateError('产品操作日志不存在');
    if (entry.status == AiActionJournalStatus.awaitingConfirmation ||
        entry.status == AiActionJournalStatus.proposed) {
      await workspace.actionController.authorize(
        proposalId: proposal.proposalId,
        authorizationSubmissionId: '${proposal.proposalId}:approve',
        authorizationEvidence: 'conversation:confirm',
        normalizedArguments: {
          ...action.arguments,
          'contentHash': ui.contentHash(),
        },
      );
    }
    await workspace.actionController.queue(proposal.proposalId);
    final completed = await workspace.workflowExecutor.execute(
      proposal.proposalId,
    );
    if (!ui.isMounted()) return;
    if (completed.status == AiActionJournalStatus.succeeded) {
      final message = domain.projectionMessage(
        request: action,
        artifactRefs: completed.receipt?.artifactRefs ?? const [],
      );
      ui.appendClarification(
        originalText,
        message,
        workKey: productTurn.scopeSnapshot.conversationWorkKey,
      );
      if (completed.receipt != null) {
        await workspace.actionController.markProjected(
          proposalId: proposal.proposalId,
          refs: completed.receipt!.artifactRefs,
        );
      }
    } else if (completed.status == AiActionJournalStatus.failed ||
        completed.status == AiActionJournalStatus.abandoned) {
      ui.appendClarification(
        originalText,
        '操作失败：${completed.receipt?.publicErrorCode ?? completed.terminalReasonCode ?? 'unknown'}',
        workKey: productTurn.scopeSnapshot.conversationWorkKey,
      );
    }
  }

  /// Session retry: re-run units without Journal.
  Future<void> retrySession({
    required String text,
    required List<BookAiMindMapGenerationUnit> units,
    required String? conversationWorkKey,
    String? retryTurnId,
    AiBookMindMap? baseMap,
    AiConversationCommand? command,
  }) async {
    try {
      await ui.runGenerateUnits(
        text: text,
        units: units,
        baseMap: baseMap,
        retryTurnId: retryTurnId,
        conversationWorkKey: conversationWorkKey,
        command: command,
      );
    } catch (error) {
      if (ui.isMounted()) {
        ui.appendClarification(
          text,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
        );
      }
    }
  }

  static String scopeNameFromProposal(AiActionProposal proposal) =>
      '${proposal.requestedArguments['scope'] ?? 'wholePublication'}';
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

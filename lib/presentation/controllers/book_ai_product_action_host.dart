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
import 'book_reader_controller.dart';

/// UI bridge for product-action orchestration. Confirmation / scope cards stay
/// in the sheet; Journal, authorize, recover, and dispatch live on the host.
class BookAiProductActionUi {
  const BookAiProductActionUi({
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
    required String actionProposalId,
    required Future<AiActionJournalEntry> Function(
      List<BookAiMindMapGenerationUnit> units,
    )
    authorizeAction,
  })
  runCreateMindMap;
  final Future<bool> Function({
    required String text,
    required AiBookMindMap target,
    String? conversationWorkKey,
    String? retryTurnId,
    required bool clearComposer,
    required String actionProposalId,
    required Future<AiActionJournalEntry> Function(
      List<BookAiMindMapGenerationUnit> units,
    )
    authorizeAction,
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
    required String actionProposalId,
    required AiAuthorizedCommand actionCommand,
    int? attempt,
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

/// Non-Widget owner of product-action Journal / authorize / recover / dispatch.
///
/// Free-input confirmation is UI-only until scope freeze; a single
/// [authorizeAfterFreeze] call then creates the immutable Command.
class BookAiProductActionHost {
  BookAiProductActionHost({
    required this.workspace,
    required this.ui,
  });

  final BookAiWorkspaceController workspace;
  final BookAiProductActionUi ui;

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

  /// Strategy A: only after units are frozen; one approve/authorize with full args.
  Future<AiActionJournalEntry> authorizeAfterFreeze(
    AiActionProposal proposal, {
    required List<BookAiMindMapGenerationUnit> units,
  }) async {
    final entry = await workspace.actionController.journal.read(
      proposal.proposalId,
    );
    if (entry == null) throw StateError('产品操作日志不存在');
    final sectionIndices = [
      for (final unit in units)
        for (final section in (unit.frozenSections ?? const [])) section.index,
    ];
    final unitLabels = [for (final unit in units) unit.label];
    final unitSectionCounts = [
      for (final unit in units) (unit.frozenSections ?? const []).length,
    ];
    final workKey = ui.chatWorkKey();
    final frozenArgs = <String, Object?>{
      'scopeFingerprint': 'sections:${sectionIndices.join(',')}',
      'scopeSectionIndices': sectionIndices,
      'unitLabels': unitLabels,
      'unitSectionCounts': unitSectionCounts,
      'contentHash': ui.contentHash(),
      if (workKey != null && workKey.isNotEmpty) 'workKey': workKey,
    };
    if (entry.status == AiActionJournalStatus.awaitingConfirmation) {
      await workspace.actionController.approve(
        proposalId: proposal.proposalId,
        authorizationSubmissionId: '${proposal.proposalId}:approve',
        authorizationEvidence: 'conversation:confirm',
        normalizedArguments: frozenArgs,
      );
    } else if (entry.status == AiActionJournalStatus.proposed) {
      await workspace.actionController.authorize(
        proposalId: proposal.proposalId,
        authorizationSubmissionId: proposal.sourceSubmissionId,
        authorizationEvidence: 'ui:mind-map-scope-confirmed',
        normalizedArguments: frozenArgs,
      );
    }
    final latest = await workspace.actionController.journal.read(
      proposal.proposalId,
    );
    if (latest == null) throw StateError('产品操作日志不存在');
    if (latest.status == AiActionJournalStatus.cancelRequested ||
        latest.status.isTerminal) {
      return latest;
    }
    if (latest.status == AiActionJournalStatus.authorized) {
      return workspace.actionController.queue(proposal.proposalId);
    }
    if (latest.status == AiActionJournalStatus.queued ||
        latest.status == AiActionJournalStatus.executing) {
      return latest;
    }
    throw StateError('产品操作尚未授权，不能执行');
  }

  AiActionProposal proposalFor({
    required String originalText,
    required AiProductActionRequest action,
    required AiBookMindMapProductTurn productTurn,
    String? parentTurnId,
    AiActionProposalSource source = AiActionProposalSource.modelTool,
  }) {
    final actionKind = switch (action) {
      AiCreateBookMindMapAction() => 'create_book_mind_map',
      AiReviseBookMindMapAction() => 'revise_book_mind_map',
      AiRegisteredProductAction(:final actionKind) => actionKind,
    };
    final scope = switch (action) {
      AiCreateBookMindMapAction() => action.scope.name,
      AiReviseBookMindMapAction() => null,
      AiRegisteredProductAction() => null,
    };
    final target = switch (action) {
      AiCreateBookMindMapAction() => null,
      AiReviseBookMindMapAction() => action.artifactId,
      AiRegisteredProductAction() => null,
    };
    final args = <String, Object?>{
      'instruction': action.instruction,
      'contentHash': ui.contentHash(),
      if (action is AiRegisteredProductAction) ...action.arguments,
    };
    if (scope != null) args['scope'] = scope;
    if (action case AiCreateBookMindMapAction(:final workId)) {
      if (workId != null) args['workId'] = workId;
      final selected = productTurn.scopeSnapshot.availableWorks.where(
        (work) => work.id == workId,
      );
      if (selected.length == 1) {
        args['workKey'] = BookReaderController.workKeyFor(selected.single);
      }
    }
    if (target != null) args['targetArtifactId'] = target;
    final workKey = productTurn.scopeSnapshot.conversationWorkKey;
    final shouldFreezeConversationWork = switch (action) {
      AiCreateBookMindMapAction(:final scope) =>
        scope != AiBookMindMapActionScope.wholePublication,
      AiReviseBookMindMapAction() => true,
      AiRegisteredProductAction() => workKey != null,
    };
    if (workKey != null && shouldFreezeConversationWork) {
      args['workKey'] = workKey;
    }
    final definition = workspace.actionController.registry.lookup(actionKind);
    final turnId = parentTurnId ?? ui.newTurnId();
    return AiActionProposal(
      protocolVersion: AiActionProposal.currentProtocolVersion,
      proposalId: 'proposal-${ui.newTurnId()}',
      parentRunId: parentTurnId,
      conversationId: ui.contentHash(),
      turnId: turnId,
      actionKind: actionKind,
      definitionVersion: definition?.definitionVersion ?? 1,
      proposalSchemaVersion: definition?.proposalSchemaVersion ?? 1,
      source: source,
      sourceSubmissionId: turnId,
      originalUserText: originalText,
      requestedArguments: args,
      scopeRef: scope,
      targetRef: target,
      expectedRevision: target == null
          ? null
          : productTurn.artifactsById[target]?.revision,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  /// Single cold-start entry for product recover / pending confirmation.
  Future<void> resumeAfterOpen() async {
    if (!storesReady) return;
    final candidates = await workspace.actionController.inspectRecovery();
    final scoped = candidates.where(
      (c) => c.entry.proposal.conversationId == ui.contentHash(),
    );
    for (final candidate in scoped.where(
      (c) => c.disposition == AiActionRecoveryDisposition.needsProjection,
    )) {
      await reconcileProjection(candidate.entry);
    }
    final pending = scoped
        .where(
          (c) =>
              c.entry.status == AiActionJournalStatus.awaitingConfirmation ||
              c.entry.status == AiActionJournalStatus.proposed,
        )
        .lastOrNull;
    if (pending == null) {
      final recoverable = scoped
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
    final proposal = pending.entry.proposal;
    final requestedWorkKey = '${proposal.requestedArguments['workKey'] ?? ''}'
        .trim();
    if (requestedWorkKey.isNotEmpty &&
        requestedWorkKey != ui.chatWorkKey() &&
        ui.workForKey(requestedWorkKey) == null) {
      await workspace.actionController.abandon(
        proposal.proposalId,
        reasonCode: 'frozen_work_context_missing',
      );
      return;
    }
    final scopeName = '${proposal.requestedArguments['scope'] ?? ''}';
    if (scopeName == 'currentChapter') {
      await workspace.actionController.abandon(
        proposal.proposalId,
        reasonCode: 'frozen_chapter_context_missing',
      );
      return;
    }
    final approved = await ui.requestConfirmation(
      proposalId: proposal.proposalId,
      title: '恢复未完成的思维导图操作',
      summary: '上次的操作尚未执行完成。确认后会继续使用原书籍和范围，不会重新解释你的要求。',
      scopeLabel: '已冻结阅读范围',
      targetLabel: proposal.targetRef,
      revisionLabel: proposal.expectedRevision == null
          ? null
          : '基于第 ${proposal.expectedRevision} 版',
    );
    if (!ui.isMounted()) return;
    if (approved != true) {
      await workspace.actionController.reject(proposal.proposalId);
      return;
    }
    try {
      await resumePendingProposal(proposal);
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
    if (candidate.entry.status == AiActionJournalStatus.cancelRequested) {
      await completeCancelled(proposal.proposalId);
      return;
    }
    try {
      await ui.resolveGraphWorkCandidates();
      final requestedWorkKey = '${proposal.requestedArguments['workKey'] ?? ''}'
          .trim();
      final context = await ui.loadAiChatContext(
        selectionOverride: null,
        workScope: requestedWorkKey.isEmpty
            ? ui.currentReadingWork()
            : ui.workForKey(requestedWorkKey),
      );
      final snapshot = ui.freezeBookMindMapTurn(
        workScope: requestedWorkKey.isEmpty
            ? ui.currentReadingWork()
            : ui.workForKey(requestedWorkKey),
        context: context,
      );
      final scopeName = scopeNameFromProposal(proposal);
      if (scopeName == 'currentChapter') {
        await workspace.actionController.abandon(
          proposal.proposalId,
          reasonCode: 'frozen_chapter_context_missing',
        );
        return;
      }
      if (proposal.actionKind == 'revise_book_mind_map') {
        final turn = AiBookMindMapActionGateway.prepareProductTurn(
          history: ui.sessionMessagesFor(
            requestedWorkKey.isEmpty ? null : requestedWorkKey,
          ),
          scopeSnapshot: snapshot,
          preferredArtifactId: proposal.targetRef,
          capabilities: workspace.resolveCapabilities(),
        );
        final targetId = proposal.targetRef;
        final target = targetId == null ? null : turn.artifactsById[targetId];
        if (target == null ||
            (proposal.expectedRevision != null &&
                target.revision != proposal.expectedRevision)) {
          await workspace.actionController.abandon(
            proposal.proposalId,
            reasonCode: 'target_revision_changed',
          );
          return;
        }
        await ui.runReviseMindMap(
          text: proposal.originalUserText,
          target: target,
          conversationWorkKey: requestedWorkKey.isEmpty
              ? null
              : requestedWorkKey,
          clearComposer: false,
          actionProposalId: proposal.proposalId,
          authorizeAction: (units) =>
              authorizeAfterFreeze(proposal, units: units),
        );
        return;
      }

      final requestedIndices = candidate.entry.command == null
          ? const <int>{}
          : candidate.entry.command!.scopeSectionIndices.toSet();
      final units = <BookAiMindMapGenerationUnit>[];
      final works = scopeName == 'wholePublication'
          ? (snapshot.manifest?.works ?? const <AiBookWork>[])
          : [
              if (requestedWorkKey.isNotEmpty)
                ui.workForKey(requestedWorkKey),
              if (requestedWorkKey.isEmpty) snapshot.currentWork,
            ].whereType<AiBookWork>().toList(growable: false);
      if (scopeName == 'wholePublication' && works.isEmpty) {
        final sections = await ui.bookMindMapSections(
          work: null,
          useFrozenWork: true,
        );
        final frozen = requestedIndices.isEmpty
            ? sections
            : sections
                  .where((s) => requestedIndices.contains(s.index))
                  .toList(growable: false);
        if (frozen.isNotEmpty) {
          units.add((
            work: null,
            label: ui.itemTitle(),
            frozenSections: List.unmodifiable(frozen),
            estimatedSections: frozen.length,
          ));
        }
      } else {
        for (final work in works) {
          final sections = await ui.bookMindMapSections(
            work: work,
            useFrozenWork: true,
          );
          final frozen = requestedIndices.isEmpty
              ? sections
              : sections
                    .where((s) => requestedIndices.contains(s.index))
                    .toList(growable: false);
          if (frozen.isEmpty) continue;
          units.add((
            work: work,
            label: work.title,
            frozenSections: List.unmodifiable(frozen),
            estimatedSections: frozen.length,
          ));
        }
      }
      if (units.isEmpty) {
        await workspace.actionController.abandon(
          proposal.proposalId,
          reasonCode: 'frozen_scope_content_missing',
        );
        return;
      }
      final command = candidate.entry.command;
      if (command == null) {
        await workspace.actionController.abandon(
          proposal.proposalId,
          reasonCode: 'authorized_command_missing',
        );
        return;
      }
      if (candidate.entry.status == AiActionJournalStatus.authorized) {
        await workspace.actionController.queue(proposal.proposalId);
      }
      final latest = await workspace.actionController.journal.read(
        proposal.proposalId,
      );
      final executable = latest?.command ?? command;
      await ui.runGenerateUnits(
        text: proposal.originalUserText,
        units: units,
        conversationWorkKey: requestedWorkKey.isEmpty
            ? null
            : requestedWorkKey,
        actionProposalId: proposal.proposalId,
        actionCommand: executable,
      );
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
    await ui.resolveGraphWorkCandidates();
    final requestedWorkKey = '${proposal.requestedArguments['workKey'] ?? ''}'
        .trim();
    final turnWork = requestedWorkKey.isEmpty
        ? ui.currentReadingWork()
        : ui.workForKey(requestedWorkKey);
    if (requestedWorkKey.isNotEmpty && turnWork == null) {
      throw StateError('原操作所属作品已经无法恢复');
    }
    final context = await ui.loadAiChatContext(
      selectionOverride: null,
      workScope: turnWork,
    );
    final snapshot = ui.freezeBookMindMapTurn(
      workScope: turnWork,
      context: context,
    );
    final productTurn = AiBookMindMapActionGateway.prepareProductTurn(
      history: ui.sessionMessagesFor(
        requestedWorkKey.isEmpty ? null : requestedWorkKey,
      ),
      scopeSnapshot: snapshot,
      preferredArtifactId: null,
      capabilities: workspace.resolveCapabilities(),
    );
    final actionKind = proposal.actionKind;
    if (actionKind == 'create_book_mind_map') {
      final scope = AiBookMindMapActionScope.values.where(
        (value) => value.name == scopeNameFromProposal(proposal),
      );
      final action = AiCreateBookMindMapAction(
        instruction:
            '${proposal.requestedArguments['instruction'] ?? proposal.originalUserText}',
        scope: scope.singleOrNull ?? AiBookMindMapActionScope.wholePublication,
      );
      final input = AiBookMindMapActionGateway.resolveCreate(
        action,
        productTurn.scopeSnapshot,
      );
      final started = await ui.runCreateMindMap(
        text: proposal.originalUserText,
        scope: input.scope,
        frozenTurn: productTurn.scopeSnapshot,
        resolvedWork: input.work,
        frozenCurrentChapter: input.frozenCurrentChapter,
        clearComposer: false,
        actionProposalId: proposal.proposalId,
        authorizeAction: (units) =>
            authorizeAfterFreeze(proposal, units: units),
      );
      if (!started) await completeCancelled(proposal.proposalId);
      return;
    }
    final targetId = proposal.targetRef;
    final target = targetId == null
        ? null
        : productTurn.artifactsById[targetId];
    if (target == null) throw StateError('待恢复的导图目标已经不在当前对话中');
    final started = await ui.runReviseMindMap(
      text: proposal.originalUserText,
      target: target,
      clearComposer: false,
      actionProposalId: proposal.proposalId,
      authorizeAction: (units) => authorizeAfterFreeze(proposal, units: units),
    );
    if (!started) await completeCancelled(proposal.proposalId);
  }

  void _notifyStoresBlocked(String originalText, {String? workKey}) {
    if (!ui.isMounted()) return;
    ui.appendClarification(
      originalText,
      storesBlocker ?? 'AI 本地存储未就绪，无法执行产品动作',
      workKey: workKey,
    );
  }

  Future<void> dispatch({
    required String originalText,
    required AiProductActionRequest action,
    required AiBookMindMapProductTurn productTurn,
    String? retryTurnId,
    String? parentTurnId,
  }) async {
    if (!storesReady) {
      // Fail-closed and user-visible: never throw past unawaited sheet calls.
      _notifyStoresBlocked(
        originalText,
        workKey: productTurn.scopeSnapshot.conversationWorkKey,
      );
      return;
    }
    final proposal = proposalFor(
      originalText: originalText,
      action: action,
      productTurn: productTurn,
      parentTurnId: parentTurnId,
    );
    try {
      await dispatchProposed(
        originalText: originalText,
        action: action,
        productTurn: productTurn,
        retryTurnId: retryTurnId,
        proposal: proposal,
      );
    } catch (error) {
      await completeFailure(proposal.proposalId);
      if (ui.isMounted()) {
        ui.appendClarification(
          originalText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
          workKey: productTurn.scopeSnapshot.conversationWorkKey,
        );
      }
    }
  }

  /// Explicit UI create (shortcut). Uses registry definition versions and
  /// deferExplicitAuthorization until units are frozen.
  Future<void> dispatchExplicitCreate({
    required String originalText,
    required AiMindMapRequestScope requestScope,
    String? parentTurnId,
    String? conversationWorkKey,
  }) async {
    if (!storesReady) {
      _notifyStoresBlocked(originalText, workKey: conversationWorkKey);
      return;
    }
    final definition = workspace.actionController.registry.lookup(
      'create_book_mind_map',
    );
    if (definition == null) {
      if (ui.isMounted()) {
        ui.appendClarification(originalText, '思维导图产品动作未注册');
      }
      return;
    }
    // Proposal schema uses product action scope names (wholePublication).
    final actionScopeName = switch (requestScope) {
      AiMindMapRequestScope.currentChapter => 'currentChapter',
      AiMindMapRequestScope.currentWork => 'currentWork',
      AiMindMapRequestScope.wholeBook => 'wholePublication',
      AiMindMapRequestScope.unspecified => 'unspecified',
    };
    final turnId = parentTurnId ?? ui.newTurnId();
    final proposal = AiActionProposal(
      protocolVersion: AiActionProposal.currentProtocolVersion,
      proposalId: 'proposal-${ui.newTurnId()}',
      parentRunId: parentTurnId,
      conversationId: ui.contentHash(),
      turnId: turnId,
      actionKind: definition.actionKind,
      definitionVersion: definition.definitionVersion,
      proposalSchemaVersion: definition.proposalSchemaVersion,
      source: AiActionProposalSource.explicitUi,
      sourceSubmissionId: ui.newTurnId(),
      originalUserText: originalText,
      requestedArguments: {
        'scope': actionScopeName,
        'instruction': originalText,
        'contentHash': ui.contentHash(),
        if (conversationWorkKey != null && conversationWorkKey.isNotEmpty)
          'workKey': conversationWorkKey,
      },
      scopeRef: actionScopeName,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    try {
      final evaluation = await workspace.actionController.propose(
        proposal,
        deferExplicitAuthorization: true,
        capabilities: workspace.resolveCapabilities(),
      );
      if (!evaluation.authorized &&
          evaluation.entry.status != AiActionJournalStatus.proposed) {
        if (ui.isMounted()) {
          ui.appendClarification(
            originalText,
            evaluation.needsClarification
                ? '还需要明确思维导图的范围。'
                : '这项思维导图操作目前未获授权，请重新发起。',
            workKey: conversationWorkKey,
          );
        }
        return;
      }
      final started = await ui.runCreateMindMap(
        text: originalText,
        scope: requestScope,
        clearComposer: true,
        actionProposalId: proposal.proposalId,
        authorizeAction: (units) =>
            authorizeAfterFreeze(proposal, units: units),
      );
      if (!started) await completeCancelled(proposal.proposalId);
    } catch (error) {
      await completeFailure(proposal.proposalId);
      if (ui.isMounted()) {
        ui.appendClarification(
          originalText,
          aiUserErrorMessage(error, operation: AiUserOperation.mindMap),
          workKey: conversationWorkKey,
        );
      }
    }
  }

  Future<void> dispatchProposed({
    required String originalText,
    required AiProductActionRequest action,
    required AiBookMindMapProductTurn productTurn,
    String? retryTurnId,
    required AiActionProposal proposal,
  }) async {
    final evaluation = await workspace.actionController.propose(
      proposal,
      capabilities: workspace.resolveCapabilities(),
    );
    // Mind-map light path: auto-allow → proceed without confirmation card.
    // Other product actions may still requireConfirmation.
    if (!evaluation.canProceedWithoutConfirmation &&
        !evaluation.needsConfirmation) {
      ui.appendClarification(
        originalText,
        evaluation.needsClarification
            ? '还需要明确思维导图的范围或要修改的导图。'
            : '这项思维导图操作目前未获授权，请重新发起。',
        workKey: productTurn.scopeSnapshot.conversationWorkKey,
      );
      return;
    }
    if (evaluation.needsConfirmation) {
      // Non-mind-map (or legacy) confirm path — UI-only until freeze.
      final domain = domains.byActionKind(proposal.actionKind);
      final view =
          domain?.confirmationView(
            action,
            contextHints: {
              if (action is AiReviseBookMindMapAction)
                'revision':
                    productTurn.artifactsById[action.artifactId]?.revision,
            },
          ) ??
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
    }
    await executeAuthorized(
      originalText: originalText,
      action: action,
      productTurn: productTurn,
      retryTurnId: retryTurnId,
      proposal: proposal,
    );
  }

  /// Domain-registry driven execute. Mind-map create/revise use domain
  /// actionKind; generic registered actions use domain adapter path.
  Future<void> executeAuthorized({
    required String originalText,
    required AiProductActionRequest action,
    required AiBookMindMapProductTurn productTurn,
    String? retryTurnId,
    required AiActionProposal proposal,
  }) async {
    final domain = domains.byActionKind(proposal.actionKind);
    if (domain == null) {
      throw StateError('未注册的产品动作: ${proposal.actionKind}');
    }
    if (!domain.productionExposed) {
      throw StateError('非生产能力不可在生产路径执行: ${proposal.actionKind}');
    }

    Future<AiActionJournalEntry> auth(
      List<BookAiMindMapGenerationUnit> units,
    ) => authorizeAfterFreeze(proposal, units: units);

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
        final started = await ui.runCreateMindMap(
          text: originalText,
          scope: input.scope,
          frozenTurn: productTurn.scopeSnapshot,
          resolvedWork: input.work,
          frozenCurrentChapter: input.frozenCurrentChapter,
          retryTurnId: retryTurnId,
          clearComposer: true,
          actionProposalId: proposal.proposalId,
          authorizeAction: auth,
        );
        if (!started) await completeCancelled(proposal.proposalId);
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
        final started = await ui.runReviseMindMap(
          text: originalText,
          target: target,
          conversationWorkKey: productTurn.scopeSnapshot.conversationWorkKey,
          retryTurnId: retryTurnId,
          clearComposer: false,
          actionProposalId: proposal.proposalId,
          authorizeAction: auth,
        );
        if (!started) await completeCancelled(proposal.proposalId);
      case final AiRegisteredProductAction registered:
        await _runRegistered(
          originalText,
          registered,
          proposal: proposal,
          productTurn: productTurn,
          domain: domain,
        );
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

  Future<void> retry({
    required String text,
    required String proposalId,
    required String? retryTurnId,
    AiBookMindMap? retryTarget,
    required Future<List<BookAiMindMapGenerationUnit>> Function(
      AiAuthorizedCommand command, {
      AiBookMindMap? retryTarget,
    })
    unitsFromCommand,
  }) async {
    try {
      final rearmed = await workspace.actionController.prepareRetry(proposalId);
      if (rearmed.status == AiActionJournalStatus.succeeded ||
          rearmed.status == AiActionJournalStatus.partiallySucceeded) {
        await reconcileProjection(rearmed);
        return;
      }
      final command = rearmed.command;
      if (command == null) throw StateError('重试缺少授权命令');
      final units = await unitsFromCommand(
        command,
        retryTarget: retryTarget,
      );
      if (units.isEmpty) {
        await workspace.actionController.abandon(
          proposalId,
          reasonCode: 'frozen_scope_content_missing',
        );
        return;
      }
      await workspace.actionController.queue(proposalId);
      await ui.runGenerateUnits(
        text: text,
        units: units,
        baseMap: retryTarget,
        retryTurnId: retryTurnId,
        conversationWorkKey: command.workKey,
        actionProposalId: proposalId,
        actionCommand: command,
        attempt: rearmed.attempt == 0 ? 1 : rearmed.attempt,
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
  T? get singleOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    final value = iterator.current;
    if (iterator.moveNext()) return null;
    return value;
  }
}

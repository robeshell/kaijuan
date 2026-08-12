import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'ai_product_action_protocol.dart';

class AiActionEvaluation {
  const AiActionEvaluation({required this.entry, required this.decision});

  final AiActionJournalEntry entry;
  final AiActionDecision decision;

  bool get needsConfirmation =>
      decision.outcome == AiActionDecisionOutcome.requireConfirmation;
  bool get needsClarification =>
      decision.outcome == AiActionDecisionOutcome.requireClarification;
  bool get authorized => entry.status == AiActionJournalStatus.authorized;
}

enum AiActionRecoveryDisposition {
  terminal,
  waitingForHuman,
  recoverable,
  abandoned,

  /// Receipt is terminal success, but conversation projection is incomplete.
  needsProjection,
}

class AiActionRecoveryCandidate {
  const AiActionRecoveryCandidate({
    required this.entry,
    required this.disposition,
    this.reasonCode,
  });

  final AiActionJournalEntry entry;
  final AiActionRecoveryDisposition disposition;
  final String? reasonCode;
}

/// App-owned control plane for product actions. It never calls a model or a
/// domain Workflow; it only validates, journals and authorizes immutable
/// commands for a separate executor.
class AiProductActionController {
  AiProductActionController({
    required this.registry,
    required this.journal,
    this.policy = const AiActionPolicy(),
    DateTime Function()? now,
    String Function()? idGenerator,
  }) : _now = now ?? DateTime.now,
       _idGenerator = idGenerator ?? _defaultId;

  final AiProductActionRegistry registry;
  AiActionJournalStore journal;
  final AiActionPolicy policy;
  final DateTime Function() _now;
  final String Function() _idGenerator;
  Future<void> _operationQueue = Future<void>.value();

  void replaceJournal(AiActionJournalStore next) {
    journal = next;
  }

  Future<AiActionEvaluation> propose(
    AiActionProposal proposal, {
    AiCapabilitySet capabilities = const AiCapabilitySet({}),
    bool deferExplicitAuthorization = false,
  }) => _exclusive(() async {
    final existing = await journal.read(proposal.proposalId);
    if (existing != null) {
      final decision =
          existing.decision ??
          AiActionDecision(
            proposalId: proposal.proposalId,
            outcome: AiActionDecisionOutcome.deny,
            reasonCode: 'journal_entry_missing_decision',
            riskClass: AiActionRiskClass.reversible,
            decidedAt: _now(),
          );
      return AiActionEvaluation(entry: existing, decision: decision);
    }

    final snapshotProposal = proposal.copyWith(
      capabilitySnapshotRef: capabilities.fingerprint,
    );
    var entry = AiActionJournalEntry.proposed(snapshotProposal);
    await journal.write(entry);
    final definition = registry.lookup(snapshotProposal.actionKind);
    final decision = definition == null
        ? AiActionDecision(
            proposalId: proposal.proposalId,
            outcome: AiActionDecisionOutcome.deny,
            reasonCode: 'unknown_action_kind',
            riskClass: AiActionRiskClass.reversible,
            decidedAt: _now(),
          )
        : snapshotProposal.definitionVersion != definition.definitionVersion ||
              snapshotProposal.proposalSchemaVersion !=
                  definition.proposalSchemaVersion
        ? AiActionDecision(
            proposalId: proposal.proposalId,
            outcome: AiActionDecisionOutcome.deny,
            reasonCode: 'incompatible_proposal_version',
            riskClass: definition.riskClass,
            decidedAt: _now(),
          )
        : !definition.supportedSources.contains(snapshotProposal.source)
        ? AiActionDecision(
            proposalId: proposal.proposalId,
            outcome: AiActionDecisionOutcome.deny,
            reasonCode: 'unsupported_action_source',
            riskClass: definition.riskClass,
            decidedAt: _now(),
          )
        : !capabilities.containsAll(definition.requiredCapabilities) ||
              (definition.anyOfCapabilities.isNotEmpty &&
                  !definition.anyOfCapabilities.any(capabilities.containsAll))
        ? AiActionDecision(
            proposalId: proposal.proposalId,
            outcome: AiActionDecisionOutcome.deny,
            reasonCode: 'missing_capability',
            riskClass: definition.riskClass,
            decidedAt: _now(),
          )
        : policy.decide(
            proposal: snapshotProposal,
            definition: definition,
            now: _now(),
          );
    final status = switch (decision.outcome) {
      AiActionDecisionOutcome.allow =>
        deferExplicitAuthorization &&
                snapshotProposal.source == AiActionProposalSource.explicitUi
            ? AiActionJournalStatus.proposed
            : AiActionJournalStatus.authorized,
      AiActionDecisionOutcome.requireConfirmation =>
        AiActionJournalStatus.awaitingConfirmation,
      AiActionDecisionOutcome.requireClarification =>
        AiActionJournalStatus.awaitingClarification,
      AiActionDecisionOutcome.deny =>
        snapshotProposal.expiresAt.isBefore(_now())
            ? AiActionJournalStatus.expired
            : AiActionJournalStatus.rejected,
    };
    AiAuthorizedCommand? command;
    if (status == AiActionJournalStatus.authorized) {
      command = _commandFor(
        proposal: snapshotProposal,
        decision: decision,
        authorizationSubmissionId: snapshotProposal.sourceSubmissionId,
        authorizationEvidence: 'proposal:${snapshotProposal.proposalId}',
      );
    }
    entry = entry.transition(
      status,
      decision: decision,
      command: command,
      now: _now(),
    );
    await journal.write(entry);
    return AiActionEvaluation(entry: entry, decision: decision);
  });

  Future<AiActionJournalEntry> approve({
    required String proposalId,
    required String authorizationSubmissionId,
    required String authorizationEvidence,
    Map<String, Object?> normalizedArguments = const {},
  }) => _exclusive(() async {
    var entry = await _requiredEntry(proposalId);
    if (entry.status == AiActionJournalStatus.authorized &&
        entry.command?.authorizationSubmissionId == authorizationSubmissionId) {
      return entry;
    }
    if (entry.status != AiActionJournalStatus.awaitingConfirmation) {
      throw StateError('Action is not awaiting confirmation');
    }
    final decision = entry.decision;
    if (decision == null ||
        decision.outcome != AiActionDecisionOutcome.requireConfirmation) {
      throw StateError('Action has no confirmable decision');
    }
    final effectiveDecision = normalizedArguments.isEmpty
        ? decision
        : AiActionDecision(
            proposalId: decision.proposalId,
            outcome: decision.outcome,
            reasonCode: decision.reasonCode,
            riskClass: decision.riskClass,
            decidedAt: decision.decidedAt,
            resolvedActionKind: decision.resolvedActionKind,
            resolvedScope: decision.resolvedScope,
            resolvedTarget: decision.resolvedTarget,
            normalizedArguments: {
              ...decision.normalizedArguments,
              ...normalizedArguments,
            },
            confirmationSummary: decision.confirmationSummary,
            allowedHumanDecisions: decision.allowedHumanDecisions,
          );
    return _authorizeEntry(
      entry: entry,
      decision: effectiveDecision,
      authorizationSubmissionId: authorizationSubmissionId,
      authorizationEvidence: authorizationEvidence,
    );
  });

  Future<AiActionJournalEntry> authorize({
    required String proposalId,
    required String authorizationSubmissionId,
    required String authorizationEvidence,
    Map<String, Object?> normalizedArguments = const {},
  }) => _exclusive(() async {
    var entry = await _requiredEntry(proposalId);
    if (entry.status == AiActionJournalStatus.authorized &&
        entry.command?.authorizationSubmissionId == authorizationSubmissionId) {
      return entry;
    }
    if (entry.status != AiActionJournalStatus.proposed) {
      throw StateError('Action is not awaiting explicit authorization');
    }
    final decision = entry.decision;
    if (decision == null || decision.outcome != AiActionDecisionOutcome.allow) {
      throw StateError('Action has no allow decision');
    }
    final effectiveDecision = normalizedArguments.isEmpty
        ? decision
        : AiActionDecision(
            proposalId: decision.proposalId,
            outcome: decision.outcome,
            reasonCode: decision.reasonCode,
            riskClass: decision.riskClass,
            decidedAt: decision.decidedAt,
            resolvedActionKind: decision.resolvedActionKind,
            resolvedScope: decision.resolvedScope,
            resolvedTarget: decision.resolvedTarget,
            normalizedArguments: {
              ...decision.normalizedArguments,
              ...normalizedArguments,
            },
            confirmationSummary: decision.confirmationSummary,
            allowedHumanDecisions: decision.allowedHumanDecisions,
          );
    return _authorizeEntry(
      entry: entry,
      decision: effectiveDecision,
      authorizationSubmissionId: authorizationSubmissionId,
      authorizationEvidence: authorizationEvidence,
    );
  });

  Future<AiActionJournalEntry> _authorizeEntry({
    required AiActionJournalEntry entry,
    required AiActionDecision decision,
    required String authorizationSubmissionId,
    required String authorizationEvidence,
  }) async {
    final command = _commandFor(
      proposal: entry.proposal,
      decision: decision,
      authorizationSubmissionId: authorizationSubmissionId,
      authorizationEvidence: authorizationEvidence,
    );
    entry = entry.transition(
      AiActionJournalStatus.authorized,
      decision: decision,
      command: command,
      now: _now(),
    );
    await journal.write(entry);
    return entry;
  }

  Future<AiActionJournalEntry> queue(String proposalId) => _exclusive(() async {
    final entry = await _requiredEntry(proposalId);
    if (entry.status == AiActionJournalStatus.queued ||
        entry.status == AiActionJournalStatus.executing ||
        entry.status == AiActionJournalStatus.cancelRequested) {
      return entry;
    }
    return _transition(proposalId, AiActionJournalStatus.queued);
  });

  Future<AiActionJournalEntry> markExecuting(
    String proposalId, {
    int? attempt,
  }) => _exclusive(() async {
    final entry = await _requiredEntry(proposalId);
    if (entry.status == AiActionJournalStatus.executing ||
        entry.status == AiActionJournalStatus.cancelRequested) {
      return entry;
    }
    if (entry.status == AiActionJournalStatus.authorized) {
      final queued = entry.transition(
        AiActionJournalStatus.queued,
        now: _now(),
      );
      await journal.write(queued);
    }
    return _transition(
      proposalId,
      AiActionJournalStatus.executing,
      attempt: attempt ?? (entry.attempt == 0 ? 1 : entry.attempt),
    );
  });

  /// Moves an authorized/queued command to the executable state without
  /// creating a second command. This is the recovery-safe entry point used by
  /// generic Workflow executors.
  Future<AiActionJournalEntry> ensureExecuting(String proposalId) =>
      markExecuting(proposalId);

  Future<AiActionJournalEntry> requestCancel(String proposalId) => _exclusive(
    () => _transition(proposalId, AiActionJournalStatus.cancelRequested),
  );

  Future<AiAuthorizedCommand> requireExecutingCommand({
    required String proposalId,
    required String commandId,
  }) => _exclusive(() async {
    final entry = await _requiredEntry(proposalId);
    final command = entry.command;
    if (command == null || command.commandId != commandId) {
      throw StateError('Action command does not match its proposal');
    }
    if (entry.status != AiActionJournalStatus.queued &&
        entry.status != AiActionJournalStatus.executing) {
      throw StateError('Action command is not executable');
    }
    return command;
  });

  Future<AiActionJournalEntry> reject(String proposalId) =>
      _exclusive(() async {
        final entry = await _requiredEntry(proposalId);
        if (entry.status != AiActionJournalStatus.proposed &&
            entry.status != AiActionJournalStatus.awaitingConfirmation &&
            entry.status != AiActionJournalStatus.awaitingClarification) {
          throw StateError('Action is not awaiting a human decision');
        }
        final next = entry.transition(
          AiActionJournalStatus.rejected,
          now: _now(),
        );
        await journal.write(next);
        return next;
      });

  Future<List<AiActionRecoveryCandidate>> inspectRecovery() =>
      _exclusive(() async {
        final entries = await journal.readAll();
        return [
          for (final entry in entries)
            AiActionRecoveryCandidate(
              entry: entry,
              disposition: _recoveryDisposition(entry),
              reasonCode: _recoveryReason(entry),
            ),
        ];
      });

  Future<AiActionJournalEntry> abandon(
    String proposalId, {
    String reasonCode = 'recovery_not_safe',
  }) => _exclusive(() async {
    final entry = await _requiredEntry(proposalId);
    if (entry.status.isTerminal) return entry;
    final next = entry.transition(
      AiActionJournalStatus.abandoned,
      terminalReasonCode: reasonCode,
      now: _now(),
    );
    await journal.write(next);
    return next;
  });

  AiActionRecoveryDisposition _recoveryDisposition(AiActionJournalEntry entry) {
    if (entry.needsProjection) {
      return AiActionRecoveryDisposition.needsProjection;
    }
    if (entry.status.isTerminal) return AiActionRecoveryDisposition.terminal;
    if (entry.status == AiActionJournalStatus.proposed ||
        entry.status == AiActionJournalStatus.awaitingConfirmation ||
        entry.status == AiActionJournalStatus.awaitingClarification) {
      return AiActionRecoveryDisposition.waitingForHuman;
    }
    return entry.command == null
        ? AiActionRecoveryDisposition.abandoned
        : AiActionRecoveryDisposition.recoverable;
  }

  String? _recoveryReason(AiActionJournalEntry entry) {
    if (entry.needsProjection) return 'conversation_projection_pending';
    if (entry.command == null &&
        !entry.status.isTerminal &&
        entry.status != AiActionJournalStatus.proposed &&
        entry.status != AiActionJournalStatus.awaitingConfirmation &&
        entry.status != AiActionJournalStatus.awaitingClarification) {
      return 'authorized_command_missing';
    }
    if (entry.command?.contentHash == null && entry.command != null) {
      return 'content_hash_missing';
    }
    return null;
  }

  /// Records that conversation projection durably completed for [refs].
  Future<AiActionJournalEntry> markProjected({
    required String proposalId,
    required Iterable<String> refs,
  }) => _exclusive(() async {
    final entry = await _requiredEntry(proposalId);
    if (!entry.status.isTerminal) {
      throw StateError('Projection tracking requires a terminal action');
    }
    final next = entry.withProjectedRefs(refs, now: _now());
    await journal.write(next);
    return next;
  });

  /// Re-arms a failed/cancelled command for another Workflow attempt without
  /// creating a new Proposal, Command, or idempotency key.
  ///
  /// Already-succeeded entries are returned unchanged so UI "retry" is a no-op
  /// that surfaces the existing Receipt.
  Future<AiActionJournalEntry> prepareRetry(String proposalId) => _exclusive(
    () async {
      final entry = await _requiredEntry(proposalId);
      if (entry.status == AiActionJournalStatus.succeeded ||
          entry.status == AiActionJournalStatus.partiallySucceeded) {
        return entry;
      }
      if (entry.status != AiActionJournalStatus.failed &&
          entry.status != AiActionJournalStatus.cancelled) {
        throw StateError(
          'Only failed or cancelled actions can be retried: ${entry.status}',
        );
      }
      if (entry.command == null) {
        throw StateError('Retry requires an authorized command');
      }
      final refs = entry.receipt?.artifactRefs ?? const <String>[];
      if (refs.isNotEmpty) {
        // Durable artifacts already exist for this command; do not regenerate.
        return entry;
      }
      final next = AiActionJournalEntry(
        proposal: entry.proposal,
        decision: entry.decision,
        command: entry.command,
        receipt: null,
        status: AiActionJournalStatus.authorized,
        stateVersion: entry.stateVersion + 1,
        eventSequence: entry.eventSequence + 1,
        attempt: entry.attempt + 1,
        updatedAt: _now(),
        projectedArtifactRefs: const [],
      );
      await journal.write(next);
      return next;
    },
  );

  Future<AiActionJournalEntry> complete(AiActionReceipt receipt) =>
      _exclusive(() => _completeReceipt(receipt));

  Future<AiActionJournalEntry> completeForProposal({
    required String proposalId,
    required AiActionJournalStatus status,
    required List<String> artifactRefs,
    String workflowRunId = '',
    int attempt = 1,
    String? publicErrorCode,
  }) => _exclusive(() async {
    final entry = await _requiredEntry(proposalId);
    final command = entry.command;
    if (command == null) throw StateError('Action has no authorized command');
    return _completeReceipt(
      AiActionReceipt(
        commandId: command.commandId,
        workflowRunId: workflowRunId.isEmpty
            ? 'workflow:${command.commandId}'
            : workflowRunId,
        attempt: attempt,
        definitionVersion: command.definitionVersion,
        workflowVersion: command.workflowVersion,
        status: status,
        artifactRefs: artifactRefs,
        publicErrorCode: publicErrorCode,
        finishedAt: _now(),
      ),
    );
  });

  Future<AiActionJournalEntry> _completeReceipt(AiActionReceipt receipt) async {
    final entries = await journal.readAll();
    AiActionJournalEntry? entry = entries
        .cast<AiActionJournalEntry?>()
        .firstWhere(
          (candidate) => candidate?.command?.commandId == receipt.commandId,
          orElse: () => null,
        );
    if (entry == null) {
      throw StateError('Unknown action command: ${receipt.commandId}');
    }
    if (entry.command?.commandId != receipt.commandId) {
      throw StateError('Receipt command does not match journal command');
    }
    if (entry.status.isTerminal) {
      if (entry.receipt == null || entry.receipt!.status != receipt.status) {
        throw StateError('Conflicting terminal receipt');
      }
      return entry;
    }
    if (entry.status == AiActionJournalStatus.cancelRequested &&
        receipt.status != AiActionJournalStatus.cancelled &&
        receipt.status != AiActionJournalStatus.failed) {
      throw StateError('A cancel-requested action cannot succeed');
    }
    entry = entry.transition(receipt.status, receipt: receipt, now: _now());
    await journal.write(entry);
    return entry;
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _operationQueue.then<T>((_) => operation());
    _operationQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<AiActionJournalEntry> _transition(
    String proposalId,
    AiActionJournalStatus status, {
    int? attempt,
  }) async {
    var entry = await _requiredEntry(proposalId);
    entry = entry.transition(status, attempt: attempt, now: _now());
    await journal.write(entry);
    return entry;
  }

  Future<AiActionJournalEntry> _requiredEntry(String id) async {
    final entry = await journal.read(id);
    if (entry == null) throw StateError('Unknown action journal entry: $id');
    return entry;
  }

  AiAuthorizedCommand _commandFor({
    required AiActionProposal proposal,
    required AiActionDecision decision,
    required String authorizationSubmissionId,
    required String authorizationEvidence,
  }) {
    final actionKind = decision.resolvedActionKind ?? proposal.actionKind;
    final definition = registry.lookup(actionKind);
    if (definition == null) {
      throw StateError('Unknown action definition: $actionKind');
    }
    if (proposal.definitionVersion != definition.definitionVersion ||
        proposal.proposalSchemaVersion != definition.proposalSchemaVersion) {
      throw StateError('Action proposal version is stale: $actionKind');
    }
    final targetArtifactId = decision.resolvedTarget ?? proposal.targetRef;
    final expectedRevision = proposal.expectedRevision;
    final scopeFingerprint = _string(
      decision.normalizedArguments['scopeFingerprint'],
    );
    final idempotencyKey = sha256
        .convert(
          utf8.encode(
            [
              authorizationSubmissionId,
              actionKind,
              scopeFingerprint ?? proposal.scopeRef ?? '',
              targetArtifactId ?? '',
              '${expectedRevision ?? ''}',
            ].join('|'),
          ),
        )
        .toString();
    final arguments = Map<String, Object?>.unmodifiable(
      decision.normalizedArguments.isEmpty
          ? proposal.requestedArguments
          : decision.normalizedArguments,
    );
    return AiAuthorizedCommand(
      protocolVersion: AiActionProposal.currentProtocolVersion,
      commandId: _idGenerator(),
      proposalId: proposal.proposalId,
      actionKind: actionKind,
      definitionVersion: proposal.definitionVersion,
      commandSchemaVersion: definition.commandSchemaVersion,
      workflowVersion: definition.workflowVersion,
      authorizationSource: proposal.source,
      authorizationSubmissionId: authorizationSubmissionId,
      authorizationEvidence: authorizationEvidence,
      authorizedAt: _now(),
      idempotencyKey: idempotencyKey,
      arguments: arguments,
      originalUserText: proposal.originalUserText,
      contentHash: _string(arguments['contentHash']),
      workKey: _string(arguments['workKey']),
      scopeFingerprint: scopeFingerprint,
      scopeSectionIndices:
          (arguments['scopeSectionIndices'] as List?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false) ??
          const [],
      targetArtifactId: targetArtifactId,
      expectedRevision: expectedRevision,
    );
  }

  static String _defaultId() =>
      'command-${DateTime.now().microsecondsSinceEpoch}';

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

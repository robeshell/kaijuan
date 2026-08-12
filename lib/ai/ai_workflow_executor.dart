import 'ai_cancel.dart';
import 'ai_product_action_controller.dart';
import 'ai_product_action_protocol.dart';
import 'ai_workflow_contract.dart';

/// Runs a frozen Product Action through a registered Workflow adapter.
///
/// The executor is deliberately boring: the model is already out of the
/// path, the command is immutable, and the journal is the only authority for
/// cancellation and terminal receipt commits. This keeps every future
/// Workflow (PPT, translation, export, ...) on the same control-plane path.
class AiProductWorkflowExecutor {
  AiProductWorkflowExecutor({
    required this.actions,
    required this.adapters,
    required this.environment,
  });

  final AiProductActionController actions;
  final AiWorkflowAdapterRegistry adapters;
  final AiWorkflowEnvironment environment;
  final Map<String, Future<AiActionJournalEntry>> _activeRuns = {};

  Future<AiActionJournalEntry> execute(
    String proposalId, {
    CancelToken? cancelToken,
    int attempt = 1,
  }) {
    final existing = _activeRuns[proposalId];
    if (existing != null) return existing;
    final future = _execute(
      proposalId,
      cancelToken: cancelToken,
      attempt: attempt,
    );
    _activeRuns[proposalId] = future;
    return future.whenComplete(() => _activeRuns.remove(proposalId));
  }

  Future<AiActionJournalEntry> _execute(
    String proposalId, {
    CancelToken? cancelToken,
    required int attempt,
  }) async {
    final token = cancelToken ?? CancelToken();
    var entry = await actions.journal.read(proposalId);
    if (entry == null) throw StateError('Unknown action proposal: $proposalId');
    if (entry.status.isTerminal) return entry;
    final command = entry.command;
    if (command == null) {
      throw StateError('Action has no authorized command: $proposalId');
    }
    final adapter = adapters.lookup(command.actionKind);
    if (adapter == null) {
      return _fail(proposalId, 'workflow_adapter_missing');
    }

    if (entry.status == AiActionJournalStatus.cancelRequested) {
      return _cancel(proposalId);
    }

    final runId = 'workflow:${command.commandId}';
    final inspection = await adapter.inspect(runId);
    if (inspection.active && entry.status != AiActionJournalStatus.executing) {
      // Another live run already owns this command; await its journal terminal
      // state rather than starting a second domain workflow.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final latest = await actions.journal.read(proposalId);
        if (latest == null || latest.status.isTerminal) {
          return latest ?? entry;
        }
      }
    }

    final recovering = entry.status == AiActionJournalStatus.executing;
    final effectiveAttempt = recovering
        ? (entry.attempt == 0 ? attempt : entry.attempt)
        : attempt;
    if (entry.status == AiActionJournalStatus.authorized ||
        entry.status == AiActionJournalStatus.queued) {
      entry = await actions.markExecuting(
        proposalId,
        attempt: effectiveAttempt,
      );
    }
    if (entry.status == AiActionJournalStatus.cancelRequested) {
      return _cancel(
        proposalId,
        workflowRunId: runId,
        attempt: effectiveAttempt,
      );
    }
    final executable = await actions.requireExecutingCommand(
      proposalId: proposalId,
      commandId: command.commandId,
    );
    final preflight = await adapter.preflight(executable, environment);
    if (!preflight.accepted) {
      return _fail(
        proposalId,
        preflight.publicErrorCode ?? 'preflight_failed',
        workflowRunId: runId,
        attempt: effectiveAttempt,
      );
    }

    final context = AiWorkflowRunContext(
      workflowRunId: runId,
      attempt: effectiveAttempt,
      environment: environment,
      cancelToken: token,
    );
    final artifactRefs = <String>{};
    AiActionJournalStatus? terminalStatus;
    String? publicErrorCode;
    try {
      final AiWorkflowCheckpoint? checkpoint;
      try {
        checkpoint = await _recoveryCheckpoint(
          command: executable,
          workflowRunId: runId,
        );
      } on StateError catch (error) {
        if ('$error'.contains('incompatible')) {
          return actions.completeForProposal(
            proposalId: proposalId,
            status: AiActionJournalStatus.abandoned,
            artifactRefs: const [],
            workflowRunId: runId,
            attempt: effectiveAttempt,
            publicErrorCode: 'incompatible_checkpoint_version',
          );
        }
        rethrow;
      }
      final events = recovering
          ? adapter.recover(
              AiWorkflowRecoveryRequest(
                command: executable,
                workflowRunId: runId,
                attempt: effectiveAttempt,
                environment: environment,
                checkpoint: checkpoint,
              ),
            )
          : adapter.start(executable, context);
      await for (final event in events) {
        final current = await actions.journal.read(proposalId);
        final cancellationRequested =
            token.isCancelled ||
            current?.status == AiActionJournalStatus.cancelRequested;
        if (event is AiWorkflowArtifactReady && !cancellationRequested) {
          artifactRefs.add(event.artifactRef);
        }
        if (event is AiWorkflowCheckpointCommitted) {
          if (event.checkpoint.workflowRunId != runId ||
              event.checkpoint.workflowVersion != executable.workflowVersion) {
            throw StateError('Workflow checkpoint identity mismatch');
          }
          await environment.checkpoints.write(event.checkpoint);
        }
        if (event is AiWorkflowSucceeded) {
          if (!cancellationRequested) artifactRefs.addAll(event.artifactRefs);
          terminalStatus = cancellationRequested
              ? AiActionJournalStatus.cancelled
              : AiActionJournalStatus.succeeded;
        } else if (event is AiWorkflowPartiallySucceeded) {
          if (!cancellationRequested) artifactRefs.addAll(event.artifactRefs);
          terminalStatus = cancellationRequested
              ? AiActionJournalStatus.cancelled
              : AiActionJournalStatus.partiallySucceeded;
          publicErrorCode = event.publicErrorCode;
        } else if (event is AiWorkflowFailed) {
          terminalStatus = cancellationRequested
              ? AiActionJournalStatus.cancelled
              : AiActionJournalStatus.failed;
          publicErrorCode = event.publicErrorCode;
        } else if (event is AiWorkflowCancelled) {
          terminalStatus = AiActionJournalStatus.cancelled;
        }
      }
      terminalStatus ??=
          (await actions.journal.read(proposalId))?.status ==
              AiActionJournalStatus.cancelRequested
          ? AiActionJournalStatus.cancelled
          : AiActionJournalStatus.failed;
      if (terminalStatus == AiActionJournalStatus.cancelled) {
        artifactRefs.clear();
        publicErrorCode = null;
      }
      return actions.completeForProposal(
        proposalId: proposalId,
        status: terminalStatus,
        artifactRefs: artifactRefs.toList(growable: false),
        workflowRunId: runId,
        attempt: effectiveAttempt,
        publicErrorCode: publicErrorCode,
      );
    } catch (error) {
      final current = await actions.journal.read(proposalId);
      if (token.isCancelled ||
          current?.status == AiActionJournalStatus.cancelRequested) {
        return _cancel(
          proposalId,
          workflowRunId: runId,
          attempt: effectiveAttempt,
        );
      }
      if ('$error'.contains('incompatible')) {
        return actions.completeForProposal(
          proposalId: proposalId,
          status: AiActionJournalStatus.abandoned,
          artifactRefs: const [],
          workflowRunId: runId,
          attempt: effectiveAttempt,
          publicErrorCode: 'incompatible_checkpoint_version',
        );
      }
      return _fail(
        proposalId,
        'workflow_execution_failed',
        workflowRunId: runId,
        attempt: effectiveAttempt,
      );
    }
  }

  Future<AiActionJournalEntry> requestCancel(
    String proposalId, {
    String reason = 'user_cancelled',
  }) async {
    final entry = await actions.journal.read(proposalId);
    if (entry == null) throw StateError('Unknown action proposal: $proposalId');
    if (entry.status.isTerminal) return entry;
    if (entry.status == AiActionJournalStatus.authorized ||
        entry.status == AiActionJournalStatus.queued ||
        entry.status == AiActionJournalStatus.executing) {
      await actions.requestCancel(proposalId);
    }
    final current = await actions.journal.read(proposalId);
    final command = current?.command;
    if (command != null) {
      final adapter = adapters.lookup(command.actionKind);
      if (adapter != null) {
        await adapter.requestCancel('workflow:${command.commandId}', reason);
      }
    }
    final after = await actions.journal.read(proposalId);
    return after ?? current!;
  }

  Future<AiWorkflowCheckpoint?> _recoveryCheckpoint({
    required AiAuthorizedCommand command,
    required String workflowRunId,
  }) async {
    final checkpoint = await environment.checkpoints.readLatest(workflowRunId);
    if (checkpoint == null) return null;
    if (checkpoint.workflowVersion != command.workflowVersion) {
      throw StateError('Workflow checkpoint version is incompatible');
    }
    return checkpoint;
  }

  Future<AiActionJournalEntry> _cancel(
    String proposalId, {
    String workflowRunId = '',
    int attempt = 1,
  }) => actions.completeForProposal(
    proposalId: proposalId,
    status: AiActionJournalStatus.cancelled,
    artifactRefs: const [],
    workflowRunId: workflowRunId,
    attempt: attempt,
  );

  Future<AiActionJournalEntry> _fail(
    String proposalId,
    String errorCode, {
    String workflowRunId = '',
    int attempt = 1,
  }) => actions.completeForProposal(
    proposalId: proposalId,
    status: AiActionJournalStatus.failed,
    artifactRefs: const [],
    workflowRunId: workflowRunId,
    attempt: attempt,
    publicErrorCode: errorCode,
  );
}

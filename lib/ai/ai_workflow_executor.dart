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
    if (entry.status == AiActionJournalStatus.authorized ||
        entry.status == AiActionJournalStatus.queued) {
      entry = await actions.ensureExecuting(proposalId);
    }
    if (entry.status == AiActionJournalStatus.cancelRequested) {
      return _cancel(proposalId);
    }
    final executable = await actions.requireExecutingCommand(
      proposalId: proposalId,
      commandId: command.commandId,
    );
    final preflight = await adapter.preflight(executable, environment);
    if (!preflight.accepted) {
      return _fail(proposalId, preflight.publicErrorCode ?? 'preflight_failed');
    }

    final runId = 'workflow:${executable.commandId}:$attempt';
    final context = AiWorkflowRunContext(
      workflowRunId: runId,
      attempt: attempt,
      environment: environment,
      cancelToken: token,
    );
    final artifactRefs = <String>{};
    AiActionJournalStatus? terminalStatus;
    String? publicErrorCode;
    try {
      await for (final event in adapter.start(executable, context)) {
        final current = await actions.journal.read(proposalId);
        final cancellationRequested =
            token.isCancelled ||
            current?.status == AiActionJournalStatus.cancelRequested;
        if (event is AiWorkflowArtifactReady && !cancellationRequested) {
          artifactRefs.add(event.artifactRef);
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
        attempt: attempt,
        publicErrorCode: publicErrorCode,
      );
    } catch (error) {
      final current = await actions.journal.read(proposalId);
      if (token.isCancelled ||
          current?.status == AiActionJournalStatus.cancelRequested) {
        return _cancel(proposalId, workflowRunId: runId, attempt: attempt);
      }
      return _fail(
        proposalId,
        'workflow_execution_failed',
        workflowRunId: runId,
        attempt: attempt,
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

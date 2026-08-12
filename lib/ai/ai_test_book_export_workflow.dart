import 'ai_cancel.dart';
import 'ai_product_action_protocol.dart';
import 'ai_workflow_contract.dart';

/// Non-product test Workflow used to prove registration-driven extension.
///
/// Adding this action must not require edits to the generic controller,
/// executor, tool parser or main chat widget dispatch.
abstract final class AiTestBookExportProductActions {
  static const actionKind = 'test_book_export';
  static const toolName = 'test_book_export';
  static const artifactKind = 'test_book_export';

  static const definition = AiProductActionDefinition(
    actionKind: actionKind,
    definitionVersion: 1,
    proposalSchemaVersion: 1,
    commandSchemaVersion: 1,
    workflowVersion: 1,
    riskClass: AiActionRiskClass.reversible,
    supportedSources: {
      AiActionProposalSource.modelTool,
      AiActionProposalSource.explicitUi,
    },
    requiredCapabilities: {'book.read'},
    toolName: toolName,
    toolDescription:
        'Test-only export workflow. Never expose in production catalogs.',
    argumentSchema: {
      'type': 'object',
      'properties': {
        'format': {
          'type': 'string',
          'enum': ['markdown', 'plain'],
        },
        'instruction': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      },
      'required': ['format', 'instruction'],
    },
    artifactKind: artifactKind,
    artifactSchemaVersion: 1,
    displayNameKey: 'ai.action.testBookExport',
  );
}

class AiTestBookExportWorkflowAdapter implements AiWorkflowAdapter {
  AiTestBookExportWorkflowAdapter({required this.artifacts});

  @override
  String get actionKind => AiTestBookExportProductActions.actionKind;

  final AiArtifactRepository artifacts;
  final Set<String> _cancelRequested = {};
  final Set<String> _active = {};

  @override
  Future<AiWorkflowPreflightResult> preflight(
    AiAuthorizedCommand command,
    AiWorkflowEnvironment environment,
  ) async {
    if (command.actionKind != actionKind) {
      return const AiWorkflowPreflightResult.rejected('action_kind_mismatch');
    }
    final format = '${command.arguments['format'] ?? ''}';
    if (format != 'markdown' && format != 'plain') {
      return const AiWorkflowPreflightResult.rejected('invalid_export_format');
    }
    return const AiWorkflowPreflightResult.accepted();
  }

  @override
  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  ) async* {
    yield* _run(command, context.workflowRunId, context.attempt, context);
  }

  @override
  Stream<AiWorkflowEvent> recover(AiWorkflowRecoveryRequest request) async* {
    final existing = request.checkpoint?.payload['artifactRef'];
    if (existing is String && existing.isNotEmpty) {
      final envelope = await artifacts.read(existing);
      if (envelope != null) {
        yield AiWorkflowSucceeded(
          workflowRunId: request.workflowRunId,
          sequence: 1,
          attempt: request.attempt,
          artifactRefs: [existing],
        );
        return;
      }
    }
    yield* _run(
      request.command,
      request.workflowRunId,
      request.attempt,
      AiWorkflowRunContext(
        workflowRunId: request.workflowRunId,
        attempt: request.attempt,
        environment: request.environment,
        cancelToken: CancelToken(),
      ),
    );
  }

  Stream<AiWorkflowEvent> _run(
    AiAuthorizedCommand command,
    String workflowRunId,
    int attempt,
    AiWorkflowRunContext context,
  ) async* {
    _active.add(workflowRunId);
    try {
      yield AiWorkflowAccepted(
        workflowRunId: workflowRunId,
        sequence: 1,
        attempt: attempt,
      );
      if (_cancelRequested.contains(workflowRunId) ||
          context.cancelToken.isCancelled) {
        yield AiWorkflowCancelled(
          workflowRunId: workflowRunId,
          sequence: 2,
          attempt: attempt,
        );
        return;
      }

      final artifactId = 'export:${command.commandId}';
      final prior = await artifacts.read(artifactId);
      if (prior != null) {
        yield AiWorkflowArtifactReady(
          workflowRunId: workflowRunId,
          sequence: 2,
          attempt: attempt,
          artifactRef: artifactId,
        );
        yield AiWorkflowSucceeded(
          workflowRunId: workflowRunId,
          sequence: 3,
          attempt: attempt,
          artifactRefs: [artifactId],
        );
        return;
      }

      final format = '${command.arguments['format'] ?? 'markdown'}';
      final body = command.originalUserText;
      final committed = await artifacts.commit(
        AiArtifactEnvelope(
          artifactId: artifactId,
          kind: AiTestBookExportProductActions.artifactKind,
          schemaVersion: 1,
          revision: 1,
          contentHash: command.contentHash ?? command.idempotencyKey,
          payload: {
            'format': format,
            'body': body,
            'instruction': '${command.arguments['instruction'] ?? ''}',
          },
          createdAt: context.environment.now(),
        ),
      );

      yield AiWorkflowCheckpointCommitted(
        workflowRunId: workflowRunId,
        sequence: 2,
        attempt: attempt,
        checkpoint: AiWorkflowCheckpoint(
          checkpointId: '$workflowRunId:export',
          workflowRunId: workflowRunId,
          attempt: attempt,
          workflowVersion: command.workflowVersion,
          stageId: 'exported',
          payload: {'artifactRef': committed.artifactId},
          createdAt: context.environment.now(),
        ),
      );
      yield AiWorkflowArtifactReady(
        workflowRunId: workflowRunId,
        sequence: 3,
        attempt: attempt,
        artifactRef: committed.artifactId,
      );
      yield AiWorkflowSucceeded(
        workflowRunId: workflowRunId,
        sequence: 4,
        attempt: attempt,
        artifactRefs: [committed.artifactId],
      );
    } finally {
      _active.remove(workflowRunId);
      _cancelRequested.remove(workflowRunId);
    }
  }

  @override
  Future<void> requestCancel(String workflowRunId, String reason) async {
    _cancelRequested.add(workflowRunId);
  }

  @override
  Future<AiWorkflowInspection> inspect(String workflowRunId) async =>
      AiWorkflowInspection(
        workflowRunId: workflowRunId,
        active: _active.contains(workflowRunId),
      );
}

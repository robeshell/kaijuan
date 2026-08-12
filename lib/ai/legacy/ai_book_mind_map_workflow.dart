export '../ai_book_mind_map_artifact.dart';

import '../ai_book_mind_map_artifact.dart';
import '../ai_book_mind_map_product_actions.dart';
import '../ai_book_structure.dart';
import '../ai_cancel.dart';
import '../ai_chat_retrieve.dart';
import '../ai_mind_map.dart';
import '../ai_product_action_protocol.dart';
import '../ai_workflow_contract.dart';

// ignore_for_file: public_member_api_docs
/// **Legacy / test-only** mind-map Product Workflow adapter.
///
/// Production mind maps use [BookAiWorkspaceController.runMindMapSession]
/// (chat session path). This adapter remains for protocol/fault-injection
/// tests and historical platform proofs — do not wire it into production domains.
/// Run-scoped inputs that cannot live on the immutable command (full section
/// text, generation callbacks). Staged immediately before executor start.
///
/// Intentionally has **no** conversation projector: adapters only produce
/// domain artifacts; App projects after Receipt.
class AiBookMindMapStagedRun {
  const AiBookMindMapStagedRun({
    required this.units,
    required this.userInstruction,
    required this.publicationTitle,
    required this.generateUnit,
    this.baseMap,
    this.onProgress,
  });

  final List<
    ({AiBookWork? work, String label, List<AiBookSectionSlice> sections})
  >
  units;
  final String userInstruction;
  final String publicationTitle;
  final AiBookMindMap? baseMap;
  final Future<AiBookMindMap?> Function({
    required AiBookWork? work,
    required String label,
    required List<AiBookSectionSlice> sections,
    required String progressLabel,
    required CancelToken cancelToken,
  })
  generateUnit;
  final void Function(String progress)? onProgress;
}

/// Deterministic domain Workflow for create/revise book mind maps.
class AiBookMindMapWorkflowAdapter implements AiWorkflowAdapter {
  AiBookMindMapWorkflowAdapter({
    required this.actionKind,
    required this.artifacts,
  });

  @override
  final String actionKind;
  final AiArtifactRepository artifacts;

  final Map<String, AiBookMindMapStagedRun> _staged = {};
  final Map<String, bool> _cancelRequested = {};
  final Map<String, bool> _active = {};

  void stage(String commandId, AiBookMindMapStagedRun run) {
    _staged[commandId] = run;
  }

  AiBookMindMapStagedRun? takeStaged(String commandId) =>
      _staged.remove(commandId);

  @override
  Future<AiWorkflowPreflightResult> preflight(
    AiAuthorizedCommand command,
    AiWorkflowEnvironment environment,
  ) async {
    if (command.actionKind != actionKind) {
      return const AiWorkflowPreflightResult.rejected('action_kind_mismatch');
    }
    if (command.commandSchemaVersion !=
            AiBookMindMapProductActions.create.commandSchemaVersion &&
        command.commandSchemaVersion !=
            AiBookMindMapProductActions.revise.commandSchemaVersion) {
      return const AiWorkflowPreflightResult.rejected(
        'incompatible_command_schema',
      );
    }
    if (command.workflowVersion !=
            AiBookMindMapProductActions.create.workflowVersion &&
        command.workflowVersion !=
            AiBookMindMapProductActions.revise.workflowVersion) {
      return const AiWorkflowPreflightResult.rejected(
        'incompatible_workflow_version',
      );
    }
    if (command.scopeSectionIndices.isEmpty) {
      return const AiWorkflowPreflightResult.rejected('missing_frozen_scope');
    }
    if (actionKind == AiBookMindMapProductActions.revise.actionKind &&
        (command.targetArtifactId == null ||
            command.expectedRevision == null)) {
      return const AiWorkflowPreflightResult.rejected(
        'missing_revision_target',
      );
    }
    return const AiWorkflowPreflightResult.accepted();
  }

  @override
  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  ) async* {
    yield* _run(
      command: command,
      workflowRunId: context.workflowRunId,
      attempt: context.attempt,
      cancelToken: context.cancelToken,
      environment: context.environment,
      checkpoint: null,
    );
  }

  @override
  Stream<AiWorkflowEvent> recover(AiWorkflowRecoveryRequest request) async* {
    yield* _run(
      command: request.command,
      workflowRunId: request.workflowRunId,
      attempt: request.attempt,
      cancelToken: CancelToken(),
      environment: request.environment,
      checkpoint: request.checkpoint,
    );
  }

  Stream<AiWorkflowEvent> _run({
    required AiAuthorizedCommand command,
    required String workflowRunId,
    required int attempt,
    required CancelToken cancelToken,
    required AiWorkflowEnvironment environment,
    required AiWorkflowCheckpoint? checkpoint,
  }) async* {
    _active[workflowRunId] = true;
    _cancelRequested[workflowRunId] = false;
    var sequence = 0;
    int nextSequence() => ++sequence;

    try {
      yield AiWorkflowAccepted(
        workflowRunId: workflowRunId,
        sequence: nextSequence(),
        attempt: attempt,
      );

      // Prefer durable checkpoint; if missing, recover orphaned artifacts that
      // were committed before the checkpoint write.
      var recoveredRefs = _artifactRefsFromCheckpoint(checkpoint);
      var unitTotal = (checkpoint?.payload['unitTotal'] as num?)?.toInt() ?? 0;
      if (recoveredRefs.isEmpty) {
        final orphaned = await artifacts.listByCommandPrefix(command.commandId);
        if (orphaned.isNotEmpty) {
          recoveredRefs = [for (final item in orphaned) item.artifactId];
          unitTotal = orphaned.length;
        }
      }

      final staged = _staged[command.commandId];
      final expectedTotal = staged?.units.length ?? unitTotal;

      if (recoveredRefs.isNotEmpty &&
          expectedTotal > 0 &&
          recoveredRefs.length >= expectedTotal) {
        final verified = <String>[];
        for (final ref in recoveredRefs.take(expectedTotal)) {
          final existing = await artifacts.read(ref);
          if (existing == null) {
            verified.clear();
            break;
          }
          verified.add(ref);
        }
        if (verified.length == expectedTotal) {
          for (final ref in verified) {
            yield AiWorkflowArtifactReady(
              workflowRunId: workflowRunId,
              sequence: nextSequence(),
              attempt: attempt,
              artifactRef: ref,
            );
          }
          yield AiWorkflowSucceeded(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
            artifactRefs: verified,
          );
          return;
        }
      }

      if (staged == null) {
        if (recoveredRefs.isNotEmpty) {
          // Partial orphans without staged input: surface what we have.
          yield AiWorkflowPartiallySucceeded(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
            artifactRefs: recoveredRefs,
            publicErrorCode: 'workflow_input_missing_after_partial_commit',
          );
          return;
        }
        yield AiWorkflowFailed(
          workflowRunId: workflowRunId,
          sequence: nextSequence(),
          attempt: attempt,
          publicErrorCode: 'workflow_input_missing',
        );
        return;
      }

      final startUnit =
          (checkpoint?.payload['completedUnits'] as num?)?.toInt() ??
          recoveredRefs.length;
      final artifactRefs = List<String>.from(recoveredRefs.take(startUnit));
      final total = staged.units.length;

      yield AiWorkflowStageStarted(
        workflowRunId: workflowRunId,
        sequence: nextSequence(),
        attempt: attempt,
        stageId: 'generate',
        stageVersion: command.workflowVersion,
      );

      for (var index = startUnit; index < total; index++) {
        if (_isCancelled(workflowRunId, cancelToken)) {
          yield AiWorkflowCancelled(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
          );
          return;
        }

        final unit = staged.units[index];
        final progress = total == 1
            ? '正在为你生成《${staged.publicationTitle}》中的《${unit.label}》的思维导图'
            : '本书共 $total 个范围，正在生成第 ${index + 1}/$total 个范围《${unit.label}》';
        staged.onProgress?.call(progress);
        yield AiWorkflowProgress(
          workflowRunId: workflowRunId,
          sequence: nextSequence(),
          attempt: attempt,
          current: index + 1,
          total: total,
          unit: 'scope',
          messageKey: 'mind_map.generating',
        );

        final artifactId = '${command.commandId}-mind-map-${index + 1}';
        // Crash window: artifact committed, checkpoint not yet written.
        final existing = await artifacts.read(artifactId);
        if (existing != null) {
          artifactRefs.add(existing.artifactId);
          yield AiWorkflowCheckpointCommitted(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
            checkpoint: AiWorkflowCheckpoint(
              checkpointId: '$workflowRunId:unit-${index + 1}',
              workflowRunId: workflowRunId,
              attempt: attempt,
              workflowVersion: command.workflowVersion,
              stageId: 'unit_committed',
              payload: {
                'completedUnits': index + 1,
                'unitTotal': total,
                'artifactRefs': List<String>.from(artifactRefs),
              },
              createdAt: environment.now(),
            ),
          );
          yield AiWorkflowArtifactReady(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
            artifactRef: existing.artifactId,
          );
          continue;
        }

        final result = await staged.generateUnit(
          work: unit.work,
          label: unit.label,
          sections: unit.sections,
          progressLabel: progress,
          cancelToken: cancelToken,
        );

        if (_isCancelled(workflowRunId, cancelToken)) {
          yield AiWorkflowCancelled(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
          );
          return;
        }

        if (result == null) {
          if (artifactRefs.isEmpty) {
            yield AiWorkflowFailed(
              workflowRunId: workflowRunId,
              sequence: nextSequence(),
              attempt: attempt,
              publicErrorCode: 'mind_map_generation_failed',
            );
          } else {
            yield AiWorkflowPartiallySucceeded(
              workflowRunId: workflowRunId,
              sequence: nextSequence(),
              attempt: attempt,
              artifactRefs: List.unmodifiable(artifactRefs),
              publicErrorCode: 'mind_map_partial_failure',
            );
          }
          return;
        }

        // Re-check cancel after model returns, before any durable side effect.
        if (_isCancelled(workflowRunId, cancelToken)) {
          yield AiWorkflowCancelled(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
          );
          return;
        }

        final base = staged.baseMap;
        final isRevise =
            actionKind == AiBookMindMapProductActions.revise.actionKind;
        final lineageRootId = isRevise
            ? (command.targetArtifactId == null
                  ? AiBookMindMapArtifactCodec.lineageRootOf(base!)
                  : (base != null
                        ? AiBookMindMapArtifactCodec.lineageRootOf(base)
                        : command.targetArtifactId!))
            : artifactId;
        final revision = isRevise ? (command.expectedRevision! + 1) : 1;

        // Order: content Artifact first, then lineage head CAS.
        // Head must never point at a missing Artifact. Cancel/crash after
        // content write leaves an orphan content file recoverable by
        // commandId prefix; head stays on the previous valid revision.
        if (isRevise) {
          final baseRevision = command.expectedRevision!;
          final currentHead = await artifacts.readLineageHead(lineageRootId);
          if (currentHead == null) {
            try {
              await artifacts.commitLineageHead(
                AiArtifactLineageHead(
                  lineageRootId: lineageRootId,
                  headArtifactId: command.targetArtifactId!,
                  revision: baseRevision,
                  updatedAt: environment.now(),
                ),
                expectedRevision: null,
              );
            } on AiArtifactRevisionConflict {
              // Concurrent worker seeded the head from the existing target.
            }
          } else if (currentHead.revision != baseRevision) {
            yield AiWorkflowFailed(
              workflowRunId: workflowRunId,
              sequence: nextSequence(),
              attempt: attempt,
              publicErrorCode: 'mind_map_revision_conflict',
            );
            return;
          }
        }

        if (_isCancelled(workflowRunId, cancelToken)) {
          yield AiWorkflowCancelled(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
          );
          return;
        }

        final committed = await artifacts.commit(
          AiBookMindMapArtifactCodec.envelopeFor(
            map: result.copyWith(
              artifactId: artifactId,
              sourceArtifactId: base == null
                  ? null
                  : base.artifactId ?? 'mind-map:${base.scopeFingerprint}',
              revision: revision,
            ),
            artifactId: artifactId,
            lineageRootId: lineageRootId,
            revision: revision,
            createdAt: environment.now(),
          ),
        );

        if (_isCancelled(workflowRunId, cancelToken)) {
          // Content exists but head was not advanced — safe orphan.
          yield AiWorkflowCancelled(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
          );
          return;
        }

        try {
          if (isRevise) {
            await artifacts.commitLineageHead(
              AiArtifactLineageHead(
                lineageRootId: lineageRootId,
                headArtifactId: artifactId,
                revision: revision,
                updatedAt: environment.now(),
              ),
              expectedRevision: command.expectedRevision,
            );
          } else {
            await artifacts.commitLineageHead(
              AiArtifactLineageHead(
                lineageRootId: lineageRootId,
                headArtifactId: artifactId,
                revision: 1,
                updatedAt: environment.now(),
              ),
              expectedRevision: null,
            );
          }
        } on AiArtifactRevisionConflict {
          yield AiWorkflowFailed(
            workflowRunId: workflowRunId,
            sequence: nextSequence(),
            attempt: attempt,
            publicErrorCode: 'mind_map_revision_conflict',
          );
          return;
        }
        artifactRefs.add(committed.artifactId);

        // Checkpoint before Receipt. Conversation projection happens only
        // after the executor commits a terminal Receipt.
        yield AiWorkflowCheckpointCommitted(
          workflowRunId: workflowRunId,
          sequence: nextSequence(),
          attempt: attempt,
          checkpoint: AiWorkflowCheckpoint(
            checkpointId: '$workflowRunId:unit-${index + 1}',
            workflowRunId: workflowRunId,
            attempt: attempt,
            workflowVersion: command.workflowVersion,
            stageId: 'unit_committed',
            payload: {
              'completedUnits': index + 1,
              'unitTotal': total,
              'artifactRefs': List<String>.from(artifactRefs),
            },
            createdAt: environment.now(),
          ),
        );
        yield AiWorkflowArtifactReady(
          workflowRunId: workflowRunId,
          sequence: nextSequence(),
          attempt: attempt,
          artifactRef: committed.artifactId,
        );
      }

      if (_isCancelled(workflowRunId, cancelToken)) {
        yield AiWorkflowCancelled(
          workflowRunId: workflowRunId,
          sequence: nextSequence(),
          attempt: attempt,
        );
        return;
      }

      yield AiWorkflowSucceeded(
        workflowRunId: workflowRunId,
        sequence: nextSequence(),
        attempt: attempt,
        artifactRefs: List.unmodifiable(artifactRefs),
      );
    } finally {
      _active.remove(workflowRunId);
      _cancelRequested.remove(workflowRunId);
      _staged.remove(command.commandId);
    }
  }

  @override
  Future<void> requestCancel(String workflowRunId, String reason) async {
    _cancelRequested[workflowRunId] = true;
  }

  @override
  Future<AiWorkflowInspection> inspect(String workflowRunId) async =>
      AiWorkflowInspection(
        workflowRunId: workflowRunId,
        active: _active[workflowRunId] == true,
        stageId: _active[workflowRunId] == true ? 'generate' : null,
      );

  bool _isCancelled(String workflowRunId, CancelToken token) =>
      token.isCancelled || _cancelRequested[workflowRunId] == true;

  List<String> _artifactRefsFromCheckpoint(AiWorkflowCheckpoint? checkpoint) {
    final raw = checkpoint?.payload['artifactRefs'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }
}

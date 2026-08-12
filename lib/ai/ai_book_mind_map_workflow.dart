import 'ai_book_mind_map_product_actions.dart';
import 'ai_book_structure.dart';
import 'ai_cancel.dart';
import 'ai_chat_retrieve.dart';
import 'ai_mind_map.dart';
import 'ai_product_action_protocol.dart';
import 'ai_workflow_contract.dart';

/// Strong-typed domain payload for a book mind map, carried inside the generic
/// [AiArtifactEnvelope] only as serialized metadata. Domain code keeps using
/// [AiBookMindMap] rather than raw maps.
abstract final class AiBookMindMapArtifactCodec {
  static const kind = 'book_mind_map';

  static Map<String, Object?> encode(AiBookMindMap map) => map.toJson();

  static AiBookMindMap? decode(Map<String, Object?> payload) =>
      AiBookMindMap.fromJson(payload);

  static AiArtifactEnvelope envelopeFor({
    required AiBookMindMap map,
    required String artifactId,
    required int revision,
    required DateTime createdAt,
  }) {
    final body = map.copyWith(artifactId: artifactId, revision: revision);
    return AiArtifactEnvelope(
      artifactId: artifactId,
      kind: kind,
      schemaVersion:
          AiBookMindMapProductActions.create.artifactSchemaVersion ?? 1,
      revision: revision,
      contentHash: body.contentHash,
      payload: encode(body),
      createdAt: createdAt,
    );
  }
}

/// Run-scoped inputs that cannot live on the immutable command (full section
/// text, generation callbacks). Staged immediately before executor start.
class AiBookMindMapStagedRun {
  const AiBookMindMapStagedRun({
    required this.units,
    required this.userInstruction,
    required this.publicationTitle,
    required this.generateUnit,
    this.baseMap,
    this.onArtifact,
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
  final Future<void> Function(AiBookMindMap artifact)? onArtifact;
  final void Function(String progress)? onProgress;
}

/// Deterministic domain Workflow for create/revise book mind maps.
///
/// Genkit is only used inside the injected generation callback for structured
/// model output. Authorization, journal, artifact CAS and receipts stay App-
/// owned.
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

      final recoveredRefs = _artifactRefsFromCheckpoint(checkpoint);
      if (recoveredRefs.isNotEmpty) {
        final verified = <String>[];
        for (final ref in recoveredRefs) {
          final existing = await artifacts.read(ref);
          if (existing == null) {
            verified.clear();
            break;
          }
          verified.add(ref);
          final map = AiBookMindMapArtifactCodec.decode(existing.payload);
          if (map != null) {
            await _staged[command.commandId]?.onArtifact?.call(map);
          }
        }
        if (verified.isNotEmpty &&
            verified.length ==
                (checkpoint?.payload['unitTotal'] as num?)?.toInt()) {
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

      final staged = _staged[command.commandId];
      if (staged == null) {
        yield AiWorkflowFailed(
          workflowRunId: workflowRunId,
          sequence: nextSequence(),
          attempt: attempt,
          publicErrorCode: 'workflow_input_missing',
        );
        return;
      }

      final startUnit =
          (checkpoint?.payload['completedUnits'] as num?)?.toInt() ?? 0;
      final artifactRefs = List<String>.from(recoveredRefs);
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

        final artifactId = '${command.commandId}-mind-map-${index + 1}';
        final revision = staged.baseMap == null
            ? 1
            : staged.baseMap!.revision + 1;
        final base = staged.baseMap;
        // Each mind-map generation writes a new artifact id (lineage via
        // sourceArtifactId + revision). CAS expectedRevision applies only when
        // overwriting an existing id; new ids always start from absence.
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
            revision: revision,
            createdAt: environment.now(),
          ),
        );
        final map = AiBookMindMapArtifactCodec.decode(committed.payload)!;
        artifactRefs.add(committed.artifactId);
        await staged.onArtifact?.call(map);

        final checkpointPayload = <String, Object?>{
          'completedUnits': index + 1,
          'unitTotal': total,
          'artifactRefs': List<String>.from(artifactRefs),
        };
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
            payload: checkpointPayload,
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

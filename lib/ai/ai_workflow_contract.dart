import 'ai_cancel.dart';
import 'ai_product_action_protocol.dart';

/// A domain-neutral execution event. Workflow adapters publish facts; they do
/// not publish assistant prose or UI widgets.
sealed class AiWorkflowEvent {
  const AiWorkflowEvent({
    required this.workflowRunId,
    required this.sequence,
    required this.attempt,
  });

  final String workflowRunId;
  final int sequence;
  final int attempt;
}

final class AiWorkflowAccepted extends AiWorkflowEvent {
  const AiWorkflowAccepted({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
  });
}

final class AiWorkflowStageStarted extends AiWorkflowEvent {
  const AiWorkflowStageStarted({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.stageId,
    required this.stageVersion,
  });

  final String stageId;
  final int stageVersion;
}

final class AiWorkflowProgress extends AiWorkflowEvent {
  const AiWorkflowProgress({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.current,
    required this.total,
    required this.unit,
    this.messageKey,
  });

  final int current;
  final int total;
  final String unit;
  final String? messageKey;
}

final class AiWorkflowCheckpointCommitted extends AiWorkflowEvent {
  const AiWorkflowCheckpointCommitted({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.checkpoint,
  });

  final AiWorkflowCheckpoint checkpoint;
}

final class AiWorkflowArtifactReady extends AiWorkflowEvent {
  const AiWorkflowArtifactReady({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.artifactRef,
  });

  final String artifactRef;
}

final class AiWorkflowSucceeded extends AiWorkflowEvent {
  const AiWorkflowSucceeded({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.artifactRefs,
  });

  final List<String> artifactRefs;
}

final class AiWorkflowPartiallySucceeded extends AiWorkflowEvent {
  const AiWorkflowPartiallySucceeded({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.artifactRefs,
    required this.publicErrorCode,
  });

  final List<String> artifactRefs;
  final String publicErrorCode;
}

final class AiWorkflowFailed extends AiWorkflowEvent {
  const AiWorkflowFailed({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
    required this.publicErrorCode,
  });

  final String publicErrorCode;
}

final class AiWorkflowCancelled extends AiWorkflowEvent {
  const AiWorkflowCancelled({
    required super.workflowRunId,
    required super.sequence,
    required super.attempt,
  });
}

class AiWorkflowCheckpoint {
  const AiWorkflowCheckpoint({
    required this.checkpointId,
    required this.workflowRunId,
    required this.attempt,
    required this.workflowVersion,
    required this.stageId,
    required this.payload,
    required this.createdAt,
  });

  final String checkpointId;
  final String workflowRunId;
  final int attempt;
  final int workflowVersion;
  final String stageId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

abstract interface class AiWorkflowCheckpointStore {
  Future<void> write(AiWorkflowCheckpoint checkpoint);
  Future<AiWorkflowCheckpoint?> readLatest(String workflowRunId);
}

class MemoryAiWorkflowCheckpointStore implements AiWorkflowCheckpointStore {
  final Map<String, AiWorkflowCheckpoint> _latest = {};

  @override
  Future<void> write(AiWorkflowCheckpoint checkpoint) async {
    final current = _latest[checkpoint.workflowRunId];
    if (current != null && current.attempt > checkpoint.attempt) return;
    _latest[checkpoint.workflowRunId] = checkpoint;
  }

  @override
  Future<AiWorkflowCheckpoint?> readLatest(String workflowRunId) async =>
      _latest[workflowRunId];
}

class AiWorkflowPreflightResult {
  const AiWorkflowPreflightResult.accepted({this.environmentFingerprint})
    : accepted = true,
      publicErrorCode = null;

  const AiWorkflowPreflightResult.rejected(this.publicErrorCode)
    : accepted = false,
      environmentFingerprint = null;

  final bool accepted;
  final String? publicErrorCode;
  final String? environmentFingerprint;
}

class AiWorkflowEnvironment {
  const AiWorkflowEnvironment({
    required this.capabilities,
    required this.checkpoints,
    required this.now,
  });

  final AiCapabilitySet capabilities;
  final AiWorkflowCheckpointStore checkpoints;
  final DateTime Function() now;
}

class AiWorkflowRecoveryRequest {
  const AiWorkflowRecoveryRequest({
    required this.command,
    required this.workflowRunId,
    required this.attempt,
    required this.environment,
    this.checkpoint,
  });

  final AiAuthorizedCommand command;
  final String workflowRunId;
  final int attempt;
  final AiWorkflowEnvironment environment;
  final AiWorkflowCheckpoint? checkpoint;
}

abstract interface class AiWorkflowAdapter {
  String get actionKind;

  Future<AiWorkflowPreflightResult> preflight(
    AiAuthorizedCommand command,
    AiWorkflowEnvironment environment,
  );

  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  );

  Stream<AiWorkflowEvent> recover(AiWorkflowRecoveryRequest request);

  Future<void> requestCancel(String workflowRunId, String reason);

  Future<AiWorkflowInspection> inspect(String workflowRunId);
}

class AiWorkflowRunContext {
  const AiWorkflowRunContext({
    required this.workflowRunId,
    required this.attempt,
    required this.environment,
    required this.cancelToken,
  });

  final String workflowRunId;
  final int attempt;
  final AiWorkflowEnvironment environment;
  final CancelToken cancelToken;
}

class AiWorkflowInspection {
  const AiWorkflowInspection({
    required this.workflowRunId,
    required this.active,
    this.stageId,
    this.messageKey,
  });

  final String workflowRunId;
  final bool active;
  final String? stageId;
  final String? messageKey;
}

/// Versioned output envelope shared by Workflow products. The repository
/// stores the immutable payload; a conversation may only project its ref.
class AiArtifactEnvelope {
  const AiArtifactEnvelope({
    required this.artifactId,
    required this.kind,
    required this.schemaVersion,
    required this.revision,
    required this.contentHash,
    required this.payload,
    required this.createdAt,
  });

  final String artifactId;
  final String kind;
  final int schemaVersion;
  final int revision;
  final String contentHash;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

abstract interface class AiArtifactRepository {
  Future<AiArtifactEnvelope?> read(String artifactId);

  Future<AiArtifactEnvelope> commit(
    AiArtifactEnvelope artifact, {
    int? expectedRevision,
  });
}

class MemoryAiArtifactRepository implements AiArtifactRepository {
  final Map<String, AiArtifactEnvelope> _artifacts = {};

  @override
  Future<AiArtifactEnvelope?> read(String artifactId) async =>
      _artifacts[artifactId];

  @override
  Future<AiArtifactEnvelope> commit(
    AiArtifactEnvelope artifact, {
    int? expectedRevision,
  }) async {
    final current = _artifacts[artifact.artifactId];
    if (expectedRevision != null &&
        (current == null || current.revision != expectedRevision)) {
      throw StateError('Artifact revision conflict: ${artifact.artifactId}');
    }
    if (current != null && artifact.revision <= current.revision) {
      throw StateError('Artifact revision must increase');
    }
    _artifacts[artifact.artifactId] = artifact;
    return artifact;
  }
}

class AiWorkflowAdapterRegistry {
  AiWorkflowAdapterRegistry(Iterable<AiWorkflowAdapter> adapters)
    : _adapters = _index(adapters);

  final Map<String, AiWorkflowAdapter> _adapters;

  AiWorkflowAdapter? lookup(String actionKind) => _adapters[actionKind];

  static Map<String, AiWorkflowAdapter> _index(
    Iterable<AiWorkflowAdapter> source,
  ) {
    final result = <String, AiWorkflowAdapter>{};
    for (final adapter in source) {
      if (result.containsKey(adapter.actionKind)) {
        throw ArgumentError(
          'Duplicate workflow adapter: ${adapter.actionKind}',
        );
      }
      result[adapter.actionKind] = adapter;
    }
    return Map.unmodifiable(result);
  }
}

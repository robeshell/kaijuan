import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The source of a product-action proposal. A model can only propose; an
/// explicit App gesture may be eligible for immediate authorization.
enum AiActionProposalSource { modelTool, explicitUi }

enum AiActionRiskClass { read, reversible, external, destructive }

enum AiActionDecisionOutcome {
  allow,
  requireConfirmation,
  requireClarification,
  deny,
}

/// Durable control-plane states. Domain artifacts and chat messages are not
/// journal entries; they are committed only after the command is authorized.
enum AiActionJournalStatus {
  proposed,
  awaitingConfirmation,
  awaitingClarification,
  authorized,
  queued,
  executing,
  cancelRequested,
  succeeded,
  partiallySucceeded,
  failed,
  cancelled,
  rejected,
  expired,
  abandoned,
}

extension AiActionJournalStatusX on AiActionJournalStatus {
  bool get isTerminal => switch (this) {
    AiActionJournalStatus.succeeded ||
    AiActionJournalStatus.partiallySucceeded ||
    AiActionJournalStatus.failed ||
    AiActionJournalStatus.cancelled ||
    AiActionJournalStatus.rejected ||
    AiActionJournalStatus.expired ||
    AiActionJournalStatus.abandoned => true,
    _ => false,
  };
}

class AiActionProposal {
  const AiActionProposal({
    required this.protocolVersion,
    required this.proposalId,
    required this.parentRunId,
    required this.conversationId,
    required this.turnId,
    required this.actionKind,
    required this.definitionVersion,
    required this.proposalSchemaVersion,
    required this.source,
    required this.sourceSubmissionId,
    required this.originalUserText,
    required this.requestedArguments,
    required this.createdAt,
    required this.expiresAt,
    this.scopeRef,
    this.targetRef,
    this.expectedRevision,
    this.frozenContextRef,
    this.capabilitySnapshotRef,
  });

  static const currentProtocolVersion = 1;

  final int protocolVersion;
  final String proposalId;
  final String? parentRunId;
  final String? conversationId;
  final String? turnId;
  final String actionKind;
  final int definitionVersion;
  final int proposalSchemaVersion;
  final AiActionProposalSource source;
  final String sourceSubmissionId;
  final String originalUserText;
  final Map<String, Object?> requestedArguments;
  final String? scopeRef;
  final String? targetRef;
  final int? expectedRevision;
  final String? frozenContextRef;
  final String? capabilitySnapshotRef;
  final DateTime createdAt;
  final DateTime expiresAt;

  AiActionProposal copyWith({String? capabilitySnapshotRef}) =>
      AiActionProposal(
        protocolVersion: protocolVersion,
        proposalId: proposalId,
        parentRunId: parentRunId,
        conversationId: conversationId,
        turnId: turnId,
        actionKind: actionKind,
        definitionVersion: definitionVersion,
        proposalSchemaVersion: proposalSchemaVersion,
        source: source,
        sourceSubmissionId: sourceSubmissionId,
        originalUserText: originalUserText,
        requestedArguments: requestedArguments,
        scopeRef: scopeRef,
        targetRef: targetRef,
        expectedRevision: expectedRevision,
        frozenContextRef: frozenContextRef,
        capabilitySnapshotRef:
            capabilitySnapshotRef ?? this.capabilitySnapshotRef,
        createdAt: createdAt,
        expiresAt: expiresAt,
      );

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'proposalId': proposalId,
    if (parentRunId != null) 'parentRunId': parentRunId,
    if (conversationId != null) 'conversationId': conversationId,
    if (turnId != null) 'turnId': turnId,
    'actionKind': actionKind,
    'definitionVersion': definitionVersion,
    'proposalSchemaVersion': proposalSchemaVersion,
    'source': source.name,
    'sourceSubmissionId': sourceSubmissionId,
    'originalUserText': originalUserText,
    'requestedArguments': requestedArguments,
    if (scopeRef != null) 'scopeRef': scopeRef,
    if (targetRef != null) 'targetRef': targetRef,
    if (expectedRevision != null) 'expectedRevision': expectedRevision,
    if (frozenContextRef != null) 'frozenContextRef': frozenContextRef,
    if (capabilitySnapshotRef != null)
      'capabilitySnapshotRef': capabilitySnapshotRef,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  static AiActionProposal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final source = _enumValue(AiActionProposalSource.values, json['source']);
    final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${json['expiresAt'] ?? ''}');
    final args = json['requestedArguments'];
    if (source == null ||
        createdAt == null ||
        expiresAt == null ||
        args is! Map) {
      return null;
    }
    final proposalId = json['proposalId'];
    final actionKind = json['actionKind'];
    final submission = json['sourceSubmissionId'];
    final text = json['originalUserText'];
    if (proposalId is! String ||
        proposalId.isEmpty ||
        actionKind is! String ||
        actionKind.isEmpty ||
        submission is! String ||
        submission.isEmpty ||
        text is! String) {
      return null;
    }
    return AiActionProposal(
      protocolVersion: _int(json['protocolVersion']) ?? 1,
      proposalId: proposalId,
      parentRunId: _string(json['parentRunId']),
      conversationId: _string(json['conversationId']),
      turnId: _string(json['turnId']),
      actionKind: actionKind,
      definitionVersion: _int(json['definitionVersion']) ?? 1,
      proposalSchemaVersion: _int(json['proposalSchemaVersion']) ?? 1,
      source: source,
      sourceSubmissionId: submission,
      originalUserText: text,
      requestedArguments: Map<String, Object?>.from(args),
      scopeRef: _string(json['scopeRef']),
      targetRef: _string(json['targetRef']),
      expectedRevision: _int(json['expectedRevision']),
      frozenContextRef: _string(json['frozenContextRef']),
      capabilitySnapshotRef: _string(json['capabilitySnapshotRef']),
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

class AiActionDecision {
  const AiActionDecision({
    required this.proposalId,
    required this.outcome,
    required this.reasonCode,
    required this.riskClass,
    required this.decidedAt,
    this.resolvedActionKind,
    this.resolvedScope,
    this.resolvedTarget,
    this.normalizedArguments = const {},
    this.confirmationSummary,
    this.allowedHumanDecisions = const [],
  });

  final String proposalId;
  final AiActionDecisionOutcome outcome;
  final String reasonCode;
  final AiActionRiskClass riskClass;
  final String? resolvedActionKind;
  final String? resolvedScope;
  final String? resolvedTarget;
  final Map<String, Object?> normalizedArguments;
  final String? confirmationSummary;
  final List<String> allowedHumanDecisions;
  final DateTime decidedAt;

  Map<String, Object?> toJson() => {
    'proposalId': proposalId,
    'outcome': outcome.name,
    'reasonCode': reasonCode,
    'riskClass': riskClass.name,
    if (resolvedActionKind != null) 'resolvedActionKind': resolvedActionKind,
    if (resolvedScope != null) 'resolvedScope': resolvedScope,
    if (resolvedTarget != null) 'resolvedTarget': resolvedTarget,
    'normalizedArguments': normalizedArguments,
    if (confirmationSummary != null) 'confirmationSummary': confirmationSummary,
    'allowedHumanDecisions': allowedHumanDecisions,
    'decidedAt': decidedAt.toUtc().toIso8601String(),
  };

  static AiActionDecision? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final outcome = _enumValue(AiActionDecisionOutcome.values, json['outcome']);
    final risk = _enumValue(AiActionRiskClass.values, json['riskClass']);
    final decidedAt = DateTime.tryParse('${json['decidedAt'] ?? ''}');
    final proposalId = json['proposalId'];
    if (outcome == null ||
        risk == null ||
        decidedAt == null ||
        proposalId is! String) {
      return null;
    }
    final args = json['normalizedArguments'];
    return AiActionDecision(
      proposalId: proposalId,
      outcome: outcome,
      reasonCode: '${json['reasonCode'] ?? ''}',
      riskClass: risk,
      resolvedActionKind: _string(json['resolvedActionKind']),
      resolvedScope: _string(json['resolvedScope']),
      resolvedTarget: _string(json['resolvedTarget']),
      normalizedArguments: args is Map
          ? Map<String, Object?>.from(args)
          : const {},
      confirmationSummary: _string(json['confirmationSummary']),
      allowedHumanDecisions:
          (json['allowedHumanDecisions'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      decidedAt: decidedAt,
    );
  }
}

class AiAuthorizedCommand {
  const AiAuthorizedCommand({
    required this.protocolVersion,
    required this.commandId,
    required this.proposalId,
    required this.actionKind,
    required this.definitionVersion,
    required this.commandSchemaVersion,
    required this.workflowVersion,
    required this.authorizationSource,
    required this.authorizationSubmissionId,
    required this.authorizationEvidence,
    required this.authorizedAt,
    required this.idempotencyKey,
    required this.arguments,
    required this.originalUserText,
    this.contentHash,
    this.workKey,
    this.scopeFingerprint,
    this.scopeSectionIndices = const [],
    this.targetArtifactId,
    this.expectedRevision,
  });

  final int protocolVersion;
  final String commandId;
  final String proposalId;
  final String actionKind;
  final int definitionVersion;
  final int commandSchemaVersion;
  final int workflowVersion;
  final AiActionProposalSource authorizationSource;
  final String authorizationSubmissionId;
  final String authorizationEvidence;
  final DateTime authorizedAt;
  final String idempotencyKey;
  final Map<String, Object?> arguments;
  final String originalUserText;
  final String? contentHash;
  final String? workKey;
  final String? scopeFingerprint;
  final List<int> scopeSectionIndices;
  final String? targetArtifactId;
  final int? expectedRevision;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'commandId': commandId,
    'proposalId': proposalId,
    'actionKind': actionKind,
    'definitionVersion': definitionVersion,
    'commandSchemaVersion': commandSchemaVersion,
    'workflowVersion': workflowVersion,
    'authorizationSource': authorizationSource.name,
    'authorizationSubmissionId': authorizationSubmissionId,
    'authorizationEvidence': authorizationEvidence,
    'authorizedAt': authorizedAt.toUtc().toIso8601String(),
    'idempotencyKey': idempotencyKey,
    'arguments': arguments,
    'originalUserText': originalUserText,
    if (contentHash != null) 'contentHash': contentHash,
    if (workKey != null) 'workKey': workKey,
    if (scopeFingerprint != null) 'scopeFingerprint': scopeFingerprint,
    'scopeSectionIndices': scopeSectionIndices,
    if (targetArtifactId != null) 'targetArtifactId': targetArtifactId,
    if (expectedRevision != null) 'expectedRevision': expectedRevision,
  };
}

class AiActionReceipt {
  const AiActionReceipt({
    required this.commandId,
    required this.workflowRunId,
    required this.attempt,
    required this.definitionVersion,
    required this.workflowVersion,
    required this.status,
    required this.finishedAt,
    this.artifactRefs = const [],
    this.publicErrorCode,
    this.diagnosticRef,
    this.startedAt,
  });

  final String commandId;
  final String workflowRunId;
  final int attempt;
  final int definitionVersion;
  final int workflowVersion;
  final AiActionJournalStatus status;
  final List<String> artifactRefs;
  final String? publicErrorCode;
  final String? diagnosticRef;
  final DateTime? startedAt;
  final DateTime finishedAt;

  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'workflowRunId': workflowRunId,
    'attempt': attempt,
    'definitionVersion': definitionVersion,
    'workflowVersion': workflowVersion,
    'status': status.name,
    'artifactRefs': artifactRefs,
    if (publicErrorCode != null) 'publicErrorCode': publicErrorCode,
    if (diagnosticRef != null) 'diagnosticRef': diagnosticRef,
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
  };
}

class AiActionJournalEntry {
  const AiActionJournalEntry({
    required this.proposal,
    required this.status,
    required this.stateVersion,
    required this.eventSequence,
    required this.updatedAt,
    this.decision,
    this.command,
    this.receipt,
    this.attempt = 0,
    this.terminalReasonCode,
  });

  factory AiActionJournalEntry.proposed(AiActionProposal proposal) =>
      AiActionJournalEntry(
        proposal: proposal,
        status: AiActionJournalStatus.proposed,
        stateVersion: 1,
        eventSequence: 0,
        updatedAt: proposal.createdAt,
      );

  final AiActionProposal proposal;
  final AiActionDecision? decision;
  final AiAuthorizedCommand? command;
  final AiActionReceipt? receipt;
  final AiActionJournalStatus status;
  final int stateVersion;
  final int eventSequence;
  final int attempt;
  final DateTime updatedAt;
  final String? terminalReasonCode;

  AiActionJournalEntry transition(
    AiActionJournalStatus next, {
    AiActionDecision? decision,
    AiAuthorizedCommand? command,
    AiActionReceipt? receipt,
    int? attempt,
    DateTime? now,
    String? terminalReasonCode,
  }) {
    if (this.command != null &&
        command != null &&
        jsonEncode(this.command!.toJson()) != jsonEncode(command.toJson())) {
      throw StateError('Authorized command is immutable');
    }
    if (this.receipt != null && receipt != null) {
      throw StateError('Action receipt is immutable');
    }
    if (receipt != null) {
      if (receipt.status != next) {
        throw StateError('Receipt status does not match journal transition');
      }
      if (!_terminalStatuses.contains(receipt.status)) {
        throw StateError('Only terminal receipts can be committed');
      }
      if (command == null && this.command == null) {
        throw StateError('Receipt requires an authorized command');
      }
      final effectiveCommand = command ?? this.command;
      if (effectiveCommand?.commandId != receipt.commandId) {
        throw StateError('Receipt command does not match journal command');
      }
    }
    if (next != status && !_allowedTransitions[status]!.contains(next)) {
      throw StateError(
        'Invalid action transition: ${status.name} -> ${next.name}',
      );
    }
    return AiActionJournalEntry(
      proposal: proposal,
      decision: decision ?? this.decision,
      command: command ?? this.command,
      receipt: receipt ?? this.receipt,
      status: next,
      stateVersion: stateVersion + 1,
      eventSequence: eventSequence + 1,
      attempt: attempt ?? this.attempt,
      updatedAt: now ?? DateTime.now(),
      terminalReasonCode: terminalReasonCode ?? this.terminalReasonCode,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'proposal': proposal.toJson(),
    if (decision != null) 'decision': decision!.toJson(),
    if (command != null) 'command': command!.toJson(),
    if (receipt != null) 'receipt': receipt!.toJson(),
    'status': status.name,
    'stateVersion': stateVersion,
    'eventSequence': eventSequence,
    'attempt': attempt,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (terminalReasonCode != null) 'terminalReasonCode': terminalReasonCode,
  };

  static AiActionJournalEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final proposal = AiActionProposal.fromJson(json['proposal']);
    final status = _enumValue(AiActionJournalStatus.values, json['status']);
    final updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    if (proposal == null || status == null || updatedAt == null) return null;
    final command = _commandFromJson(json['command']);
    return AiActionJournalEntry(
      proposal: proposal,
      decision: AiActionDecision.fromJson(json['decision']),
      command: command,
      receipt: _receiptFromJson(json['receipt']),
      status: status,
      stateVersion: _int(json['stateVersion']) ?? 1,
      eventSequence: _int(json['eventSequence']) ?? 0,
      attempt: _int(json['attempt']) ?? 0,
      updatedAt: updatedAt,
      terminalReasonCode: _string(json['terminalReasonCode']),
    );
  }

  static const _allowedTransitions =
      <AiActionJournalStatus, Set<AiActionJournalStatus>>{
        AiActionJournalStatus.proposed: {
          AiActionJournalStatus.awaitingConfirmation,
          AiActionJournalStatus.awaitingClarification,
          AiActionJournalStatus.authorized,
          AiActionJournalStatus.rejected,
          AiActionJournalStatus.expired,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.awaitingConfirmation: {
          AiActionJournalStatus.authorized,
          AiActionJournalStatus.rejected,
          AiActionJournalStatus.expired,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.awaitingClarification: {
          AiActionJournalStatus.rejected,
          AiActionJournalStatus.expired,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.authorized: {
          AiActionJournalStatus.queued,
          AiActionJournalStatus.cancelRequested,
          AiActionJournalStatus.failed,
          AiActionJournalStatus.cancelled,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.queued: {
          AiActionJournalStatus.executing,
          AiActionJournalStatus.cancelRequested,
          AiActionJournalStatus.failed,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.executing: {
          AiActionJournalStatus.cancelRequested,
          AiActionJournalStatus.succeeded,
          AiActionJournalStatus.partiallySucceeded,
          AiActionJournalStatus.failed,
          AiActionJournalStatus.cancelled,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.cancelRequested: {
          AiActionJournalStatus.cancelled,
          AiActionJournalStatus.failed,
          AiActionJournalStatus.abandoned,
        },
        AiActionJournalStatus.succeeded: {},
        AiActionJournalStatus.partiallySucceeded: {},
        AiActionJournalStatus.failed: {},
        AiActionJournalStatus.cancelled: {},
        AiActionJournalStatus.rejected: {},
        AiActionJournalStatus.expired: {},
        AiActionJournalStatus.abandoned: {},
      };

  static const _terminalStatuses = <AiActionJournalStatus>{
    AiActionJournalStatus.succeeded,
    AiActionJournalStatus.partiallySucceeded,
    AiActionJournalStatus.failed,
    AiActionJournalStatus.cancelled,
    AiActionJournalStatus.rejected,
    AiActionJournalStatus.expired,
    AiActionJournalStatus.abandoned,
  };
}

class AiCapabilitySet {
  const AiCapabilitySet(this.values);

  final Set<String> values;

  bool containsAll(Iterable<String> required) =>
      required.every(values.contains);

  String get fingerprint => sha256
      .convert(utf8.encode((values.toList()..sort()).join('|')))
      .toString();
}

class AiProductActionDefinition {
  const AiProductActionDefinition({
    required this.actionKind,
    required this.definitionVersion,
    required this.proposalSchemaVersion,
    required this.commandSchemaVersion,
    required this.workflowVersion,
    required this.riskClass,
    required this.supportedSources,
    this.requiredCapabilities = const {},
    this.optionalCapabilities = const {},
    this.anyOfCapabilities = const [],
    this.supportedScopes = const {},
    this.argumentSchema = const {},
    this.artifactKind,
    this.artifactSchemaVersion,
    this.toolDescription,
    this.toolName,
    this.displayNameKey = '',
  });

  final String actionKind;
  final int definitionVersion;
  final int proposalSchemaVersion;
  final int commandSchemaVersion;
  final int workflowVersion;
  final AiActionRiskClass riskClass;
  final Set<AiActionProposalSource> supportedSources;
  final Set<String> requiredCapabilities;
  final Set<String> optionalCapabilities;
  final List<Set<String>> anyOfCapabilities;
  final Set<String> supportedScopes;
  final Map<String, Object?> argumentSchema;
  final String? artifactKind;
  final int? artifactSchemaVersion;
  final String? toolDescription;
  final String? toolName;
  final String displayNameKey;
}

class AiProductActionRegistry {
  AiProductActionRegistry(Iterable<AiProductActionDefinition> definitions)
    : definitions = List.unmodifiable(definitions) {
    final kinds = <String>{};
    final tools = <String>{};
    for (final definition in this.definitions) {
      if (!kinds.add(definition.actionKind)) {
        throw ArgumentError('Duplicate action kind: ${definition.actionKind}');
      }
      final tool = definition.toolName;
      if (tool != null && !tools.add(tool)) {
        throw ArgumentError('Duplicate product tool: $tool');
      }
    }
  }

  final List<AiProductActionDefinition> definitions;

  AiProductActionDefinition? lookup(String actionKind) {
    for (final definition in definitions) {
      if (definition.actionKind == actionKind) return definition;
    }
    return null;
  }

  List<AiProductActionDefinition> available({
    required AiActionProposalSource source,
    required AiCapabilitySet capabilities,
  }) => [
    for (final definition in definitions)
      if (definition.supportedSources.contains(source) &&
          capabilities.containsAll(definition.requiredCapabilities) &&
          (definition.anyOfCapabilities.isEmpty ||
              definition.anyOfCapabilities.any(capabilities.containsAll)))
        definition,
  ];

  List<AiProductActionToolDescriptor> toolDescriptors({
    required AiActionProposalSource source,
    required AiCapabilitySet capabilities,
  }) => [
    for (final definition in available(
      source: source,
      capabilities: capabilities,
    ))
      if (definition.toolName != null)
        AiProductActionToolDescriptor(
          name: definition.toolName!,
          description: definition.toolDescription ?? definition.displayNameKey,
          inputSchema: definition.argumentSchema,
        ),
  ];
}

class AiProductActionToolDescriptor {
  const AiProductActionToolDescriptor({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
}

class AiActionPolicy {
  const AiActionPolicy();

  AiActionDecision decide({
    required AiActionProposal proposal,
    required AiProductActionDefinition definition,
    required DateTime now,
  }) {
    if (!definition.supportedSources.contains(proposal.source)) {
      return AiActionDecision(
        proposalId: proposal.proposalId,
        outcome: AiActionDecisionOutcome.deny,
        reasonCode: 'source_not_supported',
        riskClass: definition.riskClass,
        decidedAt: now,
      );
    }
    if (proposal.expiresAt.isBefore(now)) {
      return AiActionDecision(
        proposalId: proposal.proposalId,
        outcome: AiActionDecisionOutcome.deny,
        reasonCode: 'proposal_expired',
        riskClass: definition.riskClass,
        decidedAt: now,
      );
    }
    final requiresConfirmation =
        proposal.source == AiActionProposalSource.modelTool;
    return AiActionDecision(
      proposalId: proposal.proposalId,
      outcome: requiresConfirmation
          ? AiActionDecisionOutcome.requireConfirmation
          : AiActionDecisionOutcome.allow,
      reasonCode: requiresConfirmation ? 'model_proposal' : 'explicit_ui',
      riskClass: definition.riskClass,
      resolvedActionKind: definition.actionKind,
      normalizedArguments: proposal.requestedArguments,
      confirmationSummary: requiresConfirmation ? '请确认执行此产品操作' : null,
      allowedHumanDecisions: requiresConfirmation
          ? const ['approve', 'reject']
          : const [],
      decidedAt: now,
    );
  }
}

abstract interface class AiActionJournalStore {
  Future<AiActionJournalEntry?> read(String proposalId);

  Future<List<AiActionJournalEntry>> readAll();

  Future<void> write(AiActionJournalEntry entry);
}

class MemoryAiActionJournalStore implements AiActionJournalStore {
  final Map<String, AiActionJournalEntry> _entries = {};

  @override
  Future<AiActionJournalEntry?> read(String proposalId) async =>
      _entries[proposalId];

  @override
  Future<List<AiActionJournalEntry>> readAll() async =>
      List.unmodifiable(_entries.values);

  @override
  Future<void> write(AiActionJournalEntry entry) async {
    final existing = _entries[entry.proposal.proposalId];
    if (existing != null && entry.stateVersion <= existing.stateVersion) {
      throw StateError('Stale journal version');
    }
    _entries[entry.proposal.proposalId] = entry;
  }
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
  final name = '$raw';
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

AiAuthorizedCommand? _commandFromJson(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final json = Map<String, Object?>.from(raw);
  final source = _enumValue(
    AiActionProposalSource.values,
    json['authorizationSource'],
  );
  final authorizedAt = DateTime.tryParse('${json['authorizedAt'] ?? ''}');
  final args = json['arguments'];
  if (source == null || authorizedAt == null || args is! Map) return null;
  final fields = [
    'commandId',
    'proposalId',
    'actionKind',
    'authorizationSubmissionId',
    'authorizationEvidence',
    'idempotencyKey',
    'originalUserText',
  ];
  if (fields.any(
    (field) => json[field] is! String || (json[field] as String).isEmpty,
  )) {
    return null;
  }
  return AiAuthorizedCommand(
    protocolVersion: _int(json['protocolVersion']) ?? 1,
    commandId: json['commandId'] as String,
    proposalId: json['proposalId'] as String,
    actionKind: json['actionKind'] as String,
    definitionVersion: _int(json['definitionVersion']) ?? 1,
    commandSchemaVersion: _int(json['commandSchemaVersion']) ?? 1,
    workflowVersion: _int(json['workflowVersion']) ?? 1,
    authorizationSource: source,
    authorizationSubmissionId: json['authorizationSubmissionId'] as String,
    authorizationEvidence: json['authorizationEvidence'] as String,
    authorizedAt: authorizedAt,
    idempotencyKey: json['idempotencyKey'] as String,
    arguments: Map<String, Object?>.from(args),
    originalUserText: json['originalUserText'] as String,
    contentHash: _string(json['contentHash']),
    workKey: _string(json['workKey']),
    scopeFingerprint: _string(json['scopeFingerprint']),
    scopeSectionIndices:
        (json['scopeSectionIndices'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .toList(growable: false) ??
        const [],
    targetArtifactId: _string(json['targetArtifactId']),
    expectedRevision: _int(json['expectedRevision']),
  );
}

AiActionReceipt? _receiptFromJson(Object? raw) {
  if (raw is! Map) return null;
  final json = Map<String, Object?>.from(raw);
  final status = _enumValue(AiActionJournalStatus.values, json['status']);
  final finishedAt = DateTime.tryParse('${json['finishedAt'] ?? ''}');
  if (status == null || finishedAt == null) return null;
  return AiActionReceipt(
    commandId: '${json['commandId'] ?? ''}',
    workflowRunId: '${json['workflowRunId'] ?? ''}',
    attempt: _int(json['attempt']) ?? 0,
    definitionVersion: _int(json['definitionVersion']) ?? 1,
    workflowVersion: _int(json['workflowVersion']) ?? 1,
    status: status,
    artifactRefs:
        (json['artifactRefs'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const [],
    publicErrorCode: _string(json['publicErrorCode']),
    diagnosticRef: _string(json['diagnosticRef']),
    startedAt: DateTime.tryParse('${json['startedAt'] ?? ''}'),
    finishedAt: finishedAt,
  );
}

String encodeAiActionJson(Object? value) => jsonEncode(value);

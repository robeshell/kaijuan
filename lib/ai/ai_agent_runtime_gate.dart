enum AiAgentRuntimeKind { compatible, genkitAgent }

class AiAgentRuntimeCapabilities {
  const AiAgentRuntimeCapabilities({
    required this.attachedRequestCancellation,
    required this.providerMatrixValidated,
    required this.toolAndResumeValidated,
    required this.traceAndSnapshotValidated,
    required this.contractSuitePassed,
  });

  /// Known state of the locked Genkit Dart 0.15.1 attached Agent path.
  static const genkitDart0151 = AiAgentRuntimeCapabilities(
    attachedRequestCancellation: false,
    providerMatrixValidated: false,
    toolAndResumeValidated: false,
    traceAndSnapshotValidated: false,
    contractSuitePassed: false,
  );

  static const productionReady = AiAgentRuntimeCapabilities(
    attachedRequestCancellation: true,
    providerMatrixValidated: true,
    toolAndResumeValidated: true,
    traceAndSnapshotValidated: true,
    contractSuitePassed: true,
  );

  final bool attachedRequestCancellation;
  final bool providerMatrixValidated;
  final bool toolAndResumeValidated;
  final bool traceAndSnapshotValidated;
  final bool contractSuitePassed;

  List<String> blockers({required bool hasRuntimeFactory}) => [
    if (!hasRuntimeFactory) 'Genkit Agent runtime 尚未安装',
    if (!attachedRequestCancellation) 'attached 模型请求不支持真实取消',
    if (!providerMatrixValidated) 'Provider 模型矩阵尚未通过',
    if (!toolAndResumeValidated) '工具、Interrupt/Resume 尚未通过',
    if (!traceAndSnapshotValidated) 'Trace 与 Snapshot 尚未通过',
    if (!contractSuitePassed) 'App Runtime 契约测试尚未通过',
  ];
}

class AiAgentRuntimeDecision {
  const AiAgentRuntimeDecision({
    required this.requested,
    required this.effective,
    required this.blockers,
  });

  final AiAgentRuntimeKind requested;
  final AiAgentRuntimeKind effective;
  final List<String> blockers;

  bool get fellBack => requested != effective;
  bool get canPromoteGenkit =>
      requested == AiAgentRuntimeKind.genkitAgent &&
      effective == AiAgentRuntimeKind.genkitAgent;
}

/// Production promotion policy for the replaceable conversational runtime.
///
/// This gate is deliberately independent of Genkit SDK types. An SDK upgrade
/// must prove every App-owned capability before its factory can become the
/// effective runtime; merely compiling an Agent is insufficient.
abstract final class AiAgentRuntimeGate {
  static AiAgentRuntimeDecision decide({
    required AiAgentRuntimeKind requested,
    required AiAgentRuntimeCapabilities genkitCapabilities,
    required bool hasGenkitRuntimeFactory,
  }) {
    if (requested == AiAgentRuntimeKind.compatible) {
      return const AiAgentRuntimeDecision(
        requested: AiAgentRuntimeKind.compatible,
        effective: AiAgentRuntimeKind.compatible,
        blockers: [],
      );
    }
    final blockers = genkitCapabilities.blockers(
      hasRuntimeFactory: hasGenkitRuntimeFactory,
    );
    return AiAgentRuntimeDecision(
      requested: requested,
      effective: blockers.isEmpty
          ? AiAgentRuntimeKind.genkitAgent
          : AiAgentRuntimeKind.compatible,
      blockers: List.unmodifiable(blockers),
    );
  }
}

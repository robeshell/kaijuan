/// Objective quality gate for a generated graph.
///
/// Every metric is structure-self-consistency and requires no human
/// annotation, so any book can be screened automatically after generation.
class AiGraphQualityReport {
  const AiGraphQualityReport({
    required this.reversedKinPairs,
    required this.kinlessKinEdges,
    required this.mislabelledReferences,
    required this.mirrorPairs,
    required this.isolatedEntityRatio,
    required this.issues,
  });

  final int reversedKinPairs;
  final int kinlessKinEdges;
  final int mislabelledReferences;
  final int mirrorPairs;
  final double isolatedEntityRatio;
  final List<String> issues;

  bool get hasIssues => issues.isNotEmpty;
}

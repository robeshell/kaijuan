import 'ai_graph.dart';

/// Grounds model-supplied quotes in the local publication text.
abstract final class AiGraphEvidenceGrounder {
  static List<AiGraphEvidence> fromRaw(
    Object? raw, {
    required int sectionIndex,
    required String sectionText,
  }) {
    if (raw is! List) return const [];
    final out = <AiGraphEvidence>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final quote = map['quote'];
      if (quote is! String || quote.trim().isEmpty) continue;
      final quoteText = quote.trim();
      if (!seen.add(quoteText)) continue;
      // The caller owns section identity. Never trust a section number echoed
      // by the model; it could bypass read-progress gating and evidence jumps.
      final progress = locateQuote(sectionText, quoteText);
      out.add(
        AiGraphEvidence(
          sectionIndex: sectionIndex,
          quote: quoteText,
          progressInSection: progress,
          spanResolved: progress != null,
        ),
      );
    }
    return out;
  }

  /// Fractional start offset (0..1) after whitespace normalization.
  static double? locateQuote(String sectionText, String quote) {
    final trimmed = quote.trim();
    if (trimmed.isEmpty) return null;
    String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
    final normalized = normalize(sectionText);
    final wanted = normalize(trimmed);
    if (normalized.isEmpty || wanted.isEmpty) return null;
    final index = normalized.indexOf(wanted);
    if (index < 0) return null;
    return (index / normalized.length).clamp(0.0, 1.0);
  }
}

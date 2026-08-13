import 'ai_graph.dart';

/// Grounds model-supplied quotes in the local publication text.
abstract final class AiGraphEvidenceGrounder {
  static const int _minUnanchoredQuoteChars = 4;

  static List<AiGraphEvidence> fromRaw(
    Object? raw, {
    required int sectionIndex,
    required String sectionText,
    Iterable<String> anchors = const [],
  }) {
    if (raw is! List) return const [];
    final out = <AiGraphEvidence>[];
    final seen = <String>{};
    final names = [
      for (final value in anchors)
        if (value.trim().isNotEmpty) value.trim(),
    ];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final quote = map['quote'];
      if (quote is! String || quote.trim().isEmpty) continue;
      final quoteText = quote.trim();
      if (!seen.add(quoteText)) continue;
      // The caller owns section identity. Never trust a section number echoed
      // by the model; it could bypass read-progress gating and evidence jumps.
      final progress = locateQuote(sectionText, quoteText, anchors: names);
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

  /// Fractional start offset (0..1) after whitespace / punctuation
  /// normalization. When [anchors] occur in the section, the match closest
  /// to a name wins; a too-short quote with no nearby name is rejected.
  static double? locateQuote(
    String sectionText,
    String quote, {
    Iterable<String> anchors = const [],
  }) {
    final trimmed = quote.trim();
    if (trimmed.isEmpty) return null;
    final normalized = _normalize(sectionText);
    final wanted = _normalize(trimmed);
    if (normalized.isEmpty || wanted.isEmpty) return null;
    final hits = _allIndexes(normalized, wanted);
    if (hits.isEmpty) return null;

    final anchorHits = <int>[
      for (final anchor in anchors)
        ..._allIndexes(normalized, _normalize(anchor)),
    ];
    final namesTheEntity = [
      for (final anchor in anchors) _normalize(anchor),
    ].any((anchor) => anchor.isNotEmpty && wanted.contains(anchor));
    final chosen = _pickHit(
      quoteHits: hits,
      quoteLength: wanted.length,
      anchorHits: anchorHits,
      namesTheEntity: namesTheEntity,
    );
    if (chosen == null) return null;
    return (chosen / normalized.length).clamp(0.0, 1.0);
  }

  static String _normalize(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，。、“”‘’「」（）()：:；;！!？?…—\-·,.．]'), '');

  static List<int> _allIndexes(String haystack, String needle) {
    if (needle.isEmpty || haystack.length < needle.length) return const [];
    final out = <int>[];
    var from = 0;
    while (from <= haystack.length - needle.length) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) break;
      out.add(index);
      from = index + 1;
    }
    return out;
  }

  static int? _pickHit({
    required List<int> quoteHits,
    required int quoteLength,
    required List<int> anchorHits,
    required bool namesTheEntity,
  }) {
    if (quoteHits.isEmpty) return null;
    if (quoteLength < _minUnanchoredQuoteChars && !namesTheEntity) {
      return null;
    }
    if (anchorHits.isEmpty) return quoteHits.first;

    var best = quoteHits.first;
    var bestDistance = _distanceToNearestAnchor(
      best,
      quoteLength,
      anchorHits,
    );
    for (final hit in quoteHits.skip(1)) {
      final distance = _distanceToNearestAnchor(hit, quoteLength, anchorHits);
      if (distance < bestDistance) {
        best = hit;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int _distanceToNearestAnchor(
    int quoteStart,
    int quoteLength,
    List<int> anchorHits,
  ) {
    final quoteEnd = quoteStart + quoteLength;
    var best = 1 << 30;
    for (final anchor in anchorHits) {
      if (anchor >= quoteStart && anchor < quoteEnd) return 0;
      final gap = anchor < quoteStart ? quoteStart - anchor : anchor - quoteEnd;
      if (gap < best) best = gap;
    }
    return best;
  }
}

import 'dart:convert';

/// Defensive decoding for structured graph-model responses.
abstract final class AiGraphResponse {
  static List<String> stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? decodeObject(String text) {
    final candidate = jsonObjectCandidate(text);
    if (candidate == null) return null;
    try {
      final value = jsonDecode(candidate);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static String? jsonObjectCandidate(String text) {
    var value = text.trim();
    if (value.startsWith('```')) {
      if (!value.endsWith('```')) return null;
      value = value.replaceFirst(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false),
        '',
      );
      value = value.replaceFirst(RegExp(r'\s*```\s*$'), '');
    }
    value = value.trim();
    if (!value.startsWith('{') || !value.endsWith('}')) return null;
    return value;
  }
}

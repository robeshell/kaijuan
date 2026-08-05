import 'package:flutter/foundation.dart';

/// Debug-only AI connectivity logs. Never prints full API keys.
abstract final class AiLog {
  static void d(String message) {
    debugPrint('[AI] $message');
  }

  /// Masks secrets: shows prefix + length only.
  static String maskKey(String key) {
    final t = key.trim();
    if (t.isEmpty) return '(empty)';
    if (t.length <= 8) return '***(${t.length})';
    return '${t.substring(0, 4)}…${t.substring(t.length - 4)} (${t.length} chars)';
  }

  static String bodyPreview(String body, {int max = 240}) {
    final oneLine = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= max) return oneLine;
    return '${oneLine.substring(0, max)}…';
  }
}

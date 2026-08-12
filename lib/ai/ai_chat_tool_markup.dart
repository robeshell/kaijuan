import 'ai_model_adapter.dart';

/// Detects / strips / recovers **pseudo tool-call markup** that weak models
/// sometimes emit as plain answer text instead of native function calling.
///
/// Seen in the wild with OpenAI-compatible endpoints (e.g. DSML envelopes):
/// `<|DSML|tool_calls><|DSML|invoke name="get_chapter">…`
abstract final class AiChatToolMarkup {
  /// True when [text] looks like a leaked tool-call envelope rather than a
  /// normal reader-facing answer.
  static bool looksLikeLeakedToolCall(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return RegExp(
      r'DSML\s*\|?\s*tool_calls'
      r'|DSML\s*\|?\s*invoke'
      r'|<\|[^|>]*DSML[^|>]*\|>'
      r'|</?\s*tool_calls?\b'
      r'|<tool_call\b'
      r'|invoke\s+name\s*=\s*"(?:get_|search_|sample_|create_|revise_)'
      r'|```(?:tool_call|function_call)\b'
      r'|"name"\s*:\s*"(?:get_chapter|get_toc|search_book|sample_book|'
      r'get_current_chapter|get_reading_metadata|create_book_mind_map|'
      r'revise_book_mind_map)"',
      caseSensitive: false,
    ).hasMatch(t);
  }

  /// Remove leaked tool-call markup; keep surrounding reader-facing prose.
  static String stripLeakedToolCall(String text) {
    var out = text;
    // From the first DSML / tool_calls marker through the rest of that block
    // (often to end of message when the model "answers" with a fake call).
    out = out.replaceAll(
      RegExp(
        r'(?:^|\n)\s*<\|DSML\|[\s\S]*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(
        r'<\|?\s*tool_calls?\b[\s\S]*?(?:</\s*tool_calls?\s*>|\z)',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(
        r'```(?:tool_call|function_call)\b[\s\S]*?```',
        caseSensitive: false,
      ),
      '',
    );
    // Residual DSML tokens.
    out = out.replaceAll(
      RegExp(r'<\|/?DSML\|[^>]*>?', caseSensitive: false),
      '',
    );
    out = out.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  /// Best-effort parse of DSML-style invoke blocks into native tool calls.
  ///
  /// Returns empty when nothing usable is found — callers should fall back to
  /// a repair prompt rather than inventing tools.
  static List<AiModelToolCall> tryParseLeakedCalls(String text) {
    final calls = <AiModelToolCall>[];
    final invokeRe = RegExp(
      r'(?:<\|?\s*)?DSML\s*\|?\s*invoke\s+name\s*=\s*"([^"]+)"\s*>?'
      r'([\s\S]*?)'
      r'(?=(?:<\|?\s*)?DSML\s*\|?\s*invoke\b|(?:<\|?\s*)?DSML\s*\|?\s*tool_calls\b|\z)',
      caseSensitive: false,
    );
    final paramRe = RegExp(
      r'(?:<\|?\s*)?DSML\s*\|?\s*parameter\s+name\s*=\s*"([^"]+)"'
      r'(?:\s+string\s*=\s*"(true|false)")?\s*>'
      r'([^<]*)',
      caseSensitive: false,
    );
    var i = 0;
    for (final match in invokeRe.allMatches(text)) {
      final name = match.group(1)?.trim() ?? '';
      if (name.isEmpty) continue;
      final body = match.group(2) ?? '';
      final args = <String, dynamic>{};
      for (final p in paramRe.allMatches(body)) {
        final key = p.group(1)?.trim() ?? '';
        if (key.isEmpty) continue;
        final asString = (p.group(2) ?? 'true').toLowerCase() != 'false';
        final raw = (p.group(3) ?? '').trim();
        if (asString) {
          args[key] = raw;
        } else {
          final asInt = int.tryParse(raw);
          final asNum = num.tryParse(raw);
          args[key] = asInt ?? asNum ?? raw;
        }
      }
      i += 1;
      calls.add(
        AiModelToolCall(
          id: 'recovered-$i',
          name: name,
          arguments: args,
        ),
      );
    }
    return calls;
  }

  static const repairUserMessage =
      '<tool_call_repair>\n'
      'Your previous response contained tool-call markup as plain text '
      '(for example DSML, XML invoke, or a fenced tool_call block) instead of '
      'a native function call. Do not emit that markup again.\n'
      'Either call tools through the native tool interface now, or answer the '
      'reader in plain language using only evidence you already retrieved.\n'
      '</tool_call_repair>';

  static const budgetExhaustedUserMessage =
      '<tool_budget_exhausted>\n'
      'The App tool budget for this turn is used up. Answer the reader now '
      'with the evidence already in this conversation. Do not call tools, and '
      'do not emit DSML/XML/tool_call markup of any kind.\n'
      '</tool_budget_exhausted>';
}

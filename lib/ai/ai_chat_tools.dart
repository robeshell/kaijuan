import 'dart:convert';

import 'ai_chat_retrieve.dart';
import 'ai_provider.dart';

/// Names the model may call during book chat (text protocol, no LangChain).
abstract final class AiChatToolNames {
  static const getToc = 'get_toc';
  static const getCurrentChapter = 'get_current_chapter';
  static const getChapter = 'get_chapter';
  static const searchBook = 'search_book';
  static const sampleBook = 'sample_book';

  static const all = <String>{
    getToc,
    getCurrentChapter,
    getChapter,
    searchBook,
    sampleBook,
  };
}

/// One tool invocation parsed from the model.
class AiChatToolCall {
  const AiChatToolCall({required this.name, this.args = const {}});

  final String name;
  final Map<String, dynamic> args;

  int? get sectionIndex {
    final raw = args['sectionIndex'] ?? args['section'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  String get query => '${args['query'] ?? args['keyword'] ?? ''}'.trim();

  int? get maxChars {
    final raw = args['maxChars'] ?? args['max_chars'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }
}

/// App-side handlers. Implemented by [BookReaderController] / tests.
abstract interface class AiChatToolHost {
  /// Directory lines: `§1 标题`.
  Future<String> toolGetToc();

  /// Plain text of the chapter the reader is in.
  Future<String> toolGetCurrentChapter({int maxChars = 10000});

  /// One spine section by 1-based index (from get_toc / sample labels).
  Future<String> toolGetChapter(int sectionIndex1Based, {int maxChars = 10000});

  /// Keyword hits inside the book (local plain-text search).
  Future<String> toolSearchBook(String query, {int maxChars = 12000});

  /// Even sample across sections for whole-book questions.
  Future<String> toolSampleBook({int maxChars = 36000});
}

/// Parse / format the ```kaijuan_tools ... ``` protocol.
abstract final class AiChatTools {
  static const protocolFenceHead = '```kaijuan_tools';

  static final _exactToolFenceRe = RegExp(
    r'^\s*```kaijuan_tools\s*([\s\S]*?)```\s*$',
    caseSensitive: false,
  );

  static final _partialToolFenceRe = RegExp(
    r'^\s*```kaijuan_tools(?:\s|$)',
    caseSensitive: false,
  );

  static final _toolFenceAnywhereRe = RegExp(
    r'```kaijuan_tools\s*[\s\S]*?```',
    caseSensitive: false,
  );

  static final _partialToolFenceAtEndRe = RegExp(
    r'```kaijuan_tools\s*[\s\S]*$',
    caseSensitive: false,
  );

  static final _toolFenceHeadAnywhereRe = RegExp(
    r'```kaijuan_tools',
    caseSensitive: false,
  );

  /// True if [text] looks like a tool-call turn (not a final user answer).
  static bool looksLikeToolTurn(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return _exactToolFenceRe.hasMatch(t) ||
        _partialToolFenceRe.hasMatch(t) ||
        _danglingToolFencePrefixStart(t) == 0;
  }

  /// Whether a reply contains a complete protocol head or ends while spelling
  /// one. This is deliberately broader than [looksLikeToolTurn]: callers use
  /// it to reject/repair malformed attempts, never to execute embedded tools.
  static bool containsToolProtocolAttempt(String text) {
    return _toolFenceHeadAnywhereRe.hasMatch(text) ||
        _danglingToolFencePrefixStart(text) != null;
  }

  static List<AiChatToolCall> parseCalls(String text) {
    final fence = _exactToolFenceRe.firstMatch(text);
    final raw = fence?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = decoded;
      final out = <AiChatToolCall>[];
      for (final row in list) {
        if (row is! Map) continue;
        final name = '${row['name'] ?? ''}'.trim();
        if (name.isEmpty || !AiChatToolNames.all.contains(name)) continue;
        final args = <String, dynamic>{};
        for (final e in row.entries) {
          if (e.key == 'name') continue;
          args['${e.key}'] = e.value;
        }
        // Nested args map.
        final nested = row['args'];
        if (nested is Map) {
          for (final e in nested.entries) {
            args['${e.key}'] = e.value;
          }
        }
        out.add(AiChatToolCall(name: name, args: args));
        if (out.length >= 6) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Removes accidental tool protocol output from a final assistant answer.
  ///
  /// The prompt tells the model not to emit this after tool work, but the
  /// final stream still gets a defensive cleanup because this protocol is
  /// intentionally text-based rather than a provider-native tool call.
  static String stripToolProtocol(String text) {
    var cleaned = text.replaceAll(_toolFenceAnywhereRe, '');
    cleaned = cleaned.replaceFirst(_partialToolFenceAtEndRe, '');
    final danglingStart = _danglingToolFencePrefixStart(cleaned);
    if (danglingStart != null) {
      cleaned = cleaned.substring(0, danglingStart);
    }
    return cleaned.trimRight();
  }

  /// Finds a line-level suffix such as ```k / ```kaijuan_t. Requiring at
  /// least the first letter avoids eating an ordinary Markdown closing ```.
  static int? _danglingToolFencePrefixStart(String text) {
    final lower = text.toLowerCase();
    final start = lower.lastIndexOf('```');
    if (start < 0) return null;
    final lineStart = start == 0 ? 0 : lower.lastIndexOf('\n', start - 1) + 1;
    if (lower.substring(lineStart, start).trim().isNotEmpty) return null;
    final tail = lower.substring(start).trimRight();
    if (tail.length < 4 || !protocolFenceHead.startsWith(tail)) return null;
    return start;
  }

  static Future<String> runAll(
    List<AiChatToolCall> calls,
    AiChatToolHost host, {
    int maxTotalChars = 18000,
    CancelToken? cancelToken,
  }) async {
    if (calls.isEmpty) return '(no tools)';
    final buf = StringBuffer();
    final seen = <String>{};
    final budget = maxTotalChars.clamp(1000, 48000);
    var emitted = 0;
    for (final call in calls) {
      cancelToken?.throwIfCancelled();
      final signature = _signature(call);
      if (!seen.add(signature)) continue;
      if (buf.length >= budget) break;
      emitted++;
      buf.writeln('### tool $emitted: ${call.name}');
      try {
        final result = await _runOne(call, host);
        cancelToken?.throwIfCancelled();
        final remaining = budget - buf.length;
        final clipped = result.length > remaining
            ? '${result.substring(0, remaining.clamp(0, result.length))}…'
            : result;
        buf.writeln(clipped.isEmpty ? '(empty)' : clipped);
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        buf.writeln('Error: $e');
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  static String _signature(AiChatToolCall call) => switch (call.name) {
    AiChatToolNames.getChapter => '${call.name}:${call.sectionIndex}',
    AiChatToolNames.searchBook => '${call.name}:${_clipQuery(call.query)}',
    _ => call.name,
  };

  static int _boundedMax(int? requested, int fallback, int ceiling) =>
      (requested ?? fallback).clamp(256, ceiling);

  static String _clipQuery(String query) {
    final normalized = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 160 ? normalized : normalized.substring(0, 160);
  }

  static Future<String> _runOne(AiChatToolCall call, AiChatToolHost host) {
    return switch (call.name) {
      AiChatToolNames.getToc => host.toolGetToc(),
      AiChatToolNames.getCurrentChapter => host.toolGetCurrentChapter(
        maxChars: _boundedMax(call.maxChars, 10000, 12000),
      ),
      AiChatToolNames.getChapter => () async {
        final idx = call.sectionIndex;
        if (idx == null || idx < 1) {
          return 'Error: get_chapter needs sectionIndex (1-based from get_toc).';
        }
        return host.toolGetChapter(
          idx,
          maxChars: _boundedMax(call.maxChars, 10000, 12000),
        );
      }(),
      AiChatToolNames.searchBook => () async {
        final q = _clipQuery(call.query);
        if (q.isEmpty) return 'Error: search_book needs query.';
        return host.toolSearchBook(
          q,
          maxChars: _boundedMax(call.maxChars, 10000, 12000),
        );
      }(),
      AiChatToolNames.sampleBook => host.toolSampleBook(
        maxChars: _boundedMax(call.maxChars, 18000, 18000),
      ),
      _ => Future.value('Error: unknown tool ${call.name}'),
    };
  }

  /// Human-readable status for the UI while tools run (e.g. "正在检索「张居正」…").
  /// Falls back to the raw names so a new tool still shows *something*.
  static String describeCalls(List<AiChatToolCall> calls) {
    if (calls.isEmpty) return '正在处理…';
    final parts = <String>[];
    for (final call in calls) {
      parts.add(switch (call.name) {
        AiChatToolNames.getToc => '查询目录',
        AiChatToolNames.getCurrentChapter => '读取当前章',
        AiChatToolNames.getChapter => '读取章节 §${call.sectionIndex ?? '?'}',
        AiChatToolNames.searchBook => '检索「${call.query}」',
        AiChatToolNames.sampleBook => '全书取样',
        _ => call.name,
      });
    }
    return '正在${parts.join('、')}…';
  }

  /// Catalog text for the system prompt.
  static String catalogForPrompt() {
    return '''
Tools (call only when you need more book text; prefer few calls):
- get_toc — list section index + title
- get_current_chapter — plain text of the chapter the reader is in (optional maxChars)
- get_chapter — one section by 1-based sectionIndex from get_toc (optional maxChars). Never infer sectionIndex from a human title such as “第8章”; call get_toc first unless an exact §n from this turn is already available.
- search_book — keyword search in this book (query required)
- sample_book — even samples from every section (for whole-book overview / cast)

To call tools, reply with ONLY a fenced block (no other prose):
```kaijuan_tools
[{"name":"get_toc"},{"name":"search_book","query":"关键词"}]
```
When you have enough context, answer the user in normal prose (no tool fence).
'''
        .trim();
  }
}

/// Helpers to slice [getBookPlainText] corpus for tools.
abstract final class AiChatBookCorpus {
  static String formatTocFromSlices(List<AiBookSectionSlice> sections) {
    if (sections.isEmpty) return '(no sections)';
    final buf = StringBuffer();
    for (final s in sections) {
      final label = s.label.trim().isEmpty ? '§${s.index}' : s.label.trim();
      buf.writeln('§${s.index} $label');
    }
    return buf.toString().trimRight();
  }

  static String sectionText(
    List<AiBookSectionSlice> sections,
    int index1Based, {
    int maxChars = 10000,
  }) {
    for (final s in sections) {
      if (s.index == index1Based) {
        final t = s.text.trim();
        if (t.length <= maxChars) return '[§${s.index} ${s.label}]\n$t';
        return '[§${s.index} ${s.label}]\n${t.substring(0, maxChars)}…';
      }
    }
    return 'Error: section $index1Based not found.';
  }
}

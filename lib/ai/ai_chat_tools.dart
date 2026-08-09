import 'ai_cancel.dart';
import 'ai_chat_retrieve.dart';
import 'ai_model_adapter.dart';

/// Names the model may call during book chat through native function calling.
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

/// App-level view of one native tool invocation.
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

/// Native tool schemas and app-owned execution.
abstract final class AiChatTools {
  static const nativeDefinitions = <AiModelToolDefinition>[
    AiModelToolDefinition(
      name: AiChatToolNames.getToc,
      description: 'List this work\'s section indices and titles.',
      inputSchema: {'type': 'object', 'properties': <String, Object?>{}},
    ),
    AiModelToolDefinition(
      name: AiChatToolNames.getCurrentChapter,
      description: 'Read the plain text of the chapter currently visible.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'maxChars': {'type': 'integer', 'minimum': 256, 'maximum': 12000},
        },
      },
    ),
    AiModelToolDefinition(
      name: AiChatToolNames.getChapter,
      description:
          'Read one section by the 1-based sectionIndex returned by get_toc.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'sectionIndex': {'type': 'integer', 'minimum': 1},
          'maxChars': {'type': 'integer', 'minimum': 256, 'maximum': 12000},
        },
        'required': ['sectionIndex'],
      },
    ),
    AiModelToolDefinition(
      name: AiChatToolNames.searchBook,
      description: 'Search for a keyword or phrase inside this work.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'minLength': 1, 'maxLength': 160},
          'maxChars': {'type': 'integer', 'minimum': 256, 'maximum': 12000},
        },
        'required': ['query'],
      },
    ),
    AiModelToolDefinition(
      name: AiChatToolNames.sampleBook,
      description:
          'Read an even sample across this work for whole-book questions.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'maxChars': {'type': 'integer', 'minimum': 256, 'maximum': 18000},
        },
      },
    ),
  ];

  static Future<List<AiModelToolResult>> runNative(
    List<AiModelToolCall> calls,
    AiChatToolHost host, {
    int maxTotalChars = 18000,
    CancelToken? cancelToken,
  }) async {
    final out = <AiModelToolResult>[];
    final seen = <String>{};
    final budget = maxTotalChars.clamp(0, 48000);
    var used = 0;
    for (var index = 0; index < calls.length; index++) {
      final modelCall = calls[index];
      cancelToken?.throwIfCancelled();
      if (index >= 6) {
        out.add(
          AiModelToolResult(
            callId: modelCall.id,
            name: modelCall.name,
            output: 'Error: per-turn tool call limit exceeded.',
          ),
        );
        continue;
      }
      final call = AiChatToolCall(
        name: modelCall.name,
        args: modelCall.arguments,
      );
      final signature = _signature(call);
      if (!AiChatToolNames.all.contains(call.name) || !seen.add(signature)) {
        out.add(
          AiModelToolResult(
            callId: modelCall.id,
            name: modelCall.name,
            output: 'Error: duplicate or unknown tool call.',
          ),
        );
        continue;
      }
      if (used >= budget) {
        out.add(
          AiModelToolResult(
            callId: modelCall.id,
            name: modelCall.name,
            output: 'Error: tool result budget exhausted.',
          ),
        );
        continue;
      }
      try {
        final raw = await _runOne(call, host);
        cancelToken?.throwIfCancelled();
        final remaining = budget - used;
        final result = raw.length > remaining
            ? '${raw.substring(0, remaining.clamp(0, raw.length))}…'
            : raw;
        used += result.length;
        out.add(
          AiModelToolResult(
            callId: modelCall.id,
            name: modelCall.name,
            output: result.isEmpty ? '(empty)' : result,
          ),
        );
      } catch (_) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        out.add(
          AiModelToolResult(
            callId: modelCall.id,
            name: modelCall.name,
            output: 'Error: tool execution failed.',
          ),
        );
      }
    }
    return List.unmodifiable(out);
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

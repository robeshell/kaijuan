import 'ai_cancel.dart';
import 'ai_chat_retrieve.dart';
import 'ai_model_adapter.dart';

/// Names the model may call during book chat through native function calling.
abstract final class AiChatToolNames {
  static const getReadingMetadata = 'get_reading_metadata';
  static const getToc = 'get_toc';
  static const getCurrentChapter = 'get_current_chapter';
  static const getChapter = 'get_chapter';
  static const searchBook = 'search_book';
  static const sampleBook = 'sample_book';

  static const all = <String>{
    getReadingMetadata,
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

  int? get charOffset {
    final raw = args['charOffset'] ?? args['char_offset'] ?? args['offset'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  String get focusQuery =>
      '${args['focusQuery'] ?? args['focus_query'] ?? args['focus'] ?? ''}'
          .trim();
}

/// App-side handlers. Implemented by [BookReaderController] / tests.
abstract interface class AiChatToolHost {
  /// Frozen reading position, scope, and progress for this turn.
  Future<String> toolGetReadingMetadata();

  /// Directory lines: `§1 标题`.
  Future<String> toolGetToc();

  /// Plain text of the chapter the reader is in.
  Future<String> toolGetCurrentChapter({int maxChars = 10000});

  /// One spine section by 1-based index (from get_toc / sample labels).
  ///
  /// [charOffset] pages from that character; [focusQuery] windows around a
  /// match so mid-chapter evidence is not lost to head truncation.
  Future<String> toolGetChapter(
    int sectionIndex1Based, {
    int maxChars = 10000,
    int? charOffset,
    String? focusQuery,
  });

  /// Keyword hits inside the book (local plain-text search).
  Future<String> toolSearchBook(String query, {int maxChars = 12000});

  /// Even sample across sections for whole-book questions.
  Future<String> toolSampleBook({int maxChars = 36000});
}

/// Native tool schemas and app-owned execution.
abstract final class AiChatTools {
  static const nativeDefinitions = <AiModelToolDefinition>[
    AiModelToolDefinition(
      name: AiChatToolNames.getReadingMetadata,
      description:
          'Reading session metadata: publication title, scoped work, '
          'current chapter, section index, and reading progress percent. '
          'Call when you need position or to decide spoiler caution.',
      inputSchema: {'type': 'object', 'properties': <String, Object?>{}},
    ),
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
          'Read one section by the 1-based sectionIndex from get_toc. '
          'Long chapters are truncated: pass focusQuery to center on a phrase, '
          'or charOffset (from search_book hit windows) to page mid-chapter. '
          'Do not assume the opening equals the whole chapter.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'sectionIndex': {'type': 'integer', 'minimum': 1},
          'maxChars': {'type': 'integer', 'minimum': 256, 'maximum': 12000},
          'charOffset': {
            'type': 'integer',
            'minimum': 0,
            'description':
                '0-based character offset into the section body. '
                'Use values reported by search_book hit windows.',
          },
          'focusQuery': {
            'type': 'string',
            'maxLength': 80,
            'description':
                'Optional phrase to center the returned window on '
                '(mid-chapter evidence).',
          },
        },
        'required': ['sectionIndex'],
      },
    ),
    AiModelToolDefinition(
      name: AiChatToolNames.searchBook,
      description:
          'Search for a keyword or phrase inside this work. Returns short '
          'snippets **centered on each hit** (not chapter openings), with '
          'sectionIndex and charOffset so you can call get_chapter to read more.',
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
          'Read an even sample across this work for whole-book questions. '
          'Prefer get_chapter for close reading of specific sections.',
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
      // Allow a fuller batch of get_chapter in one model turn (was 6).
      if (index >= 10) {
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
    // Allow re-reading the same section at a different offset / focus.
    AiChatToolNames.getChapter =>
      '${call.name}:${call.sectionIndex}:${call.charOffset ?? 0}:${call.focusQuery}',
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
      AiChatToolNames.getReadingMetadata => host.toolGetReadingMetadata(),
      AiChatToolNames.getToc => host.toolGetToc(),
      AiChatToolNames.getCurrentChapter => host.toolGetCurrentChapter(
        maxChars: _boundedMax(call.maxChars, 10000, 12000),
      ),
      AiChatToolNames.getChapter => () async {
        final idx = call.sectionIndex;
        if (idx == null || idx < 1) {
          return 'Error: get_chapter needs sectionIndex (1-based from get_toc).';
        }
        final focus = call.focusQuery;
        return host.toolGetChapter(
          idx,
          maxChars: _boundedMax(call.maxChars, 10000, 12000),
          charOffset: call.charOffset,
          focusQuery: focus.isEmpty ? null : focus,
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

  /// Short Chinese label for one native tool name (status / summary).
  static String displayNameFor(String name) => switch (name) {
    AiChatToolNames.getReadingMetadata => '阅读位置',
    AiChatToolNames.getToc => '目录',
    AiChatToolNames.getCurrentChapter => '当前章',
    AiChatToolNames.getChapter => '章节',
    AiChatToolNames.searchBook => '检索',
    AiChatToolNames.sampleBook => '取样',
    'create_book_mind_map' => '导图',
    'revise_book_mind_map' => '改图',
    _ => name,
  };

  /// Human-readable status for the UI while tools run (e.g. "正在检索「张居正」…").
  /// Falls back to the raw names so a new tool still shows *something*.
  static String describeCalls(List<AiChatToolCall> calls) {
    if (calls.isEmpty) return '正在处理…';
    final parts = <String>[];
    for (final call in calls) {
      parts.add(switch (call.name) {
        AiChatToolNames.getReadingMetadata => '读取阅读位置',
        AiChatToolNames.getToc => '查询目录',
        AiChatToolNames.getCurrentChapter => '读取当前章',
        AiChatToolNames.getChapter => '读取章节 §${call.sectionIndex ?? '?'}',
        AiChatToolNames.searchBook => '检索「${call.query}」',
        AiChatToolNames.sampleBook => '全书取样',
        _ => displayNameFor(call.name),
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
    int? charOffset,
    String? focusQuery,
  }) {
    for (final s in sections) {
      if (s.index == index1Based) {
        final t = s.text.trim();
        final label = s.label.trim().isEmpty ? '§${s.index}' : s.label.trim();
        final focus = focusQuery?.trim() ?? '';
        late final String body;
        late final String mode;
        if (focus.isNotEmpty) {
          body = AiChatRetrieve.windowAroundQuery(
            t,
            query: focus,
            maxChars: maxChars,
          );
          mode = 'focusQuery="$focus"';
        } else if (charOffset != null && charOffset > 0) {
          body = AiChatRetrieve.windowAtOffset(
            t,
            charOffset: charOffset,
            maxChars: maxChars,
          );
          mode = 'charOffset=$charOffset · sectionLength=${t.length}';
        } else if (t.length <= maxChars) {
          body = t;
          mode = 'full · sectionLength=${t.length}';
        } else {
          // Default: head+tail so late-chapter material is not invisible.
          body = AiChatRetrieve.windowAroundQuery(
            t,
            query: '',
            maxChars: maxChars,
          );
          mode =
              'head+tail truncate · sectionLength=${t.length} · '
              'pass focusQuery or charOffset for mid-chapter';
        }
        return '[§${s.index} $label · $mode]\n$body';
      }
    }
    return 'Error: section $index1Based not found.';
  }
}

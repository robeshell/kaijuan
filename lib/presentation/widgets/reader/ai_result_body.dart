import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Lightweight, dependency-free formatting for AI replies.
///
/// Handles paragraphs, section titles, bullet / numbered lists, and inline
/// `**bold**` (models often emit markdown despite "no stars" prompts).
class AiResultBody extends StatelessWidget {
  const AiResultBody({
    super.key,
    required this.text,
    this.selectable = true,
    this.compact = false,
  });

  final String text;
  final bool selectable;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0)
            SizedBox(
              height: blocks[i].isHeading
                  ? (compact ? 12 : 16)
                  : (blocks[i].isListItem ? 7 : (compact ? 10 : 12)),
            ),
          _blockWidget(context, blocks[i]),
        ],
      ],
    );
  }

  Widget _blockWidget(BuildContext context, _Block block) {
    final baseStyle = TextStyle(
      fontSize: compact ? context.appBodySecondarySize : context.appBodySize,
      height: compact ? 1.55 : 1.6,
      color: context.appPrimaryText,
      fontWeight: FontWeight.w400,
    );
    final headingStyle = baseStyle.copyWith(
      fontSize: context.appCaptionSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: context.appSecondaryText,
      height: 1.35,
    );
    final style = block.isHeading ? headingStyle : baseStyle;
    final spans = _parseInlineSpans(block.text, style);

    final rich = Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: TextAlign.start,
    );

    Widget body;
    if (block.isListItem) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 10, left: 2),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: context.appSecondaryText,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: rich),
        ],
      );
    } else {
      body = rich;
    }

    if (!selectable) return body;
    return SelectionArea(child: body);
  }

  static List<_Block> _parseBlocks(String raw) {
    final normalized = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        // Models sometimes glue sections with " - " on one line.
        .replaceAll(RegExp(r'\s+-\s*(?=释义|词性|例句|注[：:])'), '\n\n');

    final lines = normalized.split('\n');
    final blocks = <_Block>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final joined = paragraph.join('\n').trim();
      paragraph.clear();
      if (joined.isEmpty) return;
      _emitParagraphBlocks(joined, blocks);
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      final listMatch = _listItemPattern.firstMatch(trimmed);
      if (listMatch != null) {
        flushParagraph();
        final item = listMatch.group(1)!.trim();
        if (item.isNotEmpty) {
          blocks.add(_Block(text: item, isHeading: false, isListItem: true));
        }
        continue;
      }

      // Markdown AT-### headings
      final headingMatch = RegExp(r'^#{1,3}\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        flushParagraph();
        blocks.add(
          _Block(text: headingMatch.group(1)!.trim(), isHeading: true),
        );
        continue;
      }

      paragraph.add(trimmed);
    }
    flushParagraph();
    return blocks;
  }

  static final _listItemPattern = RegExp(r'^(?:[-*•]|\d+[.)])\s+(.+)$');

  static void _emitParagraphBlocks(String chunk, List<_Block> blocks) {
    final lines = chunk
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    // Single-line section label: 释义 / 词性 / 例句
    if (lines.length == 1 && _isSectionTitle(lines.first)) {
      blocks.add(
        _Block(text: _stripHeadingMarks(lines.first), isHeading: true),
      );
      return;
    }

    // First line is title, rest is body → split into heading + body.
    if (lines.length >= 2 && _isSectionTitle(lines.first)) {
      blocks.add(
        _Block(text: _stripHeadingMarks(lines.first), isHeading: true),
      );
      final body = lines.skip(1).join('\n');
      if (body.isNotEmpty) {
        blocks.add(_Block(text: body, isHeading: false));
      }
      return;
    }

    // "释义：正文" on one line
    final inline = RegExp(r'^(释义|词性|例句|注)\s*[：:]\s*(.+)$');
    final match = inline.firstMatch(lines.first);
    if (lines.length == 1 && match != null) {
      blocks.add(_Block(text: match.group(1)!, isHeading: true));
      final rest = match.group(2)!.trim();
      if (rest.isNotEmpty) {
        blocks.add(_Block(text: rest, isHeading: false));
      }
      return;
    }

    blocks.add(_Block(text: lines.join('\n'), isHeading: false));
  }

  static bool _isSectionTitle(String line) {
    final t = _stripHeadingMarks(line);
    return t == '释义' ||
        t == '词性' ||
        t == '例句' ||
        t == '注' ||
        t == '译文' ||
        t == '原文';
  }

  static String _stripHeadingMarks(String line) {
    return line
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'^\*{1,2}'), '')
        .replaceAll(RegExp(r'\*{1,2}$'), '')
        .replaceAll(RegExp(r'[：:]\s*$'), '')
        .trim();
  }

  static List<InlineSpan> _parseInlineSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    // **bold** and __bold__
    final pattern = RegExp(r'(\*\*|__)(.+?)\1');
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.addAll(
          _plainWithBreaks(text.substring(start, match.start), base),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(2),
          style: base.copyWith(fontWeight: FontWeight.w600),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.addAll(_plainWithBreaks(text.substring(start), base));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: base));
    }
    return spans;
  }

  static List<InlineSpan> _plainWithBreaks(String text, TextStyle base) {
    if (!text.contains('\n')) {
      return [TextSpan(text: text, style: base)];
    }
    final parts = text.split('\n');
    final out = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) out.add(const TextSpan(text: '\n'));
      if (parts[i].isNotEmpty) {
        out.add(TextSpan(text: parts[i], style: base));
      }
    }
    return out;
  }
}

class _Block {
  const _Block({
    required this.text,
    required this.isHeading,
    this.isListItem = false,
  });

  final String text;
  final bool isHeading;
  final bool isListItem;
}

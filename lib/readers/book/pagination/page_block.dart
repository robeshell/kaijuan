import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Base class for a block of content that can be placed on a paginated page.
abstract class PageBlock {
  const PageBlock({this.paragraphSpacing = 0});

  /// Space to reserve after this block when it is the last part of a paragraph.
  final double paragraphSpacing;
}

/// A run of inline text with a specific style.
class InlineRun {
  const InlineRun({required this.text, required this.style});

  final String text;
  final TextStyle style;
}

/// Text block that can be split across pages at line boundaries.
class TextBlock extends PageBlock {
  TextBlock({
    required this.runs,
    required this.baseStyle,
    super.paragraphSpacing = 0,
  }) {
    _buildPlainText();
  }

  final List<InlineRun> runs;
  final TextStyle baseStyle;

  late final String plainText;
  final _runRanges = <_RunRange>[];

  void _buildPlainText() {
    final buffer = StringBuffer();
    _runRanges.clear();
    for (final run in runs) {
      final start = buffer.length;
      buffer.write(run.text);
      _runRanges.add(_RunRange(start, buffer.length, run.style));
    }
    plainText = buffer.toString();
  }

  /// Full span for measuring the whole block.
  InlineSpan get span => TextSpan(
        style: baseStyle,
        children: [
          for (final run in runs) TextSpan(text: run.text, style: run.style),
        ],
      );

  /// Builds a span containing only [start]..[end] code units.
  InlineSpan spanForRange(int start, int end) {
    final children = <InlineSpan>[];
    for (final range in _runRanges) {
      final overlapStart = start.clamp(range.start, range.end);
      final overlapEnd = end.clamp(range.start, range.end);
      if (overlapStart < overlapEnd) {
        children.add(
          TextSpan(
            text: plainText.substring(overlapStart, overlapEnd),
            style: range.style,
          ),
        );
      }
    }
    return TextSpan(style: baseStyle, children: children);
  }

  /// Creates a new block from a subset of this block's text range.
  TextBlock subBlock(
    int start,
    int end, {
    double? paragraphSpacing,
  }) {
    final sliced = <InlineRun>[];
    for (final range in _runRanges) {
      final overlapStart = start.clamp(range.start, range.end);
      final overlapEnd = end.clamp(range.start, range.end);
      if (overlapStart < overlapEnd) {
        sliced.add(
          InlineRun(
            text: plainText.substring(overlapStart, overlapEnd),
            style: range.style,
          ),
        );
      }
    }
    return TextBlock(
      runs: sliced,
      baseStyle: baseStyle,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    );
  }
}

class _RunRange {
  _RunRange(this.start, this.end, this.style);

  final int start;
  final int end;
  final TextStyle style;
}

/// Image block. The paginator fills in [bytes] and [displaySize].
class ImageBlock extends PageBlock {
  const ImageBlock({
    required this.src,
    this.width,
    this.height,
    this.bytes,
    this.displaySize,
    super.paragraphSpacing = 0,
  });

  final String src;
  final double? width;
  final double? height;
  final Uint8List? bytes;
  final Size? displaySize;
}

/// Horizontal rule block.
class RuleBlock extends PageBlock {
  const RuleBlock({super.paragraphSpacing = 0});
}

/// Table block rendered as a scrollable full-page block.
class TableBlock extends PageBlock {
  const TableBlock({required this.html, super.paragraphSpacing = 0});

  final String html;
}

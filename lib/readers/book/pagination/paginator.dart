import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'html_block_parser.dart';
import 'page_block.dart';
import '../prepared_section.dart';

/// One page worth of blocks.
class PageSpec {
  const PageSpec(this.blocks);

  final List<PageBlock> blocks;
}

/// Result of paginating all sections.
class PaginatorResult {
  const PaginatorResult({
    required this.pages,
    required this.sectionStartPageIndices,
  });

  final List<PageSpec> pages;

  /// Index of the first page of each section. Length equals section count.
  final List<int> sectionStartPageIndices;
}

/// Paginates prepared HTML sections into fixed-size pages.
///
/// Text blocks are split at line boundaries; images, rules and tables are
/// treated as atomic blocks.
class Paginator {
  Paginator({
    required this.pageSize,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    required this.readBytes,
    this.textScaler = TextScaler.noScaling,
  });

  final Size pageSize;
  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final Future<Uint8List?> Function(String entry) readBytes;
  final TextScaler textScaler;

  final _imageSizeCache = <String, Size>{};

  Future<PaginatorResult> paginate(List<PreparedSection> sections) async {
    final allPages = <PageSpec>[];
    final startIndices = <int>[];

    for (final section in sections) {
      startIndices.add(allPages.length);
      final parser = HtmlBlockParser(
        fontSize: fontSize,
        lineHeight: lineHeight,
        textColor: textColor,
      );
      final blocks = parser.parse(section.html);
      final pages = await _paginateBlocks(blocks);
      allPages.addAll(pages);
    }

    return PaginatorResult(
      pages: allPages,
      sectionStartPageIndices: startIndices,
    );
  }

  Future<List<PageSpec>> _paginateBlocks(List<PageBlock> blocks) async {
    final pages = <PageSpec>[];
    var currentBlocks = <PageBlock>[];
    var usedHeight = 0.0;

    void flushPage() {
      if (currentBlocks.isEmpty) return;
      pages.add(PageSpec(List.unmodifiable(currentBlocks)));
      currentBlocks = [];
      usedHeight = 0.0;
    }

    for (final block in blocks) {
      switch (block) {
        case TextBlock textBlock:
          final subBlocks = await _paginateTextBlock(textBlock);
          for (final sub in subBlocks) {
            final height = _textBlockHeight(sub) + sub.paragraphSpacing;
            if (usedHeight + height > pageSize.height &&
                currentBlocks.isNotEmpty) {
              flushPage();
            }
            currentBlocks.add(sub);
            usedHeight += height;
          }
        case ImageBlock imageBlock:
          final sized = await _resolveImageBlock(imageBlock);
          final height = _imageHeight(sized) + block.paragraphSpacing;

          if (usedHeight + height > pageSize.height &&
              currentBlocks.isNotEmpty) {
            flushPage();
          }
          currentBlocks.add(sized);
          usedHeight += height;

          if (usedHeight >= pageSize.height) {
            flushPage();
          }
        case RuleBlock _:
          const ruleHeight = 8.0;
          if (usedHeight + ruleHeight + block.paragraphSpacing >
                  pageSize.height &&
              currentBlocks.isNotEmpty) {
            flushPage();
          }
          currentBlocks.add(block);
          usedHeight += ruleHeight + block.paragraphSpacing;
          if (usedHeight >= pageSize.height) {
            flushPage();
          }
        case TableBlock _:
          // Tables get a dedicated page that can scroll internally.
          if (currentBlocks.isNotEmpty) flushPage();
          currentBlocks.add(block);
          pages.add(PageSpec(List.unmodifiable(currentBlocks)));
          currentBlocks = [];
          usedHeight = 0.0;
      }
    }

    flushPage();

    if (pages.isEmpty) {
      pages.add(
        PageSpec([
          TextBlock(
            runs: [
              InlineRun(
                text: '本章无正文',
                style: TextStyle(
                  fontSize: fontSize,
                  height: lineHeight,
                  color: textColor,
                ),
              ),
            ],
            baseStyle: TextStyle(
              fontSize: fontSize,
              height: lineHeight,
              color: textColor,
            ),
          ),
        ]),
      );
    }

    return pages;
  }

  Future<List<TextBlock>> _paginateTextBlock(TextBlock block) async {
    final painter = TextPainter(
      text: block.span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: pageSize.width);

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) {
      painter.dispose();
      return const [];
    }

    final lineRanges = <_LineRange>[];
    var y = 0.0;
    for (final metric in metrics) {
      final midY = y + metric.height / 2;
      final position = painter.getPositionForOffset(Offset(0, midY));
      final boundary = painter.getLineBoundary(position);
      lineRanges.add(
        _LineRange(
          start: boundary.start,
          end: boundary.end,
          height: metric.height,
        ),
      );
      y += metric.height;
    }

    final subBlocks = <TextBlock>[];
    var lineIndex = 0;

    while (lineIndex < lineRanges.length) {
      var lineEnd = lineIndex;
      var linesHeight = 0.0;
      while (lineEnd < lineRanges.length) {
        final h = lineRanges[lineEnd].height;
        if (linesHeight + h > pageSize.height && lineEnd > lineIndex) {
          break;
        }
        linesHeight += h;
        lineEnd++;
      }

      if (lineEnd == lineIndex) {
        // Even a single line doesn't fit; force one line so we don't hang.
        lineEnd = lineIndex + 1;
      }

      final startRange = lineRanges[lineIndex];
      final endRange = lineRanges[lineEnd - 1];
      final isLastPiece = lineEnd >= lineRanges.length;
      subBlocks.add(
        block.subBlock(
          startRange.start,
          endRange.end,
          paragraphSpacing: isLastPiece ? block.paragraphSpacing : 0,
        ),
      );

      lineIndex = lineEnd;
    }

    painter.dispose();
    return subBlocks;
  }

  Future<ImageBlock> _resolveImageBlock(ImageBlock block) async {
    if (block.displaySize != null) return block;

    final cached = _imageSizeCache[block.src];
    if (cached != null) {
      return ImageBlock(
        src: block.src,
        width: block.width,
        height: block.height,
        bytes: block.bytes,
        displaySize: cached,
        paragraphSpacing: block.paragraphSpacing,
      );
    }

    Size? size;
    final bytes = block.bytes ?? await readBytes(block.src);
    if (bytes != null && bytes.isNotEmpty) {
      size = await _decodeImageSize(bytes);
    }
    size ??= _sizeFromAttributes(block.width, block.height);
    size ??= const Size(200, 150);

    _imageSizeCache[block.src] = size;
    return ImageBlock(
      src: block.src,
      width: block.width,
      height: block.height,
      bytes: bytes,
      displaySize: size,
      paragraphSpacing: block.paragraphSpacing,
    );
  }

  double _imageHeight(ImageBlock block) {
    final size = block.displaySize;
    if (size == null) return 150;
    final displayWidth = pageSize.width;
    final displayHeight = displayWidth / size.width * size.height;
    return math.min(displayHeight, pageSize.height);
  }

  double _textBlockHeight(TextBlock block) {
    final painter = TextPainter(
      text: block.span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: pageSize.width);
    final metrics = painter.computeLineMetrics();
    final height = metrics.fold(0.0, (sum, m) => sum + m.height);
    painter.dispose();
    return height;
  }

  static Future<Size?> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Size? _sizeFromAttributes(double? width, double? height) {
    if (width != null && height != null && width > 0 && height > 0) {
      return Size(width, height);
    }
    return null;
  }
}

class _LineRange {
  _LineRange({required this.start, required this.end, required this.height});

  final int start;
  final int end;
  final double height;
}

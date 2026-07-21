import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../epub_image_extension.dart';
import '../book_css_rules.dart';
import '../prepared_section.dart';
import 'html_block_parser.dart';
import 'page_block.dart';

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

  /// Leave a small band so TextPainter vs RichText drift cannot pack one
  /// extra line past the visible page.
  double get _maxContentHeight => math.max(0.0, pageSize.height - 24);

  Future<PaginatorResult> paginate(List<PreparedSection> sections) async {
    final allPages = <PageSpec>[];
    final startIndices = <int>[];

    for (final section in sections) {
      startIndices.add(allPages.length);
      final pages = await paginateSection(section);
      allPages.addAll(pages);
      await Future<void>.delayed(Duration.zero);
    }

    return PaginatorResult(
      pages: allPages,
      sectionStartPageIndices: startIndices,
    );
  }

  /// Paginate a single spine section into pages.
  Future<List<PageSpec>> paginateSection(
    PreparedSection section, {
    List<String> packageStylesheets = const [],
  }) async {
    final css = BookCssRules.parseAll([
      ...packageStylesheets,
      ...section.sectionStylesheets,
    ]);
    final parser = HtmlBlockParser(
      fontSize: fontSize,
      lineHeight: lineHeight,
      textColor: textColor,
      baseHref: section.href,
      cssRules: css,
    );
    final blocks = parser.parse(section.html);
    return _paginateBlocks(blocks, baseHref: section.href);
  }

  Future<List<PageSpec>> _paginateBlocks(
    List<PageBlock> blocks, {
    required String baseHref,
  }) async {
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
            if (usedHeight + height > _maxContentHeight &&
                currentBlocks.isNotEmpty) {
              flushPage();
            }
            currentBlocks.add(sub);
            usedHeight += height;
          }
        case ImageBlock imageBlock:
          final sized = await _resolveImageBlock(
            imageBlock,
            baseHref: baseHref,
          );
          final height = _imageHeight(sized) + block.paragraphSpacing;

          if (usedHeight + height > _maxContentHeight &&
              currentBlocks.isNotEmpty) {
            flushPage();
          }
          currentBlocks.add(sized);
          usedHeight += height;

          if (usedHeight >= _maxContentHeight) {
            flushPage();
          }
        case RuleBlock _:
          const ruleHeight = 8.0;
          if (usedHeight + ruleHeight + block.paragraphSpacing >
                  _maxContentHeight &&
              currentBlocks.isNotEmpty) {
            flushPage();
          }
          currentBlocks.add(block);
          usedHeight += ruleHeight + block.paragraphSpacing;
          if (usedHeight >= _maxContentHeight) {
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
    final contentWidth =
        (pageSize.width - block.textIndent).clamp(1.0, pageSize.width);
    final painter = TextPainter(
      text: block.span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: contentWidth);

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
    var isFirstSubBlock = true;

    while (lineIndex < lineRanges.length) {
      var lineEnd = lineIndex;
      var linesHeight = 0.0;
      while (lineEnd < lineRanges.length) {
        final h = lineRanges[lineEnd].height;
        if (linesHeight + h > _maxContentHeight && lineEnd > lineIndex) {
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
          textIndent: isFirstSubBlock ? block.textIndent : 0,
        ),
      );
      isFirstSubBlock = false;

      lineIndex = lineEnd;
    }

    painter.dispose();
    return subBlocks;
  }

  Future<ImageBlock> _resolveImageBlock(
    ImageBlock block, {
    required String baseHref,
  }) async {
    final src = block.src.startsWith('data:')
        ? block.src
        : EpubImageExtension.resolveImageEntry(baseHref, block.src);
    if (block.displaySize != null) {
      return block.src == src
          ? block
          : ImageBlock(
              src: src,
              width: block.width,
              height: block.height,
              bytes: block.bytes,
              displaySize: block.displaySize,
              paragraphSpacing: block.paragraphSpacing,
            );
    }

    final cached = _imageSizeCache[src];
    if (cached != null) {
      return ImageBlock(
        src: src,
        width: block.width,
        height: block.height,
        bytes: block.bytes,
        displaySize: cached,
        paragraphSpacing: block.paragraphSpacing,
      );
    }

    // Prefer HTML width/height so we can skip ZIP read + decode during open.
    Size? size = _sizeFromAttributes(block.width, block.height);
    Uint8List? bytes = block.bytes;
    if (size == null && !src.startsWith('data:')) {
      bytes = await readBytes(src);
      if (bytes != null && bytes.isNotEmpty) {
        size = await _decodeImageSize(bytes);
      }
    }
    size ??= const Size(200, 150);

    _imageSizeCache[src] = size;
    return ImageBlock(
      src: src,
      width: block.width,
      height: block.height,
      // Keep bytes only when already loaded; otherwise paint loads lazily.
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
    return math.min(displayHeight, _maxContentHeight);
  }

  double _textBlockHeight(TextBlock block) {
    final contentWidth =
        (pageSize.width - block.textIndent).clamp(1.0, pageSize.width);
    final painter = TextPainter(
      text: block.span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: contentWidth);
    // Prefer painter.height over summing line metrics — closer to RichText.
    final height = painter.height;
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

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'page_block.dart';

/// Parses a sanitized HTML section into paginated blocks.
///
/// Block-level tags become [TextBlock]s; inline formatting is flattened into
/// styled runs. Images, horizontal rules and tables become atomic blocks.
class HtmlBlockParser {
  HtmlBlockParser({
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    this.paragraphSpacing,
  });

  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final double? paragraphSpacing;

  double get _paragraphSpacing => paragraphSpacing ?? fontSize * 0.6;

  TextStyle get _baseStyle => TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        color: textColor,
      );

  List<PageBlock> parse(String html) {
    final document = html_parser.parse(html);
    final body = document.body;
    final root = body ?? document.documentElement;
    if (root == null) return const [];

    final blocks = <PageBlock>[];
    for (final node in root.nodes) {
      final block = _blockFromNode(node);
      if (block != null) {
        blocks.add(block);
      }
    }
    return blocks;
  }

  PageBlock? _blockFromNode(dom.Node node) {
    if (node is! dom.Element) {
      final text = node.text?.trim();
      if (text == null || text.isEmpty) return null;
      return _textBlock([InlineRun(text: text, style: _baseStyle)]);
    }

    final tag = node.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'style':
      case 'script':
      case 'link':
      case 'meta':
      case 'title':
        return null;
      case 'img':
        return _imageBlock(node);
      case 'hr':
        return const RuleBlock();
      case 'table':
        return TableBlock(
          html: node.outerHtml,
          paragraphSpacing: _paragraphSpacing,
        );
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _headingBlock(node, tag);
      case 'ul':
      case 'ol':
        return _listBlock(node, tag == 'ol');
      default:
        return _textBlockFromElement(node);
    }
  }

  TextBlock _textBlock(List<InlineRun> runs) => TextBlock(
        runs: runs,
        baseStyle: _baseStyle,
        paragraphSpacing: _paragraphSpacing,
      );

  TextBlock _textBlockFromElement(dom.Element element) => _textBlock(_inlineRuns(element));

  TextBlock _headingBlock(dom.Element element, String tag) {
    final scale = switch (tag) {
      'h1' => 1.6,
      'h2' => 1.4,
      'h3' => 1.25,
      'h4' => 1.15,
      'h5' => 1.1,
      _ => 1.05,
    };
    final style = _baseStyle.copyWith(
      fontSize: fontSize * scale,
      fontWeight: FontWeight.bold,
    );
    return TextBlock(
      runs: _inlineRuns(element, overrideStyle: style),
      baseStyle: style,
      paragraphSpacing: fontSize * 0.8,
    );
  }

  TextBlock? _listBlock(dom.Element element, bool ordered) {
    final runs = <InlineRun>[];
    var index = 1;
    for (final child in element.children) {
      if (child.localName?.toLowerCase() != 'li') continue;
      final prefix = ordered ? '$index. ' : '• ';
      runs.add(InlineRun(text: prefix, style: _baseStyle));
      runs.addAll(_inlineRuns(child));
      runs.add(InlineRun(text: '\n', style: _baseStyle));
      index++;
    }
    if (runs.isEmpty) return null;
    return _textBlock(runs);
  }

  ImageBlock _imageBlock(dom.Element element) {
    final src = element.attributes['src'] ?? '';
    final width = _parseDim(element.attributes['width']);
    final height = _parseDim(element.attributes['height']);
    return ImageBlock(
      src: src,
      width: width,
      height: height,
      paragraphSpacing: _paragraphSpacing,
    );
  }

  List<InlineRun> _inlineRuns(
    dom.Node node, {
    TextStyle? overrideStyle,
  }) {
    final base = overrideStyle ?? _baseStyle;
    final runs = <InlineRun>[];
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = child.text;
        if (text.isNotEmpty) {
          runs.add(InlineRun(text: text, style: base));
        }
      } else if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        final childStyle = _styleForInline(tag, base);
        if (tag == 'br') {
          runs.add(InlineRun(text: '\n', style: base));
        } else if (tag == 'img') {
          runs.add(InlineRun(text: '[图片]', style: base));
        } else {
          runs.addAll(_inlineRuns(child, overrideStyle: childStyle));
        }
      }
    }
    return runs;
  }

  TextStyle _styleForInline(String tag, TextStyle base) {
    return switch (tag) {
      'b' || 'strong' => base.copyWith(fontWeight: FontWeight.bold),
      'i' || 'em' => base.copyWith(fontStyle: FontStyle.italic),
      'u' => base.copyWith(decoration: TextDecoration.underline),
      's' || 'strike' => base.copyWith(decoration: TextDecoration.lineThrough),
      'a' => base.copyWith(
          decoration: TextDecoration.underline,
          color: base.color?.withValues(alpha: 0.85),
        ),
      'small' => base.copyWith(fontSize: fontSize * 0.85),
      'sup' || 'sub' => base.copyWith(fontSize: fontSize * 0.75),
      'code' => base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: base.color?.withValues(alpha: 0.08),
        ),
      _ => base,
    };
  }

  static double? _parseDim(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    final numeric = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(cleaned)?.group(1);
    return numeric == null ? null : double.tryParse(numeric);
  }
}

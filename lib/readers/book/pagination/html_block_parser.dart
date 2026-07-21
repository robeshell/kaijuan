import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../book_css_rules.dart';
import '../book_epub.dart';
import 'page_block.dart';

/// Parses a sanitized HTML section into paginated blocks.
///
/// Block-level tags become [TextBlock]s; inline formatting is flattened into
/// styled runs. Images, horizontal rules and tables become atomic blocks.
/// Container tags (`div` / `section` / …) are walked recursively so nested
/// images are not collapsed into `[图片]` placeholders.
class HtmlBlockParser {
  HtmlBlockParser({
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    this.paragraphSpacing,
    this.baseHref = '',
    this.cssRules = const BookCssRules(),
  });

  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final double? paragraphSpacing;

  /// Spine item href used to resolve relative `<a href>`.
  final String baseHref;

  final BookCssRules cssRules;

  double get _paragraphSpacing => paragraphSpacing ?? fontSize * 0.6;

  static const _skipTags = {
    'style',
    'script',
    'link',
    'meta',
    'title',
    'head',
  };

  static const _containerTags = {
    'div',
    'section',
    'article',
    'main',
    'aside',
    'header',
    'footer',
    'nav',
    'figure',
    'blockquote',
    'body',
  };

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
    _collectBlocks(root, blocks);
    return blocks;
  }

  void _collectBlocks(dom.Node node, List<PageBlock> out) {
    if (node is! dom.Element) {
      final text = node.text?.trim();
      if (text != null && text.isNotEmpty) {
        out.add(_textBlock([InlineRun(text: text, style: _baseStyle)]));
      }
      return;
    }

    final tag = node.localName?.toLowerCase() ?? '';
    if (_skipTags.contains(tag)) return;

    switch (tag) {
      case 'img':
        out.add(_imageBlock(node));
        return;
      case 'hr':
        out.add(const RuleBlock());
        return;
      case 'table':
        out.add(
          TableBlock(
            html: node.outerHtml,
            paragraphSpacing: _paragraphSpacing,
          ),
        );
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        out.add(_headingBlock(node, tag));
        return;
      case 'ul':
      case 'ol':
        final list = _listBlock(node, tag == 'ol');
        if (list != null) out.add(list);
        return;
      case 'p':
      case 'li':
      case 'pre':
      case 'figcaption':
        // Leaf-ish text blocks: still split out nested atomic media.
        _collectMixed(node, out);
        return;
    }

    if (_containerTags.contains(tag)) {
      for (final child in node.nodes) {
        _collectBlocks(child, out);
      }
      return;
    }

    // Unknown tags: prefer expanding children; fall back to text.
    if (node.children.isNotEmpty && _hasBlockChild(node)) {
      for (final child in node.nodes) {
        _collectBlocks(child, out);
      }
      return;
    }
    _collectMixed(node, out);
  }

  bool _hasBlockChild(dom.Element element) {
    for (final child in element.children) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (_containerTags.contains(tag) ||
          tag == 'p' ||
          tag == 'img' ||
          tag == 'hr' ||
          tag == 'table' ||
          tag == 'ul' ||
          tag == 'ol' ||
          tag.startsWith('h')) {
        return true;
      }
    }
    return false;
  }

  /// Emits text runs for [element], but promotes nested img/hr/table to
  /// their own blocks so they are not lost as `[图片]`.
  void _collectMixed(dom.Element element, List<PageBlock> out) {
    final tag = element.localName?.toLowerCase() ?? '';
    final blockTag =
        tag == 'p' || tag == 'li' || tag == 'pre' || tag == 'figcaption'
            ? tag
            : null;
    final runs = <InlineRun>[];

    void flushText() {
      final text = runs.map((r) => r.text).join();
      if (text.trim().isEmpty) {
        runs.clear();
        return;
      }
      out.add(
        _textBlock(
          List<InlineRun>.from(runs),
          paragraphSpacing:
              blockTag == null ? null : _blockSpacing(blockTag, element),
          textIndent: blockTag == null ? 0 : _blockIndent(blockTag, element),
        ),
      );
      runs.clear();
    }

    final rootStyle = blockTag == null
        ? _baseStyle
        : cssRules.applyToStyle(
            _baseStyle,
            tag: blockTag,
            classes: _classes(element),
            baseFontSize: fontSize,
          );

    void walk(dom.Node node, TextStyle style) {
      if (node is dom.Text) {
        if (node.text.isNotEmpty) {
          runs.add(InlineRun(text: node.text, style: style));
        }
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) return;
      if (tag == 'img') {
        flushText();
        out.add(_imageBlock(node));
        return;
      }
      if (tag == 'hr') {
        flushText();
        out.add(const RuleBlock());
        return;
      }
      if (tag == 'table') {
        flushText();
        out.add(
          TableBlock(
            html: node.outerHtml,
            paragraphSpacing: _paragraphSpacing,
          ),
        );
        return;
      }
      if (tag == 'br') {
        runs.add(InlineRun(text: '\n', style: style));
        return;
      }
      if (tag == 'a') {
        final hrefAttr = node.attributes['href'];
        final linkStyle = _styleForInline(
          tag,
          style,
          classAttr: node.attributes['class'],
        );
        final resolvedHref = _resolveLinkHref(hrefAttr);
        void walkLink(dom.Node linkNode, TextStyle linkSt) {
          if (linkNode is dom.Text) {
            if (linkNode.text.isNotEmpty) {
              runs.add(
                InlineRun(
                  text: linkNode.text,
                  style: linkSt,
                  href: resolvedHref,
                ),
              );
            }
            return;
          }
          if (linkNode is! dom.Element) return;
          final linkTag = linkNode.localName?.toLowerCase() ?? '';
          if (linkTag == 'br') {
            runs.add(InlineRun(text: '\n', style: linkSt, href: resolvedHref));
            return;
          }
          if (linkTag == 'img' || linkTag == 'hr' || linkTag == 'table') {
            walk(linkNode, linkSt);
            return;
          }
          final childStyle = _styleForInline(
            linkTag,
            linkSt,
            classAttr: linkNode.attributes['class'],
          );
          for (final c in linkNode.nodes) {
            walkLink(c, childStyle);
          }
        }

        for (final child in node.nodes) {
          walkLink(child, linkStyle);
        }
        return;
      }
      final childStyle = _styleForInline(
        tag,
        style,
        classAttr: node.attributes['class'],
      );
      for (final child in node.nodes) {
        walk(child, childStyle);
      }
    }

    walk(element, rootStyle);
    flushText();
  }

  String? _resolveLinkHref(String? hrefAttr) {
    if (hrefAttr == null || hrefAttr.trim().isEmpty) return null;
    final trimmed = hrefAttr.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http:') ||
        lower.startsWith('https:') ||
        lower.startsWith('mailto:')) {
      return null;
    }
    final resolved = BookEpub.resolveHref(baseHref, trimmed);
    if (resolved.path.contains(':')) return null;
    if (resolved.fragment == null || resolved.fragment!.isEmpty) {
      return resolved.path;
    }
    return '${resolved.path}#${resolved.fragment}';
  }

  TextBlock _textBlock(
    List<InlineRun> runs, {
    TextStyle? baseStyle,
    double? paragraphSpacing,
    double textIndent = 0,
  }) =>
      TextBlock(
        runs: runs,
        baseStyle: baseStyle ?? _baseStyle,
        paragraphSpacing: paragraphSpacing ?? _paragraphSpacing,
        textIndent: textIndent,
      );

  List<String> _classes(dom.Element element) {
    final raw = element.attributes['class'];
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();
  }

  double _blockSpacing(String tag, dom.Element element) {
    final extra = cssRules.extraParagraphSpacing(
      tag: tag,
      classes: _classes(element),
      baseFontSize: fontSize,
    );
    return (extra ?? 0) + _paragraphSpacing;
  }

  double _blockIndent(String tag, dom.Element element) {
    return cssRules.textIndent(
          tag: tag,
          classes: _classes(element),
          baseFontSize: fontSize,
        ) ??
        0;
  }

  TextBlock _headingBlock(dom.Element element, String tag) {
    final classes = _classes(element);
    final scale = cssRules.headingScale(tag, classes: classes);
    final style = cssRules.applyToStyle(
      _baseStyle.copyWith(
        fontSize: fontSize * scale,
        fontWeight: FontWeight.bold,
      ),
      tag: tag,
      classes: classes,
      baseFontSize: fontSize,
    );
    final runs = <InlineRun>[];
    void walk(dom.Node node, TextStyle current) {
      if (node is dom.Text) {
        if (node.text.isNotEmpty) {
          runs.add(InlineRun(text: node.text, style: current));
        }
        return;
      }
      if (node is! dom.Element) return;
      final childTag = node.localName?.toLowerCase() ?? '';
      if (childTag == 'br') {
        runs.add(InlineRun(text: '\n', style: current));
        return;
      }
      if (childTag == 'img') return;
      final childStyle = _styleForInline(
        childTag,
        current,
        classAttr: node.attributes['class'],
      );
      for (final child in node.nodes) {
        walk(child, childStyle);
      }
    }

    for (final child in element.nodes) {
      walk(child, style);
    }
    return TextBlock(
      runs: runs.isEmpty
          ? [InlineRun(text: element.text, style: style)]
          : runs,
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
      void walk(dom.Node node, TextStyle style) {
        if (node is dom.Text) {
          if (node.text.isNotEmpty) {
            runs.add(InlineRun(text: node.text, style: style));
          }
          return;
        }
        if (node is! dom.Element) return;
        final tag = node.localName?.toLowerCase() ?? '';
        if (tag == 'img' || tag == 'table' || tag == 'ul' || tag == 'ol') {
          return;
        }
        if (tag == 'br') {
          runs.add(InlineRun(text: '\n', style: style));
          return;
        }
        final childStyle = _styleForInline(tag, style);
        for (final c in node.nodes) {
          walk(c, childStyle);
        }
      }

      for (final node in child.nodes) {
        walk(node, _baseStyle);
      }
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

  TextStyle _styleForInline(
    String tag,
    TextStyle base, {
    String? classAttr,
  }) {
    var style = switch (tag) {
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
    final classes = classAttr == null || classAttr.trim().isEmpty
        ? const <String>[]
        : classAttr.split(RegExp(r'\s+')).where((c) => c.isNotEmpty);
    return cssRules.applyToStyle(
      style,
      tag: tag,
      classes: classes,
      baseFontSize: fontSize,
    );
  }

  static double? _parseDim(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    final numeric = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(cleaned)?.group(1);
    return numeric == null ? null : double.tryParse(numeric);
  }
}

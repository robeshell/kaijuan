import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'book_footnotes.dart';

/// Result of preparing a spine section for flutter_html rendering.
class PreparedSectionHtml {
  const PreparedSectionHtml({
    required this.html,
    this.footnotes = const {},
  });

  final String html;

  /// Footnote fragment id → plain text (for tap popups).
  final Map<String, String> footnotes;
}

/// Pre-processes a spine section's XHTML for rendering with flutter_html.
abstract final class BookHtmlPreprocessor {
  /// Returns `<link rel="stylesheet">` href values from the document `<head>`.
  static List<String> linkedStylesheetHrefs(String rawHtml) {
    final document = html_parser.parse(rawHtml, generateSpans: true);
    final links = document.head?.querySelectorAll('link[rel="stylesheet"]') ??
        const <Element>[];
    final hrefs = <String>[];
    for (final link in links) {
      final href = link.attributes['href']?.trim();
      if (href != null && href.isNotEmpty) hrefs.add(href);
    }
    return hrefs;
  }

  /// Returns a sanitized HTML fragment ready for [Html], plus any footnotes.
  ///
  /// - Extracts the contents of `<body>`.
  /// - Extracts footnotes, removes footnote asides, rewrites noteref markers.
  /// - Removes `<script>`, `<iframe>`, `<video>`, `<audio>`, `<object>`,
  ///   `<embed>`, `<form>` and their children.
  /// - Strips `xmlns:*` and `epub:type` attributes that flutter_html ignores.
  /// - Inlines the document-level CSS as `<style>` blocks at the top.
  static PreparedSectionHtml prepareSection({
    required String rawHtml,
    required String baseHref,
    required List<String> stylesheets,
  }) {
    final document = html_parser.parse(rawHtml, generateSpans: true);
    final body = document.body;
    if (body == null) {
      return const PreparedSectionHtml(html: '');
    }

    // Footnotes must run before epub:type is stripped.
    final footnotes = BookFootnotes.process(body);
    _sanitizeNode(body);

    final buffer = StringBuffer();
    if (stylesheets.isNotEmpty) {
      buffer.write('<style>\n');
      for (final css in stylesheets) {
        buffer.write(css);
        buffer.write('\n');
      }
      buffer.write('</style>\n');
    }
    buffer.write(body.innerHtml);

    return PreparedSectionHtml(
      html: buffer.toString(),
      footnotes: footnotes,
    );
  }

  static final _tagsToRemove = {
    'script',
    'iframe',
    'video',
    'audio',
    'object',
    'embed',
    'form',
  };

  static final _attrsToRemove = {
    RegExp(r'^xmlns(:\w+)?$', caseSensitive: false),
    RegExp(r'^epub:type$', caseSensitive: false),
    RegExp(r'^xml:lang$', caseSensitive: false),
  };

  static void _sanitizeNode(Node node) {
    if (node is! Element) return;

    // Remove blacklisted tags entirely.
    final children = List<Node>.from(node.nodes);
    for (final child in children) {
      if (child is Element && _tagsToRemove.contains(child.localName)) {
        child.remove();
      } else {
        _sanitizeNode(child);
      }
    }

    // Strip XHTML/EPUB-specific attributes that flutter_html doesn't need.
    final attrsToRemove = <String>[];
    for (final attr in node.attributes.keys) {
      final name = attr.toString();
      for (final pattern in _attrsToRemove) {
        if (pattern.hasMatch(name)) {
          attrsToRemove.add(name);
          break;
        }
      }
    }
    for (final name in attrsToRemove) {
      node.attributes.remove(name);
    }
  }
}

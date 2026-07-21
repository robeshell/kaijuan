import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_svg/flutter_html_svg.dart';
import 'package:flutter_html_table/flutter_html_table.dart';

import '../../readers/book/book_html_preprocessor.dart';
import '../../readers/book/book_theme.dart';
import 'epub_image_extension.dart';

/// Renders one spine section with flutter_html using the reader's current
/// typography and theme settings.
class HtmlSectionView extends StatelessWidget {
  const HtmlSectionView({
    super.key,
    required this.html,
    required this.baseHref,
    required this.readBytes,
    this.packageStylesheets = const [],
    this.sectionStylesheets = const [],
    required this.fontSize,
    required this.lineHeight,
    required this.margin,
    required this.theme,
    this.onLinkTap,
  });

  final String html;
  final String baseHref;
  final Future<Uint8List?> Function(String entry) readBytes;
  final List<String> packageStylesheets;
  final List<String> sectionStylesheets;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final BookReadingTheme theme;
  final void Function(String url, {String baseHref})? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final fg = Color(theme.foregroundArgb);
    final bg = Color(theme.backgroundArgb);
    final data = BookHtmlPreprocessor.wrapWithStylesheets(
      html: html,
      packageStylesheets: packageStylesheets,
      sectionStylesheets: sectionStylesheets,
    );

    return Html(
      data: data,
      extensions: [
        EpubImageExtension(baseHref: baseHref, readBytes: readBytes),
        const TableHtmlExtension(),
        const SvgHtmlExtension(),
      ],
      style: {
        'body': Style(
          fontSize: FontSize(fontSize),
          lineHeight: LineHeight(lineHeight),
          color: fg,
          backgroundColor: bg,
          margin: Margins.zero,
          padding: HtmlPaddings.symmetric(horizontal: margin, vertical: 16),
        ),
        'p': Style(
          margin: Margins.only(bottom: fontSize * 0.6),
        ),
        'h1': Style(
          margin: Margins.only(top: fontSize * 1.2, bottom: fontSize * 0.8),
          fontSize: FontSize(fontSize * 1.6),
          fontWeight: FontWeight.bold,
        ),
        'h2': Style(
          margin: Margins.only(top: fontSize, bottom: fontSize * 0.7),
          fontSize: FontSize(fontSize * 1.4),
          fontWeight: FontWeight.bold,
        ),
        'h3': Style(
          margin: Margins.only(top: fontSize * 0.8, bottom: fontSize * 0.6),
          fontSize: FontSize(fontSize * 1.2),
          fontWeight: FontWeight.bold,
        ),
        'img': Style(
          alignment: Alignment.center,
          width: Width.auto(),
        ),
        'a': Style(
          color: fg.withValues(alpha: 0.85),
          textDecoration: TextDecoration.underline,
        ),
        'a.kaika-noteref-link': Style(
          textDecoration: TextDecoration.none,
          display: Display.inline,
        ),
        'sup': Style(
          fontSize: FontSize(fontSize * 0.75),
          display: Display.inline,
        ),
        '.kaika-noteref': Style(
          color: fg.withValues(alpha: 0.75),
          textDecoration: TextDecoration.none,
          display: Display.inline,
        ),
        '.epub-footnote': Style(
          width: Width(10),
          height: Height.auto(),
        ),
      },
      onLinkTap: (url, attributes, element) {
        if (url == null || url.isEmpty) return;
        onLinkTap?.call(url, baseHref: baseHref);
      },
      onCssParseError: (css, messages) {
        // Real-world EPUB CSS frequently contains unsupported declarations.
        // Return null so flutter_html can continue.
        return null;
      },
    );
  }
}

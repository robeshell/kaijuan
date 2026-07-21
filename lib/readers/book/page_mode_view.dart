import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../readers/book/book_theme.dart';
import 'html_section_view.dart';
import 'prepared_section.dart';

/// Horizontal page-flip view with one section per page.
///
/// This is a stopgap implementation for v1.0; true line-bound pagination will
/// replace it in a later phase. It still reports section-based progress so the
/// controller contract stays unchanged.
class PageModeView extends StatefulWidget {
  const PageModeView({
    super.key,
    required this.sections,
    required this.readBytes,
    required this.initialSection,
    this.jumpTargetSection,
    required this.onPositionChanged,
    required this.fontSize,
    required this.lineHeight,
    required this.margin,
    required this.theme,
  });

  final List<PreparedSection> sections;
  final Future<Uint8List?> Function(String entry) readBytes;
  final int initialSection;
  final int? jumpTargetSection;
  final void Function(int sectionIndex, double progressInSection)
      onPositionChanged;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final BookReadingTheme theme;

  @override
  State<PageModeView> createState() => _PageModeViewState();
}

class _PageModeViewState extends State<PageModeView> {
  late final PageController _pageController;
  int _lastReportedSection = -1;
  int? _lastJumpTarget;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialSection);
    _lastReportedSection = widget.initialSection;
  }

  @override
  void didUpdateWidget(covariant PageModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.jumpTargetSection;
    if (target != null && target != _lastJumpTarget) {
      _lastJumpTarget = target;
      _jumpToSection(target);
    }
  }

  void _jumpToSection(int sectionIndex) {
    if (!_pageController.hasClients) return;
    final target = sectionIndex.clamp(0, widget.sections.length - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    if (index == _lastReportedSection) return;
    _lastReportedSection = index;
    widget.onPositionChanged(index, 0);
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    const chromeHeight = kBookReaderChromeBarHeight;
    final contentPadding = EdgeInsets.only(
      top: safe.top + chromeHeight,
      bottom: safe.bottom + chromeHeight,
    );

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      onPageChanged: _onPageChanged,
      itemCount: widget.sections.length,
      itemBuilder: (context, index) {
        final section = widget.sections[index];
        final fg = Color(widget.theme.foregroundArgb);
        final hasImage = section.html.toLowerCase().contains('<img');
        final visibleText = section.html
            .replaceAll(RegExp(r'<[^>]+>', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s'), '');

        final child = hasImage || visibleText.isNotEmpty
            ? HtmlSectionView(
                html: section.html,
                baseHref: section.href,
                readBytes: widget.readBytes,
                fontSize: widget.fontSize,
                lineHeight: widget.lineHeight,
                margin: widget.margin,
                theme: widget.theme,
              )
            : Center(
                child: Text(
                  section.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: widget.fontSize * 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );

        return Padding(
          padding: contentPadding,
          child: child,
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

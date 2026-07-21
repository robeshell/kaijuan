import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../readers/book/book_theme.dart';
import 'html_section_view.dart';
import 'prepared_section.dart';

/// Scrollable view over the whole book, one section per list item.
///
/// Position is reported as a section index + progress within that section,
/// derived from the overall scroll offset. This is an approximation that works
/// well when chapter lengths are not wildly different.
class ScrollModeView extends StatefulWidget {
  const ScrollModeView({
    super.key,
    required this.sections,
    required this.readBytes,
    required this.initialSection,
    required this.initialProgress,
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
  final double initialProgress;
  final int? jumpTargetSection;
  final void Function(int sectionIndex, double progressInSection)
      onPositionChanged;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final BookReadingTheme theme;

  @override
  State<ScrollModeView> createState() => _ScrollModeViewState();
}

class _ScrollModeViewState extends State<ScrollModeView> {
  final _scrollController = ScrollController();
  int _lastReportedSection = -1;
  double _lastReportedProgress = -1;
  bool _hasJumped = false;
  bool _isProgrammaticJump = false;
  int? _lastJumpTarget;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ScrollModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.jumpTargetSection;
    if (target != null && target != _lastJumpTarget) {
      _lastJumpTarget = target;
      _jumpToSection(target, 0);
    }
  }

  void _jumpToInitial() {
    if (_hasJumped || !mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent == 0) return;

    _hasJumped = true;
    _jumpToSection(widget.initialSection, widget.initialProgress);
  }

  /// Schedules a scroll jump after the current frame to avoid calling
  /// [notifyListeners] synchronously during build.
  void _jumpToSection(int sectionIndex, double progressInSection) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent == 0) return;

      final length = widget.sections.length;
      final target = length <= 1
          ? 0.0
          : ((sectionIndex + progressInSection.clamp(0.0, 1.0)) /
                  (length - 1)) *
              position.maxScrollExtent;

      _isProgrammaticJump = true;
      _scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      _isProgrammaticJump = false;
    });
  }

  void _onScroll() {
    if (_isProgrammaticJump) return;
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent == 0) return;

    final totalProgress =
        (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final sectionWithProgress = totalProgress * (widget.sections.length - 1);
    final sectionIndex = sectionWithProgress.floor();
    final progressInSection =
        (sectionWithProgress - sectionIndex).clamp(0.0, 1.0);

    if (sectionIndex == _lastReportedSection &&
        (progressInSection - _lastReportedProgress).abs() < 0.01) {
      return;
    }
    _lastReportedSection = sectionIndex;
    _lastReportedProgress = progressInSection;
    widget.onPositionChanged(sectionIndex, progressInSection);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.sections.length,
      itemBuilder: (context, index) {
        final section = widget.sections[index];
        final child = HtmlSectionView(
          html: section.html,
          baseHref: section.href,
          readBytes: widget.readBytes,
          fontSize: widget.fontSize,
          lineHeight: widget.lineHeight,
          margin: widget.margin,
          theme: widget.theme,
        );

        // Use LayoutBuilder/NotificationListener to detect when maxScrollExtent
        // becomes available so the initial jump can happen after first layout.
        if (index == widget.sections.length - 1) {
          return NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _jumpToInitial();
              return false;
            },
            child: child,
          );
        }
        return child;
      },
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
}

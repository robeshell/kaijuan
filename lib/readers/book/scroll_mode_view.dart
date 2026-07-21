import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../readers/book/book_theme.dart';
import 'book_models.dart';
import 'html_section_view.dart';
import 'prepared_section.dart';

/// Scrollable view over the whole book, one section per list item.
///
/// Progress is derived from **measured section heights**, not equal-length
/// chapter approximation. Pending jumps are retried until layout can satisfy
/// them (caller clears via [onJumpApplied]).
class ScrollModeView extends StatefulWidget {
  const ScrollModeView({
    super.key,
    required this.sections,
    required this.readBytes,
    this.packageStylesheets = const [],
    this.ensureSection,
    required this.initialSection,
    required this.initialProgress,
    this.jumpTarget,
    this.onJumpApplied,
    required this.onPositionChanged,
    this.onLinkTap,
    required this.fontSize,
    required this.lineHeight,
    required this.margin,
    required this.theme,
  });

  final List<PreparedSection> sections;
  final Future<Uint8List?> Function(String entry) readBytes;
  final List<String> packageStylesheets;

  /// Lazily prepare spine HTML before a list item builds.
  final Future<void> Function(int index)? ensureSection;
  final int initialSection;
  final double initialProgress;
  final BookLocator? jumpTarget;
  final VoidCallback? onJumpApplied;
  final void Function(int sectionIndex, double progressInSection)
  onPositionChanged;
  final void Function(String url, {String baseHref})? onLinkTap;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final BookReadingTheme theme;

  @override
  State<ScrollModeView> createState() => _ScrollModeViewState();
}

class _ScrollModeViewState extends State<ScrollModeView> {
  final _scrollController = ScrollController();
  late List<double?> _sectionHeights;
  final _ensureFutures = <int, Future<void>>{};

  int _lastReportedSection = -1;
  double _lastReportedProgress = -1;
  bool _isProgrammaticJump = false;
  bool _didInitialJump = false;

  /// Jump that still needs a successful scroll (initial restore or pending).
  ({int section, double progress})? _outstandingJump;

  @override
  void initState() {
    super.initState();
    _sectionHeights = List<double?>.filled(widget.sections.length, null);
    _scrollController.addListener(_onScroll);
    _outstandingJump = (
      section: widget.initialSection,
      progress: widget.initialProgress,
    );
  }

  @override
  void didUpdateWidget(covariant ScrollModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections.length != widget.sections.length) {
      _sectionHeights = List<double?>.filled(widget.sections.length, null);
      _didInitialJump = false;
    }

    final target = widget.jumpTarget;
    if (target != null) {
      final same =
          _outstandingJump != null &&
          _outstandingJump!.section == target.sectionIndex &&
          (_outstandingJump!.progress - target.progressInSection).abs() < 1e-9;
      if (!same) {
        _outstandingJump = (
          section: target.sectionIndex,
          progress: target.progressInSection,
        );
        _tryOutstandingJump();
      }
    }
  }

  void _onSectionHeight(int index, double height) {
    if (index < 0 || index >= _sectionHeights.length) return;
    final previous = _sectionHeights[index];
    if (previous != null && (previous - height).abs() < 0.5) return;
    _sectionHeights[index] = height;
    _tryOutstandingJump();
    if (!_isProgrammaticJump) {
      _onScroll();
    }
  }

  bool _heightsKnownThrough(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sectionHeights.length) {
      return false;
    }
    for (var i = 0; i <= sectionIndex; i++) {
      if (_sectionHeights[i] == null) return false;
    }
    return true;
  }

  double? _offsetFor(int sectionIndex, double progressInSection) {
    if (!_heightsKnownThrough(sectionIndex)) return null;
    var offset = 0.0;
    for (var i = 0; i < sectionIndex; i++) {
      offset += _sectionHeights[i]!;
    }
    offset +=
        _sectionHeights[sectionIndex]! * progressInSection.clamp(0.0, 1.0);
    return offset;
  }

  /// Average known section height; used to coax ListView into building ahead.
  double _estimatedSectionHeight() {
    var sum = 0.0;
    var count = 0;
    for (final h in _sectionHeights) {
      if (h != null && h > 0) {
        sum += h;
        count++;
      }
    }
    if (count == 0) return 800;
    return sum / count;
  }

  void _tryOutstandingJump() {
    final jump = _outstandingJump;
    if (jump == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _outstandingJump != jump) return;
      if (!_scrollController.hasClients) return;

      final exact = _offsetFor(jump.section, jump.progress);
      if (exact != null) {
        final position = _scrollController.position;
        _isProgrammaticJump = true;
        _scrollController.jumpTo(exact.clamp(0.0, position.maxScrollExtent));
        _isProgrammaticJump = false;
        _outstandingJump = null;
        _didInitialJump = true;
        widget.onJumpApplied?.call();
        return;
      }

      // Nudge scroll so ListView builds intervening sections and reports heights.
      final estimate = _estimatedSectionHeight() * jump.section;
      final position = _scrollController.position;
      final target = estimate.clamp(0.0, position.maxScrollExtent);
      if ((position.pixels - target).abs() > 1) {
        _isProgrammaticJump = true;
        _scrollController.jumpTo(target);
        _isProgrammaticJump = false;
      }
    });
  }

  void _onScroll() {
    if (_isProgrammaticJump) return;
    if (!mounted || !_scrollController.hasClients) return;

    final pixels = _scrollController.position.pixels;
    final mapped = _locatorFromOffset(pixels);
    if (mapped == null) return;

    final sectionIndex = mapped.sectionIndex;
    final progressInSection = mapped.progressInSection;

    if (sectionIndex == _lastReportedSection &&
        (progressInSection - _lastReportedProgress).abs() < 0.01) {
      return;
    }
    _lastReportedSection = sectionIndex;
    _lastReportedProgress = progressInSection;
    widget.onPositionChanged(sectionIndex, progressInSection);
  }

  BookLocator? _locatorFromOffset(double pixels) {
    if (_sectionHeights.isEmpty) return null;

    // Single chapter: progress is viewport-relative within that section height.
    if (_sectionHeights.length == 1) {
      final height = _sectionHeights[0];
      if (height == null || height <= 0) {
        return const BookLocator(sectionIndex: 0);
      }
      final viewport = _scrollController.position.viewportDimension;
      final scrollable = (height - viewport).clamp(0.0, double.infinity);
      final progress = scrollable <= 0
          ? 0.0
          : (pixels / scrollable).clamp(0.0, 1.0);
      return BookLocator(sectionIndex: 0, progressInSection: progress);
    }

    var offset = 0.0;
    for (var i = 0; i < _sectionHeights.length; i++) {
      final height = _sectionHeights[i];
      if (height == null) {
        // Fall back to last fully known section.
        if (i == 0) return const BookLocator(sectionIndex: 0);
        return BookLocator(sectionIndex: i - 1, progressInSection: 1);
      }
      if (pixels < offset + height || i == _sectionHeights.length - 1) {
        final local = height <= 0
            ? 0.0
            : ((pixels - offset) / height).clamp(0.0, 1.0);
        return BookLocator(sectionIndex: i, progressInSection: local);
      }
      offset += height;
    }
    return BookLocator(
      sectionIndex: _sectionHeights.length - 1,
      progressInSection: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        if (!_didInitialJump) {
          _tryOutstandingJump();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.sections.length,
        itemBuilder: (context, index) {
          final section = widget.sections[index];
          final ensure = widget.ensureSection;
          if (ensure != null && section.html.isEmpty) {
            final future = _ensureFutures.putIfAbsent(
              index,
              () => ensure(index),
            );
            return FutureBuilder<void>(
              future: future,
              builder: (context, snapshot) {
                final ready = widget.sections[index];
                if (ready.html.isEmpty) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _SectionSizeReporter(
                  onHeight: (height) => _onSectionHeight(index, height),
                  child: HtmlSectionView(
                    html: ready.html,
                    baseHref: ready.href,
                    readBytes: widget.readBytes,
                    packageStylesheets: widget.packageStylesheets,
                    sectionStylesheets: ready.sectionStylesheets,
                    fontSize: widget.fontSize,
                    lineHeight: widget.lineHeight,
                    margin: widget.margin,
                    theme: widget.theme,
                    onLinkTap: widget.onLinkTap,
                  ),
                );
              },
            );
          }
          return _SectionSizeReporter(
            onHeight: (height) => _onSectionHeight(index, height),
            child: HtmlSectionView(
              html: section.html,
              baseHref: section.href,
              readBytes: widget.readBytes,
              packageStylesheets: widget.packageStylesheets,
              sectionStylesheets: section.sectionStylesheets,
              fontSize: widget.fontSize,
              lineHeight: widget.lineHeight,
              margin: widget.margin,
              theme: widget.theme,
              onLinkTap: widget.onLinkTap,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
}

/// Reports child height after layout without affecting layout itself.
class _SectionSizeReporter extends SingleChildRenderObjectWidget {
  const _SectionSizeReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSectionSizeReporter(onHeight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSectionSizeReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderSectionSizeReporter extends RenderProxyBox {
  _RenderSectionSizeReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_lastHeight != null && (_lastHeight! - height).abs() < 0.5) return;
    _lastHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onHeight(height);
    });
  }
}

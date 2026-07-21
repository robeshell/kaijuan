import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_svg/flutter_html_svg.dart';
import 'package:flutter_html_table/flutter_html_table.dart';

import '../../../presentation/controllers/book_reader_controller.dart';
import '../book_theme.dart';
import 'page_block.dart';
import 'paginator.dart';

/// Renders a paginated book as a horizontal [PageView].
class PagedModeView extends StatefulWidget {
  const PagedModeView({
    super.key,
    required this.result,
    required this.readBytes,
    required this.controller,
    required this.onPageChanged,
    required this.pageSize,
    required this.theme,
    this.onLinkTap,
    this.textScaler = TextScaler.noScaling,
  });

  final PaginatorResult result;
  final Future<Uint8List?> Function(String entry) readBytes;
  final BookReaderController controller;
  final void Function(int pageIndex) onPageChanged;
  final void Function(String url, {String baseHref})? onLinkTap;
  final Size pageSize;
  final BookReadingTheme theme;
  final TextScaler textScaler;

  @override
  State<PagedModeView> createState() => _PagedModeViewState();
}

class _PagedModeViewState extends State<PagedModeView> {
  late final PageController _pageController;
  int _lastReportedPage = -1;

  /// > 0 when one or more programmatic [animateToPage] calls are in flight.
  /// Using a counter rather than a bool so that when a new animation
  /// interrupts a previous one the old Future's completion does not
  /// prematurely clear the guard. Only the last animation's completion
  /// brings the count back to 0.
  int _programmaticJumpCount = 0;

  final _imageFutures = <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.controller.pageIndex);
    _lastReportedPage = widget.controller.pageIndex;
    widget.controller.addListener(_onControllerPageChanged);
  }

  @override
  void didUpdateWidget(PagedModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) {
      _imageFutures.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _bytesFor(String src) {
    return _imageFutures.putIfAbsent(src, () => widget.readBytes(src));
  }

  void _onControllerPageChanged() {
    if (!_pageController.hasClients) return;
    final maxPage = widget.result.pages.length - 1;
    if (maxPage < 0) return;
    final target = widget.controller.pageIndex.clamp(0, maxPage);
    final current = _pageController.page?.round() ?? widget.controller.pageIndex;
    if (target == current) return;
    _programmaticJumpCount++;
    _pageController
        .animateToPage(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() => _programmaticJumpCount--);
  }

  void _onPageChanged(int index) {
    if (_programmaticJumpCount > 0) return;
    if (index == _lastReportedPage) return;
    _lastReportedPage = index;
    widget.onPageChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      onPageChanged: _onPageChanged,
      itemCount: widget.result.pages.length,
      itemBuilder: (context, index) {
        final page = widget.result.pages[index];
        return _PagedPageBody(
          page: page,
          pageSize: widget.pageSize,
          theme: widget.theme,
          textScaler: widget.textScaler,
          onLinkTap: widget.onLinkTap,
          imageBuilder: (block, fg) => _buildImage(block, fg),
        );
      },
    );
  }

  Widget _buildImage(ImageBlock block, Color fg) {
    final natural = block.displaySize;
    final maxHeight = widget.pageSize.height;
    final scaledHeight = natural != null && natural.width > 0
        ? widget.pageSize.width / natural.width * natural.height
        : maxHeight;
    final height = math.min(scaledHeight, maxHeight);

    final bytes = block.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return _memoryImage(bytes, height, fg);
    }

    return FutureBuilder<Uint8List?>(
      future: _bytesFor(block.src),
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded == null || loaded.isEmpty) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SizedBox(width: widget.pageSize.width, height: height);
          }
          return _ImagePlaceholder(fg: fg);
        }
        return _memoryImage(loaded, height, fg);
      },
    );
  }

  Widget _memoryImage(Uint8List bytes, double height, Color fg) {
    return SizedBox(
      width: widget.pageSize.width,
      height: height,
      child: Image.memory(
        bytes,
        width: widget.pageSize.width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _ImagePlaceholder(fg: fg),
      ),
    );
  }
}

class _PagedPageBody extends StatefulWidget {
  const _PagedPageBody({
    required this.page,
    required this.pageSize,
    required this.theme,
    required this.textScaler,
    required this.imageBuilder,
    this.onLinkTap,
  });

  final PageSpec page;
  final Size pageSize;
  final BookReadingTheme theme;
  final TextScaler textScaler;
  final void Function(String url, {String baseHref})? onLinkTap;
  final Widget Function(ImageBlock block, Color fg) imageBuilder;

  @override
  State<_PagedPageBody> createState() => _PagedPageBodyState();
}

class _PagedPageBodyState extends State<_PagedPageBody> {
  final _linkRecognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
    super.dispose();
  }

  InlineSpan _textSpan(TextBlock block) {
    final onLinkTap = widget.onLinkTap;
    return TextSpan(
      style: block.baseStyle,
      children: [
        for (final run in block.runs)
          if (run.href != null && onLinkTap != null)
            TextSpan(
              text: run.text,
              style: run.style,
              recognizer: () {
                final recognizer = TapGestureRecognizer()
                  ..onTap = () => onLinkTap(run.href!);
                _linkRecognizers.add(recognizer);
                return recognizer;
              }(),
            )
          else
            TextSpan(text: run.text, style: run.style),
      ],
    );
  }

  Widget _buildBlock(PageBlock block, Color fg) {
    switch (block) {
      case TextBlock textBlock:
        return Padding(
          padding: EdgeInsets.only(
            left: textBlock.textIndent,
            bottom: textBlock.paragraphSpacing,
          ),
          child: RichText(
            text: _textSpan(textBlock),
            textScaler: widget.textScaler,
          ),
        );
      case ImageBlock imageBlock:
        return Padding(
          padding: EdgeInsets.only(bottom: imageBlock.paragraphSpacing),
          child: widget.imageBuilder(imageBlock, fg),
        );
      case RuleBlock ruleBlock:
        return Padding(
          padding: EdgeInsets.only(bottom: ruleBlock.paragraphSpacing),
          child: SizedBox(
            height: 8,
            child: Center(
              child: Divider(
                height: 1,
                thickness: 1,
                color: fg.withValues(alpha: 0.2),
              ),
            ),
          ),
        );
      case TableBlock tableBlock:
        return SizedBox(
          width: widget.pageSize.width,
          height: widget.pageSize.height,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Html(
              data: tableBlock.html,
              extensions: const [TableHtmlExtension(), SvgHtmlExtension()],
              style: {
                'table': Style(
                  color: fg,
                  fontSize: FontSize(widget.pageSize.width * 0.03),
                ),
              },
            ),
          ),
        );
    }
    throw StateError('Unexpected PageBlock: $block');
  }

  @override
  Widget build(BuildContext context) {
    // Recreate recognizers for this build; dispose previous first.
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();

    final fg = Color(widget.theme.foregroundArgb);
    final pageWidth = widget.pageSize.width;
    final pageHeight = widget.pageSize.height;

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: pageWidth,
        height: pageHeight,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: pageWidth,
            maxWidth: pageWidth,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final block in widget.page.blocks) _buildBlock(block, fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.fg});

  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            color: fg.withValues(alpha: 0.5),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            '图片',
            style: TextStyle(color: fg.withValues(alpha: 0.5), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_svg/flutter_html_svg.dart';
import 'package:flutter_html_table/flutter_html_table.dart';

import '../book_theme.dart';
import 'page_block.dart';
import 'paginator.dart';

/// Renders a paginated book as a horizontal [PageView].
class PagedModeView extends StatefulWidget {
  const PagedModeView({
    super.key,
    required this.result,
    required this.readBytes,
    required this.initialPage,
    this.jumpTargetPage,
    required this.onPageChanged,
    required this.pageSize,
    required this.theme,
    this.textScaler = TextScaler.noScaling,
  });

  final PaginatorResult result;
  final Future<Uint8List?> Function(String entry) readBytes;
  final int initialPage;
  final int? jumpTargetPage;
  final void Function(int pageIndex) onPageChanged;
  final Size pageSize;
  final BookReadingTheme theme;
  final TextScaler textScaler;

  @override
  State<PagedModeView> createState() => _PagedModeViewState();
}

class _PagedModeViewState extends State<PagedModeView> {
  late final PageController _pageController;
  int _lastReportedPage = -1;
  int? _lastJumpTarget;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPage);
    _lastReportedPage = widget.initialPage;
  }

  @override
  void didUpdateWidget(covariant PagedModeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.jumpTargetPage;
    if (target != null && target != _lastJumpTarget) {
      _lastJumpTarget = target;
      _jumpToPage(target);
    }
  }

  void _jumpToPage(int pageIndex) {
    if (!_pageController.hasClients) return;
    final target = pageIndex.clamp(0, widget.result.pages.length - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    if (index == _lastReportedPage) return;
    _lastReportedPage = index;
    widget.onPageChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final fg = Color(widget.theme.foregroundArgb);

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      onPageChanged: _onPageChanged,
      itemCount: widget.result.pages.length,
      itemBuilder: (context, index) {
        final page = widget.result.pages[index];
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.pageSize.width * 0.06,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final block in page.blocks) _buildBlock(block, fg),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBlock(PageBlock block, Color fg) {
    switch (block) {
      case TextBlock textBlock:
        return RichText(
          text: textBlock.span,
          textScaler: widget.textScaler,
        );
      case ImageBlock imageBlock:
        return _buildImage(imageBlock, fg);
      case RuleBlock _:
        return Divider(
          height: 24,
          color: fg.withValues(alpha: 0.2),
        );
      case TableBlock tableBlock:
        return Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Html(
              data: tableBlock.html,
              extensions: const [
                TableHtmlExtension(),
                SvgHtmlExtension(),
              ],
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

  Widget _buildImage(ImageBlock block, Color fg) {
    final bytes = block.bytes;
    if (bytes == null || bytes.isEmpty) {
      return _ImagePlaceholder(fg: fg);
    }
    return Image.memory(
      bytes,
      width: widget.pageSize.width,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _ImagePlaceholder(fg: fg),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
          Icon(Icons.image_outlined, color: fg.withValues(alpha: 0.5), size: 32),
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

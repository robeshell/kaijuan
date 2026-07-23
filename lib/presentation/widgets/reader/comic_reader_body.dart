import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../readers/comic/comic_models.dart';
import '../../controllers/comic_reader_controller.dart';
import 'comic_page_image.dart';
import 'comic_zoom_host.dart';

/// Mode-specific page host for the comic reader.
class ComicReaderBody extends StatelessWidget {
  const ComicReaderBody({super.key, required this.controller});

  final ComicReaderController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.mode) {
      ComicReaderMode.slide => _SlideBody(controller: controller),
      ComicReaderMode.staticView => _StaticBody(controller: controller),
      ComicReaderMode.vertical => _VerticalBody(controller: controller),
      ComicReaderMode.spread => _SpreadBody(controller: controller),
    };
  }
}

void _handleTapZones({
  required ComicReaderController controller,
  required Offset localPosition,
  required double width,
}) {
  // Match book: when chrome is up, any tap only dismisses it.
  if (controller.chromeVisible) {
    controller.hideChrome();
    return;
  }
  final edge = width * 0.25;
  final rtl = controller.direction == ComicReadDirection.rtl;
  final x = localPosition.dx;
  if (x < edge) {
    if (rtl) {
      controller.goForward();
    } else {
      controller.goBackward();
    }
  } else if (x > width - edge) {
    if (rtl) {
      controller.goBackward();
    } else {
      controller.goForward();
    }
  } else {
    controller.toggleChrome();
  }
}

class _SlideBody extends StatefulWidget {
  const _SlideBody({required this.controller});

  final ComicReaderController controller;

  @override
  State<_SlideBody> createState() => _SlideBodyState();
}

class _SlideBodyState extends State<_SlideBody> {
  late final PageController _pageController;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.controller.pageIndex);
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _pageController.dispose();
    super.dispose();
  }

  void _onController() {
    if (!_pageController.hasClients) return;
    final target = widget.controller.pageIndex;
    final current = _pageController.page?.round() ?? target;
    if (current != target && !_syncing) {
      _syncing = true;
      _pageController
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final reverse = c.direction == ComicReadDirection.rtl;
    return ComicZoomHost(
      resetToken: '${c.pageIndex}:${c.mode.name}',
      onTapAt: (pos, width) => _handleTapZones(
        controller: c,
        localPosition: pos,
        width: width,
      ),
      child: PageView.builder(
        controller: _pageController,
        reverse: reverse,
        itemCount: c.pageCount,
        onPageChanged: (i) {
          if (c.pageIndex != i) c.jumpTo(i);
        },
        itemBuilder: (context, index) {
          return ComicPageImage(controller: c, pageIndex: index);
        },
      ),
    );
  }
}

class _StaticBody extends StatelessWidget {
  const _StaticBody({required this.controller});

  final ComicReaderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ComicZoomHost(
      resetToken: '${c.pageIndex}:${c.mode.name}',
      onTapAt: (pos, width) => _handleTapZones(
        controller: c,
        localPosition: pos,
        width: width,
      ),
      child: ComicPageImage(
        controller: c,
        pageIndex: c.pageIndex,
      ),
    );
  }
}

class _VerticalBody extends StatefulWidget {
  const _VerticalBody({required this.controller});

  final ComicReaderController controller;

  @override
  State<_VerticalBody> createState() => _VerticalBodyState();
}

/// Fallback width/height when page pixels are unknown.
const _kFallbackAspect = 0.7;

class _VerticalBodyState extends State<_VerticalBody> {
  final _scrollController = ScrollController();
  final _aspects = <int, double>{};
  bool _syncingFromController = false;
  bool _syncingFromScroll = false;
  bool _didInitialJump = false;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  double _aspectFor(int index) => _aspects[index] ?? _kFallbackAspect;

  double _extentFor(int index, double width) {
    final aspect = _aspectFor(index);
    if (aspect <= 0 || width <= 0) return 0;
    return width / aspect;
  }

  double _offsetForPage(int pageIndex, double width) {
    var offset = 0.0;
    final last = pageIndex.clamp(0, math.max(0, widget.controller.pageCount));
    for (var i = 0; i < last; i++) {
      offset += _extentFor(i, width);
    }
    return offset;
  }

  int _pageIndexForOffset(double offset, double width) {
    final count = widget.controller.pageCount;
    if (count <= 0 || width <= 0) return 0;
    var cursor = 0.0;
    for (var i = 0; i < count; i++) {
      final extent = _extentFor(i, width);
      if (offset + 1 < cursor + extent / 2) {
        return i.clamp(0, count - 1);
      }
      cursor += extent;
    }
    return count - 1;
  }

  void _onScroll() {
    if (_syncingFromController || _width <= 0) return;
    if (!_scrollController.hasClients) return;
    final c = widget.controller;
    final index = _pageIndexForOffset(_scrollController.offset, _width);
    if (index == c.pageIndex) return;
    _syncingFromScroll = true;
    c.reportVisiblePage(index);
    _syncingFromScroll = false;
  }

  void _onController() {
    if (_syncingFromScroll || _width <= 0) return;
    if (!_scrollController.hasClients) return;
    final c = widget.controller;
    final target = _offsetForPage(c.pageIndex, _width);
    final current = _scrollController.offset;
    final pageExtent = _extentFor(c.pageIndex, _width);
    if (pageExtent > 0 && (current - target).abs() < pageExtent * 0.35) {
      return;
    }
    _syncingFromController = true;
    _scrollController
        .animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
      _syncingFromController = false;
    });
  }

  void _ensureInitialOffset() {
    if (_didInitialJump || _width <= 0) return;
    if (!_scrollController.hasClients) return;
    final c = widget.controller;
    if (c.pageIndex <= 0) {
      _didInitialJump = true;
      return;
    }
    final target = _offsetForPage(c.pageIndex, _width);
    _syncingFromController = true;
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
    _syncingFromController = false;
    _didInitialJump = true;
  }

  void _onPageSize(int index, double aspect) {
    if (aspect <= 0) return;
    final prev = _aspects[index];
    if (prev != null && (prev - aspect).abs() < 0.001) return;
    setState(() => _aspects[index] = aspect);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width != _width) {
          _width = width;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!_didInitialJump) {
              _ensureInitialOffset();
            } else {
              _onController();
            }
          });
        }

        return ComicZoomHost(
          enabled: false,
          resetToken: c.mode.name,
          onTapAt: (_, _) {
            if (c.chromeVisible) {
              c.hideChrome();
            } else {
              c.toggleChrome();
            }
          },
          child: ListView.builder(
            controller: _scrollController,
            itemCount: c.pageCount,
            itemBuilder: (context, index) {
              final aspect = _aspectFor(index);
              return AspectRatio(
                aspectRatio: aspect,
                child: ComicPageImage(
                  controller: c,
                  pageIndex: index,
                  fit: BoxFit.fitWidth,
                  onImageSize: (size) {
                    if (size.height <= 0) return;
                    _onPageSize(index, size.width / size.height);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Minimum width/height ratio to show a glued two-page spread.
const _kMinSpreadViewportAspect = 1.05;

class _SpreadBody extends StatelessWidget {
  const _SpreadBody({required this.controller});

  final ComicReaderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final spread = c.spreadFor(c.pageIndex);
        final rtl = c.direction == ComicReadDirection.rtl;
        final wideEnough = constraints.maxWidth > 0 &&
            constraints.maxHeight > 0 &&
            constraints.maxWidth / constraints.maxHeight >=
                _kMinSpreadViewportAspect;
        final useSpread = spread.usesSpreadLayout && wideEnough;

        if (!useSpread) {
          return ComicZoomHost(
            resetToken: '${c.pageIndex}:${c.mode.name}:single',
            onTapAt: (pos, width) => _handleTapZones(
              controller: c,
              localPosition: pos,
              width: width,
            ),
            child: ComicPageImage(
              controller: c,
              pageIndex: c.pageIndex,
            ),
          );
        }

        final left = rtl ? spread.secondaryPage! : spread.primaryPage;
        final right = rtl ? spread.primaryPage : spread.secondaryPage!;

        return ComicZoomHost(
          resetToken: '${c.pageIndex}:${c.mode.name}:spread',
          onTapAt: (pos, width) => _handleTapZones(
            controller: c,
            localPosition: pos,
            width: width,
          ),
          child: _GluedSpread(
            controller: c,
            leftIndex: left,
            rightIndex: right,
          ),
        );
      },
    );
  }
}

/// Two pages edge-to-edge, scaled as one unit into the viewport.
class _GluedSpread extends StatefulWidget {
  const _GluedSpread({
    required this.controller,
    required this.leftIndex,
    required this.rightIndex,
  });

  final ComicReaderController controller;
  final int leftIndex;
  final int rightIndex;

  @override
  State<_GluedSpread> createState() => _GluedSpreadState();
}

class _GluedSpreadState extends State<_GluedSpread> {
  ui.Image? _left;
  ui.Image? _right;
  bool _loading = true;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _GluedSpread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftIndex != widget.leftIndex ||
        oldWidget.rightIndex != widget.rightIndex ||
        oldWidget.controller != widget.controller) {
      _load();
    }
  }

  @override
  void dispose() {
    _left?.dispose();
    _right?.dispose();
    _left = null;
    _right = null;
    super.dispose();
  }

  Future<ui.Image?> _retainClone(int index) async {
    final cache = widget.controller.cache;
    if (cache == null) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      final src = await cache.get(index);
      if (src == null) return null;
      try {
        return src.clone();
      } catch (_) {
        // Evicted/disposed between get and clone; retry.
      }
    }
    return null;
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    setState(() => _loading = true);

    final left = await _retainClone(widget.leftIndex);
    final right = await _retainClone(widget.rightIndex);
    if (!mounted || gen != _loadGen) {
      left?.dispose();
      right?.dispose();
      return;
    }

    _left?.dispose();
    _right?.dispose();
    setState(() {
      _left = left;
      _right = right;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final right = _right;
    if (_loading || left == null || right == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final h1 = left.height.toDouble();
    final h2 = right.height.toDouble();
    final targetH = math.max(h1, h2);
    final leftW = left.width.toDouble() * targetH / h1;
    final rightW = right.width.toDouble() * targetH / h2;

    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RawImage(
              image: left,
              width: leftW,
              height: targetH,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
            RawImage(
              image: right,
              width: rightW,
              height: targetH,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
          ],
        ),
      ),
    );
  }
}

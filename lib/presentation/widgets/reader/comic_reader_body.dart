import 'package:flutter/material.dart';

import '../../../readers/comic/comic_models.dart';
import '../../controllers/comic_reader_controller.dart';
import 'comic_page_image.dart';

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

/// Tap zones: left 25% / right 25% turn pages; center toggles chrome.
class _TapZones extends StatelessWidget {
  const _TapZones({
    required this.controller,
    required this.child,
  });

  final ComicReaderController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final edge = w * 0.25;
        final rtl = controller.direction == ComicReadDirection.rtl;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            // Left edge
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: edge,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (rtl) {
                    controller.goForward();
                  } else {
                    controller.goBackward();
                  }
                },
              ),
            ),
            // Right edge
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: edge,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (rtl) {
                    controller.goBackward();
                  } else {
                    controller.goForward();
                  }
                },
              ),
            ),
            // Center
            Positioned(
              left: edge,
              right: edge,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: controller.toggleChrome,
              ),
            ),
          ],
        );
      },
    );
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
    return _TapZones(
      controller: c,
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
    return _TapZones(
      controller: controller,
      child: ComicPageImage(
        controller: controller,
        pageIndex: controller.pageIndex,
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

/// Fixed page aspect for vertical list: width / height = 0.7 → height = w / 0.7.
const _kVerticalAspect = 0.7;

class _VerticalBodyState extends State<_VerticalBody> {
  final _scrollController = ScrollController();
  bool _syncingFromController = false;
  bool _syncingFromScroll = false;
  double _itemExtent = 0;
  bool _didInitialJump = false;

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

  void _onScroll() {
    if (_syncingFromController || _itemExtent <= 0) return;
    if (!_scrollController.hasClients) return;
    final c = widget.controller;
    final index = comicVerticalPageIndex(
      scrollOffset: _scrollController.offset,
      itemExtent: _itemExtent,
      pageCount: c.pageCount,
    );
    if (index == c.pageIndex) return;
    _syncingFromScroll = true;
    c.reportVisiblePage(index);
    _syncingFromScroll = false;
  }

  void _onController() {
    if (_syncingFromScroll || _itemExtent <= 0) return;
    if (!_scrollController.hasClients) return;
    final c = widget.controller;
    final target = comicVerticalOffsetForPage(
      pageIndex: c.pageIndex,
      itemExtent: _itemExtent,
      pageCount: c.pageCount,
    );
    final current = _scrollController.offset;
    // Ignore tiny differences while the user is still flinging mid-page.
    if ((current - target).abs() < _itemExtent * 0.35) return;
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
    if (_didInitialJump || _itemExtent <= 0) return;
    if (!_scrollController.hasClients) return;
    final c = widget.controller;
    if (c.pageIndex <= 0) {
      _didInitialJump = true;
      return;
    }
    final target = comicVerticalOffsetForPage(
      pageIndex: c.pageIndex,
      itemExtent: _itemExtent,
      pageCount: c.pageCount,
    );
    _syncingFromController = true;
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
    _syncingFromController = false;
    _didInitialJump = true;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final extent = width > 0 ? width / _kVerticalAspect : 0.0;
        if (extent != _itemExtent) {
          _itemExtent = extent;
          // After first layout (or width change), restore scroll to pageIndex.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!_didInitialJump) {
              _ensureInitialOffset();
            } else {
              _onController();
            }
          });
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: c.toggleChrome,
          child: ListView.builder(
            controller: _scrollController,
            itemExtent: extent > 0 ? extent : null,
            itemCount: c.pageCount,
            itemBuilder: (context, index) {
              return ComicPageImage(
                controller: c,
                pageIndex: index,
                fit: BoxFit.fitWidth,
              );
            },
          ),
        );
      },
    );
  }
}

class _SpreadBody extends StatelessWidget {
  const _SpreadBody({required this.controller});

  final ComicReaderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final spread = c.spreadFor(c.pageIndex);
    final rtl = c.direction == ComicReadDirection.rtl;

    Widget page(int? index) {
      if (index == null) return const SizedBox.expand();
      return ComicPageImage(controller: c, pageIndex: index);
    }

    final left = rtl ? spread.secondaryPage : spread.primaryPage;
    final right = rtl ? spread.primaryPage : spread.secondaryPage;

    return _TapZones(
      controller: c,
      child: spread.usesSpreadLayout
          ? Row(
              children: [
                Expanded(child: page(left)),
                Expanded(child: page(right)),
              ],
            )
          : page(spread.primaryPage),
    );
  }
}

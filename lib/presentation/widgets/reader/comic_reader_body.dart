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

class _VerticalBodyState extends State<_VerticalBody> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: c.toggleChrome,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: c.pageCount,
        itemBuilder: (context, index) {
          return AspectRatio(
            aspectRatio: 0.7,
            child: ComicPageImage(
              controller: c,
              pageIndex: index,
              fit: BoxFit.fitWidth,
            ),
          );
        },
      ),
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

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../controllers/book_reader_controller.dart';

/// Always-on WeChat Reading–style page meta: chapter (top-left) and whole-book
/// progress (bottom-right). Sits in the Foliate vertical margin band and fades
/// when the interactive glass chrome is shown.
class BookPageMetaOverlay extends StatelessWidget {
  const BookPageMetaOverlay({super.key, required this.controller});

  final BookReaderController controller;

  @override
  Widget build(BuildContext context) {
    final theme = controller.readingTheme;
    final meta = Color(theme.metaColorArgb);
    final visible = !controller.chromeVisible;
    final short = context.appIsShortViewport;
    final edge = short ? 12.0 : 20.0;
    final vPad = short ? 6.0 : 10.0;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(edge, vPad, edge, vPad),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      controller.currentChapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: meta,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    controller.bookProgressLabel,
                    style: TextStyle(
                      color: meta,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

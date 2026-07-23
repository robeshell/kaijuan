import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../controllers/comic_reader_controller.dart';
import 'comic_reader_tool_strip.dart';
import 'glass_bar.dart';

/// Top + bottom chrome for the comic reader — same opaque surface language as
/// [BookReaderChrome] (no frosted glass on the tool strip).
class ComicReaderChrome extends StatelessWidget {
  const ComicReaderChrome({
    super.key,
    required this.controller,
    required this.onBack,
  });

  final ComicReaderController controller;
  final VoidCallback onBack;

  static const double _barHeight = 56;
  static const double _macTrafficLightClearance = 78;

  @override
  Widget build(BuildContext context) {
    final theme = controller.readingTheme;
    final surface = Color(theme.backgroundArgb);
    final fg = Color(theme.foregroundArgb);
    final fgMuted = Color(theme.metaColorArgb);
    final accent = Theme.of(context).colorScheme.primary;

    final leadingClearance =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
        ? _macTrafficLightClearance
        : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GlassBar(
            glass: surface,
            blur: false,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: _barHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    children: [
                      SizedBox(width: leadingClearance),
                      IconButton(
                        tooltip: '返回',
                        onPressed: onBack,
                        icon: Icon(
                          Icons.arrow_back_outlined,
                          color: fg,
                          weight: 300,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              controller.item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              controller.pageLabel,
                              style: TextStyle(color: fgMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: controller.isCurrentPageBookmarked
                            ? '移除当前页书签'
                            : '添加当前页书签',
                        onPressed: controller.toggleBookmark,
                        icon: Icon(
                          controller.isCurrentPageBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border_outlined,
                          color: fg,
                          weight: 300,
                        ),
                      ),
                      if (leadingClearance > 0)
                        SizedBox(width: leadingClearance - 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: GlassBar(
            glass: surface,
            blur: false,
            child: SafeArea(
              top: false,
              child: Material(
                type: MaterialType.transparency,
                child: ComicReaderToolStrip(
                  controller: controller,
                  fg: fg,
                  fgMuted: fgMuted,
                  accent: accent,
                  chromeVisible: controller.chromeVisible,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

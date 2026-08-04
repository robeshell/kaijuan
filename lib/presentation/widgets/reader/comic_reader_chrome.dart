import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../controllers/comic_reader_controller.dart';
import 'comic_reader_tool_strip.dart';
import 'glass_bar.dart';
import 'reader_chrome_top_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = controller.readingTheme;
    final surface = Color(theme.backgroundArgb);
    final fg = Color(theme.foregroundArgb);
    final fgMuted = Color(theme.metaColorArgb);
    final accent = Theme.of(context).colorScheme.primary;
    final density = readerChromeIconDensity(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ReaderChromeTopBar(
            surface: surface,
            fg: fg,
            fgMuted: fgMuted,
            title: controller.item.title,
            subtitle: controller.pageLabel,
            onBack: onBack,
            trailing: [
              IconButton(
                tooltip: controller.isCurrentPageBookmarked
                    ? '移除当前页书签'
                    : '添加当前页书签',
                visualDensity: density,
                onPressed: controller.toggleBookmark,
                icon: Icon(
                  controller.isCurrentPageBookmarked
                      ? KaijuanIcons.bookmarkFilled
                      : KaijuanIcons.bookmark,
                  color: fg,
                  weight: 300,
                ),
              ),
            ],
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

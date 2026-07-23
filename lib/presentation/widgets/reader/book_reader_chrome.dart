import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../readers/book/book_theme.dart';
import '../../controllers/book_reader_controller.dart';
import 'book_reader_tool_strip.dart';
import 'glass_bar.dart';

/// Top + bottom glass chrome for the reflow book reader.
///
/// Bottom is the WeChat-style tool strip (progress + five keys). Typography /
/// brightness / reading-mode expand above the keys — no Material default sheets.
class BookReaderChrome extends StatelessWidget {
  const BookReaderChrome({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onOpenToc,
  });

  final BookReaderController controller;
  final VoidCallback onBack;
  final VoidCallback onOpenToc;

  /// Clear of macOS traffic lights (same band as [DesktopTitleBar]).
  static const double _macTrafficLightClearance = 78;

  @override
  Widget build(BuildContext context) {
    final theme = controller.readingTheme;
    // Opaque reading surface — translucent glass made the tool strip unreadable.
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
                height: kBookReaderChromeBarHeight,
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
                              controller.progressPercentLabel,
                              style: TextStyle(color: fgMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: controller.isCurrentPositionBookmarked
                            ? '移除当前位置书签'
                            : '添加当前位置书签',
                        onPressed: controller.toggleBookmark,
                        icon: Icon(
                          controller.isCurrentPositionBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border_outlined,
                          color: fg,
                          weight: 300,
                        ),
                      ),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: () => controller.openSearch(),
                        icon: Icon(
                          Icons.search,
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
                child: BookReaderToolStrip(
                  controller: controller,
                  fg: fg,
                  fgMuted: fgMuted,
                  accent: accent,
                  onOpenToc: onOpenToc,
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

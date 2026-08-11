import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../controllers/book_reader_controller.dart';
import 'book_ai_chat_sheet.dart';
import 'book_reader_tool_strip.dart';
import 'glass_bar.dart';
import 'reader_chrome_top_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = controller.preferences.readingTheme;
    // Opaque reading surface — translucent glass made the tool strip unreadable.
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
            subtitle: controller.progressPercentLabel,
            onBack: onBack,
            trailing: [
              IconButton(
                tooltip: controller.isCurrentPositionBookmarked
                    ? '移除当前位置书签'
                    : '添加当前位置书签',
                visualDensity: density,
                onPressed: controller.toggleBookmark,
                icon: Icon(
                  controller.isCurrentPositionBookmarked
                      ? KaijuanIcons.bookmarkFilled
                      : KaijuanIcons.bookmark,
                  color: fg,
                  weight: 300,
                ),
              ),
              IconButton(
                tooltip: '本书 AI',
                visualDensity: density,
                onPressed: () async {
                  controller.hideChrome();
                  // Capture text first; do not clear the page highlight
                  // (default clearSelectionMenu wipes WebView selection).
                  final sel = await controller.annotations.peekSelectedText();
                  controller.annotations.dismissSelectionMenuKeepHighlight();
                  if (!context.mounted) return;
                  await showBookAiChatSheet(
                    context,
                    controller: controller,
                    initialSelection: sel.isEmpty ? null : sel,
                  );
                },
                icon: Icon(KaijuanIcons.aiChat, color: fg, weight: 300),
              ),
              IconButton(
                tooltip: '搜索',
                visualDensity: density,
                onPressed: () => controller.search.openSearch(),
                icon: Icon(KaijuanIcons.search, color: fg, weight: 300),
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

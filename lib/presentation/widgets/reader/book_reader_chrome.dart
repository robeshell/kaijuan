import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../readers/book/book_theme.dart';
import '../../controllers/book_reader_controller.dart';
import 'book_reader_settings_sheet.dart';
import 'glass_bar.dart';

/// Top + bottom glass chrome for the reflow book reader.
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
    final isPureBlack = theme == BookReadingTheme.pureBlack;
    final glass = isPureBlack
        ? const Color(0xB3000000)
        : theme.isDark
            ? const Color(0xB3212124)
            : const Color(0xB3FFFFFF);
    final fg = theme.isDark ? const Color(0xFFF2F2F4) : const Color(0xFF1C1C1E);
    final fgMuted = theme.isDark
        ? const Color(0x99F2F2F4)
        : const Color(0x991C1C1E);

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
            glass: glass,
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
                              style: TextStyle(
                                color: fgMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '目录',
                        onPressed: onOpenToc,
                        icon: Icon(
                          Icons.list_outlined,
                          color: fg,
                          weight: 300,
                        ),
                      ),
                      IconButton(
                        tooltip: '排版',
                        onPressed: () => showBookReaderSettingsSheet(
                          context,
                          controller,
                        ),
                        icon: Icon(
                          Icons.format_size_outlined,
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
            glass: glass,
            child: SafeArea(
              top: false,
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    AppSpacing.x2,
                    AppSpacing.x4,
                    AppSpacing.x3,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: controller.hasPageMode ? '上一页' : '上一节',
                        onPressed: controller.hasPageMode
                            ? (controller.pageIndex > 0
                                ? controller.goPreviousPage
                                : null)
                            : (controller.sectionIndex > 0
                                ? controller.goPreviousSection
                                : null),
                        icon: Icon(
                          Icons.skip_previous_outlined,
                          color: controller.hasPageMode
                              ? (controller.pageIndex > 0 ? fg : fgMuted)
                              : (controller.sectionIndex > 0 ? fg : fgMuted),
                          weight: 300,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          controller.hasPageMode
                              ? controller.pageLabel
                              : '${controller.sectionLabel} 节',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: fg, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: controller.hasPageMode ? '下一页' : '下一节',
                        onPressed: controller.hasPageMode
                            ? (controller.pageIndex < controller.pageCount - 1
                                ? controller.goNextPage
                                : null)
                            : (controller.sectionIndex <
                                    controller.sectionCount - 1
                                ? controller.goNextSection
                                : null),
                        icon: Icon(
                          Icons.skip_next_outlined,
                          color: controller.hasPageMode
                              ? (controller.pageIndex < controller.pageCount - 1
                                  ? fg
                                  : fgMuted)
                              : (controller.sectionIndex <
                                      controller.sectionCount - 1
                                  ? fg
                                  : fgMuted),
                          weight: 300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

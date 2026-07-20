import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../readers/comic/comic_models.dart';
import '../../controllers/comic_reader_controller.dart';

/// Top + bottom glass chrome for the comic reader.
///
/// On desktop the host uses a transparent / custom title bar
/// (`fullSizeContentView` on macOS). The reader is pushed full-window, so
/// chrome must clear traffic lights (mac) and the title-bar band (mac/win).
class ComicReaderChrome extends StatelessWidget {
  const ComicReaderChrome({
    super.key,
    required this.controller,
    required this.onBack,
  });

  final ComicReaderController controller;
  final VoidCallback onBack;

  /// Clear of macOS traffic lights (same band as [DesktopTitleBar]).
  static const double _macTrafficLightClearance = 78;

  @override
  Widget build(BuildContext context) {
    final theme = controller.readingTheme;
    final glass = theme.isDark
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
          child: _GlassBar(
            glass: glass,
            // Top padding from app-level desktop MediaQuery via SafeArea.
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.only(left: leadingClearance),
                child: SizedBox(
                  height: 56,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Row(
                    children: [
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
                        child: Text(
                          controller.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '阅读选项',
                        icon: Icon(
                          Icons.more_horiz_outlined,
                          color: fg,
                          weight: 300,
                        ),
                        onSelected: (value) => _onMenu(value),
                        itemBuilder: (context) => [
                          for (final mode in ComicReaderMode.values)
                            CheckedPopupMenuItem(
                              value: 'mode:${mode.storageValue}',
                              checked: controller.mode == mode,
                              child: Text(mode.label),
                            ),
                          const PopupMenuDivider(),
                          for (final d in ComicReadDirection.values)
                            CheckedPopupMenuItem(
                              value: 'dir:${d.storageValue}',
                              checked: controller.direction == d,
                              child: Text(d.label),
                            ),
                          const PopupMenuDivider(),
                          for (final t in ComicReadingTheme.values)
                            CheckedPopupMenuItem(
                              value: 'theme:${t.storageValue}',
                              checked: controller.readingTheme == t,
                              child: Text(t.label),
                            ),
                        ],
                      ),
                      // Balance leading traffic-light clearance so title stays centered.
                      if (leadingClearance > 0)
                        SizedBox(width: leadingClearance - 8),
                    ],
                    ),
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
          child: _GlassBar(
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            controller.pageLabel,
                            style: TextStyle(color: fgMuted, fontSize: 13),
                          ),
                          const Spacer(),
                          if (controller.mode != ComicReaderMode.vertical)
                            Text(
                              controller.direction.label,
                              style: TextStyle(color: fgMuted, fontSize: 12),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      if (controller.pageCount > 1)
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: (controller.pageCount - 1).toDouble(),
                            value: controller.displayPage
                                .toDouble()
                                .clamp(0, controller.pageCount - 1),
                            onChanged: controller.onSliderChanged,
                            onChangeEnd: controller.onSliderChangeEnd,
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

  void _onMenu(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return;
    switch (parts[0]) {
      case 'mode':
        controller.setMode(ComicReaderMode.fromStorage(parts[1]));
      case 'dir':
        controller.setDirection(ComicReadDirection.fromStorage(parts[1]));
      case 'theme':
        controller.setReadingTheme(ComicReadingTheme.fromStorage(parts[1]));
    }
  }
}

class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.glass, required this.child});

  final Color glass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glass,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

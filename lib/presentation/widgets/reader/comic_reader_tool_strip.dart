import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/comic_reading_preferences.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../readers/comic/comic_models.dart';
import '../../controllers/comic_reader_controller.dart';
import 'comic_thumbnails_sheet.dart';
import 'reader_bookmarks_sheet.dart';
import 'reader_tool_strip_shared.dart';

enum ComicToolStripPanel { brightness, direction, readingMode }

/// Bottom tool strip aligned with the book reader: progress scrubber + keys +
/// expandable panels. Custom tracks — no Material [Slider].
class ComicReaderToolStrip extends StatefulWidget {
  const ComicReaderToolStrip({
    super.key,
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.chromeVisible,
  });

  final ComicReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final bool chromeVisible;

  @override
  State<ComicReaderToolStrip> createState() => _ComicReaderToolStripState();
}

class _ComicReaderToolStripState extends State<ComicReaderToolStrip> {
  ComicToolStripPanel? _panel;
  double? _dragFraction;

  ComicReaderController get controller => widget.controller;

  @override
  void didUpdateWidget(covariant ComicReaderToolStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.chromeVisible && _panel != null) {
      _panel = null;
    }
  }

  void _togglePanel(ComicToolStripPanel panel) {
    setState(() => _panel = _panel == panel ? null : panel);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fraction = (_dragFraction ?? controller.progressFraction).clamp(
          0.0,
          1.0,
        );
        final progressPct = (fraction * 100).toStringAsFixed(1);

        return ReaderToolStripLayout(
          fgMuted: widget.fgMuted,
          panel: _panel == null ? null : _buildPanel(),
          progress: ReaderProgressScrubber(
            fraction: fraction,
            centerLabel: controller.pageLabel,
            semanticValue: '$progressPct% · ${controller.pageLabel}',
            fgMuted: widget.fgMuted,
            accent: widget.accent,
            stepBackLabel: '上一页',
            stepForwardLabel: '下一页',
            onStepBack: controller.goBackward,
            onStepForward: controller.goForward,
            onDragStart: (value) => setState(() => _dragFraction = value),
            onDragUpdate: (value) {
              setState(() => _dragFraction = value);
              controller.previewFraction(value);
            },
            onDragEnd: (value) {
              setState(() => _dragFraction = null);
              controller.seekToFraction(value);
            },
          ),
          toolKeys: [
            ReaderToolKey(
              tooltip: '缩略图',
              icon: KaijuanIcons.grid,
              fg: widget.fg,
              accent: widget.accent,
              selected: false,
              onTap: () => showComicThumbnailsSheet(
                context,
                controller: controller,
              ),
            ),
            ReaderToolKey(
              tooltip: '书签',
              icon: KaijuanIcons.bookmarks,
              fg: widget.fg,
              accent: widget.accent,
              selected: false,
              onTap: () => showReaderBookmarksSheet(
                context,
                listenable: controller,
                bookmarks: () => controller.bookmarks,
                labelFor: controller.bookmarkLabel,
                onOpen: controller.goToBookmark,
                onRemove: controller.removeBookmark,
              ),
            ),
            ReaderToolKey(
              tooltip: '亮度',
              icon: KaijuanIcons.sunny,
              fg: widget.fg,
              accent: widget.accent,
              selected: _panel == ComicToolStripPanel.brightness,
              onTap: () => _togglePanel(ComicToolStripPanel.brightness),
            ),
            ReaderToolKey(
              tooltip: '方向',
              icon: KaijuanIcons.swapHorizontal,
              fg: widget.fg,
              accent: widget.accent,
              selected: _panel == ComicToolStripPanel.direction,
              onTap: () => _togglePanel(ComicToolStripPanel.direction),
            ),
            ReaderToolKey(
              tooltip: '阅读模式',
              icon: KaijuanIcons.tune,
              fg: widget.fg,
              accent: widget.accent,
              selected: _panel == ComicToolStripPanel.readingMode,
              onTap: () => _togglePanel(ComicToolStripPanel.readingMode),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPanel() {
    return switch (_panel!) {
      ComicToolStripPanel.brightness => _BrightnessPanel(
        controller: controller,
        fg: widget.fg,
        fgMuted: widget.fgMuted,
        accent: widget.accent,
      ),
      ComicToolStripPanel.direction => _DirectionPanel(
        controller: controller,
        fg: widget.fg,
        fgMuted: widget.fgMuted,
        accent: widget.accent,
      ),
      ComicToolStripPanel.readingMode => _ReadingModePanel(
        controller: controller,
        fg: widget.fg,
        fgMuted: widget.fgMuted,
        accent: widget.accent,
      ),
    };
  }
}

class _BrightnessPanel extends StatefulWidget {
  const _BrightnessPanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
  });

  final ComicReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;

  @override
  State<_BrightnessPanel> createState() => _BrightnessPanelState();
}

class _BrightnessPanelState extends State<_BrightnessPanel> {
  late double _preview;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.controller.brightness;
  }

  @override
  Widget build(BuildContext context) {
    if (!_dragging) {
      _preview = widget.controller.brightness;
    }
    final t =
        ((_preview - ComicReadingPreferences.minBrightness) /
                (ComicReadingPreferences.maxBrightness -
                    ComicReadingPreferences.minBrightness))
            .clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReaderToolPanelLabel('亮度', widget.fgMuted),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            Icon(KaijuanIcons.brightnessLow, size: 18, color: widget.fgMuted),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: ReaderFractionTrack(
                fraction: t,
                trackColor: widget.fgMuted.withValues(alpha: 0.22),
                fillColor: widget.accent,
                thumbColor: widget.accent,
                semanticLabel: '亮度',
                semanticValue: '${(t * 100).round()}%',
                onDragStart: (v) {
                  _dragging = true;
                  final next =
                      ComicReadingPreferences.minBrightness +
                      v *
                          (ComicReadingPreferences.maxBrightness -
                              ComicReadingPreferences.minBrightness);
                  setState(() => _preview = next);
                  widget.controller.previewBrightness(next);
                },
                onDragUpdate: (v) {
                  final next =
                      ComicReadingPreferences.minBrightness +
                      v *
                          (ComicReadingPreferences.maxBrightness -
                              ComicReadingPreferences.minBrightness);
                  setState(() => _preview = next);
                  widget.controller.previewBrightness(next);
                },
                onDragEnd: (v) {
                  _dragging = false;
                  unawaited(
                    widget.controller.setBrightness(
                      ComicReadingPreferences.minBrightness +
                          v *
                              (ComicReadingPreferences.maxBrightness -
                                  ComicReadingPreferences.minBrightness),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Icon(KaijuanIcons.brightnessHigh, size: 18, color: widget.fgMuted),
          ],
        ),
      ],
    );
  }
}

class _DirectionPanel extends StatelessWidget {
  const _DirectionPanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
  });

  final ComicReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderToolPanelLabel('阅读方向', fgMuted),
        const SizedBox(height: AppSpacing.x2),
        ReaderSegmentedChoices<ComicReadDirection>(
          values: ComicReadDirection.values,
          labels: [for (final d in ComicReadDirection.values) d.label],
          selected: controller.direction,
          onSelected: controller.setDirection,
          fg: fg,
          fgMuted: fgMuted,
          accent: accent,
        ),
      ],
    );
  }
}

class _ReadingModePanel extends StatelessWidget {
  const _ReadingModePanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
  });

  final ComicReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderToolPanelLabel('翻页模式', fgMuted),
        const SizedBox(height: AppSpacing.x2),
        ReaderSegmentedChoices<ComicReaderMode>(
          values: ComicReaderMode.values,
          labels: [for (final m in ComicReaderMode.values) m.label],
          selected: controller.mode,
          onSelected: controller.setMode,
          fg: fg,
          fgMuted: fgMuted,
          accent: accent,
        ),
        const SizedBox(height: AppSpacing.x3),
        ReaderToolPanelLabel('背景', fgMuted),
        const SizedBox(height: AppSpacing.x2),
        ReaderSegmentedChoices<ComicReadingTheme>(
          values: ComicReadingTheme.values,
          labels: [for (final t in ComicReadingTheme.values) t.label],
          selected: controller.readingTheme,
          onSelected: controller.setReadingTheme,
          fg: fg,
          fgMuted: fgMuted,
          accent: accent,
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/comic_reading_preferences.dart';
import '../../../core/theme.dart';
import '../../../readers/comic/comic_models.dart';
import '../../controllers/comic_reader_controller.dart';
import 'comic_thumbnails_sheet.dart';
import 'reader_bookmarks_sheet.dart';

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

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: _panel == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x4,
                        AppSpacing.x3,
                        AppSpacing.x4,
                        AppSpacing.x2,
                      ),
                      child: _buildPanel(),
                    ),
            ),
            if (_panel != null)
              Divider(
                height: 1,
                thickness: 1,
                color: widget.fgMuted.withValues(alpha: 0.18),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x4,
                AppSpacing.x3,
                AppSpacing.x4,
                AppSpacing.x2,
              ),
              child: _ProgressScrubber(
                fraction: fraction,
                pageLabel: controller.pageLabel,
                fg: widget.fg,
                fgMuted: widget.fgMuted,
                accent: widget.accent,
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
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: widget.fgMuted.withValues(alpha: 0.18),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x2,
                AppSpacing.x2,
                AppSpacing.x2,
                AppSpacing.x3,
              ),
              child: Row(
                children: [
                  _ToolKey(
                    tooltip: '缩略图',
                    icon: Icons.grid_view_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: false,
                    onTap: () => showComicThumbnailsSheet(
                      context,
                      controller: controller,
                    ),
                  ),
                  _ToolKey(
                    tooltip: '书签',
                    icon: Icons.bookmarks_outlined,
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
                  _ToolKey(
                    tooltip: '亮度',
                    icon: Icons.wb_sunny_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: _panel == ComicToolStripPanel.brightness,
                    onTap: () => _togglePanel(ComicToolStripPanel.brightness),
                  ),
                  _ToolKey(
                    tooltip: '方向',
                    icon: Icons.swap_horiz_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: _panel == ComicToolStripPanel.direction,
                    onTap: () => _togglePanel(ComicToolStripPanel.direction),
                  ),
                  _ToolKey(
                    tooltip: '阅读模式',
                    icon: Icons.tune_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: _panel == ComicToolStripPanel.readingMode,
                    onTap: () => _togglePanel(ComicToolStripPanel.readingMode),
                  ),
                ],
              ),
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

class _ToolKey extends StatelessWidget {
  const _ToolKey({
    required this.tooltip,
    required this.icon,
    required this.fg,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color fg;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : fg;
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.menu),
            child: SizedBox(
              height: 48,
              child: Icon(icon, color: color, size: 22, weight: 300),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressScrubber extends StatelessWidget {
  const _ProgressScrubber({
    required this.fraction,
    required this.pageLabel,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.onStepBack,
    required this.onStepForward,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double fraction;
  final String pageLabel;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          pageLabel,
          textAlign: TextAlign.center,
          style: TextStyle(color: fgMuted, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            _StepButton(
              icon: Icons.chevron_left,
              color: fgMuted,
              onTap: onStepBack,
            ),
            Expanded(
              child: _CustomFractionTrack(
                fraction: fraction,
                trackColor: fgMuted.withValues(alpha: 0.22),
                fillColor: accent,
                thumbColor: accent,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
              ),
            ),
            _StepButton(
              icon: Icons.chevron_right,
              color: fgMuted,
              onTap: onStepForward,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: SizedBox(
          width: 36,
          height: 28,
          child: Icon(icon, size: 22, color: color, weight: 300),
        ),
      ),
    );
  }
}

class _CustomFractionTrack extends StatelessWidget {
  const _CustomFractionTrack({
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
    required this.thumbColor,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double fraction;
  final Color trackColor;
  final Color fillColor;
  final Color thumbColor;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  double _valueFor(Offset local, double width) {
    if (width <= 0) return 0;
    return (local.dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final x = fraction * width;
        return SizedBox(
          height: 28,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              onDragStart(_valueFor(details.localPosition, width));
            },
            onHorizontalDragUpdate: (details) {
              onDragUpdate(_valueFor(details.localPosition, width));
            },
            onHorizontalDragEnd: (_) => onDragEnd(fraction),
            onTapDown: (details) {
              final value = _valueFor(details.localPosition, width);
              onDragStart(value);
              onDragEnd(value);
            },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Center(
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Center(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: math.max(0, x),
                      height: 2,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (x - 7).clamp(0.0, math.max(0.0, width - 14)),
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 13, color: color));
  }
}

class _SegmentedChoices<T> extends StatelessWidget {
  const _SegmentedChoices({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
    required this.fg,
    required this.fgMuted,
    required this.accent,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;
  final Color fg;
  final Color fgMuted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.menu),
        border: Border.all(color: fgMuted.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 36,
                color: fgMuted.withValues(alpha: 0.18),
              ),
            Expanded(
              child: Material(
                color: values[i] == selected
                    ? accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(values[i]),
                  child: SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: values[i] == selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: values[i] == selected ? accent : fg,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
    final t = ((_preview - ComicReadingPreferences.minBrightness) /
            (ComicReadingPreferences.maxBrightness -
                ComicReadingPreferences.minBrightness))
        .clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelLabel('亮度', widget.fgMuted),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            Icon(Icons.brightness_low, size: 18, color: widget.fgMuted),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: _CustomFractionTrack(
                fraction: t,
                trackColor: widget.fgMuted.withValues(alpha: 0.22),
                fillColor: widget.accent,
                thumbColor: widget.accent,
                onDragStart: (v) {
                  _dragging = true;
                  final next = ComicReadingPreferences.minBrightness +
                      v *
                          (ComicReadingPreferences.maxBrightness -
                              ComicReadingPreferences.minBrightness);
                  setState(() => _preview = next);
                  widget.controller.previewBrightness(next);
                },
                onDragUpdate: (v) {
                  final next = ComicReadingPreferences.minBrightness +
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
            Icon(Icons.brightness_high, size: 18, color: widget.fgMuted),
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
        _PanelLabel('阅读方向', fgMuted),
        const SizedBox(height: AppSpacing.x2),
        _SegmentedChoices<ComicReadDirection>(
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
        _PanelLabel('翻页模式', fgMuted),
        const SizedBox(height: AppSpacing.x2),
        _SegmentedChoices<ComicReaderMode>(
          values: ComicReaderMode.values,
          labels: [for (final m in ComicReaderMode.values) m.label],
          selected: controller.mode,
          onSelected: controller.setMode,
          fg: fg,
          fgMuted: fgMuted,
          accent: accent,
        ),
        const SizedBox(height: AppSpacing.x3),
        _PanelLabel('背景', fgMuted),
        const SizedBox(height: AppSpacing.x2),
        _SegmentedChoices<ComicReadingTheme>(
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

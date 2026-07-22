import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/book_reading_preferences.dart';
import '../../../core/theme.dart';
import '../../../readers/book/book_theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_overlays.dart';

enum BookToolStripPanel { brightness, typography, readingMode }

/// WeChat-style bottom tool strip: progress scrubber + five keys + expandable
/// panels. Uses Kaika tokens — no Material Slider / SegmentedButton defaults.
class BookReaderToolStrip extends StatefulWidget {
  const BookReaderToolStrip({
    super.key,
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.onOpenToc,
    required this.chromeVisible,
  });

  final BookReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final VoidCallback onOpenToc;
  final bool chromeVisible;

  @override
  State<BookReaderToolStrip> createState() => _BookReaderToolStripState();
}

class _BookReaderToolStripState extends State<BookReaderToolStrip> {
  BookToolStripPanel? _panel;
  double? _dragFraction;

  BookReaderController get controller => widget.controller;

  @override
  void didUpdateWidget(covariant BookReaderToolStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.chromeVisible && _panel != null) {
      _panel = null;
    }
  }

  void _togglePanel(BookToolStripPanel panel) {
    setState(() => _panel = _panel == panel ? null : panel);
  }

  void _onListenPlaceholder() {
    showAppSnackBar(context, '听书即将推出');
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
              Divider(height: 1, thickness: 1, color: widget.fgMuted.withValues(alpha: 0.18)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x4,
                AppSpacing.x3,
                AppSpacing.x4,
                AppSpacing.x2,
              ),
              child: _ProgressScrubber(
                fraction: fraction,
                fg: widget.fg,
                fgMuted: widget.fgMuted,
                accent: widget.accent,
                onStepBack: () {
                  if (controller.hasPageMode) {
                    controller.goPreviousPage();
                  } else {
                    controller.goPreviousSection();
                  }
                },
                onStepForward: () {
                  if (controller.hasPageMode) {
                    controller.goNextPage();
                  } else {
                    controller.goNextSection();
                  }
                },
                onDragStart: (value) => setState(() => _dragFraction = value),
                onDragUpdate: (value) => setState(() => _dragFraction = value),
                onDragEnd: (value) {
                  setState(() => _dragFraction = null);
                  controller.seekToFraction(value);
                },
              ),
            ),
            Divider(height: 1, thickness: 1, color: widget.fgMuted.withValues(alpha: 0.18)),
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
                    tooltip: '目录',
                    icon: Icons.list_alt_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: false,
                    onTap: widget.onOpenToc,
                  ),
                  _ToolKey(
                    tooltip: '听书',
                    icon: Icons.headphones_outlined,
                    fg: widget.fgMuted,
                    accent: widget.accent,
                    selected: false,
                    onTap: _onListenPlaceholder,
                  ),
                  _ToolKey(
                    tooltip: '亮度',
                    icon: Icons.wb_sunny_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: _panel == BookToolStripPanel.brightness,
                    onTap: () => _togglePanel(BookToolStripPanel.brightness),
                  ),
                  _ToolKey(
                    tooltip: '字体排版',
                    icon: Icons.text_fields_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: _panel == BookToolStripPanel.typography,
                    onTap: () => _togglePanel(BookToolStripPanel.typography),
                  ),
                  _ToolKey(
                    tooltip: '阅读模式',
                    icon: Icons.tune_outlined,
                    fg: widget.fg,
                    accent: widget.accent,
                    selected: _panel == BookToolStripPanel.readingMode,
                    onTap: () => _togglePanel(BookToolStripPanel.readingMode),
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
      BookToolStripPanel.brightness => _BrightnessPanel(
        controller: controller,
        fg: widget.fg,
        fgMuted: widget.fgMuted,
        accent: widget.accent,
      ),
      BookToolStripPanel.typography => _TypographyPanel(
        controller: controller,
        fg: widget.fg,
        fgMuted: widget.fgMuted,
        accent: widget.accent,
      ),
      BookToolStripPanel.readingMode => _ReadingModePanel(
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
            borderRadius: BorderRadius.circular(AppRadii.medium),
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
    return Row(
      children: [
        _StepButton(icon: Icons.chevron_left, color: fgMuted, onTap: onStepBack),
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
        borderRadius: BorderRadius.circular(AppRadii.small),
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
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: fgMuted.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 36, color: fgMuted.withValues(alpha: 0.18)),
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
                        style: TextStyle(
                          fontSize: 13,
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

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 13, color: color));
  }
}

class _BrightnessPanel extends StatefulWidget {
  const _BrightnessPanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
  });

  final BookReaderController controller;
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
        ((_preview - BookReadingPreferences.minBrightness) /
                (BookReadingPreferences.maxBrightness -
                    BookReadingPreferences.minBrightness))
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
                  final next = BookReadingPreferences.minBrightness +
                      v *
                          (BookReadingPreferences.maxBrightness -
                              BookReadingPreferences.minBrightness);
                  setState(() => _preview = next);
                  widget.controller.previewBrightness(next);
                },
                onDragUpdate: (v) {
                  final next = BookReadingPreferences.minBrightness +
                      v *
                          (BookReadingPreferences.maxBrightness -
                              BookReadingPreferences.minBrightness);
                  setState(() => _preview = next);
                  widget.controller.previewBrightness(next);
                },
                onDragEnd: (v) {
                  _dragging = false;
                  unawaited(
                    widget.controller.setBrightness(
                      BookReadingPreferences.minBrightness +
                          v *
                              (BookReadingPreferences.maxBrightness -
                                  BookReadingPreferences.minBrightness),
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

class _TypographyPanel extends StatefulWidget {
  const _TypographyPanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
  });

  final BookReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;

  @override
  State<_TypographyPanel> createState() => _TypographyPanelState();
}

class _TypographyPanelState extends State<_TypographyPanel> {
  late double _previewFontSize;
  late double _previewLineHeight;
  late double _previewMargin;
  late double _previewVerticalMargin;
  String? _dragging;
  _TypographySub? _sub;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _previewFontSize = c.fontSize;
    _previewLineHeight = c.lineHeight;
    _previewMargin = c.margin;
    _previewVerticalMargin = c.verticalMargin;
  }

  void _syncPreviewsIfIdle() {
    if (_dragging != null) return;
    final c = widget.controller;
    _previewFontSize = c.fontSize;
    _previewLineHeight = c.lineHeight;
    _previewMargin = c.margin;
    _previewVerticalMargin = c.verticalMargin;
  }

  double _lerp(double min, double max, double t) => min + t * (max - min);

  double _t(double value, double min, double max) {
    if (max <= min) return 0;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.48;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        child: switch (_sub) {
          _TypographySub.font => _FontPickerPanel(
            controller: widget.controller,
            fg: widget.fg,
            fgMuted: widget.fgMuted,
            accent: widget.accent,
            onClose: () => setState(() => _sub = null),
          ),
          _TypographySub.more => _MoreSettingsPanel(
            controller: widget.controller,
            fg: widget.fg,
            fgMuted: widget.fgMuted,
            accent: widget.accent,
            onClose: () => setState(() => _sub = null),
          ),
          null => _buildMain(),
        },
      ),
    );
  }

  Widget _buildMain() {
    final controller = widget.controller;
    _syncPreviewsIfIdle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThemePresetCards(
          selected: controller.readingTheme,
          accent: widget.accent,
          onSelected: controller.setReadingTheme,
        ),
        const SizedBox(height: AppSpacing.x3),
        _PrefScrubberRow(
          title: '字号',
          icon: Icons.format_size,
          valueLabel: _previewFontSize.round().toString(),
          fraction: _t(
            _previewFontSize,
            BookReadingPreferences.minFontSize,
            BookReadingPreferences.maxFontSize,
          ),
          accent: widget.accent,
          fgMuted: widget.fgMuted,
          trailing: _BoldToggle(
            selected: controller.bold,
            accent: widget.accent,
            fg: widget.fg,
            onTap: () => unawaited(controller.setBold(!controller.bold)),
          ),
          onDragStart: (t) {
            _dragging = 'font';
            setState(() {
              _previewFontSize = _lerp(
                BookReadingPreferences.minFontSize,
                BookReadingPreferences.maxFontSize,
                t,
              );
            });
          },
          onDragUpdate: (t) {
            setState(() {
              _previewFontSize = _lerp(
                BookReadingPreferences.minFontSize,
                BookReadingPreferences.maxFontSize,
                t,
              );
            });
          },
          onDragEnd: (t) {
            _dragging = null;
            unawaited(
              controller.setFontSize(
                _lerp(
                  BookReadingPreferences.minFontSize,
                  BookReadingPreferences.maxFontSize,
                  t,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        _PrefScrubberRow(
          title: '行间距',
          icon: Icons.format_line_spacing,
          valueLabel: _previewLineHeight.toStringAsFixed(1),
          fraction: _t(
            _previewLineHeight,
            BookReadingPreferences.minLineHeight,
            BookReadingPreferences.maxLineHeight,
          ),
          accent: widget.accent,
          fgMuted: widget.fgMuted,
          onDragStart: (t) {
            _dragging = 'line';
            setState(() {
              _previewLineHeight = _lerp(
                BookReadingPreferences.minLineHeight,
                BookReadingPreferences.maxLineHeight,
                t,
              );
            });
          },
          onDragUpdate: (t) {
            setState(() {
              _previewLineHeight = _lerp(
                BookReadingPreferences.minLineHeight,
                BookReadingPreferences.maxLineHeight,
                t,
              );
            });
          },
          onDragEnd: (t) {
            _dragging = null;
            unawaited(
              controller.setLineHeight(
                _lerp(
                  BookReadingPreferences.minLineHeight,
                  BookReadingPreferences.maxLineHeight,
                  t,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PrefScrubberRow(
                title: '水平页边距',
                icon: Icons.swap_horiz,
                valueLabel: ((_previewMargin - BookReadingPreferences.minMargin) /
                        8)
                    .round()
                    .clamp(0, 5)
                    .toString(),
                fraction: _t(
                  _previewMargin,
                  BookReadingPreferences.minMargin,
                  BookReadingPreferences.maxMargin,
                ),
                accent: widget.accent,
                fgMuted: widget.fgMuted,
                onDragStart: (t) {
                  _dragging = 'hMargin';
                  setState(() {
                    _previewMargin = _lerp(
                      BookReadingPreferences.minMargin,
                      BookReadingPreferences.maxMargin,
                      t,
                    );
                  });
                },
                onDragUpdate: (t) {
                  setState(() {
                    _previewMargin = _lerp(
                      BookReadingPreferences.minMargin,
                      BookReadingPreferences.maxMargin,
                      t,
                    );
                  });
                },
                onDragEnd: (t) {
                  _dragging = null;
                  unawaited(
                    controller.setMargin(
                      _lerp(
                        BookReadingPreferences.minMargin,
                        BookReadingPreferences.maxMargin,
                        t,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: _PrefScrubberRow(
                title: '垂直页边距',
                icon: Icons.swap_vert,
                valueLabel: (_previewVerticalMargin / 6)
                    .round()
                    .clamp(0, 8)
                    .toString(),
                fraction: _t(
                  _previewVerticalMargin,
                  BookReadingPreferences.minVerticalMargin,
                  BookReadingPreferences.maxVerticalMargin,
                ),
                accent: widget.accent,
                fgMuted: widget.fgMuted,
                onDragStart: (t) {
                  _dragging = 'vMargin';
                  setState(() {
                    _previewVerticalMargin = _lerp(
                      BookReadingPreferences.minVerticalMargin,
                      BookReadingPreferences.maxVerticalMargin,
                      t,
                    );
                  });
                },
                onDragUpdate: (t) {
                  setState(() {
                    _previewVerticalMargin = _lerp(
                      BookReadingPreferences.minVerticalMargin,
                      BookReadingPreferences.maxVerticalMargin,
                      t,
                    );
                  });
                },
                onDragEnd: (t) {
                  _dragging = null;
                  unawaited(
                    controller.setVerticalMargin(
                      _lerp(
                        BookReadingPreferences.minVerticalMargin,
                        BookReadingPreferences.maxVerticalMargin,
                        t,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        Row(
          children: [
            Expanded(
              child: _TypographyActionRow(
                label: controller.bodyFont.label,
                fg: widget.fg,
                fgMuted: widget.fgMuted,
                onTap: () => setState(() => _sub = _TypographySub.font),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: _TypographyActionRow(
                label: '更多设置',
                fg: widget.fg,
                fgMuted: widget.fgMuted,
                onTap: () => setState(() => _sub = _TypographySub.more),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _TypographySub { font, more }

class _SubPanelHeader extends StatelessWidget {
  const _SubPanelHeader({
    required this.title,
    required this.fg,
    required this.fgMuted,
    required this.onClose,
    this.leadingAction,
  });

  final String title;
  final Color fg;
  final Color fgMuted;
  final VoidCallback onClose;
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        if (leadingAction != null) ...[
          const SizedBox(width: AppSpacing.x2),
          leadingAction!,
        ],
        const Spacer(),
        GestureDetector(
          onTap: onClose,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x1),
            child: Icon(Icons.keyboard_arrow_down, size: 22, color: fgMuted),
          ),
        ),
      ],
    );
  }
}

class _FontPickerPanel extends StatelessWidget {
  const _FontPickerPanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.onClose,
  });

  final BookReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final VoidCallback onClose;

  static const _grid = BookBodyFont.values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubPanelHeader(
          title: '字体',
          fg: fg,
          fgMuted: fgMuted,
          onClose: onClose,
          leadingAction: GestureDetector(
            onTap: () => showAppSnackBar(context, '导入字体即将推出'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: accent),
                const SizedBox(width: 2),
                Text(
                  '导入',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileW = (constraints.maxWidth - AppSpacing.x2) / 2;
            return Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x2,
              children: [
                for (final font in _grid)
                  SizedBox(
                    width: tileW,
                    child: _FontTile(
                      font: font,
                      selected: controller.bodyFont == font,
                      accent: accent,
                      fg: fg,
                      fgMuted: fgMuted,
                      onTap: () => unawaited(controller.setBodyFont(font)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        Center(
          child: GestureDetector(
            onTap: () => showAppSnackBar(context, '补充字体即将推出'),
            child: Text(
              '补充字体 >',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: fgMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.font,
    required this.selected,
    required this.accent,
    required this.fg,
    required this.fgMuted,
    required this.onTap,
  });

  final BookBodyFont font;
  final bool selected;
  final Color accent;
  final Color fg;
  final Color fgMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSystem = font == BookBodyFont.system;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: selected ? accent : fgMuted.withValues(alpha: 0.22),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                font.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                  fontFamily: font.previewFamily,
                ),
              ),
            ),
            if (isSystem)
              Icon(Icons.chevron_right, size: 18, color: fgMuted),
          ],
        ),
      ),
    );
  }
}

class _MoreSettingsPanel extends StatefulWidget {
  const _MoreSettingsPanel({
    required this.controller,
    required this.fg,
    required this.fgMuted,
    required this.accent,
    required this.onClose,
  });

  final BookReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;
  final VoidCallback onClose;

  @override
  State<_MoreSettingsPanel> createState() => _MoreSettingsPanelState();
}

class _MoreSettingsPanelState extends State<_MoreSettingsPanel> {
  late double _previewLetter;
  late double _previewParagraph;
  String? _dragging;

  @override
  void initState() {
    super.initState();
    _previewLetter = widget.controller.letterSpacing;
    _previewParagraph = widget.controller.paragraphSpacing;
  }

  void _syncIfIdle() {
    if (_dragging != null) return;
    _previewLetter = widget.controller.letterSpacing;
    _previewParagraph = widget.controller.paragraphSpacing;
  }

  double _lerp(double min, double max, double t) => min + t * (max - min);

  double _t(double value, double min, double max) {
    if (max <= min) return 0;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  String _fmt(double v) {
    if (v == 0) return '0';
    final s = v.toStringAsFixed(1);
    return v > 0 && !s.startsWith('-') ? s : s;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    _syncIfIdle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubPanelHeader(
          title: '更多设置',
          fg: widget.fg,
          fgMuted: widget.fgMuted,
          onClose: widget.onClose,
        ),
        const SizedBox(height: AppSpacing.x3),
        _PanelLabel('词间距', widget.fgMuted),
        const SizedBox(height: AppSpacing.x1),
        _PrefScrubberRow(
          icon: Icons.space_bar,
          valueLabel: _fmt(_previewLetter),
          fraction: _t(
            _previewLetter,
            BookReadingPreferences.minLetterSpacing,
            BookReadingPreferences.maxLetterSpacing,
          ),
          accent: widget.accent,
          fgMuted: widget.fgMuted,
          onDragStart: (t) {
            _dragging = 'letter';
            setState(() {
              _previewLetter = _lerp(
                BookReadingPreferences.minLetterSpacing,
                BookReadingPreferences.maxLetterSpacing,
                t,
              );
            });
          },
          onDragUpdate: (t) {
            setState(() {
              _previewLetter = _lerp(
                BookReadingPreferences.minLetterSpacing,
                BookReadingPreferences.maxLetterSpacing,
                t,
              );
            });
          },
          onDragEnd: (t) {
            _dragging = null;
            unawaited(
              c.setLetterSpacing(
                _lerp(
                  BookReadingPreferences.minLetterSpacing,
                  BookReadingPreferences.maxLetterSpacing,
                  t,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        _PanelLabel('段间距', widget.fgMuted),
        const SizedBox(height: AppSpacing.x1),
        _PrefScrubberRow(
          icon: Icons.vertical_distribute,
          valueLabel: _fmt(_previewParagraph),
          fraction: _t(
            _previewParagraph,
            BookReadingPreferences.minParagraphSpacing,
            BookReadingPreferences.maxParagraphSpacing,
          ),
          accent: widget.accent,
          fgMuted: widget.fgMuted,
          onDragStart: (t) {
            _dragging = 'para';
            setState(() {
              _previewParagraph = _lerp(
                BookReadingPreferences.minParagraphSpacing,
                BookReadingPreferences.maxParagraphSpacing,
                t,
              );
            });
          },
          onDragUpdate: (t) {
            setState(() {
              _previewParagraph = _lerp(
                BookReadingPreferences.minParagraphSpacing,
                BookReadingPreferences.maxParagraphSpacing,
                t,
              );
            });
          },
          onDragEnd: (t) {
            _dragging = null;
            unawaited(
              c.setParagraphSpacing(
                _lerp(
                  BookReadingPreferences.minParagraphSpacing,
                  BookReadingPreferences.maxParagraphSpacing,
                  t,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        _PanelLabel('对齐方式', widget.fgMuted),
        const SizedBox(height: AppSpacing.x2),
        _AlignToggle(
          selected: c.textAlign,
          accent: widget.accent,
          fgMuted: widget.fgMuted,
          onSelected: c.setTextAlign,
        ),
        const SizedBox(height: AppSpacing.x3),
        _PrefToggleRow(
          label: '首行缩进',
          value: c.firstLineIndent,
          fg: widget.fg,
          accent: widget.accent,
          onChanged: c.setFirstLineIndent,
        ),
        const SizedBox(height: AppSpacing.x2),
        _PrefToggleRow(
          label: '连字符',
          value: c.hyphenate,
          fg: widget.fg,
          accent: widget.accent,
          onChanged: c.setHyphenate,
        ),
      ],
    );
  }
}

class _AlignToggle extends StatelessWidget {
  const _AlignToggle({
    required this.selected,
    required this.accent,
    required this.fgMuted,
    required this.onSelected,
  });

  final BookTextAlign selected;
  final Color accent;
  final Color fgMuted;
  final ValueChanged<BookTextAlign> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AlignChip(
          icon: Icons.format_align_left,
          selected: selected == BookTextAlign.start,
          accent: accent,
          fgMuted: fgMuted,
          onTap: () => onSelected(BookTextAlign.start),
        ),
        const SizedBox(width: AppSpacing.x2),
        _AlignChip(
          icon: Icons.format_align_justify,
          selected: selected == BookTextAlign.justify,
          accent: accent,
          fgMuted: fgMuted,
          onTap: () => onSelected(BookTextAlign.justify),
        ),
      ],
    );
  }
}

class _AlignChip extends StatelessWidget {
  const _AlignChip({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.fgMuted,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color accent;
  final Color fgMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 48,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(
            color: selected ? accent : fgMuted.withValues(alpha: 0.22),
          ),
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Icon(icon, size: 20, color: selected ? accent : fgMuted),
      ),
    );
  }
}

class _PrefToggleRow extends StatelessWidget {
  const _PrefToggleRow({
    required this.label,
    required this.value,
    required this.fg,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Color fg;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 48,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.small),
              color: value ? accent : fg.withValues(alpha: 0.18),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemePresetCards extends StatelessWidget {
  const _ThemePresetCards({
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final BookReadingTheme selected;
  final Color accent;
  final ValueChanged<BookReadingTheme> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < BookReadingTheme.values.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: _ThemePresetCard(
              theme: BookReadingTheme.values[i],
              selected: selected == BookReadingTheme.values[i],
              accent: accent,
              onTap: () => onSelected(BookReadingTheme.values[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemePresetCard extends StatelessWidget {
  const _ThemePresetCard({
    required this.theme,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final BookReadingTheme theme;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = Color(theme.backgroundArgb);
    final fg = Color(theme.foregroundArgb);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: selected ? accent : fg.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Aa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              theme.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg.withValues(alpha: 0.88),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrefScrubberRow extends StatelessWidget {
  const _PrefScrubberRow({
    required this.icon,
    required this.valueLabel,
    required this.fraction,
    required this.accent,
    required this.fgMuted,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.title,
    this.trailing,
  });

  final String? title;
  final IconData icon;
  final String valueLabel;
  final double fraction;
  final Color accent;
  final Color fgMuted;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 18, color: fgMuted),
        const SizedBox(width: AppSpacing.x2),
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
        const SizedBox(width: AppSpacing.x2),
        SizedBox(
          width: 28,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: fgMuted,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.x2),
          trailing!,
        ],
      ],
    );
    if (title == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title!,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: fgMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        row,
      ],
    );
  }
}

class _BoldToggle extends StatelessWidget {
  const _BoldToggle({
    required this.selected,
    required this.accent,
    required this.fg,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(
            color: selected ? accent : fg.withValues(alpha: 0.22),
            width: selected ? 1.5 : 1,
          ),
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          'B',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: selected ? accent : fg,
          ),
        ),
      ),
    );
  }
}

class _TypographyActionRow extends StatelessWidget {
  const _TypographyActionRow({
    required this.label,
    required this.fg,
    required this.fgMuted,
    required this.onTap,
  });

  final String label;
  final Color fg;
  final Color fgMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: fgMuted.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: fgMuted),
          ],
        ),
      ),
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

  final BookReaderController controller;
  final Color fg;
  final Color fgMuted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final modes = controller.scrollModeEnabled
        ? BookReadingMode.values
        : const [BookReadingMode.page];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.scrollModeEnabled) ...[
          _PanelLabel('阅读模式', fgMuted),
          const SizedBox(height: AppSpacing.x2),
          _SegmentedChoices<BookReadingMode>(
            values: modes,
            labels: [for (final m in modes) m.label],
            selected: controller.readingMode,
            onSelected: controller.setReadingMode,
            fg: fg,
            fgMuted: fgMuted,
            accent: accent,
          ),
          const SizedBox(height: AppSpacing.x3),
        ],
        if (controller.readingMode == BookReadingMode.page) ...[
          _PanelLabel('翻页效果', fgMuted),
          const SizedBox(height: AppSpacing.x2),
          _SegmentedChoices<BookPageTurnEffect>(
            values: BookPageTurnEffect.values,
            labels: [for (final e in BookPageTurnEffect.values) e.label],
            selected: controller.pageTurnEffect,
            onSelected: controller.setPageTurnEffect,
            fg: fg,
            fgMuted: fgMuted,
            accent: accent,
          ),
        ],
      ],
    );
  }
}

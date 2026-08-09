import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';

/// Shared bottom-tool-strip primitives for book and comic readers.
///
/// Behavior and visuals match the pre-extract private widgets in each engine
/// strip. Engine-specific keys, panels, and seek logic stay in the callers.

/// Icon-only tool key in the five-key row ([Expanded] so keys share width).
class ReaderToolKey extends StatelessWidget {
  const ReaderToolKey({
    super.key,
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

/// Prev / next chevron beside a progress track.
class ReaderStepButton extends StatelessWidget {
  const ReaderStepButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22, color: color, weight: 300),
          ),
        ),
      ),
    );
  }
}

/// Diamond-thumb fraction scrubber used for progress, brightness, and prefs.
class ReaderFractionTrack extends StatelessWidget {
  const ReaderFractionTrack({
    super.key,
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
    required this.thumbColor,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.semanticLabel,
    this.semanticValue,
    required this.semanticValueForFraction,
  });

  final double fraction;
  final Color trackColor;
  final Color fillColor;
  final Color thumbColor;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final String? semanticLabel;
  final String? semanticValue;
  final String Function(double fraction) semanticValueForFraction;

  double _valueFor(Offset local, double width) {
    if (width <= 0) return 0;
    return (local.dx / width).clamp(0.0, 1.0);
  }

  void _nudge(double delta) {
    final next = (fraction + delta).clamp(0.0, 1.0);
    onDragStart(next);
    onDragUpdate(next);
    onDragEnd(next);
  }

  @override
  Widget build(BuildContext context) {
    final valueText = semanticValue ?? semanticValueForFraction(fraction);
    final increasedFraction = (fraction + 0.05).clamp(0.0, 1.0);
    final decreasedFraction = (fraction - 0.05).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final x = fraction * width;
        return Semantics(
          slider: true,
          label: semanticLabel,
          value: valueText,
          increasedValue: fraction >= 1
              ? null
              : semanticValueForFraction(increasedFraction),
          decreasedValue: fraction <= 0
              ? null
              : semanticValueForFraction(decreasedFraction),
          onIncrease: fraction >= 1 ? null : () => _nudge(0.05),
          onDecrease: fraction <= 0 ? null : () => _nudge(-0.05),
          child: SizedBox(
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
          ),
        );
      },
    );
  }
}

/// Progress row: optional center label + step buttons + fraction track.
class ReaderProgressScrubber extends StatelessWidget {
  const ReaderProgressScrubber({
    super.key,
    required this.fraction,
    required this.fgMuted,
    required this.accent,
    required this.stepBackLabel,
    required this.stepForwardLabel,
    required this.semanticValue,
    required this.semanticValueForFraction,
    required this.onStepBack,
    required this.onStepForward,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.centerLabel,
    this.semanticLabel = '阅读进度',
    this.stepBackIcon = KaijuanIcons.chevronLeft,
    this.stepForwardIcon = KaijuanIcons.chevronRight,
  });

  final double fraction;
  final Color fgMuted;
  final Color accent;
  final String stepBackLabel;
  final String stepForwardLabel;
  final String semanticValue;
  final String Function(double fraction) semanticValueForFraction;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  /// When set (comic), shown above the track with tabular figures.
  final String? centerLabel;
  final String semanticLabel;
  final IconData stepBackIcon;
  final IconData stepForwardIcon;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        ReaderStepButton(
          icon: stepBackIcon,
          color: fgMuted,
          tooltip: stepBackLabel,
          onTap: onStepBack,
        ),
        Expanded(
          child: ReaderFractionTrack(
            fraction: fraction,
            trackColor: fgMuted.withValues(alpha: 0.22),
            fillColor: accent,
            thumbColor: accent,
            semanticLabel: semanticLabel,
            semanticValue: semanticValue,
            semanticValueForFraction: semanticValueForFraction,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
          ),
        ),
        ReaderStepButton(
          icon: stepForwardIcon,
          color: fgMuted,
          tooltip: stepForwardLabel,
          onTap: onStepForward,
        ),
      ],
    );

    final label = centerLabel;
    if (label == null) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fgMuted,
            fontSize: KaiProductTokens.typographyReaderToolValue,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        row,
      ],
    );
  }
}

/// Segmented control used in reading-mode / direction / theme panels.
class ReaderSegmentedChoices<T> extends StatelessWidget {
  const ReaderSegmentedChoices({
    super.key,
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
              child: Semantics(
                button: true,
                selected: values[i] == selected,
                label: labels[i],
                child: Material(
                  color: values[i] == selected
                      ? accent.withValues(alpha: 0.14)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(values[i]),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize:
                                KaiProductTokens.typographyReaderToolValue,
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
            ),
          ],
        ],
      ),
    );
  }
}

/// Muted section label inside an expanded tool panel.
class ReaderToolPanelLabel extends StatelessWidget {
  const ReaderToolPanelLabel(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: KaiProductTokens.typographyReaderToolValue,
        color: color,
      ),
    );
  }
}

/// Bottom strip column: expandable panel, progress, five-key row.
///
/// Callers supply [panel], [progress], and [toolKeys] (already [Expanded]
/// children such as [ReaderToolKey]).
class ReaderToolStripLayout extends StatelessWidget {
  const ReaderToolStripLayout({
    super.key,
    required this.panel,
    required this.progress,
    required this.toolKeys,
    required this.fgMuted,
  });

  /// Expanded panel body, or null when no panel is open.
  final Widget? panel;
  final Widget progress;
  final List<Widget> toolKeys;
  final Color fgMuted;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hairline = fgMuted.withValues(alpha: 0.18);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: panel == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    context.appIsShortViewport ? AppSpacing.x2 : AppSpacing.x3,
                    AppSpacing.x4,
                    AppSpacing.x2,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          MediaQuery.sizeOf(context).height *
                          context.appReaderToolPanelMaxHeightFraction,
                    ),
                    child: SingleChildScrollView(child: panel),
                  ),
                ),
        ),
        if (panel != null) Divider(height: 1, thickness: 1, color: hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x3,
            AppSpacing.x4,
            AppSpacing.x2,
          ),
          child: progress,
        ),
        Divider(height: 1, thickness: 1, color: hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x2,
            AppSpacing.x3,
          ),
          child: Row(children: toolKeys),
        ),
      ],
    );
  }
}

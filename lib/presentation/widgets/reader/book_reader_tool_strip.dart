import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/book_reading_preferences.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';
import '../../../readers/book/book_theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_overlays.dart';
import 'reader_tool_strip_shared.dart';

enum BookToolStripPanel { brightness, typography, readingMode, tts }

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

  void _onListenTap() {
    // 只展开面板；真正开播由面板内播放键触发。
    _togglePanel(BookToolStripPanel.tts);
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

        final pageMode = controller.hasPageMode;
        final stepBackLabel = pageMode ? '上一页' : '上一节';
        final stepForwardLabel = pageMode ? '下一页' : '下一节';
        final progressPct = (fraction * 100).toStringAsFixed(1);

        return ReaderToolStripLayout(
          fgMuted: widget.fgMuted,
          panel: _panel == null ? null : _buildPanel(),
          progress: ReaderProgressScrubber(
            fraction: fraction,
            fgMuted: widget.fgMuted,
            accent: widget.accent,
            stepBackLabel: stepBackLabel,
            stepForwardLabel: stepForwardLabel,
            semanticValue: '$progressPct%',
            semanticValueForFraction: (value) =>
                '${(value * 100).toStringAsFixed(1)}%',
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
          toolKeys: [
            ReaderToolKey(
              tooltip: '目录',
              icon: KaijuanIcons.toc,
              fg: widget.fg,
              accent: widget.accent,
              selected: false,
              onTap: widget.onOpenToc,
            ),
            ReaderToolKey(
              tooltip: controller.ttsPlaying
                  ? '听书中'
                  : (controller.ttsPaused ? '听书已暂停' : '听书'),
              icon: controller.ttsActive
                  ? KaijuanIcons.headphonesFilled
                  : KaijuanIcons.headphones,
              fg: widget.fg,
              accent: widget.accent,
              selected:
                  _panel == BookToolStripPanel.tts || controller.ttsActive,
              onTap: _onListenTap,
            ),
            ReaderToolKey(
              tooltip: '亮度',
              icon: KaijuanIcons.sunny,
              fg: widget.fg,
              accent: widget.accent,
              selected: _panel == BookToolStripPanel.brightness,
              onTap: () => _togglePanel(BookToolStripPanel.brightness),
            ),
            ReaderToolKey(
              tooltip: '字体排版',
              icon: KaijuanIcons.typography,
              fg: widget.fg,
              accent: widget.accent,
              selected: _panel == BookToolStripPanel.typography,
              onTap: () => _togglePanel(BookToolStripPanel.typography),
            ),
            ReaderToolKey(
              tooltip: '阅读模式',
              icon: KaijuanIcons.tune,
              fg: widget.fg,
              accent: widget.accent,
              selected: _panel == BookToolStripPanel.readingMode,
              onTap: () => _togglePanel(BookToolStripPanel.readingMode),
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
      BookToolStripPanel.tts => _TtsPanel(
        controller: controller,
        fg: widget.fg,
        fgMuted: widget.fgMuted,
        accent: widget.accent,
      ),
    };
  }
}

class _TtsPanel extends StatelessWidget {
  const _TtsPanel({
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
    final playing = controller.ttsPlaying;
    final active = controller.ttsActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          active ? (playing ? '正在朗读' : '已暂停') : '听书',
          style: TextStyle(
            color: fg,
            fontSize: KaiProductTokens.typographyReaderToolValue,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _TtsIconButton(
              icon: KaijuanIcons.previous,
              label: '上一句',
              fg: fg,
              enabled: active,
              onPressed: () => unawaited(controller.ttsSkipPrevious()),
            ),
            _TtsIconButton(
              icon: playing ? KaijuanIcons.pause : KaijuanIcons.play,
              label: playing ? '暂停' : (active ? '继续' : '开始'),
              fg: accent,
              enabled: true,
              large: true,
              onPressed: () => unawaited(controller.toggleTtsPlayPause()),
            ),
            _TtsIconButton(
              icon: KaijuanIcons.next,
              label: '下一句',
              fg: fg,
              enabled: active,
              onPressed: () => unawaited(controller.ttsSkipNext()),
            ),
            _TtsIconButton(
              icon: KaijuanIcons.stop,
              label: '停止',
              fg: fg,
              enabled: active,
              onPressed: () => unawaited(controller.stopTts()),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '语速',
          style: TextStyle(
            color: fgMuted,
            fontSize: context.appCaptionSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final rate in BookReaderController.ttsRatePresets)
              _TtsRateChip(
                label: rate == 1.0 ? '1.0x' : '${rate}x',
                selected: (controller.ttsRate - rate).abs() < 0.01,
                accent: accent,
                fg: fg,
                onTap: () => unawaited(controller.setTtsRate(rate)),
              ),
          ],
        ),
      ],
    );
  }
}

class _TtsIconButton extends StatelessWidget {
  const _TtsIconButton({
    required this.icon,
    required this.label,
    required this.fg,
    required this.enabled,
    required this.onPressed,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color fg;
  final bool enabled;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: large ? 36 : 26, color: fg, weight: 300),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: KaiProductTokens.typographyReaderToolLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TtsRateChip extends StatelessWidget {
  const _TtsRateChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.16)
          : fg.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : fg,
              fontSize: KaiProductTokens.typographyReaderToolValue,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Human-readable band for continuous margin scrubbers (窄 / 中 / 宽).
String _marginBandLabel(double value, double min, double max) {
  if (max <= min) return '中';
  final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
  if (t < 1 / 3) return '窄';
  if (t < 2 / 3) return '中';
  return '宽';
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
                semanticValueForFraction: (value) =>
                    '${(value * 100).round()}%',
                onDragStart: (v) {
                  _dragging = true;
                  final next =
                      BookReadingPreferences.minBrightness +
                      v *
                          (BookReadingPreferences.maxBrightness -
                              BookReadingPreferences.minBrightness);
                  setState(() => _preview = next);
                  widget.controller.previewBrightness(next);
                },
                onDragUpdate: (v) {
                  final next =
                      BookReadingPreferences.minBrightness +
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
            Icon(KaijuanIcons.brightnessHigh, size: 18, color: widget.fgMuted),
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
    final maxH =
        MediaQuery.sizeOf(context).height *
        context.appReaderToolPanelMaxHeightFraction;
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
          icon: KaijuanIcons.fontIncrease,
          valueLabel: _previewFontSize.round().toString(),
          semanticValueForFraction: (value) => _lerp(
            BookReadingPreferences.minFontSize,
            BookReadingPreferences.maxFontSize,
            value,
          ).round().toString(),
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
          icon: KaijuanIcons.lineSpacing,
          valueLabel: _previewLineHeight.toStringAsFixed(1),
          semanticValueForFraction: (value) => _lerp(
            BookReadingPreferences.minLineHeight,
            BookReadingPreferences.maxLineHeight,
            value,
          ).toStringAsFixed(1),
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
        Builder(
          builder: (context) {
            final stackMargins =
                context.appIsCompact || context.appIsShortViewport;
            final hMargin = _PrefScrubberRow(
              title: '水平页边距',
              icon: KaijuanIcons.swapHorizontal,
              valueLabel: _marginBandLabel(
                _previewMargin,
                BookReadingPreferences.minMargin,
                BookReadingPreferences.maxMargin,
              ),
              semanticValueForFraction: (value) => _marginBandLabel(
                _lerp(
                  BookReadingPreferences.minMargin,
                  BookReadingPreferences.maxMargin,
                  value,
                ),
                BookReadingPreferences.minMargin,
                BookReadingPreferences.maxMargin,
              ),
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
            );
            final vMargin = _PrefScrubberRow(
              title: '垂直页边距',
              icon: KaijuanIcons.swapVertical,
              valueLabel: _marginBandLabel(
                _previewVerticalMargin,
                BookReadingPreferences.minVerticalMargin,
                BookReadingPreferences.maxVerticalMargin,
              ),
              semanticValueForFraction: (value) => _marginBandLabel(
                _lerp(
                  BookReadingPreferences.minVerticalMargin,
                  BookReadingPreferences.maxVerticalMargin,
                  value,
                ),
                BookReadingPreferences.minVerticalMargin,
                BookReadingPreferences.maxVerticalMargin,
              ),
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
            );
            if (stackMargins) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hMargin,
                  const SizedBox(height: AppSpacing.x3),
                  vMargin,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: hMargin),
                const SizedBox(width: AppSpacing.x3),
                Expanded(child: vMargin),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        Row(
          children: [
            Expanded(
              child: _TypographyActionRow(
                label: controller.fontLabel,
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
            fontSize: KaiProductTokens.typographyReaderBookTitle,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
        if (leadingAction != null) ...[
          const SizedBox(width: AppSpacing.x2),
          leadingAction!,
        ],
        const Spacer(),
        Tooltip(
          message: '关闭',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x1),
                child: Icon(KaijuanIcons.chevronDown, size: 22, color: fgMuted),
              ),
            ),
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

  Future<void> _import(BuildContext context) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '字体',
          extensions: ['ttf', 'otf', 'woff', 'woff2'],
          // iOS requires UTIs; extensions alone crash file_selector_ios.
          uniformTypeIdentifiers: [
            'public.truetype-ttf-font',
            'public.opentype-font',
            'public.font',
            'public.data',
          ],
        ),
      ],
    );
    if (files.isEmpty) return;
    final error = await controller.importFontFile(files.first.path);
    if (!context.mounted) return;
    if (error != null) showAppSnackBar(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final selection = controller.fontSelection;
    final store = controller.fontStore;
    final userFonts = store?.fonts ?? const <BookUserFont>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubPanelHeader(
          title: '字体',
          fg: fg,
          fgMuted: fgMuted,
          onClose: onClose,
          leadingAction: GestureDetector(
            onTap: () => unawaited(_import(context)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(KaijuanIcons.add, size: 16, color: accent),
                const SizedBox(width: 2),
                Text(
                  '导入',
                  style: TextStyle(
                    fontSize: KaiProductTokens.typographyReaderToolValue,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        _FontSectionTitle(label: '图书', fg: fgMuted),
        const SizedBox(height: AppSpacing.x2),
        _FontChoiceTile(
          label: '图书自带',
          selected: selection.kind == BookFontKind.book,
          accent: accent,
          fg: fg,
          fgMuted: fgMuted,
          onTap: () => unawaited(
            controller.setFontSelection(const BookFontSelection.book()),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        _FontSectionTitle(label: '系统字体', fg: fgMuted),
        const SizedBox(height: AppSpacing.x2),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileW = (constraints.maxWidth - AppSpacing.x2) / 2;
            return Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x2,
              children: [
                for (final font in BookSystemFont.all)
                  SizedBox(
                    width: tileW,
                    child: _FontChoiceTile(
                      label: font.label,
                      previewFamily: font.previewFamily,
                      selected:
                          selection.kind == BookFontKind.system &&
                          selection.systemId == font.id,
                      accent: accent,
                      fg: fg,
                      fgMuted: fgMuted,
                      onTap: () => unawaited(
                        controller.setFontSelection(
                          BookFontSelection.system(font.id),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.x3),
        _FontSectionTitle(label: '推荐下载（OFL）', fg: fgMuted),
        const SizedBox(height: AppSpacing.x2),
        for (final catalog in BookCatalogFont.all) ...[
          _CatalogFontTile(
            catalog: catalog,
            store: store,
            selection: selection,
            accent: accent,
            fg: fg,
            fgMuted: fgMuted,
            onDownload: () async {
              final error = await controller.downloadCatalogFont(catalog);
              if (!context.mounted) return;
              if (error != null) showAppSnackBar(context, error);
            },
            onSelect: (userFont) => unawaited(
              controller.setFontSelection(BookFontSelection.user(userFont.id)),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
        if (userFonts.any((f) => f.source == BookUserFontSource.import)) ...[
          const SizedBox(height: AppSpacing.x2),
          _FontSectionTitle(label: '我的导入', fg: fgMuted),
          const SizedBox(height: AppSpacing.x2),
          for (final font in userFonts.where(
            (f) => f.source == BookUserFontSource.import,
          )) ...[
            _UserFontTile(
              font: font,
              selected:
                  selection.kind == BookFontKind.user &&
                  selection.userFontId == font.id,
              accent: accent,
              fg: fg,
              fgMuted: fgMuted,
              onTap: () => unawaited(
                controller.setFontSelection(BookFontSelection.user(font.id)),
              ),
              onDelete: () => unawaited(controller.deleteUserFont(font.id)),
            ),
            const SizedBox(height: AppSpacing.x2),
          ],
        ],
      ],
    );
  }
}

class _FontSectionTitle extends StatelessWidget {
  const _FontSectionTitle({required this.label, required this.fg});

  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: context.appCaptionSize,
        fontWeight: FontWeight.w600,
        color: fg,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _FontChoiceTile extends StatelessWidget {
  const _FontChoiceTile({
    required this.label,
    required this.selected,
    required this.accent,
    required this.fg,
    required this.fgMuted,
    required this.onTap,
    this.previewFamily,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color fg;
  final Color fgMuted;
  final VoidCallback onTap;
  final String? previewFamily;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.menu),
          border: Border.all(
            color: selected ? accent : fgMuted.withValues(alpha: 0.22),
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: context.appLabelSize,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: fg,
            fontFamily: previewFamily,
          ),
        ),
      ),
    );
  }
}

class _CatalogFontTile extends StatelessWidget {
  const _CatalogFontTile({
    required this.catalog,
    required this.store,
    required this.selection,
    required this.accent,
    required this.fg,
    required this.fgMuted,
    required this.onDownload,
    required this.onSelect,
  });

  final BookCatalogFont catalog;
  final BookFontStore? store;
  final BookFontSelection selection;
  final Color accent;
  final Color fg;
  final Color fgMuted;
  final VoidCallback onDownload;
  final void Function(BookUserFont font) onSelect;

  @override
  Widget build(BuildContext context) {
    final installed = store?.byCatalogId(catalog.id);
    final downloading = store?.isDownloading(catalog.id) ?? false;
    final progress = store?.downloadProgress(catalog.id);
    final selected =
        installed != null &&
        selection.kind == BookFontKind.user &&
        selection.userFontId == installed.id;

    return GestureDetector(
      onTap: () {
        if (downloading) return;
        if (installed != null) {
          onSelect(installed);
        } else {
          onDownload();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.menu),
          border: Border.all(
            color: selected ? accent : fgMuted.withValues(alpha: 0.22),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    catalog.displayName,
                    style: TextStyle(
                      fontSize: context.appLabelSize,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  Text(
                    downloading
                        ? '下载中 ${((progress ?? 0) * 100).round()}%'
                        : installed != null
                        ? catalog.license
                        : '${catalog.license} · ${catalog.sizeLabel}',
                    style: TextStyle(
                      fontSize: context.appCaptionSmallSize,
                      color: fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (downloading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress,
                ),
              )
            else if (installed == null)
              Icon(KaijuanIcons.download, size: 18, color: accent)
            else if (selected)
              Icon(KaijuanIcons.check, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class _UserFontTile extends StatelessWidget {
  const _UserFontTile({
    required this.font,
    required this.selected,
    required this.accent,
    required this.fg,
    required this.fgMuted,
    required this.onTap,
    required this.onDelete,
  });

  final BookUserFont font;
  final bool selected;
  final Color accent;
  final Color fg;
  final Color fgMuted;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 120),
      height: 44,
      padding: const EdgeInsets.only(left: AppSpacing.x3, right: AppSpacing.x1),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.menu),
        border: Border.all(
          color: selected ? accent : fgMuted.withValues(alpha: 0.22),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  font.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.appLabelSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: '删除字体',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(AppRadii.control),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    KaijuanIcons.delete,
                    size: 18,
                    color: fgMuted,
                    weight: 300,
                  ),
                ),
              ),
            ),
          ),
        ],
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
        ReaderToolPanelLabel('字间距', widget.fgMuted),
        const SizedBox(height: AppSpacing.x1),
        _PrefScrubberRow(
          icon: KaijuanIcons.letterSpacing,
          valueLabel: _fmt(_previewLetter),
          semanticLabel: '字间距',
          semanticValueForFraction: (value) => _fmt(
            _lerp(
              BookReadingPreferences.minLetterSpacing,
              BookReadingPreferences.maxLetterSpacing,
              value,
            ),
          ),
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
        ReaderToolPanelLabel('段间距', widget.fgMuted),
        const SizedBox(height: AppSpacing.x1),
        _PrefScrubberRow(
          icon: KaijuanIcons.paragraphSpacing,
          valueLabel: _fmt(_previewParagraph),
          semanticLabel: '段间距',
          semanticValueForFraction: (value) => _fmt(
            _lerp(
              BookReadingPreferences.minParagraphSpacing,
              BookReadingPreferences.maxParagraphSpacing,
              value,
            ),
          ),
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
        ReaderToolPanelLabel('对齐方式', widget.fgMuted),
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
          icon: KaijuanIcons.alignLeft,
          label: '左对齐',
          selected: selected == BookTextAlign.start,
          accent: accent,
          fgMuted: fgMuted,
          onTap: () => onSelected(BookTextAlign.start),
        ),
        const SizedBox(width: AppSpacing.x2),
        _AlignChip(
          icon: KaijuanIcons.alignJustify,
          label: '两端对齐',
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
    required this.label,
    required this.selected,
    required this.accent,
    required this.fgMuted,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final Color fgMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            width: 48,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: selected ? accent : fgMuted.withValues(alpha: 0.22),
              ),
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Icon(icon, size: 20, color: selected ? accent : fgMuted),
          ),
        ),
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: label,
      toggled: value,
      button: true,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: context.appLabelSize,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.control),
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
      ),
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
          borderRadius: BorderRadius.circular(AppRadii.menu),
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
                fontSize: KaiProductTokens.typographyReaderChapterTitle,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              theme.label,
              style: TextStyle(
                fontSize: context.appCaptionSmallSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    required this.semanticValueForFraction,
    required this.fraction,
    required this.accent,
    required this.fgMuted,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.title,
    this.semanticLabel,
    this.trailing,
  });

  final String? title;
  final String? semanticLabel;
  final IconData icon;
  final String valueLabel;
  final String Function(double fraction) semanticValueForFraction;
  final double fraction;
  final Color accent;
  final Color fgMuted;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ?? title;
    // Chinese band labels (窄/中/宽) need a bit more room than digits.
    final valueWidth = valueLabel.runes.length > 1 ? 36.0 : 28.0;
    final row = Row(
      children: [
        Icon(icon, size: 18, color: fgMuted),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: ReaderFractionTrack(
            fraction: fraction,
            trackColor: fgMuted.withValues(alpha: 0.22),
            fillColor: accent,
            thumbColor: accent,
            semanticLabel: label,
            semanticValue: valueLabel,
            semanticValueForFraction: semanticValueForFraction,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        SizedBox(
          width: valueWidth,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: KaiProductTokens.typographyReaderToolValue,
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
            fontSize: KaiProductTokens.typographyReaderToolValue,
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: selected ? '取消粗体' : '粗体',
      child: Semantics(
        button: true,
        selected: selected,
        label: '粗体',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: selected ? accent : fg.withValues(alpha: 0.22),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Text(
              'B',
              style: TextStyle(
                fontSize: KaiProductTokens.typographyReaderOverlayTitle,
                fontWeight: FontWeight.w600,
                color: selected ? accent : fg,
              ),
            ),
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
          borderRadius: BorderRadius.circular(AppRadii.menu),
          border: Border.all(color: fgMuted.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: context.appLabelSize,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Icon(KaijuanIcons.chevronRight, size: 20, color: fgMuted),
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
          ReaderToolPanelLabel('阅读模式', fgMuted),
          const SizedBox(height: AppSpacing.x2),
          ReaderSegmentedChoices<BookReadingMode>(
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
          ReaderToolPanelLabel('翻页效果', fgMuted),
          const SizedBox(height: AppSpacing.x2),
          ReaderSegmentedChoices<BookPageTurnEffect>(
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

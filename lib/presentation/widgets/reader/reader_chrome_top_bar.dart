import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';
import 'glass_bar.dart';

/// Shared top chrome bar height (icon row inside SafeArea).
const double kReaderChromeBarHeight = 56.0;
const double kReaderChromeBarHeightShort = 44.0;

/// Clear of macOS traffic lights (same band as [DesktopTitleBar]).
const double kReaderChromeMacTrafficLightClearance = 78.0;

/// Opaque top reader chrome: traffic-light clearance, back, title, trailing.
///
/// Book and comic inject [title]/[subtitle] and trailing actions; layout and
/// material match pre-extract chrome (no frosted glass).
class ReaderChromeTopBar extends StatelessWidget {
  const ReaderChromeTopBar({
    super.key,
    required this.surface,
    required this.fg,
    required this.fgMuted,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.trailing = const <Widget>[],
  });

  final Color surface;
  final Color fg;
  final Color fgMuted;
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Actions after the title (e.g. bookmark, search). Built by the caller so
  /// tooltips and callbacks stay engine-specific.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final short = context.appIsShortViewport;
    final barH = short ? kReaderChromeBarHeightShort : kReaderChromeBarHeight;
    final density = short ? VisualDensity.compact : VisualDensity.standard;

    final leadingClearance =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
        ? kReaderChromeMacTrafficLightClearance
        : 0.0;

    return GlassBar(
      glass: surface,
      blur: false,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: barH,
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                SizedBox(width: leadingClearance),
                IconButton(
                  tooltip: '返回',
                  visualDensity: density,
                  onPressed: onBack,
                  icon: Icon(KaijuanIcons.back, color: fg, weight: 300),
                ),
                Expanded(
                  child: short
                      ? Text(
                          '$title  ·  $subtitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: fg,
                            fontSize:
                                KaiProductTokens.typographyReaderOverlayTitle,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontSize: KaiProductTokens
                                    .typographyReaderOverlayTitle,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: fgMuted,
                                fontSize: KaiProductTokens
                                    .typographyReaderOverlaySubtitle,
                              ),
                            ),
                          ],
                        ),
                ),
                ...trailing,
                if (leadingClearance > 0)
                  SizedBox(width: leadingClearance - 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual density for reader chrome icon buttons (compact on short viewports).
VisualDensity readerChromeIconDensity(BuildContext context) {
  return context.appIsShortViewport
      ? VisualDensity.compact
      : VisualDensity.standard;
}

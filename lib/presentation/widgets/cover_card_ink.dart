import 'package:flutter/material.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';

/// Multi-select corner badge on a cover — filled check, no thick cover border.
class CoverSelectBadge extends StatelessWidget {
  const CoverSelectBadge({super.key, required this.selected, this.size = 22});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (!selected) {
      return Icon(
        KaijuanIcons.circle,
        size: size,
        color: Colors.white,
        shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
      );
    }
    // White disc behind accent check so it stays readable on warm covers.
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(KaijuanIcons.checkCircleFilled, size: size, color: accent),
      ),
    );
  }
}

/// Soft lift under cover artwork (library / shelf / collage).
///
/// Uses a pure black/white hairline outline (not a tinted neutral) so light
/// covers stay defined on light canvas without reading as dirt on the image edge.
class SoftCoverFrame extends StatelessWidget {
  const SoftCoverFrame({
    super.key,
    required this.child,
    this.radius = AppProductRadii.cover,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);
    final radiusGeom = BorderRadius.circular(radius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radiusGeom,
        boxShadow: [
          BoxShadow(
            color: context.appGlass.shadow,
            blurRadius: 10 * context.appSkinEffects.shadowScale,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // Foreground ring sits on the clipped edge without shrinking layout.
      foregroundDecoration: BoxDecoration(
        borderRadius: radiusGeom,
        border: Border.all(color: outline, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Cover / collage card tap target without Material ink wash on the artwork.
///
/// Press feedback is a subtle [scale] of `0.96` (interruptible). Set
/// [enablePressScale] to false when motion would be distracting (e.g. dense
/// multi-select grids). Keyboard focus keeps a visible accent ring; hover and
/// press stay free of grey ink overlays per library cover rules.
class CoverCardInk extends StatefulWidget {
  const CoverCardInk({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppProductRadii.cover),
    ),
    this.enablePressScale = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// When false, skips the tactile press scale (still handles taps).
  final bool enablePressScale;

  @override
  State<CoverCardInk> createState() => _CoverCardInkState();
}

class _CoverCardInkState extends State<CoverCardInk> {
  static const _pressScale = 0.96;
  static const _pressDuration = Duration(milliseconds: 150);

  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (!widget.enablePressScale || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final allowScale =
        widget.enablePressScale && interactive && !reduceMotion;
    final accent = Theme.of(context).colorScheme.primary;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: allowScale ? (_) => _setPressed(true) : null,
        onTapUp: allowScale ? (_) => _setPressed(false) : null,
        onTapCancel: allowScale ? () => _setPressed(false) : null,
        onFocusChange: (focused) {
          if (_focused == focused) return;
          setState(() => _focused = focused);
        },
        borderRadius: widget.borderRadius,
        splashFactory: NoSplash.splashFactory,
        // Keep press/hover clean on artwork; only focus gets a tint cue.
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return accent.withValues(alpha: 0.12);
          }
          return Colors.transparent;
        }),
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: AnimatedScale(
          scale: _pressed && allowScale ? _pressScale : 1,
          duration: reduceMotion ? Duration.zero : _pressDuration,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : _pressDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                width: 2,
                color: _focused ? accent : Colors.transparent,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

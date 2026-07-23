import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Multi-select corner badge on a cover — filled check, no thick cover border.
class CoverSelectBadge extends StatelessWidget {
  const CoverSelectBadge({
    super.key,
    required this.selected,
    this.size = 22,
  });

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (!selected) {
      return Icon(
        Icons.circle_outlined,
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
        child: Icon(Icons.check_circle, size: size, color: accent),
      ),
    );
  }
}

/// Soft lift under cover artwork (library / shelf / collage).
class SoftCoverFrame extends StatelessWidget {
  const SoftCoverFrame({
    super.key,
    required this.child,
    this.radius = 12,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: context.appGlass.shadow,
            blurRadius: 10 * context.appSkinEffects.shadowScale,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

/// Cover / collage card tap target without Material ink wash on the artwork.
class CoverCardInk extends StatelessWidget {
  const CoverCardInk({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        mouseCursor: SystemMouseCursors.click,
        child: child,
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Frosted glass or solid surface bar for reader chrome overlays.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.glass,
    required this.child,
    this.blur = true,
  });

  final Color glass;
  final Widget child;

  /// When false, draw an opaque surface (no BackdropFilter). Book tool strips
  /// need this so controls stay readable over the page.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final glassTheme = context.appGlass;
    final effects = context.appSkinEffects;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: glass,
        boxShadow: [
          BoxShadow(
            color: glassTheme.shadow,
            blurRadius: 16 * effects.shadowScale,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (!blur || glassTheme.blur <= 0) return box;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: glassTheme.blur,
          sigmaY: glassTheme.blur,
        ),
        child: box,
      ),
    );
  }
}

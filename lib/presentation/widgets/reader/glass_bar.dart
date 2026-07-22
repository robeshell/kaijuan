import 'dart:ui';

import 'package:flutter/material.dart';

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
    final box = DecoratedBox(
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
    );
    if (!blur) return box;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: box,
      ),
    );
  }
}

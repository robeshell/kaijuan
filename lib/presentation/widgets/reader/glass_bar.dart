import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted glass bar used by reader chrome overlays.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.glass,
    required this.child,
  });

  final Color glass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
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
        ),
      ),
    );
  }
}

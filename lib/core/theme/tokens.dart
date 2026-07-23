import 'package:flutter/material.dart';

/// Layer 1 primitive tokens: spacing, radii, and the accent palette.
///
/// Semantic colors live in glass.dart ([AppGlassTheme]) and skins.dart
/// ([AppSkinPreset]); assembly lives in app_theme.dart ([AppTheme]).
/// Business UI must only reference the semantic layer — see
/// docs/DESIGN_FOUNDATION.md.

abstract final class AppSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
}

abstract final class AppRadii {
  static const double control = 10; // buttons, inputs, small controls
  static const double card = 14; // cards, cover frames
  static const double menu = 12; // menus, popovers, snackbars
  static const double sheet = 18; // bottom sheets
  static const double dialog = 20; // dialogs
  static const double pill = 999; // stadium / capsule shapes
}

class AccentPreset {
  const AccentPreset({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;

  /// Contrast foreground for content drawn on top of the accent.
  Color get onAccent =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

abstract final class AppColors {
  static const accentPresets = <AccentPreset>[
    AccentPreset(id: 'ember', label: '暖橙', color: Color(0xFFEA580C)),
    AccentPreset(id: 'sky', label: '晴空', color: Color(0xFF0284C7)),
    AccentPreset(id: 'forest', label: '松绿', color: Color(0xFF047857)),
    AccentPreset(id: 'rose', label: '绯红', color: Color(0xFFBE123C)),
    AccentPreset(id: 'slate', label: '岩灰', color: Color(0xFF475569)),
  ];

  static AccentPreset get defaultAccent => accentPresets.first;

  static AccentPreset presetById(String? id) {
    for (final preset in accentPresets) {
      if (preset.id == id) return preset;
    }
    return defaultAccent;
  }

  /// Subtle wash for inputs / inset wells (not full-page background).
  static const lightWash = Color(0xFFF5F5F7);
}

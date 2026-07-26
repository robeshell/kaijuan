import 'package:flutter/material.dart';

import 'brand_tokens.g.dart';

/// Layer 1 primitive tokens: spacing, radii, and the accent palette.
///
/// Semantic colors live in glass.dart ([AppGlassTheme]) and skins.dart
/// ([AppSkinPreset]); assembly lives in app_theme.dart ([AppTheme]).
/// Business UI must only reference the semantic layer — see
/// docs/DESIGN_FOUNDATION.md.

abstract final class AppSpacing {
  static const double x1 = KaiBrandSpacing.x1;
  static const double x2 = KaiBrandSpacing.x2;
  static const double x3 = KaiBrandSpacing.x3;
  static const double x4 = KaiBrandSpacing.x4;
  static const double x6 = KaiBrandSpacing.x6;
  static const double x8 = KaiBrandSpacing.x8;
}

abstract final class AppRadii {
  static const double control = KaiBrandRadii.control;
  static const double card = KaiBrandRadii.card;
  static const double menu = KaiBrandRadii.menu;
  static const double sheet = KaiBrandRadii.sheet;
  static const double dialog = KaiBrandRadii.dialog;
  static const double pill = KaiBrandRadii.pill;
}

/// Product-level shape tokens for book/comic content frames.
abstract final class AppProductRadii {
  static const double cover = KaiProductTokens.coverRadius;
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
    AccentPreset(
      id: KaiProductAccents.emberId,
      label: KaiProductAccents.emberLabel,
      color: KaiProductAccents.ember,
    ),
    AccentPreset(
      id: KaiProductAccents.skyId,
      label: KaiProductAccents.skyLabel,
      color: KaiProductAccents.sky,
    ),
    AccentPreset(
      id: KaiProductAccents.forestId,
      label: KaiProductAccents.forestLabel,
      color: KaiProductAccents.forest,
    ),
    AccentPreset(
      id: KaiProductAccents.roseId,
      label: KaiProductAccents.roseLabel,
      color: KaiProductAccents.rose,
    ),
    AccentPreset(
      id: KaiProductAccents.slateId,
      label: KaiProductAccents.slateLabel,
      color: KaiProductAccents.slate,
    ),
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

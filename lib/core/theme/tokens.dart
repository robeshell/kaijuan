import 'dart:math' as math;

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

/// Disabled foreground: secondary × this alpha (brand `derivedAlphas.disabledForeground`).
const appDisabledForegroundOpacity = 0.55;

/// List / surface accent wash (brand `derivedAlphas.selection.listTileSelected`).
const appListTileSelectedOpacity = 0.04;

class AccentPreset {
  const AccentPreset({
    required this.id,
    required this.label,
    required this.color,
    required this.onAccent,
  });

  final String id;
  final String label;
  final Color color;

  /// Contrast foreground for content drawn on top of the accent.
  final Color onAccent;

  /// Fallback for unregistered custom colors; registered presets use brand tokens.
  static Color readableForeground(Color color) {
    const candidates = <Color>[
      Colors.white,
      Color(0xFF1C1C22),
      Color(0xFF141418),
    ];
    Color best = candidates.first;
    var bestRatio = 0.0;
    for (final candidate in candidates) {
      final ratio = _contrastRatio(candidate, color);
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = candidate;
      }
    }
    return best;
  }

  static double _relativeLuminance(Color color) {
    double channel(double c) {
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  static double _contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a);
    final l2 = _relativeLuminance(b);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }
}

abstract final class AppColors {
  static const defaultAccent = AccentPreset(
    id: KaiProductAccents.emberId,
    label: KaiProductAccents.emberLabel,
    color: KaiProductAccents.ember,
    onAccent: KaiProductAccents.emberOnAccent,
  );

  static const accentPresets = <AccentPreset>[
    defaultAccent,
    AccentPreset(
      id: KaiProductAccents.skyId,
      label: KaiProductAccents.skyLabel,
      color: KaiProductAccents.sky,
      onAccent: KaiProductAccents.skyOnAccent,
    ),
    AccentPreset(
      id: KaiProductAccents.forestId,
      label: KaiProductAccents.forestLabel,
      color: KaiProductAccents.forest,
      onAccent: KaiProductAccents.forestOnAccent,
    ),
    AccentPreset(
      id: KaiProductAccents.roseId,
      label: KaiProductAccents.roseLabel,
      color: KaiProductAccents.rose,
      onAccent: KaiProductAccents.roseOnAccent,
    ),
    AccentPreset(
      id: KaiProductAccents.slateId,
      label: KaiProductAccents.slateLabel,
      color: KaiProductAccents.slate,
      onAccent: KaiProductAccents.slateOnAccent,
    ),
  ];

  static AccentPreset presetById(String? id) {
    for (final preset in accentPresets) {
      if (preset.id == id) return preset;
    }
    return defaultAccent;
  }

  /// Subtle wash for inputs / inset wells (not full-page background).
  static const lightWash = Color(0xFFF5F5F7);
}

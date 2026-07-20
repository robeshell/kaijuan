import 'package:flutter/material.dart';

/// Design tokens for KaikaNext, following docs/DESIGN_FOUNDATION.md.
///
/// Three layers: primitive tokens (this file's constants) → semantic tokens
/// ([AppSemantics]) → theme assembly ([AppTheme]). Business UI must only
/// reference the semantic layer.

// ---------------------------------------------------------------------------
// Layer 1: primitive tokens
// ---------------------------------------------------------------------------

abstract final class AppSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
}

abstract final class AppRadii {
  static const double small = 8; // small controls
  static const double medium = 12; // cards, buttons
  static const double large = 16; // embedded cards
  static const double panel = 20; // panels, dialogs
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

  // Neutral ramp — the chrome canvas stays neutral so covers supply color.
  static const _lightCanvas = Color(0xFFF7F7F8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightText = Color(0xFF1C1C1E);
  static const _darkCanvas = Color(0xFF141416);
  static const _darkSurface = Color(0xFF1E1E21);
  static const _darkText = Color(0xFFF2F2F4);
}

// ---------------------------------------------------------------------------
// Layer 2: semantic tokens
// ---------------------------------------------------------------------------

/// Semantic colors not covered by ColorScheme. Reach via
/// `Theme.of(context).extension<AppSemantics>()!`.
class AppSemantics extends ThemeExtension<AppSemantics> {
  const AppSemantics({
    required this.canvas,
    required this.surface,
    required this.glassFill,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
  });

  /// Neutral app canvas behind everything.
  final Color canvas;

  /// Opaque surface for cards and sheets.
  final Color surface;

  /// Translucent fill for glass chrome (sidebars, reader bars, menus).
  /// Pair with a BackdropFilter blur at the widget layer.
  final Color glassFill;

  /// Hairline separators — text color at 8% opacity.
  final Color hairline;

  final Color textPrimary;
  final Color textSecondary;

  factory AppSemantics.light() => const AppSemantics(
    canvas: AppColors._lightCanvas,
    surface: AppColors._lightSurface,
    glassFill: Color(0xB3FFFFFF), // white 70%
    hairline: Color(0x141C1C1E), // text 8%
    textPrimary: AppColors._lightText,
    textSecondary: Color(0x991C1C1E), // text 60%
  );

  factory AppSemantics.dark() => const AppSemantics(
    canvas: AppColors._darkCanvas,
    surface: AppColors._darkSurface,
    glassFill: Color(0xB3212124), // near-black 70%
    hairline: Color(0x14F2F2F4),
    textPrimary: AppColors._darkText,
    textSecondary: Color(0x99F2F2F4),
  );

  @override
  AppSemantics copyWith({
    Color? canvas,
    Color? surface,
    Color? glassFill,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
  }) {
    return AppSemantics(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      glassFill: glassFill ?? this.glassFill,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppSemantics lerp(AppSemantics? other, double t) {
    if (other == null) return this;
    return AppSemantics(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// Layer 3: theme assembly
// ---------------------------------------------------------------------------

abstract final class AppTheme {
  static ThemeData light(AccentPreset accent) =>
      _base(brightness: Brightness.light, accent: accent.color);

  static ThemeData dark(AccentPreset accent) =>
      _base(brightness: Brightness.dark, accent: accent.color);

  static ThemeData _base({
    required Brightness brightness,
    required Color accent,
  }) {
    final light = brightness == Brightness.light;
    final semantics = light ? AppSemantics.light() : AppSemantics.dark();
    // fromSeed derives onPrimary for the seed's tonal primary, not for the
    // raw accent we force below — compute the matching contrast color.
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final scheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: accent,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent,
      surface: semantics.surface,
      onSurface: semantics.textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: semantics.canvas,
      dividerColor: semantics.hairline,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: [semantics],
    );
  }
}

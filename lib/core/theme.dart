import 'package:flutter/material.dart';

/// Design tokens for kaijuan, following docs/DESIGN_FOUNDATION.md.
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

  // Light neutrals — keep chrome clean/white so covers supply color.
  // Avoid mid-gray canvases (#F0–F5 range) which read "dirty" next to white cards.
  static const _lightCanvas = Color(0xFFFFFFFF);
  static const _lightSurface = Color(0xFFFFFFFF);
  /// Subtle wash only for inputs / inset wells (not full-page background).
  static const lightWash = Color(0xFFF5F5F7);
  static const _lightText = Color(0xFF111113);
  /// Cool neutral secondary — not black@60% on gray (that goes muddy).
  static const _lightTextSecondary = Color(0xFF6B6B73);
  static const _lightHairline = Color(0x0F000000); // 6% black, crisp not sooty
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
    glassFill: Color(0xE6FFFFFF), // white ~90% — less gray stack
    hairline: AppColors._lightHairline,
    textPrimary: AppColors._lightText,
    textSecondary: AppColors._lightTextSecondary,
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
    // fromSeed adds gray surfaceContainer* + surfaceTint that make M3 chrome muddy.
    final scheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: accent,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent,
      surface: semantics.surface,
      onSurface: semantics.textPrimary,
      onSurfaceVariant: semantics.textSecondary,
      surfaceTint: Colors.transparent,
      outline: semantics.hairline,
      outlineVariant: semantics.hairline,
      surfaceContainerLowest: semantics.surface,
      surfaceContainerLow: light ? AppColors.lightWash : semantics.surface,
      surfaceContainer: semantics.surface,
      surfaceContainerHigh: light ? AppColors.lightWash : semantics.surface,
      surfaceContainerHighest: light ? AppColors.lightWash : semantics.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: semantics.canvas,
      dividerColor: semantics.hairline,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: [semantics],
      // Kill M3 primary-tinted overlays that turn white → dirty gray/orange.
      applyElevationOverlayColor: false,
      appBarTheme: AppBarTheme(
        backgroundColor: semantics.canvas,
        foregroundColor: semantics.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: semantics.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.12),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? accent : semantics.textSecondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: semantics.surface,
        indicatorColor: accent.withValues(alpha: 0.10),
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        unselectedIconTheme: IconThemeData(color: semantics.textSecondary),
        unselectedLabelTextStyle: TextStyle(
          color: semantics.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: semantics.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: AppColors.lightWash,
        filled: true,
      ),
      // Quiet chrome for dialogs / menus / tips (both brands).
      iconTheme: IconThemeData(
        color: semantics.textSecondary,
        size: 20,
        weight: 300,
        fill: 0,
      ),
      primaryIconTheme: IconThemeData(
        color: accent,
        size: 20,
        weight: 300,
        fill: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: semantics.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          side: BorderSide(color: semantics.hairline),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: semantics.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: semantics.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: semantics.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        dragHandleColor: semantics.hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.panel),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: semantics.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          side: BorderSide(color: semantics.hairline),
        ),
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: semantics.textPrimary,
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: semantics.textPrimary,
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(semantics.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.medium),
              side: BorderSide(color: semantics.hairline),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 3),
        decoration: BoxDecoration(
          color: light ? const Color(0xE6111113) : const Color(0xE6F2F2F4),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: light ? Colors.white : const Color(0xFF111113),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xE62C2C2E),
        contentTextStyle: const TextStyle(
          color: Color(0xFFF4F4F5),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.3,
          letterSpacing: 0.2,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const StadiumBorder(),
        insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: semantics.textSecondary,
        textColor: semantics.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: semantics.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: semantics.textSecondary,
        ),
      ),
    );
  }
}

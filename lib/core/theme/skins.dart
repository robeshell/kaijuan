import 'package:flutter/material.dart';

import 'glass.dart';

/// A bundled appearance: brightness + four surface tones + glass + effects.
///
/// Skins own the app chrome's look; reading themes (paper/sepia/dark…) are
/// content-level and stay independent of the skin — see
/// docs/DESIGN_FOUNDATION.md.
@immutable
class AppSkinPreset {
  const AppSkinPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.elevated,
    required this.overlay,
    required this.glass,
    required this.effects,
  });

  final String id;
  final String name;
  final String description;
  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color elevated;
  final Color overlay;
  final AppGlassTheme glass;
  final AppSkinEffects effects;
}

abstract final class AppSkins {
  /// Persisted selection id meaning "follow the platform brightness".
  /// Not a real preset — resolved to [standard]/[deepNight] at build time.
  static const systemId = 'system';

  static const _lightCanvas = Color(0xFFF7F7F8);
  static const _lightSurface = Color(0xFFFAFAFB);
  static const _lightElevated = Color(0xFFFFFFFF);
  static const _lightOverlay = Color(0xFFF1F2F4);
  static const _darkCanvas = Color(0xFF0D0D0F);
  static const _darkSurface = Color(0xFF17171A);
  static const _darkElevated = Color(0xFF202024);
  static const _darkOverlay = Color(0xFF29292E);

  /// The original 开卷 appearance. Keep these tokens stable so adding new
  /// skins never changes the visual baseline existing users already know.
  static const standard = AppSkinPreset(
    id: 'default',
    name: '默认',
    description: '开卷的中性浅色玻璃界面',
    brightness: Brightness.light,
    canvas: _lightCanvas,
    surface: _lightSurface,
    elevated: _lightElevated,
    overlay: _lightOverlay,
    glass: AppGlassTheme.light,
    effects: AppSkinEffects.standard,
  );

  static const pure = AppSkinPreset(
    id: 'pure',
    name: '纯净',
    description: '冷静通透的实色表面与清晰层次',
    brightness: Brightness.light,
    canvas: Color(0xFFF1F4F8),
    surface: Color(0xFFFAFCFF),
    elevated: Color(0xFFFFFFFF),
    overlay: Color(0xFFE5EBF2),
    glass: AppGlassTheme(
      canvasHighlight: Color(0xFFF8FBFF),
      surface: Color(0xFFFFFFFF),
      strongSurface: Color(0xFFFFFFFF),
      border: Color(0x1F526174),
      innerHighlight: Color(0xFFFFFFFF),
      shadow: Color(0x00000000),
      primaryText: Color(0xFF18202A),
      secondaryText: Color(0xFF536171),
      mutedText: Color(0xFF718092),
      blur: 0,
      strongBlur: 0,
    ),
    effects: AppSkinEffects(
      motionDuration: Duration(seconds: 26),
      paletteTransitionDuration: Duration(milliseconds: 240),
      motionStrength: 0.22,
      primaryGlowOpacity: 0.38,
      secondaryGlowOpacity: 0.24,
      lightVeilOpacity: 0.015,
      darkVeilOpacity: 0.08,
      shadowScale: 0,
    ),
  );

  static const deepNight = AppSkinPreset(
    id: 'deep-night',
    name: '深夜',
    description: '专注于书页与封面的低亮深色界面',
    brightness: Brightness.dark,
    canvas: _darkCanvas,
    surface: _darkSurface,
    elevated: _darkElevated,
    overlay: _darkOverlay,
    glass: AppGlassTheme.dark,
    effects: AppSkinEffects(
      motionDuration: Duration(seconds: 18),
      paletteTransitionDuration: Duration(milliseconds: 520),
      motionStrength: 0.68,
      primaryGlowOpacity: 0.76,
      secondaryGlowOpacity: 0.54,
      lightVeilOpacity: 0.04,
      darkVeilOpacity: 0.22,
      shadowScale: 1.12,
    ),
  );

  static const defaultPreset = standard;
  static const presets = [standard, pure, deepNight];

  static AppSkinPreset byId(String? id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return defaultPreset;
  }

  /// Resolve a persisted selection id ([systemId] or a preset id) against
  /// the platform brightness.
  static AppSkinPreset resolve(String? id, Brightness platformBrightness) {
    if (id == systemId) {
      return platformBrightness == Brightness.dark ? deepNight : standard;
    }
    return byId(id);
  }
}

import 'package:flutter/material.dart';

import 'brand_tokens.g.dart';
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

  /// The original 开卷 appearance. Keep these tokens stable so adding new
  /// skins never changes the visual baseline existing users already know.
  static const standard = AppSkinPreset(
    id: 'default',
    name: '默认',
    description: '开卷的中性浅色玻璃界面',
    brightness: Brightness.light,
    canvas: KaiBrandDefaultSkin.canvas,
    surface: KaiBrandDefaultSkin.surface,
    elevated: KaiBrandDefaultSkin.elevated,
    overlay: KaiBrandDefaultSkin.overlay,
    glass: AppGlassTheme.light,
    effects: AppSkinEffects.standard,
  );

  static const pure = AppSkinPreset(
    id: 'pure',
    name: '纯净',
    description: '冷静通透的实色表面与清晰层次',
    brightness: Brightness.light,
    canvas: KaiBrandPureSkin.canvas,
    surface: KaiBrandPureSkin.surface,
    elevated: KaiBrandPureSkin.elevated,
    overlay: KaiBrandPureSkin.overlay,
    glass: AppGlassTheme(
      canvasHighlight: KaiBrandPureSkin.glassCanvasHighlight,
      surface: KaiBrandPureSkin.glassSurface,
      strongSurface: KaiBrandPureSkin.glassStrongSurface,
      chromeSurface: KaiBrandPureSkin.glassChromeSurface,
      border: KaiBrandPureSkin.glassBorder,
      innerHighlight: KaiBrandPureSkin.glassInnerHighlight,
      shadow: KaiBrandPureSkin.glassShadow,
      primaryText: KaiBrandPureSkin.glassPrimaryText,
      secondaryText: KaiBrandPureSkin.glassSecondaryText,
      mutedText: KaiBrandPureSkin.glassMutedText,
      blur: KaiBrandPureSkin.glassBlur,
      strongBlur: KaiBrandPureSkin.glassStrongBlur,
    ),
    effects: AppSkinEffects(
      motionDuration: Duration(seconds: KaiBrandPureSkin.effectMotionDurationS),
      paletteTransitionDuration: Duration(
        milliseconds: KaiBrandPureSkin.effectPaletteTransitionMs,
      ),
      motionStrength: KaiBrandPureSkin.effectMotionStrength,
      primaryGlowOpacity: KaiBrandPureSkin.effectPrimaryGlowOpacity,
      secondaryGlowOpacity: KaiBrandPureSkin.effectSecondaryGlowOpacity,
      lightVeilOpacity: KaiBrandPureSkin.effectLightVeilOpacity,
      darkVeilOpacity: KaiBrandPureSkin.effectDarkVeilOpacity,
      shadowScale: KaiBrandPureSkin.effectShadowScale,
    ),
  );

  static const deepNight = AppSkinPreset(
    id: 'deep-night',
    name: '深夜',
    description: '专注于书页与封面的低亮深色界面',
    brightness: Brightness.dark,
    canvas: KaiBrandDeepNightSkin.canvas,
    surface: KaiBrandDeepNightSkin.surface,
    elevated: KaiBrandDeepNightSkin.elevated,
    overlay: KaiBrandDeepNightSkin.overlay,
    glass: AppGlassTheme.dark,
    effects: AppSkinEffects(
      motionDuration: Duration(
        seconds: KaiBrandDeepNightSkin.effectMotionDurationS,
      ),
      paletteTransitionDuration: Duration(
        milliseconds: KaiBrandDeepNightSkin.effectPaletteTransitionMs,
      ),
      motionStrength: KaiBrandDeepNightSkin.effectMotionStrength,
      primaryGlowOpacity: KaiBrandDeepNightSkin.effectPrimaryGlowOpacity,
      secondaryGlowOpacity: KaiBrandDeepNightSkin.effectSecondaryGlowOpacity,
      lightVeilOpacity: KaiBrandDeepNightSkin.effectLightVeilOpacity,
      darkVeilOpacity: KaiBrandDeepNightSkin.effectDarkVeilOpacity,
      shadowScale: KaiBrandDeepNightSkin.effectShadowScale,
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

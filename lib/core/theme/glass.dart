import 'package:flutter/material.dart';

/// Layer 2 semantic tokens: glass surfaces and skin motion/material effects.
///
/// These are [ThemeExtension]s carried by the active skin preset (see
/// skins.dart). Components consume them via the context getters in
/// context.dart — never hardcode translucency, shadow, or text colors.

@immutable
class AppGlassTheme extends ThemeExtension<AppGlassTheme> {
  const AppGlassTheme({
    required this.canvasHighlight,
    required this.surface,
    required this.strongSurface,
    required this.border,
    required this.innerHighlight,
    required this.shadow,
    required this.primaryText,
    required this.secondaryText,
    required this.mutedText,
    required this.blur,
    required this.strongBlur,
  });

  static const light = AppGlassTheme(
    canvasHighlight: Color(0xFFFBFBFC),
    surface: Color(0xB8FFFFFF),
    strongSurface: Color(0xDEFFFFFF),
    border: Color(0x12000000),
    innerHighlight: Color(0x8CFFFFFF),
    shadow: Color(0x16000000),
    primaryText: Color(0xFF1C1C22),
    secondaryText: Color(0xFF5A5A62),
    mutedText: Color(0xFF77747D),
    blur: 20,
    strongBlur: 28,
  );

  static const dark = AppGlassTheme(
    canvasHighlight: Color(0xFF17171A),
    surface: Color(0xB817171A),
    strongSurface: Color(0xE6202024),
    border: Color(0x1CFFFFFF),
    innerHighlight: Color(0x1FFFFFFF),
    shadow: Color(0x6B000000),
    primaryText: Color(0xFFF7F3F4),
    secondaryText: Color(0x99FFFFFF),
    mutedText: Color(0xB3FFFFFF),
    blur: 20,
    strongBlur: 28,
  );

  final Color canvasHighlight;
  final Color surface;
  final Color strongSurface;
  final Color border;
  final Color innerHighlight;
  final Color shadow;
  final Color primaryText;
  final Color secondaryText;
  final Color mutedText;
  final double blur;
  final double strongBlur;

  @override
  AppGlassTheme copyWith({
    Color? canvasHighlight,
    Color? surface,
    Color? strongSurface,
    Color? border,
    Color? innerHighlight,
    Color? shadow,
    Color? primaryText,
    Color? secondaryText,
    Color? mutedText,
    double? blur,
    double? strongBlur,
  }) {
    return AppGlassTheme(
      canvasHighlight: canvasHighlight ?? this.canvasHighlight,
      surface: surface ?? this.surface,
      strongSurface: strongSurface ?? this.strongSurface,
      border: border ?? this.border,
      innerHighlight: innerHighlight ?? this.innerHighlight,
      shadow: shadow ?? this.shadow,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      mutedText: mutedText ?? this.mutedText,
      blur: blur ?? this.blur,
      strongBlur: strongBlur ?? this.strongBlur,
    );
  }

  @override
  AppGlassTheme lerp(covariant AppGlassTheme? other, double t) {
    if (other == null) return this;
    return AppGlassTheme(
      canvasHighlight: Color.lerp(canvasHighlight, other.canvasHighlight, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      strongSurface: Color.lerp(strongSurface, other.strongSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      innerHighlight: Color.lerp(innerHighlight, other.innerHighlight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      blur: blur + (other.blur - blur) * t,
      strongBlur: strongBlur + (other.strongBlur - strongBlur) * t,
    );
  }
}

/// Material and motion characteristics that belong to a skin without changing
/// page structure. Components consume these semantic values instead of
/// branching on a skin identifier.
@immutable
class AppSkinEffects extends ThemeExtension<AppSkinEffects> {
  const AppSkinEffects({
    required this.motionDuration,
    required this.paletteTransitionDuration,
    required this.motionStrength,
    required this.primaryGlowOpacity,
    required this.secondaryGlowOpacity,
    required this.lightVeilOpacity,
    required this.darkVeilOpacity,
    required this.shadowScale,
  });

  static const standard = AppSkinEffects(
    motionDuration: Duration(seconds: 14),
    paletteTransitionDuration: Duration(milliseconds: 420),
    motionStrength: 1,
    primaryGlowOpacity: 0.90,
    secondaryGlowOpacity: 0.72,
    lightVeilOpacity: 0.04,
    darkVeilOpacity: 0.12,
    shadowScale: 1,
  );

  final Duration motionDuration;
  final Duration paletteTransitionDuration;
  final double motionStrength;
  final double primaryGlowOpacity;
  final double secondaryGlowOpacity;
  final double lightVeilOpacity;
  final double darkVeilOpacity;
  final double shadowScale;

  @override
  AppSkinEffects copyWith({
    Duration? motionDuration,
    Duration? paletteTransitionDuration,
    double? motionStrength,
    double? primaryGlowOpacity,
    double? secondaryGlowOpacity,
    double? lightVeilOpacity,
    double? darkVeilOpacity,
    double? shadowScale,
  }) {
    return AppSkinEffects(
      motionDuration: motionDuration ?? this.motionDuration,
      paletteTransitionDuration:
          paletteTransitionDuration ?? this.paletteTransitionDuration,
      motionStrength: motionStrength ?? this.motionStrength,
      primaryGlowOpacity: primaryGlowOpacity ?? this.primaryGlowOpacity,
      secondaryGlowOpacity:
          secondaryGlowOpacity ?? this.secondaryGlowOpacity,
      lightVeilOpacity: lightVeilOpacity ?? this.lightVeilOpacity,
      darkVeilOpacity: darkVeilOpacity ?? this.darkVeilOpacity,
      shadowScale: shadowScale ?? this.shadowScale,
    );
  }

  @override
  AppSkinEffects lerp(covariant AppSkinEffects? other, double t) {
    if (other == null) return this;
    int lerpDuration(Duration from, Duration to) =>
        (from.inMicroseconds + (to.inMicroseconds - from.inMicroseconds) * t)
            .round();
    return AppSkinEffects(
      motionDuration: Duration(
        microseconds: lerpDuration(motionDuration, other.motionDuration),
      ),
      paletteTransitionDuration: Duration(
        microseconds: lerpDuration(
          paletteTransitionDuration,
          other.paletteTransitionDuration,
        ),
      ),
      motionStrength:
          motionStrength + (other.motionStrength - motionStrength) * t,
      primaryGlowOpacity:
          primaryGlowOpacity +
          (other.primaryGlowOpacity - primaryGlowOpacity) * t,
      secondaryGlowOpacity:
          secondaryGlowOpacity +
          (other.secondaryGlowOpacity - secondaryGlowOpacity) * t,
      lightVeilOpacity:
          lightVeilOpacity + (other.lightVeilOpacity - lightVeilOpacity) * t,
      darkVeilOpacity:
          darkVeilOpacity + (other.darkVeilOpacity - darkVeilOpacity) * t,
      shadowScale: shadowScale + (other.shadowScale - shadowScale) * t,
    );
  }
}

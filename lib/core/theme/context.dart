import 'package:flutter/material.dart';

import 'glass.dart';

const appChromeSurfaceTransparency = 0.20;
const appChromeSurfaceOpacity = 1 - appChromeSurfaceTransparency;

/// Semantic-token getters for business UI. This is the only layer widgets
/// should read — see docs/DESIGN_FOUNDATION.md.
extension AppThemeContext on BuildContext {
  ThemeData get appTheme => Theme.of(this);

  ColorScheme get appColors => Theme.of(this).colorScheme;

  AppGlassTheme get appGlass =>
      Theme.of(this).extension<AppGlassTheme>() ?? AppGlassTheme.light;

  AppSkinEffects get appSkinEffects =>
      Theme.of(this).extension<AppSkinEffects>() ?? AppSkinEffects.standard;

  Color get appPrimaryText => appGlass.primaryText;

  Color get appSecondaryText => appGlass.secondaryText;

  Color get appMutedText => appGlass.mutedText;

  Color get appChromeSurface =>
      appGlass.strongSurface.withValues(alpha: appChromeSurfaceOpacity);

  Color get appDivider => appColors.outlineVariant;

  Color appTint(double alpha) => appPrimaryText.withValues(alpha: alpha);

  ButtonStyle get appDestructiveButtonStyle {
    final error = appColors.error;
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return error.withValues(alpha: 0.38);
        }
        return error;
      }),
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return error.withValues(alpha: 0.025);
        }
        if (states.contains(WidgetState.pressed)) {
          return error.withValues(alpha: 0.16);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return error.withValues(alpha: 0.12);
        }
        return error.withValues(alpha: 0.08);
      }),
    );
  }
}

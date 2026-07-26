import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'glass.dart';

bool get appUsesDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

const appChromeSurfaceTransparency = 0.20;
const appChromeSurfaceOpacity = 1 - appChromeSurfaceTransparency;

enum AppWindowClass { compact, medium, wide }

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

  /// Skin overlay ramp — theme maps it to [ColorScheme.surfaceContainerHigh].
  Color get appOverlay => appColors.surfaceContainerHigh;

  Color get appDivider => appColors.outlineVariant;

  Color appTint(double alpha) => appPrimaryText.withValues(alpha: alpha);

  AppWindowClass get appWindowClass {
    final size = MediaQuery.sizeOf(this);
    if (appUsesDesktopPlatform) {
      return size.width < 1100 ? AppWindowClass.medium : AppWindowClass.wide;
    }
    if (size.width <= 600 || size.height < 600) {
      return AppWindowClass.compact;
    }
    if (size.width < 1000) return AppWindowClass.medium;
    return AppWindowClass.wide;
  }

  bool get appIsCompact => appWindowClass == AppWindowClass.compact;

  /// Touch-first navigation (bottom bar). Desktop never uses mobile shell.
  bool get appUsesMobileShell {
    if (appUsesDesktopPlatform) return false;
    final size = MediaQuery.sizeOf(this);
    return size.width < 820 || size.height < 600;
  }

  /// Persistent side rail: desktop always; mobile only when wide (≥1000).
  bool get appUsesSideRail =>
      appUsesDesktopPlatform || MediaQuery.sizeOf(this).width >= 1000;

  double get appPageGutter => switch (appWindowClass) {
    AppWindowClass.compact => 16,
    AppWindowClass.medium => 24,
    AppWindowClass.wide => 32,
  };

  double get appPageTitleSize => appIsCompact ? 26 : 28;

  /// Scroll padding so last rows clear the overlaid bottom bar (`extendBody`).
  double get appContentBottomPadding => appUsesMobileShell ? 140 : 96;

  double get appSidebarWidth => switch (appWindowClass) {
    AppWindowClass.compact => 0,
    AppWindowClass.medium => 216,
    AppWindowClass.wide => 236,
  };

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

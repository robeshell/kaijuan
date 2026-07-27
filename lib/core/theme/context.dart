import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'brand_tokens.g.dart';
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

  Color get appChromeSurface {
    return appGlass.strongSurface.withValues(alpha: appChromeSurfaceOpacity);
  }

  /// Skin overlay ramp — theme maps it to [ColorScheme.surfaceContainerHigh].
  Color get appOverlay => appColors.surfaceContainerHigh;

  Color get appDivider => appColors.outlineVariant;

  Color appTint(double alpha) => appPrimaryText.withValues(alpha: alpha);

  AppWindowClass get appWindowClass {
    final size = MediaQuery.sizeOf(this);
    if (appUsesDesktopPlatform) {
      return size.width < KaiBrandLayout.desktopBreakpoint
          ? AppWindowClass.medium
          : AppWindowClass.wide;
    }
    if (size.width <= KaiBrandLayout.compactWidth ||
        size.height < KaiBrandLayout.compactHeight) {
      return AppWindowClass.compact;
    }
    if (size.width < KaiBrandLayout.mobileWideBreakpoint) {
      return AppWindowClass.medium;
    }
    return AppWindowClass.wide;
  }

  bool get appIsCompact => appWindowClass == AppWindowClass.compact;

  /// Landscape aspect (width > height). Used with [appIsShortViewport] for
  /// phone landscape chrome compression — orientation is never locked.
  bool get appIsLandscape {
    final size = MediaQuery.sizeOf(this);
    return size.width > size.height;
  }

  /// Short usable height (phone landscape, split-screen, small fold).
  /// Chrome / bottom bar / tool panels should compress.
  bool get appIsShortViewport {
    final size = MediaQuery.sizeOf(this);
    final padding = MediaQuery.paddingOf(this);
    final usable = size.height - padding.vertical;
    return usable < 480;
  }

  /// Touch-first navigation (bottom bar). Desktop never uses mobile shell.
  bool get appUsesMobileShell {
    if (appUsesDesktopPlatform) return false;
    final size = MediaQuery.sizeOf(this);
    return size.width < KaiBrandLayout.mobileShellWidth ||
        size.height < KaiBrandLayout.compactHeight;
  }

  /// Persistent side rail: desktop always; mobile only when wide (≥1000).
  bool get appUsesSideRail =>
      appUsesDesktopPlatform ||
      MediaQuery.sizeOf(this).width >= KaiBrandLayout.mobileWideBreakpoint;

  double get appPageGutter => switch (appWindowClass) {
    AppWindowClass.compact => KaiBrandLayout.compactGutter,
    AppWindowClass.medium => KaiBrandLayout.mediumGutter,
    AppWindowClass.wide => KaiBrandLayout.wideGutter,
  };

  double get appPageTitleSize => appIsCompact
      ? KaiBrandLayout.compactPageTitle
      : KaiBrandLayout.regularPageTitle;

  /// Scroll padding so last rows clear the overlaid bottom bar (`extendBody`).
  double get appContentBottomPadding {
    if (!appUsesMobileShell) return KaiBrandLayout.desktopBottomPadding;
    // Short landscape: bar is thinner and often icon-only.
    if (appIsShortViewport) return 88;
    return KaiBrandLayout.mobileBottomPadding;
  }

  /// Max fraction of viewport height for reader tool-strip expand panels.
  double get appReaderToolPanelMaxHeightFraction =>
      appIsShortViewport ? 0.38 : 0.48;

  double get appSidebarWidth => switch (appWindowClass) {
    AppWindowClass.compact => 0,
    AppWindowClass.medium => KaiBrandLayout.mediumSidebarWidth,
    AppWindowClass.wide => KaiBrandLayout.wideSidebarWidth,
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

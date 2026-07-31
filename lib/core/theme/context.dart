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

enum AppComponentProfile { mobile, desktop }

AppComponentProfile resolveAppComponentProfile(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => AppComponentProfile.desktop,
    TargetPlatform.iOS || TargetPlatform.android => AppComponentProfile.mobile,
    _ => AppComponentProfile.mobile,
  };
}

extension AppComponentProfileTokens on AppComponentProfile {
  double get pageTitleSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.pageTitleSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.pageTitleSize,
  };

  double get sectionTitleSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.sectionTitleSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.sectionTitleSize,
  };

  double get titleSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.titleSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.titleSize,
  };

  double get bodySize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.bodySize,
    AppComponentProfile.desktop => KaiBrandDesktopType.bodySize,
  };

  double get bodySecondarySize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.bodySecondarySize,
    AppComponentProfile.desktop => KaiBrandDesktopType.bodySecondarySize,
  };

  double get labelSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.labelSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.labelSize,
  };

  double get listTitleSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.listTitleSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.listTitleSize,
  };

  double get captionSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.captionSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.captionSize,
  };

  double get captionSmallSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.captionSmallSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.captionSmallSize,
  };

  TextTheme applyTypeScale(
    TextTheme base, {
    required Color foreground,
    required Color secondary,
  }) {
    TextStyle role(
      TextStyle? source, {
      required double mobileSize,
      required double mobileLineHeight,
      required int mobileWeight,
      required double mobileLetterSpacing,
      required double desktopSize,
      required double desktopLineHeight,
      required int desktopWeight,
      required double desktopLetterSpacing,
      Color? color,
    }) {
      final mobile = this == AppComponentProfile.mobile;
      final size = mobile ? mobileSize : desktopSize;
      final lineHeight = mobile ? mobileLineHeight : desktopLineHeight;
      final weight = mobile ? mobileWeight : desktopWeight;
      final letterSpacing = mobile ? mobileLetterSpacing : desktopLetterSpacing;
      return (source ?? const TextStyle()).copyWith(
        color: color ?? foreground,
        fontSize: size,
        height: lineHeight / size,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        letterSpacing: letterSpacing,
      );
    }

    final displayLarge = role(
      base.displayLarge,
      mobileSize: KaiBrandMobileType.displayLargeSize,
      mobileLineHeight: KaiBrandMobileType.displayLargeLineHeight,
      mobileWeight: KaiBrandMobileType.displayLargeWeight,
      mobileLetterSpacing: KaiBrandMobileType.displayLargeLetterSpacing,
      desktopSize: KaiBrandDesktopType.displayLargeSize,
      desktopLineHeight: KaiBrandDesktopType.displayLargeLineHeight,
      desktopWeight: KaiBrandDesktopType.displayLargeWeight,
      desktopLetterSpacing: KaiBrandDesktopType.displayLargeLetterSpacing,
    );
    final pageTitle = role(
      base.headlineMedium,
      mobileSize: KaiBrandMobileType.pageTitleSize,
      mobileLineHeight: KaiBrandMobileType.pageTitleLineHeight,
      mobileWeight: KaiBrandMobileType.pageTitleWeight,
      mobileLetterSpacing: KaiBrandMobileType.pageTitleLetterSpacing,
      desktopSize: KaiBrandDesktopType.pageTitleSize,
      desktopLineHeight: KaiBrandDesktopType.pageTitleLineHeight,
      desktopWeight: KaiBrandDesktopType.pageTitleWeight,
      desktopLetterSpacing: KaiBrandDesktopType.pageTitleLetterSpacing,
    );
    final sectionTitle = role(
      base.headlineSmall,
      mobileSize: KaiBrandMobileType.sectionTitleSize,
      mobileLineHeight: KaiBrandMobileType.sectionTitleLineHeight,
      mobileWeight: KaiBrandMobileType.sectionTitleWeight,
      mobileLetterSpacing: KaiBrandMobileType.sectionTitleLetterSpacing,
      desktopSize: KaiBrandDesktopType.sectionTitleSize,
      desktopLineHeight: KaiBrandDesktopType.sectionTitleLineHeight,
      desktopWeight: KaiBrandDesktopType.sectionTitleWeight,
      desktopLetterSpacing: KaiBrandDesktopType.sectionTitleLetterSpacing,
    );
    final title = role(
      base.titleLarge,
      mobileSize: KaiBrandMobileType.titleSize,
      mobileLineHeight: KaiBrandMobileType.titleLineHeight,
      mobileWeight: KaiBrandMobileType.titleWeight,
      mobileLetterSpacing: KaiBrandMobileType.titleLetterSpacing,
      desktopSize: KaiBrandDesktopType.titleSize,
      desktopLineHeight: KaiBrandDesktopType.titleLineHeight,
      desktopWeight: KaiBrandDesktopType.titleWeight,
      desktopLetterSpacing: KaiBrandDesktopType.titleLetterSpacing,
    );
    final body = role(
      base.bodyMedium,
      mobileSize: KaiBrandMobileType.bodySize,
      mobileLineHeight: KaiBrandMobileType.bodyLineHeight,
      mobileWeight: KaiBrandMobileType.bodyWeight,
      mobileLetterSpacing: KaiBrandMobileType.bodyLetterSpacing,
      desktopSize: KaiBrandDesktopType.bodySize,
      desktopLineHeight: KaiBrandDesktopType.bodyLineHeight,
      desktopWeight: KaiBrandDesktopType.bodyWeight,
      desktopLetterSpacing: KaiBrandDesktopType.bodyLetterSpacing,
    );
    final bodySecondary = role(
      base.bodySmall,
      mobileSize: KaiBrandMobileType.bodySecondarySize,
      mobileLineHeight: KaiBrandMobileType.bodySecondaryLineHeight,
      mobileWeight: KaiBrandMobileType.bodySecondaryWeight,
      mobileLetterSpacing: KaiBrandMobileType.bodySecondaryLetterSpacing,
      desktopSize: KaiBrandDesktopType.bodySecondarySize,
      desktopLineHeight: KaiBrandDesktopType.bodySecondaryLineHeight,
      desktopWeight: KaiBrandDesktopType.bodySecondaryWeight,
      desktopLetterSpacing: KaiBrandDesktopType.bodySecondaryLetterSpacing,
      color: secondary,
    );
    final label = role(
      base.labelLarge,
      mobileSize: KaiBrandMobileType.labelSize,
      mobileLineHeight: KaiBrandMobileType.labelLineHeight,
      mobileWeight: KaiBrandMobileType.labelWeight,
      mobileLetterSpacing: KaiBrandMobileType.labelLetterSpacing,
      desktopSize: KaiBrandDesktopType.labelSize,
      desktopLineHeight: KaiBrandDesktopType.labelLineHeight,
      desktopWeight: KaiBrandDesktopType.labelWeight,
      desktopLetterSpacing: KaiBrandDesktopType.labelLetterSpacing,
    );
    final caption = role(
      base.labelSmall,
      mobileSize: KaiBrandMobileType.captionSize,
      mobileLineHeight: KaiBrandMobileType.captionLineHeight,
      mobileWeight: KaiBrandMobileType.captionWeight,
      mobileLetterSpacing: KaiBrandMobileType.captionLetterSpacing,
      desktopSize: KaiBrandDesktopType.captionSize,
      desktopLineHeight: KaiBrandDesktopType.captionLineHeight,
      desktopWeight: KaiBrandDesktopType.captionWeight,
      desktopLetterSpacing: KaiBrandDesktopType.captionLetterSpacing,
      color: secondary,
    );

    return base.copyWith(
      displayLarge: displayLarge,
      displayMedium: displayLarge,
      headlineLarge: pageTitle,
      headlineMedium: pageTitle,
      headlineSmall: sectionTitle,
      titleLarge: title,
      titleMedium: title,
      titleSmall: title,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: bodySecondary,
      labelLarge: label,
      labelMedium: label,
      labelSmall: caption,
    );
  }
}

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

  double get appPageTitleSize => appComponentProfile.pageTitleSize;

  AppComponentProfile get appComponentProfile =>
      resolveAppComponentProfile(defaultTargetPlatform);

  double get appSectionTitleSize => appComponentProfile.sectionTitleSize;

  double get appTitleSize => appComponentProfile.titleSize;

  double get appBodySize => appComponentProfile.bodySize;

  double get appBodySecondarySize => appComponentProfile.bodySecondarySize;

  double get appLabelSize => appComponentProfile.labelSize;

  double get appListTitleSize => appComponentProfile.listTitleSize;

  double get appCaptionSize => appComponentProfile.captionSize;

  double get appCaptionSmallSize => appComponentProfile.captionSmallSize;

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

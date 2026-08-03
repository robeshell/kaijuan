import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'brand_tokens.g.dart';
import 'glass.dart';
import 'tokens.dart';

bool get appUsesDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;



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

/// Width-driven window class for phone / fold / tablet shells.
///
/// Short height (tabletop fold, landscape, split-screen) must **not** demote
/// a medium/wide width to [AppWindowClass.compact] — that is handled by
/// [resolveAppIsShortViewport] for chrome compression only.
AppWindowClass resolveAppWindowClass({
  required double width,
  required bool desktopPlatform,
}) {
  if (desktopPlatform) {
    return width < KaiBrandLayout.desktopBreakpoint
        ? AppWindowClass.medium
        : AppWindowClass.wide;
  }
  if (width <= KaiBrandLayout.compactWidth) {
    return AppWindowClass.compact;
  }
  if (width < KaiBrandLayout.mobileWideBreakpoint) {
    return AppWindowClass.medium;
  }
  return AppWindowClass.wide;
}

/// Side rail when the expanded chrome actually fits.
///
/// Mobile/fold: open-fold / tablet widths (~840+) get a rail instead of waiting
/// until the old 1000px device preset. Desktop: only when the window is wide
/// enough that a 216px rail does not crush content (else bottom bar).
///
/// Mobile shell and side rail stay exclusive — never neither.
const double kAppMobileSideRailMinWidth = 840;

/// Desktop windows narrower than this use bottom navigation temporarily.
const double kAppDesktopSideRailMinWidth = 900;

bool resolveAppUsesSideRail({
  required double width,
  required bool desktopPlatform,
}) {
  if (desktopPlatform) {
    return width >= kAppDesktopSideRailMinWidth;
  }
  return width >= kAppMobileSideRailMinWidth;
}

bool resolveAppUsesMobileShell({
  required double width,
  required bool desktopPlatform,
}) {
  return !resolveAppUsesSideRail(
    width: width,
    desktopPlatform: desktopPlatform,
  );
}

/// Shared metrics for [AppNavigationBar] and bottom insets (keep in sync).
abstract final class AppNavigationChromeMetrics {
  static const double barHeight = 56;
  static const double barHeightShort = 44;
  static const double barMinBottom = 6;
  static const double barMinBottomShort = 4;
  /// Gap between last content / FAB and the top of the nav chrome.
  static const double contentGap = 16;
}

/// Total height occupied by the floating bottom nav (bar + safe-area bottom).
double resolveAppNavigationBarExtent({
  required bool shortViewport,
  required double systemBottomInset,
}) {
  final barHeight = shortViewport
      ? AppNavigationChromeMetrics.barHeightShort
      : AppNavigationChromeMetrics.barHeight;
  final minBottom = shortViewport
      ? AppNavigationChromeMetrics.barMinBottomShort
      : AppNavigationChromeMetrics.barMinBottom;
  final bottomPad = systemBottomInset > minBottom
      ? systemBottomInset
      : minBottom;
  return barHeight + bottomPad;
}

/// Scroll/FAB clearance above bottom chrome (or desktop comfort pad).
double resolveAppContentBottomPadding({
  required bool mobileShell,
  required bool shortViewport,
  required double systemBottomInset,
}) {
  if (!mobileShell) {
    return KaiBrandLayout.desktopBottomPadding;
  }
  return resolveAppNavigationBarExtent(
        shortViewport: shortViewport,
        systemBottomInset: systemBottomInset,
      ) +
      AppNavigationChromeMetrics.contentGap;
}

/// FAB distance from the physical bottom edge.
double resolveAppFabBottomInset({
  required bool mobileShell,
  required bool shortViewport,
  required double systemBottomInset,
  required double viewPaddingBottom,
}) {
  if (!mobileShell) {
    return 24 + viewPaddingBottom;
  }
  return resolveAppNavigationBarExtent(
        shortViewport: shortViewport,
        systemBottomInset: systemBottomInset,
      ) +
      AppNavigationChromeMetrics.contentGap;
}

/// Usable height after system padding — phone landscape, split, tabletop fold.
bool resolveAppIsShortViewport({
  required double height,
  required double paddingVertical,
  double threshold = 480,
}) {
  return height - paddingVertical < threshold;
}

/// Cover grid tile max cross-axis extent; larger on open folds / tablets.
double resolveCoverGridMaxExtent(AppWindowClass windowClass) {
  return switch (windowClass) {
    AppWindowClass.compact => 160,
    AppWindowClass.medium => 176,
    AppWindowClass.wide => 200,
  };
}

/// Extra inset when a vertical fold/hinge bisects the window (logical px).
/// Applied into page gutters so controls stay off the crease.
double resolveHingeGutterBoost({
  required Size size,
  required List<DisplayFeature> displayFeatures,
}) {
  var boost = 0.0;
  for (final feature in displayFeatures) {
    if (feature.type != DisplayFeatureType.hinge &&
        feature.type != DisplayFeatureType.fold) {
      continue;
    }
    final bounds = feature.bounds;
    final verticalCrease = bounds.height >= bounds.width;
    if (!verticalCrease) continue;
    final centerX = bounds.center.dx;
    // Only center-ish creases (dual-pane folds), not edge bezels.
    if (centerX < size.width * 0.28 || centerX > size.width * 0.72) {
      continue;
    }
    boost = boost < bounds.width + 12 ? bounds.width + 12 : boost;
  }
  return boost;
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

  double get inputTextSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.inputTextSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.inputTextSize,
  };

  TextStyle get inputTextStyle => switch (this) {
    AppComponentProfile.mobile => TextStyle(
      fontSize: KaiBrandMobileType.inputTextSize,
      height:
          KaiBrandMobileType.inputTextLineHeight /
          KaiBrandMobileType.inputTextSize,
      fontWeight:
          FontWeight.values[KaiBrandMobileType.inputTextWeight ~/ 100 - 1],
      letterSpacing: KaiBrandMobileType.inputTextLetterSpacing,
    ),
    AppComponentProfile.desktop => TextStyle(
      fontSize: KaiBrandDesktopType.inputTextSize,
      height:
          KaiBrandDesktopType.inputTextLineHeight /
          KaiBrandDesktopType.inputTextSize,
      fontWeight:
          FontWeight.values[KaiBrandDesktopType.inputTextWeight ~/ 100 - 1],
      letterSpacing: KaiBrandDesktopType.inputTextLetterSpacing,
    ),
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

  double get gridTitleSize => switch (this) {
    AppComponentProfile.mobile => KaiBrandMobileType.gridTitleSize,
    AppComponentProfile.desktop => KaiBrandDesktopType.gridTitleSize,
  };

  TextStyle get gridTitleStyle => switch (this) {
    AppComponentProfile.mobile => TextStyle(
      fontSize: KaiBrandMobileType.gridTitleSize,
      height:
          KaiBrandMobileType.gridTitleLineHeight /
          KaiBrandMobileType.gridTitleSize,
      fontWeight:
          FontWeight.values[KaiBrandMobileType.gridTitleWeight ~/ 100 - 1],
      letterSpacing: KaiBrandMobileType.gridTitleLetterSpacing,
    ),
    AppComponentProfile.desktop => TextStyle(
      fontSize: KaiBrandDesktopType.gridTitleSize,
      height:
          KaiBrandDesktopType.gridTitleLineHeight /
          KaiBrandDesktopType.gridTitleSize,
      fontWeight:
          FontWeight.values[KaiBrandDesktopType.gridTitleWeight ~/ 100 - 1],
      letterSpacing: KaiBrandDesktopType.gridTitleLetterSpacing,
    ),
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

  Color get appChromeSurface => appGlass.chromeSurface;

  /// Skin overlay ramp — theme maps it to [ColorScheme.surfaceContainerHigh].
  Color get appOverlay => appColors.surfaceContainerHigh;

  Color get appDivider => appColors.outlineVariant;

  Color appTint(double alpha) => appPrimaryText.withValues(alpha: alpha);

  AppWindowClass get appWindowClass {
    final size = MediaQuery.sizeOf(this);
    return resolveAppWindowClass(
      width: size.width,
      desktopPlatform: appUsesDesktopPlatform,
    );
  }

  bool get appIsCompact => appWindowClass == AppWindowClass.compact;

  /// Landscape aspect (width > height). Used with [appIsShortViewport] for
  /// phone landscape chrome compression — orientation is never locked.
  bool get appIsLandscape {
    final size = MediaQuery.sizeOf(this);
    return size.width > size.height;
  }

  /// Short usable height (phone landscape, split-screen, tabletop fold).
  /// Chrome / bottom bar / tool panels should compress — does not change
  /// [appWindowClass] gutters or density.
  bool get appIsShortViewport {
    final size = MediaQuery.sizeOf(this);
    final padding = MediaQuery.paddingOf(this);
    return resolveAppIsShortViewport(
      height: size.height,
      paddingVertical: padding.vertical,
    );
  }

  /// Bottom navigation shell (phone, most folds, narrow desktop windows).
  /// Exclusive with [appUsesSideRail] — always exactly one chrome path.
  bool get appUsesMobileShell {
    final size = MediaQuery.sizeOf(this);
    return resolveAppUsesMobileShell(
      width: size.width,
      desktopPlatform: appUsesDesktopPlatform,
    );
  }

  /// Persistent side rail when width can host rail + usable content.
  bool get appUsesSideRail {
    final size = MediaQuery.sizeOf(this);
    return resolveAppUsesSideRail(
      width: size.width,
      desktopPlatform: appUsesDesktopPlatform,
    );
  }

  /// Roomier **content** density (not phone-narrow). Orthogonal to nav chrome:
  /// open folds are often [appContentWide] + [appUsesMobileShell].
  bool get appContentWide => !appIsCompact;

  double get appPageGutter {
    final base = switch (appWindowClass) {
      AppWindowClass.compact => KaiBrandLayout.compactGutter,
      AppWindowClass.medium => KaiBrandLayout.mediumGutter,
      AppWindowClass.wide => KaiBrandLayout.wideGutter,
    };
    final hinge = resolveHingeGutterBoost(
      size: MediaQuery.sizeOf(this),
      displayFeatures: MediaQuery.displayFeaturesOf(this),
    );
    // Split hinge boost across both gutters so content clears the crease.
    return base + hinge / 2;
  }

  /// Max tile width for library / collection cover grids (fold-adaptive).
  double get appCoverGridMaxExtent =>
      resolveCoverGridMaxExtent(appWindowClass);

  double get appPageTitleSize => appComponentProfile.pageTitleSize;

  AppComponentProfile get appComponentProfile =>
      resolveAppComponentProfile(defaultTargetPlatform);

  double get appSectionTitleSize => appComponentProfile.sectionTitleSize;

  double get appTitleSize => appComponentProfile.titleSize;

  double get appBodySize => appComponentProfile.bodySize;

  double get appInputTextSize => appComponentProfile.inputTextSize;

  TextStyle get appInputTextStyle => appComponentProfile.inputTextStyle;

  double get appBodySecondarySize => appComponentProfile.bodySecondarySize;

  double get appLabelSize => appComponentProfile.labelSize;

  double get appListTitleSize => appComponentProfile.listTitleSize;

  double get appGridTitleSize => appComponentProfile.gridTitleSize;

  TextStyle get appGridTitleStyle => appComponentProfile.gridTitleStyle;

  double get appCaptionSize => appComponentProfile.captionSize;

  double get appCaptionSmallSize => appComponentProfile.captionSmallSize;

  /// Scroll padding so last rows clear overlaid bottom chrome (`extendBody`).
  /// Derived from real nav bar metrics + system inset (not a fixed 140/88).
  double get appContentBottomPadding {
    return resolveAppContentBottomPadding(
      mobileShell: appUsesMobileShell,
      shortViewport: appIsShortViewport,
      systemBottomInset: MediaQuery.paddingOf(this).bottom,
    );
  }

  /// Floating action (e.g. library import) distance from the bottom edge.
  double get appFabBottomInset {
    final viewPad = MediaQuery.viewPaddingOf(this);
    return resolveAppFabBottomInset(
      mobileShell: appUsesMobileShell,
      shortViewport: appIsShortViewport,
      systemBottomInset: MediaQuery.paddingOf(this).bottom,
      viewPaddingBottom: viewPad.bottom,
    );
  }

  /// Floating action trailing inset (gutter + system edge + hinge boost).
  double get appFabTrailingInset {
    return appPageGutter + MediaQuery.viewPaddingOf(this).right;
  }

  /// Max fraction of viewport height for reader tool-strip expand panels.
  double get appReaderToolPanelMaxHeightFraction =>
      appIsShortViewport ? 0.38 : 0.48;

  double get appSidebarWidth {
    if (!appUsesSideRail) return 0;
    return switch (appWindowClass) {
      AppWindowClass.compact => KaiBrandLayout.mediumSidebarWidth,
      AppWindowClass.medium => KaiBrandLayout.mediumSidebarWidth,
      AppWindowClass.wide => KaiBrandLayout.wideSidebarWidth,
    };
  }

  ButtonStyle get appDestructiveButtonStyle {
    final error = appColors.error;
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return error.withValues(alpha: appDisabledForegroundOpacity);
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

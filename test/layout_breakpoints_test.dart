import 'dart:ui'
    show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/core/theme/brand_tokens.g.dart';

void main() {
  group('resolveAppWindowClass (mobile / fold)', () {
    test('outer phone and closed fold stay compact by width', () {
      expect(
        resolveAppWindowClass(width: 360, desktopPlatform: false),
        AppWindowClass.compact,
      );
      expect(
        resolveAppWindowClass(width: 600, desktopPlatform: false),
        AppWindowClass.compact,
      );
    });

    test('open fold / mid tablet is medium even when height is short', () {
      expect(
        resolveAppWindowClass(width: 720, desktopPlatform: false),
        AppWindowClass.medium,
      );
      expect(
        resolveAppWindowClass(width: 900, desktopPlatform: false),
        AppWindowClass.medium,
      );
    });

    test('large tablet / unfolded wide is wide', () {
      expect(
        resolveAppWindowClass(width: 1000, desktopPlatform: false),
        AppWindowClass.wide,
      );
    });
  });

  group('resolveAppUsesMobileShell / SideRail', () {
    test('never leaves a chrome gap at mid widths', () {
      for (final width in [700.0, 820.0, 839.0, 840.0, 900.0, 999.0]) {
        final shell = resolveAppUsesMobileShell(
          width: width,
          desktopPlatform: false,
        );
        final rail = resolveAppUsesSideRail(
          width: width,
          desktopPlatform: false,
        );
        expect(shell || rail, isTrue, reason: 'width=$width needs chrome');
        expect(shell && rail, isFalse, reason: 'width=$width exclusive chrome');
      }
    });

    test('mobile side rail starts at open-fold min width', () {
      expect(
        resolveAppUsesSideRail(
          width: kAppMobileSideRailMinWidth - 1,
          desktopPlatform: false,
        ),
        isFalse,
      );
      expect(
        resolveAppUsesSideRail(
          width: kAppMobileSideRailMinWidth,
          desktopPlatform: false,
        ),
        isTrue,
      );
      expect(
        resolveAppUsesMobileShell(
          width: kAppMobileSideRailMinWidth,
          desktopPlatform: false,
        ),
        isFalse,
      );
    });

    test('desktop narrow window uses bottom bar, not side rail', () {
      expect(
        resolveAppUsesSideRail(width: 800, desktopPlatform: true),
        isFalse,
      );
      expect(
        resolveAppUsesMobileShell(width: 800, desktopPlatform: true),
        isTrue,
      );
      expect(
        resolveAppUsesSideRail(
          width: kAppDesktopSideRailMinWidth,
          desktopPlatform: true,
        ),
        isTrue,
      );
    });
  });

  group('resolveAppIsShortViewport', () {
    test('detects tabletop / landscape usable height', () {
      expect(
        resolveAppIsShortViewport(height: 500, paddingVertical: 40),
        isTrue,
      );
      expect(
        resolveAppIsShortViewport(height: 900, paddingVertical: 40),
        isFalse,
      );
    });
  });

  group('resolveCoverGridMaxExtent', () {
    test('grows with window class for open folds', () {
      expect(resolveCoverGridMaxExtent(AppWindowClass.compact), 160);
      expect(resolveCoverGridMaxExtent(AppWindowClass.medium), 176);
      expect(resolveCoverGridMaxExtent(AppWindowClass.wide), 200);
    });
  });

  group('resolveAppNavigationBarExtent / bottom padding', () {
    test('uses bar metrics plus system inset', () {
      expect(
        resolveAppNavigationBarExtent(
          shortViewport: false,
          systemBottomInset: 34,
        ),
        AppNavigationChromeMetrics.barHeight + 34,
      );
      expect(
        resolveAppNavigationBarExtent(
          shortViewport: true,
          systemBottomInset: 0,
        ),
        AppNavigationChromeMetrics.barHeightShort +
            AppNavigationChromeMetrics.barMinBottomShort,
      );
    });

    test('content bottom padding adds content gap on mobile shell', () {
      final pad = resolveAppContentBottomPadding(
        mobileShell: true,
        shortViewport: false,
        systemBottomInset: 34,
      );
      expect(
        pad,
        AppNavigationChromeMetrics.barHeight +
            34 +
            AppNavigationChromeMetrics.contentGap,
      );
    });

    test('desktop comfort pad when no mobile shell', () {
      expect(
        resolveAppContentBottomPadding(
          mobileShell: false,
          shortViewport: false,
          systemBottomInset: 0,
        ),
        KaiBrandLayout.desktopBottomPadding,
      );
    });

    test('FAB bottom matches content gap above bar on mobile shell', () {
      final fab = resolveAppFabBottomInset(
        mobileShell: true,
        shortViewport: false,
        systemBottomInset: 20,
        viewPaddingBottom: 20,
      );
      expect(
        fab,
        AppNavigationChromeMetrics.barHeight +
            20 +
            AppNavigationChromeMetrics.contentGap,
      );
    });
  });

  group('resolveAppComponentProfile (type density)', () {
    test('desktop OS stays desktop type at every width', () {
      for (final window in AppWindowClass.values) {
        expect(
          resolveAppComponentProfile(
            platform: TargetPlatform.macOS,
            windowClass: window,
          ),
          AppComponentProfile.desktop,
        );
      }
    });

    test('phone OS uses mobile type only when compact', () {
      expect(
        resolveAppComponentProfile(
          platform: TargetPlatform.iOS,
          windowClass: AppWindowClass.compact,
        ),
        AppComponentProfile.mobile,
      );
      expect(
        resolveAppComponentProfile(
          platform: TargetPlatform.android,
          windowClass: AppWindowClass.compact,
        ),
        AppComponentProfile.mobile,
      );
    });

    test('open fold / tablet (medium+wide) upgrades phone OS to desktop type',
        () {
      expect(
        resolveAppComponentProfile(
          platform: TargetPlatform.android,
          windowClass: AppWindowClass.medium,
        ),
        AppComponentProfile.desktop,
      );
      expect(
        resolveAppComponentProfile(
          platform: TargetPlatform.iOS,
          windowClass: AppWindowClass.wide,
        ),
        AppComponentProfile.desktop,
      );
      // Section titles shrink from mobile 22 → desktop 18.
      expect(
        resolveAppComponentProfile(
          platform: TargetPlatform.android,
          windowClass: AppWindowClass.wide,
        ).sectionTitleSize,
        KaiBrandDesktopType.sectionTitleSize,
      );
      expect(
        resolveAppComponentProfile(
          platform: TargetPlatform.android,
          windowClass: AppWindowClass.compact,
        ).sectionTitleSize,
        KaiBrandMobileType.sectionTitleSize,
      );
    });
  });

  group('resolveHingeGutterBoost', () {
    test('boosts when a vertical hinge sits near center', () {
      final boost = resolveHingeGutterBoost(
        size: const Size(800, 600),
        displayFeatures: [
          DisplayFeature(
            bounds: Rect.fromLTWH(395, 0, 10, 600),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.unknown,
          ),
        ],
      );
      expect(boost, greaterThanOrEqualTo(22));
    });

    test('ignores edge features', () {
      final boost = resolveHingeGutterBoost(
        size: const Size(800, 600),
        displayFeatures: [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 0, 8, 600),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.unknown,
          ),
        ],
      );
      expect(boost, 0);
    });
  });
}

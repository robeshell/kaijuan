import 'package:flutter/foundation.dart';

/// Product-level reader capabilities that intentionally differ by platform.
abstract final class BookReaderCapabilities {
  static bool supportsScrollMode(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => false,
  };

  static bool get supportsScrollModeOnCurrentPlatform =>
      supportsScrollMode(defaultTargetPlatform);

  /// Stable vertical page inset beneath the overlay reader chrome.
  static double pageVerticalInset(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android || TargetPlatform.iOS => 16.0,
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.fuchsia => 24.0,
      };

  static double get pageVerticalInsetOnCurrentPlatform =>
      pageVerticalInset(defaultTargetPlatform);
}

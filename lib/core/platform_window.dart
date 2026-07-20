import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'platform_window_stub.dart'
    if (dart.library.io) 'platform_window_io.dart'
    as implementation;

/// Minimizes the application window.
Future<void> minimizeWindow() => implementation.minimizeWindow();

/// Maximizes the application window.
Future<void> maximizeWindow() => implementation.maximizeWindow();

/// Restores the window from maximized or minimized state.
Future<void> restoreWindow() => implementation.restoreWindow();

/// Closes the application window.
Future<void> closeWindow() => implementation.closeWindow();

/// Returns whether the window is currently maximized.
Future<bool> isWindowMaximized() => implementation.isWindowMaximized();

/// Starts a window-drag operation from the current pointer position.
Future<void> startWindowDrag() => implementation.startWindowDrag();

/// Whether Flutter paints custom min/max/close (Windows).
bool get supportsCustomWindowChrome =>
    implementation.supportsCustomWindowChrome;

/// OS maximize / restore changes (Windows).
Stream<bool> get windowMaximizedChanges =>
    implementation.windowMaximizedChanges;

/// Height reserved for the desktop title bar (macOS traffic-light band /
/// Windows custom caption).
double get platformTitleBarHeight => implementation.platformTitleBarHeight;

/// Merges [platformTitleBarHeight] into [MediaQuery] padding/viewPadding so
/// every [SafeArea] / padded scaffold clears the custom window chrome.
///
/// Does not layout-offset the tree by itself — only updates metrics. Overlay
/// title bars (traffic lights / drag strip) stay at physical top.
MediaQueryData mediaQueryWithDesktopTitleBar(MediaQueryData data) {
  final inset = platformTitleBarHeight;
  if (inset <= 0) return data;
  final topPad = math.max(data.padding.top, inset);
  final topView = math.max(data.viewPadding.top, inset);
  return data.copyWith(
    padding: data.padding.copyWith(top: topPad),
    viewPadding: data.viewPadding.copyWith(top: topView),
  );
}

/// Applies [mediaQueryWithDesktopTitleBar] for the subtree.
class DesktopTitleBarMediaQuery extends StatelessWidget {
  const DesktopTitleBarMediaQuery({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = mediaQueryWithDesktopTitleBar(MediaQuery.of(context));
    return MediaQuery(data: data, child: child);
  }
}

import 'dart:async';
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

/// Thin title-band drag strip for full-screen readers.
///
/// - **Windows**: custom caption is hidden; this is the only way to move the
///   window while chrome is hidden.
/// - **macOS**: `isMovableByWindowBackground` fails over a full-screen
///   Platform View (book WebView); this strip calls native `performDrag`.
///
/// Place in a [Stack] **above** the engine/WebView. A nearly-opaque hit fill
/// is required so the layer wins over the platform view.
class ReaderWindowDragHandle extends StatelessWidget {
  const ReaderWindowDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final height = platformTitleBarHeight;
    if (height <= 0) return const SizedBox.shrink();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        // Fire-and-forget; user is already pressing.
        unawaited(startWindowDrag());
      },
      // Platform views ignore fully transparent Flutter siblings for hit tests.
      child: ColoredBox(
        color: const Color(0x01000000),
        child: SizedBox(height: height, width: double.infinity),
      ),
    );
  }
}

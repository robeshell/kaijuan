import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform_window.dart';
import '../../core/theme.dart';

/// In-content desktop title bar (MusicPlayerNext / Reverie pattern).
///
/// Overlaid on the shell — not a layout strip that pushes content down.
///
/// - **macOS**: transparent band under native traffic lights; drag via
///   `isMovableByWindowBackground` in native code.
/// - **Windows**: drag surface + custom min / max / close (system caption
///   hidden by the runner).
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({
    super.key,
    required this.title,
  });

  final String title;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {
  bool _maximized = false;
  StreamSubscription<bool>? _maximizedSubscription;

  bool get _usesCustomWindowChrome =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_usesCustomWindowChrome) {
      unawaited(_refreshMaximized());
      _maximizedSubscription = windowMaximizedChanges.listen((maximized) {
        if (mounted) setState(() => _maximized = maximized);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_maximizedSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    final maximized = await isWindowMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    final next = !_maximized;
    if (mounted) setState(() => _maximized = next);
    if (next) {
      await maximizeWindow();
    } else {
      await restoreWindow();
    }
    await _refreshMaximized();
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final height = platformTitleBarHeight;
    if (height <= 0) return const SizedBox.shrink();

    final customChrome = _usesCustomWindowChrome;

    // Transparent so the side rail / canvas continue under the chrome —
    // same as Reverie. Content itself reserves top inset.
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            if (customChrome)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () => unawaited(_toggleMaximize()),
                  onPanStart: (_) => unawaited(startWindowDrag()),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: semantics.textSecondary,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (_isMacOS)
              // Push any trailing actions clear of traffic lights.
              const Spacer()
            else
              const Spacer(),
            if (customChrome) ...[
              _WindowControlButton(
                icon: Icons.horizontal_rule_outlined,
                tooltip: '最小化',
                onPressed: () => unawaited(minimizeWindow()),
              ),
              const SizedBox(width: 2),
              _WindowControlButton(
                icon: _maximized
                    ? Icons.filter_none_outlined
                    : Icons.crop_square_outlined,
                tooltip: _maximized ? '向下还原' : '最大化',
                onPressed: () => unawaited(_toggleMaximize()),
              ),
              const SizedBox(width: 2),
              _WindowControlButton(
                icon: Icons.close_outlined,
                tooltip: '关闭',
                closeButton: true,
                onPressed: () => unawaited(closeWindow()),
              ),
              const SizedBox(width: 8),
            ] else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.closeButton = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool closeButton;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          hoverColor: closeButton
              ? const Color(0xFFE81123).withValues(alpha: 0.9)
              : semantics.hairline,
          child: SizedBox(
            width: 40,
            height: 32,
            child: Center(
              child: Icon(
                icon,
                size: 16,
                color: semantics.textSecondary.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

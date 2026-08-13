import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/reader/book_cover_hero.dart';

/// Book-reader route: the tapped cover travels along a cubic arc while
/// growing into the waiting-cover frame, then the same path reverses on pop.
class CoverOpenPageRoute<T> extends PageRoute<T> {
  CoverOpenPageRoute({
    required this.builder,
    required this.coverPath,
    required this.title,
    required this.backdropColor,
    this.sourceRect,
    this.itemId,
    super.settings,
  });

  final WidgetBuilder builder;
  final String? coverPath;
  final String title;
  final Color backdropColor;
  final Rect? sourceRect;
  final String? itemId;

  static const Duration flightDuration = Duration(milliseconds: 460);
  static const Duration flightReverseDuration = Duration(milliseconds: 420);
  static const Duration fadeDuration = Duration(milliseconds: 220);

  bool get _flies => CoverFlightGeometry.isUsable(sourceRect);

  /// True only after the open flight finishes. Keeping this false during the
  /// transition leaves the library painted; flipping it true after settle
  /// offstages the grid so reading is cheap. [preparePreviousRoute] flips it
  /// back before reverse so close does not remount the grid on frame 0.
  bool _settled = false;

  @override
  bool get opaque => _settled;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => _flies ? flightDuration : Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      _flies ? flightReverseDuration : fadeDuration;

  @override
  TickerFuture didPush() {
    final pushed = super.didPush();
    animation?.addStatusListener(_onStatus);
    if (animation?.isCompleted ?? false) {
      _settled = true;
    }
    // Hide the source cover on the next frame so the first flight frame can
    // composite the flyer on top of the real card (no grid rebuild on frame 0).
    if (_flies && itemId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final id = itemId;
        if (id != null) CoverFlightSession.begin(id);
      });
    }
    return pushed;
  }

  @override
  bool didPop(T? result) {
    _markUnsettled();
    if (_flies && itemId != null) CoverFlightSession.begin(itemId!);
    return super.didPop(result);
  }

  @override
  void dispose() {
    animation?.removeStatusListener(_onStatus);
    CoverFlightSession.end(itemId);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (!_settled) {
        _settled = true;
        changedInternalState();
      }
    } else if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _markUnsettled();
    }
  }

  void _markUnsettled() {
    if (!_settled) return;
    _settled = false;
    changedInternalState();
  }

  /// Rebuild the library under the reader *before* reverse starts.
  ///
  /// Callers should wait two frames after this so the grid can paint
  /// before [Navigator.pop] starts the reverse flight.
  void preparePreviousRoute() {
    if (!_flies) return;
    _markUnsettled();
    final id = itemId;
    if (id != null) CoverFlightSession.begin(id);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || !_flies) {
      return FadeTransition(opacity: animation, child: child);
    }
    return CoverFlightTransition(
      animation: animation,
      sourceRect: sourceRect!,
      coverPath: coverPath,
      title: title,
      backdropColor: backdropColor,
      child: child,
    );
  }
}

class CoverFlightTransition extends StatelessWidget {
  const CoverFlightTransition({
    super.key,
    required this.animation,
    required this.sourceRect,
    required this.coverPath,
    required this.title,
    required this.backdropColor,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final String? coverPath;
  final String title;
  final Color backdropColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final source = CoverFlightGeometry.localRectOf(context, sourceRect);
    final dest = CoverFlightGeometry.destinationRect(
      viewport: MediaQuery.sizeOf(context),
      safePadding: MediaQuery.paddingOf(context),
      aspectRatio: source.size.aspectRatio,
      shortViewport: context.appIsShortViewport,
    );
    final path = CoverFlightPath(source: source, dest: dest);
    // Reuse the library's already-decoded cover. A dest-sized cacheWidth
    // forces a new decode on the first flight frame and hitches the start.
    final flyer = CoverFlightLeaf(coverPath: coverPath, title: title);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final raw = animation.value.clamp(0.0, 1.0);
            final reversing =
                animation.status == AnimationStatus.reverse ||
                animation.status == AnimationStatus.dismissed;
            final opacity = reversing
                ? const Interval(0, 0.78, curve: Curves.linear).transform(raw)
                : 1.0;
            return IgnorePointer(
              child: ColoredBox(
                color: backdropColor.withValues(alpha: opacity),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, reader) {
            final raw = animation.value.clamp(0.0, 1.0);
            final reversing =
                animation.status == AnimationStatus.reverse ||
                animation.status == AnimationStatus.dismissed;
            // Keep the reader in the tree (Foliate can load) but do not
            // composite the WebView during the flight.
            final hideReader = reversing ? raw < 0.99 : raw < 0.96;
            return Offstage(offstage: hideReader, child: reader);
          },
        ),
        AnimatedBuilder(
          animation: animation,
          child: flyer,
          builder: (context, leaf) {
            final raw = animation.value.clamp(0.0, 1.0);
            final reversing =
                animation.status == AnimationStatus.reverse ||
                animation.status == AnimationStatus.dismissed;
            if (!reversing && raw >= 0.995) return const SizedBox.shrink();
            final t = CoverFlightGeometry.flightTime.transform(raw);
            final rect = path.rectAt(t);
            return Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(child: leaf),
            );
          },
        ),
      ],
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/brand_tokens.g.dart';
import '../../../core/theme/tokens.dart';

/// Reads the global bounds of a mounted cover widget.
Rect? captureGlobalRect(BuildContext? context) {
  final box = context?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Marks the artwork that should fly into the book reader.
///
/// [openReadingItem] measures the first handle under the tap [BuildContext].
/// While that item is in flight, the source artwork is hidden so the flying
/// cover is the only copy.
class CoverFlightHandle extends StatelessWidget {
  const CoverFlightHandle({super.key, required this.child, this.itemId});

  final Widget child;
  final String? itemId;

  static Rect? rectOf(BuildContext context) {
    Element? found;
    context.visitAncestorElements((element) {
      if (element.widget is CoverFlightHandle) {
        found = element;
        return false;
      }
      return true;
    });
    if (found != null) return captureGlobalRect(found);

    void visit(Element element) {
      if (found != null) return;
      if (element.widget is CoverFlightHandle) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return captureGlobalRect(found);
  }

  /// Prefers the handle whose [itemId] matches, so a long-press menu can
  /// still launch the correct cover after the sheet closes.
  static Rect? resolve(BuildContext context, String itemId) {
    Element? matched;
    void visit(Element element) {
      if (matched != null) return;
      final widget = element.widget;
      if (widget is CoverFlightHandle && widget.itemId == itemId) {
        matched = element;
        return;
      }
      element.visitChildren(visit);
    }

    visit(context as Element);
    if (matched != null) return captureGlobalRect(matched);
    return rectOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final id = itemId;
    if (id == null) return child;
    return ValueListenableBuilder<String?>(
      valueListenable: CoverFlightSession.inFlightItemId,
      builder: (context, flyingId, painted) {
        return Opacity(opacity: flyingId == id ? 0 : 1, child: painted);
      },
      child: child,
    );
  }
}

/// Which library item currently owns the flying cover.
class CoverFlightSession {
  CoverFlightSession._();

  static final ValueNotifier<String?> inFlightItemId = ValueNotifier<String?>(
    null,
  );

  static void begin(String itemId) {
    if (inFlightItemId.value == itemId) return;
    inFlightItemId.value = itemId;
  }

  static void end([String? itemId]) {
    if (itemId != null && inFlightItemId.value != itemId) return;
    if (inFlightItemId.value == null) return;
    inFlightItemId.value = null;
  }
}

/// Shared cover-flight math. Destination padding matches [ReaderWaitingCover].
abstract final class CoverFlightGeometry {
  static const double destHPad = 40;
  static const double destVPad = 48;
  static const double destHPadShort = 28;
  static const double destVPadShort = 16;

  /// Lift of the cubic control points, as a fraction of travel distance.
  static const double arcLift = 0.08;

  /// Time curve is linear so speed along the arc stays even.
  /// Path shape is a separate cubic; this only maps clock → arc-length `t`.
  static const Curve flightTime = Curves.linear;

  static bool isUsable(Rect? rect) {
    if (rect == null || rect.hasNaN) return false;
    return rect.width >= 8 && rect.height >= 8;
  }

  /// Converts a global cover rect into [context]'s local coordinates.
  static Rect localRectOf(BuildContext context, Rect globalRect) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return globalRect;
    return Rect.fromPoints(
      box.globalToLocal(globalRect.topLeft),
      box.globalToLocal(globalRect.bottomRight),
    );
  }

  static EdgeInsets destinationPadding({
    required EdgeInsets safePadding,
    required bool shortViewport,
  }) {
    final h = shortViewport ? destHPadShort : destHPad;
    final v = shortViewport ? destVPadShort : destVPad;
    return EdgeInsets.fromLTRB(
      safePadding.left + h,
      safePadding.top + v,
      safePadding.right + h,
      safePadding.bottom + v,
    );
  }

  static Rect destinationRect({
    required Size viewport,
    required EdgeInsets safePadding,
    required double aspectRatio,
    required bool shortViewport,
  }) {
    final padding = destinationPadding(
      safePadding: safePadding,
      shortViewport: shortViewport,
    );
    final maxW = (viewport.width - padding.horizontal).clamp(
      1.0,
      viewport.width,
    );
    final maxH = (viewport.height - padding.vertical).clamp(
      1.0,
      viewport.height,
    );
    final aspect = (aspectRatio.isFinite && aspectRatio > 0)
        ? aspectRatio
        : 0.7;
    var width = maxW;
    var height = width / aspect;
    if (height > maxH) {
      height = maxH;
      width = height * aspect;
    }
    final left = padding.left + (maxW - width) / 2;
    final top = padding.top + (maxH - height) / 2;
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Interpolated cover frame along the cubic path, parameterized by arc length.
  static Rect flightRect(Rect source, Rect dest, double t) {
    return CoverFlightPath(source: source, dest: dest).rectAt(t);
  }

  static Offset cubicBezier(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
  ) {
    final u = 1 - t;
    final uu = u * u;
    final tt = t * t;
    return p0 * (uu * u) +
        p1 * (3 * uu * t) +
        p2 * (3 * u * tt) +
        p3 * (tt * t);
  }
}

/// Precomputed cubic path so each frame is a LUT lookup, not a layout.
///
/// The curve is a shallow upward cubic. [rectAt] uses arc-length `t` so the
/// cover travels at even speed instead of lingering at the ends of a raw
/// Bezier parameter.
class CoverFlightPath {
  CoverFlightPath({
    required this.source,
    required this.dest,
    this.liftFraction = CoverFlightGeometry.arcLift,
    int samples = 32,
  }) : assert(samples >= 8) {
    _p0 = source.center;
    _p3 = dest.center;
    final lift = (_p3 - _p0).distance * liftFraction;
    _p1 = Offset.lerp(_p0, _p3, 0.28)! + Offset(0, -lift);
    _p2 = Offset.lerp(_p0, _p3, 0.72)! + Offset(0, -lift);

    _points = List<Offset>.filled(samples, Offset.zero);
    _cum = List<double>.filled(samples, 0);
    _points[0] = _p0;
    var traveled = 0.0;
    var prev = _p0;
    for (var i = 1; i < samples; i++) {
      final pt = CoverFlightGeometry.cubicBezier(
        _p0,
        _p1,
        _p2,
        _p3,
        i / (samples - 1),
      );
      _points[i] = pt;
      traveled += (pt - prev).distance;
      _cum[i] = traveled;
      prev = pt;
    }
    _length = traveled;
  }

  final Rect source;
  final Rect dest;
  final double liftFraction;

  late final Offset _p0;
  late final Offset _p1;
  late final Offset _p2;
  late final Offset _p3;
  late final List<Offset> _points;
  late final List<double> _cum;
  late final double _length;

  Offset centerAt(double t) {
    final tt = t.clamp(0.0, 1.0);
    if (_length <= 0) return Offset.lerp(_p0, _p3, tt)!;
    final target = tt * _length;
    if (target <= 0) return _points.first;
    if (target >= _length) return _points.last;
    var lo = 0;
    var hi = _cum.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _cum[hi] - _cum[lo];
    final local = span <= 0 ? 0.0 : (target - _cum[lo]) / span;
    return Offset.lerp(_points[lo], _points[hi], local)!;
  }

  Size sizeAt(double t) =>
      Size.lerp(source.size, dest.size, t.clamp(0.0, 1.0))!;

  Rect rectAt(double t) {
    final tt = t.clamp(0.0, 1.0);
    final size = sizeAt(tt);
    final center = centerAt(tt);
    return Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
  }
}

/// Cover painted in an explicit rect (flight overlay or waiting layer).
class CoverFlightLeaf extends StatelessWidget {
  const CoverFlightLeaf({
    super.key,
    required this.coverPath,
    required this.title,
    this.cacheWidth,
  });

  final String? coverPath;
  final String title;

  /// Decode once at destination size so the flight only scales a bitmap.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final radius = AppProductRadii.cover.toDouble();
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: _CoverFlightArt(
            coverPath: coverPath,
            title: title,
            cacheWidth: cacheWidth,
          ),
        ),
      ),
    );
  }
}

class _CoverFlightArt extends StatelessWidget {
  const _CoverFlightArt({
    required this.coverPath,
    required this.title,
    this.cacheWidth,
  });

  final String? coverPath;
  final String title;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _TitleFallback(title: title),
      );
    }
    return _TitleFallback(title: title);
  }
}

class _TitleFallback extends StatelessWidget {
  const _TitleFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg.withValues(alpha: 0.72),
              fontSize: KaiProductTokens.typographyReaderWaitingCover,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

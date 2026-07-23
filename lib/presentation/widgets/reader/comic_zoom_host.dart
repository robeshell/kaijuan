import 'package:flutter/material.dart';

/// Pinch zoom around [child].
///
/// Single taps fire immediately via [onTapAt] (no double-tap gesture — that
/// would delay chrome toggle ~300ms). Scale resets when [resetToken] changes.
class ComicZoomHost extends StatefulWidget {
  const ComicZoomHost({
    super.key,
    required this.child,
    required this.resetToken,
    this.onTapAt,
    this.enabled = true,
  });

  final Widget child;

  /// Change to reset transform (typically [pageIndex] or mode).
  final Object resetToken;

  /// Local tap position and host width; only fired when scale ≈ 1.
  final void Function(Offset localPosition, double width)? onTapAt;

  /// When false, only forwards taps (no zoom) — e.g. vertical mode.
  final bool enabled;

  @override
  State<ComicZoomHost> createState() => _ComicZoomHostState();
}

class _ComicZoomHostState extends State<ComicZoomHost> {
  final _transform = TransformationController();
  double _scale = 1;

  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  bool get _scaled => _scale > 1.02;

  @override
  void didUpdateWidget(covariant ComicZoomHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _resetTransform();
    }
    if (oldWidget.enabled && !widget.enabled) {
      _resetTransform();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _resetTransform() {
    _transform.value = Matrix4.identity();
    if (_scale != 1) {
      setState(() => _scale = 1);
    }
  }

  void _onInteractionEnd(ScaleEndDetails _) {
    final next = _transform.value.getMaxScaleOnAxis();
    if ((next - _scale).abs() > 0.001) {
      setState(() => _scale = next);
    }
  }

  void _handleTapUp(TapUpDetails details, double width) {
    if (_scaled) {
      _resetTransform();
      return;
    }
    widget.onTapAt?.call(details.localPosition, width);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final content = widget.enabled
            ? InteractiveViewer(
                transformationController: _transform,
                minScale: _minScale,
                maxScale: _maxScale,
                panEnabled: _scaled,
                scaleEnabled: true,
                clipBehavior: Clip.hardEdge,
                onInteractionEnd: _onInteractionEnd,
                child: sizedChild(constraints),
              )
            : sizedChild(constraints);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => _handleTapUp(d, width),
          child: content,
        );
      },
    );
  }

  /// [InteractiveViewer] requires a bounded child with finite size.
  Widget sizedChild(BoxConstraints constraints) {
    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: widget.child,
    );
  }
}

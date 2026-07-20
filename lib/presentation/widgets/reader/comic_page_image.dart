import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../controllers/comic_reader_controller.dart';

/// Renders one comic page from the controller's page cache.
class ComicPageImage extends StatefulWidget {
  const ComicPageImage({
    super.key,
    required this.controller,
    required this.pageIndex,
    this.fit = BoxFit.contain,
  });

  final ComicReaderController controller;
  final int pageIndex;
  final BoxFit fit;

  @override
  State<ComicPageImage> createState() => _ComicPageImageState();
}

class _ComicPageImageState extends State<ComicPageImage> {
  Future<ui.Image?>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.cache?.get(widget.pageIndex);
  }

  @override
  void didUpdateWidget(covariant ComicPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.controller != widget.controller) {
      _future = widget.controller.cache?.get(widget.pageIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return FutureBuilder<ui.Image?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final image = snapshot.data;
        if (image == null) {
          return const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white54),
          );
        }
        return RawImage(
          image: image,
          fit: widget.fit,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}

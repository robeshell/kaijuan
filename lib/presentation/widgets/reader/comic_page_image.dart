import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../controllers/comic_reader_controller.dart';

/// Renders one comic page from the controller's page cache.
///
/// Holds a [ui.Image.clone] so LRU eviction of the cache entry cannot dispose
/// the pixels still shown by this widget.
class ComicPageImage extends StatefulWidget {
  const ComicPageImage({
    super.key,
    required this.controller,
    required this.pageIndex,
    this.fit = BoxFit.contain,
    this.onImageSize,
  });

  final ComicReaderController controller;
  final int pageIndex;
  final BoxFit fit;

  /// Called when the decoded image size is known (for vertical aspect layout).
  final ValueChanged<Size>? onImageSize;

  @override
  State<ComicPageImage> createState() => _ComicPageImageState();
}

class _ComicPageImageState extends State<ComicPageImage> {
  ui.Image? _image;
  bool _loading = true;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ComicPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.controller != widget.controller) {
      _load();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    setState(() => _loading = true);

    final retained = await _retainClone(widget.pageIndex);
    if (!mounted || gen != _loadGen) {
      retained?.dispose();
      return;
    }

    _image?.dispose();
    _image = retained;
    setState(() => _loading = false);

    final image = _image;
    final onSize = widget.onImageSize;
    if (image != null && onSize != null) {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || gen != _loadGen) return;
        onSize(size);
      });
    }
  }

  /// Clone a cache image so this State owns a handle independent of LRU dispose.
  Future<ui.Image?> _retainClone(int index) async {
    final cache = widget.controller.cache;
    if (cache == null) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      final src = await cache.get(index);
      if (src == null) return null;
      try {
        return src.clone();
      } catch (_) {
        // Cache may have disposed between get() and clone(); retry decode.
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _image == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final image = _image;
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
  }
}

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'comic_session.dart';

/// LRU cache of decoded [ui.Image] pages for the active comic session.
class ComicPageCache {
  ComicPageCache({
    required this.session,
    this.capacity = 12,
  });

  final ComicSession session;
  final int capacity;

  // Insertion-ordered map so we can evict the least-recently-used key.
  final _images = <int, ui.Image>{};
  final _inflight = <int, Future<ui.Image?>>{};

  Future<ui.Image?> get(int index) {
    if (index < 0 || index >= session.pageCount) {
      return SynchronousFuture(null);
    }
    final hit = _images.remove(index);
    if (hit != null) {
      _images[index] = hit; // move to MRU
      return SynchronousFuture(hit);
    }
    return _inflight.putIfAbsent(index, () => _decode(index));
  }

  /// Warm neighbors of [center] without blocking.
  void preloadAround(int center, {int radius = 2}) {
    for (var i = center - radius; i <= center + radius; i++) {
      if (i == center) continue;
      if (i < 0 || i >= session.pageCount) continue;
      if (_images.containsKey(i) || _inflight.containsKey(i)) continue;
      // Fire and forget; errors swallowed inside _decode.
      get(i);
    }
  }

  Future<ui.Image?> _decode(int index) async {
    try {
      final bytes = session.readPage(index);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      _insert(index, image);
      return image;
    } catch (e, st) {
      debugPrint('ComicPageCache decode failed page=$index: $e\n$st');
      return null;
    } finally {
      _inflight.remove(index);
    }
  }

  void _insert(int index, ui.Image image) {
    _images[index] = image;
    while (_images.length > capacity) {
      final oldest = _images.keys.first;
      final evicted = _images.remove(oldest);
      evicted?.dispose();
    }
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _inflight.clear();
  }
}

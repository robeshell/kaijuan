import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';

import '../../../brand/brand_config.dart';

typedef BookAiMindMapImageSaver =
    Future<String> Function(Uint8List bytes, String title);

/// Captures the complete native mind-map canvas and saves it as PNG.
abstract final class BookAiMindMapExport {
  static const double _preferredPixelRatio = 2.5;
  static const double _maxImageDimension = 7000;
  static const double _maxImagePixels = 24 * 1000 * 1000;

  static Future<Uint8List?> capturePng(GlobalKey boundaryKey) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || boundary.size.isEmpty) return null;
    if (boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final pixelRatio = pixelRatioForSize(boundary.size);
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Keeps large maps readable without asking the rasterizer for an unsafe
  /// texture or allocating an unbounded PNG buffer.
  @visibleForTesting
  static double pixelRatioForSize(Size size) {
    if (size.isEmpty) return 1;
    final longestSideLimit =
        _maxImageDimension / math.max(size.width, size.height);
    final pixelBudgetLimit = math.sqrt(
      _maxImagePixels / (size.width * size.height),
    );
    return math.max(
      0.05,
      math.min(
        _preferredPixelRatio,
        math.min(longestSideLimit, pixelBudgetLimit),
      ),
    );
  }

  /// Mobile saves to Photos; desktop lets the reader choose the destination.
  static Future<String> savePng(
    Uint8List bytes, {
    required String title,
  }) async {
    final safeTitle = _safeFileComponent(title);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final baseName = '${BrandConfig.app.displayName}思维导图-$safeTitle-$stamp';
    if (_isMobile) {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) throw StateError('未获得相册权限');
      }
      await Gal.putImageBytes(bytes, name: baseName);
      return '已保存到相册';
    }

    final location = await getSaveLocation(
      suggestedName: '$baseName.png',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (location == null) return '已取消';
    await File(location.path).writeAsBytes(bytes, flush: true);
    return '已保存';
  }

  static String _safeFileComponent(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return '未命名';
    return normalized.length <= 48 ? normalized : normalized.substring(0, 48);
  }

  static bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Capture and export helpers for [BookExcerptCard] via [RepaintBoundary].
abstract final class BookExcerptExport {
  static const _clipboardChannel = MethodChannel('com.kaika.reader/clipboard');

  static Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3,
  }) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static Future<File> writeTempPng(Uint8List bytes, {String? name}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      p.join(dir.path, name ?? 'kaika-excerpt-$stamp.png'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Mobile → Photos; desktop → save panel (sandbox-safe).
  static Future<String> saveImage(Uint8List bytes) async {
    if (_isMobile) {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw StateError('未获得相册权限');
        }
      }
      await Gal.putImageBytes(bytes, name: 'Kaika摘录');
      return '已保存到相册';
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final location = await getSaveLocation(
      suggestedName: 'Kaika摘录-$stamp.png',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (location == null) return '已取消';
    await File(location.path).writeAsBytes(bytes, flush: true);
    return '已保存';
  }

  static Future<void> shareImage(
    Uint8List bytes, {
    Rect? sharePositionOrigin,
  }) async {
    final file = await writeTempPng(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// PNG → system pasteboard via app MethodChannel (no pasteboard plugin / KGP).
  static Future<bool> copyImage(Uint8List bytes) async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows) return false;
    try {
      final ok = await _clipboardChannel.invokeMethod<bool>(
        'copyImagePng',
        bytes,
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }
}

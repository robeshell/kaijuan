import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'book_font_models.dart';
import 'book_loopback_server.dart';

/// Owns `{support}/fonts/*` and the installed-font manifest.
class BookFontStore extends ChangeNotifier {
  BookFontStore._(this._fontsDir, this._manifestFile, this._fonts);

  final Directory _fontsDir;
  final File _manifestFile;
  List<BookUserFont> _fonts;
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloading = {};

  List<BookUserFont> get fonts => List.unmodifiable(_fonts);
  bool isDownloading(String catalogId) => _downloading.contains(catalogId);
  double? downloadProgress(String catalogId) => _downloadProgress[catalogId];

  BookUserFont? byId(String id) {
    for (final font in _fonts) {
      if (font.id == id) return font;
    }
    return null;
  }

  BookUserFont? byCatalogId(String catalogId) {
    for (final font in _fonts) {
      if (font.catalogId == catalogId) return font;
    }
    return null;
  }

  File fileFor(BookUserFont font) =>
      File(p.join(_fontsDir.path, font.fileName));

  /// Loopback URL for Foliate `@font-face` (same origin as the reader).
  String? loopbackUrlFor(BookUserFont font) {
    final server = BookLoopbackServer.sharedOrNull;
    if (server == null) return null;
    return server.fontUriFor(font.id, font.fileName).toString();
  }

  static Future<BookFontStore> load(Directory supportDirectory) async {
    final fontsDir = Directory(p.join(supportDirectory.path, 'fonts'));
    await fontsDir.create(recursive: true);
    final manifest = File(p.join(fontsDir.path, 'manifest.json'));
    var fonts = <BookUserFont>[];
    try {
      if (await manifest.exists()) {
        final raw = jsonDecode(await manifest.readAsString());
        if (raw is List) {
          fonts = [
            for (final item in raw)
              if (item is Map<String, dynamic>) BookUserFont.fromJson(item),
          ];
        }
      }
    } catch (error) {
      debugPrint('[BookFontStore] manifest load failed: $error');
    }

    // Drop entries whose files are gone.
    final existing = <BookUserFont>[];
    for (final font in fonts) {
      final file = File(p.join(fontsDir.path, font.fileName));
      if (await file.exists()) {
        existing.add(font);
      }
    }
    final store = BookFontStore._(fontsDir, manifest, existing);
    if (existing.length != fonts.length) {
      await store._saveManifest();
    }
    store._syncLoopbackMounts();
    return store;
  }

  void _syncLoopbackMounts() {
    final server = BookLoopbackServer.sharedOrNull;
    if (server == null) return;
    for (final font in _fonts) {
      server.mountFont(font.id, fileFor(font));
    }
  }

  /// Re-bind after loopback starts (open book).
  void attachLoopback() => _syncLoopbackMounts();

  Future<void> _saveManifest() async {
    await _fontsDir.create(recursive: true);
    await _manifestFile.writeAsString(
      jsonEncode([for (final font in _fonts) font.toJson()]),
      flush: true,
    );
  }

  Future<BookUserFont> downloadCatalogFont(
    BookCatalogFont catalog, {
    void Function(double progress)? onProgress,
  }) async {
    final existing = byCatalogId(catalog.id);
    if (existing != null) return existing;
    if (_downloading.contains(catalog.id)) {
      throw StateError('正在下载 ${catalog.displayName}');
    }

    _downloading.add(catalog.id);
    _downloadProgress[catalog.id] = 0;
    notifyListeners();

    final id = 'catalog_${catalog.id}';
    final fileName = '$id.${catalog.fileExtension}';
    final dest = File(p.join(_fontsDir.path, fileName));
    final temp = File('${dest.path}.part');

    Object? lastError;
    try {
      for (final url in catalog.urls) {
        try {
          await _downloadToFile(
            url: url,
            dest: temp,
            onProgress: (p) {
              _downloadProgress[catalog.id] = p;
              onProgress?.call(p);
              notifyListeners();
            },
          );
          if (await dest.exists()) await dest.delete();
          await temp.rename(dest.path);
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
          debugPrint('[BookFontStore] download failed ($url): $error');
          if (await temp.exists()) {
            try {
              await temp.delete();
            } catch (_) {}
          }
        }
      }
      if (lastError != null || !await dest.exists()) {
        throw lastError ?? StateError('下载失败');
      }

      final font = BookUserFont(
        id: id,
        displayName: catalog.displayName,
        fileName: fileName,
        source: BookUserFontSource.download,
        catalogId: catalog.id,
      );
      _fonts = [..._fonts.where((f) => f.id != id), font];
      await _saveManifest();
      BookLoopbackServer.sharedOrNull?.mountFont(font.id, dest);
      return font;
    } finally {
      _downloading.remove(catalog.id);
      _downloadProgress.remove(catalog.id);
      notifyListeners();
    }
  }

  Future<BookUserFont> importFontFile(String path) async {
    final source = File(path);
    if (!await source.exists()) {
      throw StateError('找不到字体文件');
    }
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (!const {'ttf', 'otf', 'woff', 'woff2'}.contains(ext)) {
      throw StateError('仅支持 ttf / otf / woff / woff2');
    }
    final base = p.basenameWithoutExtension(path);
    final id =
        'import_${DateTime.now().millisecondsSinceEpoch}_${base.hashCode.abs()}';
    final fileName = '$id.$ext';
    final dest = File(p.join(_fontsDir.path, fileName));
    await source.copy(dest.path);

    final font = BookUserFont(
      id: id,
      displayName: base,
      fileName: fileName,
      source: BookUserFontSource.import,
    );
    _fonts = [..._fonts, font];
    await _saveManifest();
    BookLoopbackServer.sharedOrNull?.mountFont(font.id, dest);
    notifyListeners();
    return font;
  }

  Future<void> deleteUserFont(String id) async {
    final font = byId(id);
    if (font == null) return;
    _fonts = [for (final f in _fonts) if (f.id != id) f];
    await _saveManifest();
    BookLoopbackServer.sharedOrNull?.unmountFont(id);
    final file = fileFor(font);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  static Future<void> _downloadToFile({
    required String url,
    required File dest,
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'KaikaReader/1.0');
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final total = response.contentLength;
      var received = 0;
      final sink = dest.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }
        onProgress?.call(1);
      } finally {
        await sink.close();
      }
      if (received < 1024) {
        throw StateError('字体文件过小，可能下载失败');
      }
    } finally {
      client.close(force: true);
    }
  }
}

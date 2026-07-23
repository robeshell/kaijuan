import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'comic_archive.dart';
import 'import_models.dart';

/// Metrics for [EpubImportRouter.classifyMetrics] without Foliate / WebView.
class EpubKindProbeResult {
  const EpubKindProbeResult({
    required this.sectionCount,
    required this.sampledSectionCount,
    required this.sampledImageOnlySections,
    required this.totalTextLength,
    required this.imageCount,
    this.title,
  });

  final int sectionCount;
  final int sampledSectionCount;
  final int sampledImageOnlySections;
  final int totalTextLength;
  final int imageCount;
  final String? title;
}

/// File-backed EPUB kind probe: OPF spine + bounded XHTML samples.
///
/// Same thresholds as Foliate metadata-probe (`textLength <= 80` ⇒ image-only
/// wrapper). Never materializes the whole EPUB as one Dart [Uint8List] and
/// never opens a WebView.
abstract final class EpubKindProbe {
  static const maxSamples = 12;
  static const imageOnlyTextThreshold = 80;

  static Future<EpubKindProbeResult> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ImportException('文件不存在');
    }
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return inspectArchive(archive);
    } finally {
      await input.close();
    }
  }

  /// Shared by tests and [inspect].
  static EpubKindProbeResult inspectArchive(Archive archive) {
    final listing = ComicArchive.listFromArchive(archive);
    final spine = _spineDocuments(archive);
    if (spine.isEmpty) {
      return EpubKindProbeResult(
        sectionCount: 0,
        sampledSectionCount: 0,
        sampledImageOnlySections: 0,
        totalTextLength: 0,
        imageCount: listing.pageNames.length,
        title: listing.title,
      );
    }

    final indices = _sampleIndices(spine.length, maxSamples);
    var sampledImageOnly = 0;
    var totalText = 0;
    for (final i in indices) {
      final doc = spine[i];
      if (doc.isImage) {
        sampledImageOnly++;
        continue;
      }
      final html = _readText(archive, doc.href);
      if (html == null) continue;
      final textLength = _plainTextLength(html);
      totalText += textLength;
      final hasImage = _htmlContainsImage(html);
      if (hasImage && textLength <= imageOnlyTextThreshold) {
        sampledImageOnly++;
      }
    }

    return EpubKindProbeResult(
      sectionCount: spine.length,
      sampledSectionCount: indices.length,
      sampledImageOnlySections: sampledImageOnly,
      totalTextLength: totalText,
      imageCount: listing.pageNames.length,
      title: listing.title,
    );
  }

  static List<_SpineDoc> _spineDocuments(Archive archive) {
    final names = {
      for (final f in archive.files)
        if (f.isFile) f.name,
    };
    final containerName = _findEntry(names, 'META-INF/container.xml');
    if (containerName == null) return const [];
    final containerXml = _readText(archive, containerName);
    if (containerXml == null) return const [];
    final rootMatch = RegExp(
      r'full-path\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    if (rootMatch == null) return const [];

    final opfPath = _normalizeZipPath(rootMatch.group(1)!);
    final opfXml = _readText(archive, opfPath);
    if (opfXml == null) return const [];
    final opfDir = p.posix.dirname(opfPath);

    final manifest = <String, _ManifestItem>{};
    for (final m in RegExp(
      r'<item\b([^>]+)/?>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final attrs = m.group(1)!;
      final id = _attr(attrs, 'id');
      final href = _attr(attrs, 'href');
      if (id == null || href == null) continue;
      final mediaType = _attr(attrs, 'media-type')?.toLowerCase() ?? '';
      manifest[id] = _ManifestItem(
        href: _resolveZipPath(opfDir, href),
        mediaType: mediaType,
      );
    }

    final docs = <_SpineDoc>[];
    for (final m in RegExp(
      r'<itemref\b([^>]+)/?>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final idref = _attr(m.group(1)!, 'idref');
      if (idref == null) continue;
      final item = manifest[idref];
      if (item == null) continue;
      if (_isImageItem(item)) {
        docs.add(_SpineDoc(href: item.href, isImage: true));
        continue;
      }
      if (_isHtmlItem(item)) {
        docs.add(_SpineDoc(href: item.href, isImage: false));
      }
    }
    return docs;
  }

  static bool _isImageItem(_ManifestItem item) {
    const types = {
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp',
      'image/svg+xml',
    };
    if (types.contains(item.mediaType)) return true;
    return ComicArchive.imageExtensions.contains(
      p.extension(item.href).toLowerCase(),
    );
  }

  static bool _isHtmlItem(_ManifestItem item) {
    if (item.mediaType.contains('html') || item.mediaType.contains('xml')) {
      // Exclude pure SVG/XML images already handled above.
      if (item.mediaType == 'image/svg+xml') return false;
      final ext = p.extension(item.href).toLowerCase();
      if (ext == '.ncx') return false;
      return true;
    }
    final ext = p.extension(item.href).toLowerCase();
    return ext == '.xhtml' || ext == '.html' || ext == '.htm';
  }

  static List<int> _sampleIndices(int count, int maxSamples) {
    if (count <= 0) return const [];
    if (count <= maxSamples) {
      return [for (var i = 0; i < count; i++) i];
    }
    return [
      for (var i = 0; i < maxSamples; i++)
        ((i * (count - 1)) / (maxSamples - 1)).round(),
    ];
  }

  static int _plainTextLength(String html) {
    var text = html.replaceAll(
      RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length;
  }

  static bool _htmlContainsImage(String html) {
    return RegExp(
          r'<(?:img|image|svg)\b',
          caseSensitive: false,
        ).hasMatch(html) ||
        RegExp(
          r'''(?:src|xlink:href)\s*=\s*["'][^"']+\.(?:jpg|jpeg|png|gif|webp|bmp|svg)''',
          caseSensitive: false,
        ).hasMatch(html);
  }

  static String? _attr(String attrs, String name) {
    final m = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(attrs);
    return m?.group(1);
  }

  static String _normalizeZipPath(String path) =>
      path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

  static String _resolveZipPath(String baseDir, String href) {
    final cleaned = href.split('?').first.split('#').first;
    final joined = baseDir == '.' || baseDir.isEmpty
        ? cleaned
        : p.posix.normalize(p.posix.join(baseDir, cleaned));
    return _normalizeZipPath(joined);
  }

  static String? _findEntry(Set<String> names, String want) {
    final n = _normalizeZipPath(want);
    if (names.contains(n)) return n;
    final lower = n.toLowerCase();
    for (final name in names) {
      if (name.toLowerCase() == lower) return name;
    }
    return null;
  }

  static String? _readText(Archive archive, String entry) {
    final resolved = _findEntry(
      {for (final f in archive.files) if (f.isFile) f.name},
      entry,
    );
    if (resolved == null) return null;
    final file = archive.findFile(resolved);
    final bytes = file?.readBytes();
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _ManifestItem {
  const _ManifestItem({required this.href, required this.mediaType});
  final String href;
  final String mediaType;
}

class _SpineDoc {
  const _SpineDoc({required this.href, required this.isImage});
  final String href;
  final bool isImage;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Result of listing pages in a comic archive (CBZ/ZIP/EPUB-as-images).
class ComicPageListing {
  const ComicPageListing({
    required this.pageNames,
    this.title,
  });

  /// Entry paths inside the zip, in reading order.
  final List<String> pageNames;

  /// Optional package title (EPUB `dc:title`); null for plain CBZ/ZIP.
  final String? title;
}

/// Read-only access to zip-based comic archives (CBZ / ZIP / image EPUB).
///
/// - **CBZ/ZIP**: image entries sorted with [naturalCompare].
/// - **EPUB** (has `META-INF/container.xml`): OPF spine order when images
///   can be resolved from spine items / XHTML; otherwise falls back to
///   natural-sorted images.
///
/// Entry bytes are decompressed on demand. The reader should keep one open
/// [ComicSession] rather than re-listing in a tight loop.
abstract final class ComicArchive {
  static const imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  };

  static const _imageMediaTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/bmp',
    'image/svg+xml',
  };

  /// Naturally-sorted or spine-ordered image entry names.
  static Future<List<String>> listPages(String path) async {
    final listing = await listPagesDetailed(path);
    return listing.pageNames;
  }

  /// Same as [listPages], plus optional EPUB metadata title.
  static Future<ComicPageListing> listPagesDetailed(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return _listFromArchive(archive);
    } finally {
      await input.close();
    }
  }

  /// Shared by import and [ComicSession] so order stays consistent.
  static ComicPageListing listFromArchive(Archive archive) =>
      _listFromArchive(archive);

  static ComicPageListing _listFromArchive(Archive archive) {
    final names = {
      for (final f in archive.files)
        if (f.isFile) f.name,
    };

    if (names.contains('META-INF/container.xml') ||
        names.any((n) => n.toLowerCase() == 'meta-inf/container.xml')) {
      final epub = _listEpubPages(archive, names);
      if (epub.pageNames.isNotEmpty) return epub;
    }

    final pages = names.where(_isImageEntry).toList()..sort(naturalCompare);
    return ComicPageListing(pageNames: pages);
  }

  static ComicPageListing _listEpubPages(Archive archive, Set<String> names) {
    final containerName = _findEntry(names, 'META-INF/container.xml');
    if (containerName == null) {
      return const ComicPageListing(pageNames: []);
    }
    final containerXml = _readText(archive, containerName);
    if (containerXml == null) {
      return const ComicPageListing(pageNames: []);
    }

    final rootMatch = RegExp(
      r'full-path\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    if (rootMatch == null) {
      return const ComicPageListing(pageNames: []);
    }

    final opfPath = _normalizeZipPath(rootMatch.group(1)!);
    final opfXml = _readText(archive, opfPath);
    if (opfXml == null) {
      return const ComicPageListing(pageNames: []);
    }

    final opfDir = p.posix.dirname(opfPath);
    final title = _firstXmlText(opfXml, 'dc:title') ??
        _firstXmlText(opfXml, 'title');

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

    final pages = <String>[];
    final seen = <String>{};

    void addPage(String entry) {
      final key = _findEntry(names, entry) ?? entry;
      if (!_isImageEntry(key) && !_isSvgEntry(key)) return;
      final resolved = _findEntry(names, key);
      if (resolved == null) return;
      if (seen.add(resolved)) pages.add(resolved);
    }

    for (final m in RegExp(
      r'<itemref\b([^>]+)/?>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final idref = _attr(m.group(1)!, 'idref');
      if (idref == null) continue;
      final item = manifest[idref];
      if (item == null) continue;

      if (_imageMediaTypes.contains(item.mediaType) ||
          _isImageEntry(item.href)) {
        addPage(item.href);
        continue;
      }

      if (item.mediaType.contains('html') ||
          item.mediaType.contains('xml') ||
          item.href.toLowerCase().endsWith('.xhtml') ||
          item.href.toLowerCase().endsWith('.html') ||
          item.href.toLowerCase().endsWith('.htm')) {
        final html = _readText(archive, item.href);
        if (html == null) continue;
        final htmlDir = p.posix.dirname(item.href);
        for (final src in _imageRefsFromHtml(html)) {
          addPage(_resolveZipPath(htmlDir, src));
        }
      }
    }

    if (pages.isEmpty) {
      final fallback = names.where(_isImageEntry).toList()..sort(naturalCompare);
      return ComicPageListing(pageNames: fallback, title: title);
    }
    return ComicPageListing(pageNames: pages, title: title);
  }

  static Iterable<String> _imageRefsFromHtml(String html) {
    final refs = <String>[];
    final patterns = [
      RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''xlink:href\s*=\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''href\s*=\s*["']([^"']+\.(?:jpg|jpeg|png|gif|webp|bmp|svg))["']''',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      for (final m in re.allMatches(html)) {
        final ref = m.group(1)!.trim();
        if (ref.isEmpty || ref.startsWith('data:')) continue;
        refs.add(ref.split('#').first);
      }
    }
    return refs;
  }

  static String? _firstXmlText(String xml, String localName) {
    final re = RegExp(
      '<$localName(?:\\s[^>]*)?>([^<]*)</$localName>',
      caseSensitive: false,
    );
    final m = re.firstMatch(xml);
    final text = m?.group(1)?.trim();
    if (text == null || text.isEmpty) return null;
    return _decodeXmlEntities(text);
  }

  static String _decodeXmlEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

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

  /// Decompresses a single entry. Used for covers; reader should use session.
  static Future<Uint8List?> readEntry(String path, String entry) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final file = archive.findFile(entry) ??
          archive.findFile(_normalizeZipPath(entry));
      final bytes = file?.readBytes();
      return bytes == null ? null : Uint8List.fromList(bytes);
    } finally {
      await input.close();
    }
  }

  static bool _isImageEntry(String name) =>
      imageExtensions.contains(p.extension(name).toLowerCase());

  static bool _isSvgEntry(String name) =>
      p.extension(name).toLowerCase() == '.svg';

  /// Numbers-aware comparison so `page2` sorts before `page10`.
  static int naturalCompare(String a, String b) {
    final chunksA = _chunks(a);
    final chunksB = _chunks(b);
    final length = chunksA.length < chunksB.length
        ? chunksA.length
        : chunksB.length;
    for (var i = 0; i < length; i++) {
      final ca = chunksA[i];
      final cb = chunksB[i];
      final na = int.tryParse(ca);
      final nb = int.tryParse(cb);
      final result = (na != null && nb != null)
          ? na.compareTo(nb)
          : ca.toLowerCase().compareTo(cb.toLowerCase());
      if (result != 0) return result;
    }
    return chunksA.length.compareTo(chunksB.length);
  }

  static List<String> _chunks(String value) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var inDigits = false;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (buffer.isNotEmpty && isDigit != inDigits) {
        chunks.add(buffer.toString());
        buffer.clear();
      }
      inDigits = isDigit;
      buffer.writeCharCode(code);
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }
}

class _ManifestItem {
  const _ManifestItem({required this.href, required this.mediaType});
  final String href;
  final String mediaType;
}

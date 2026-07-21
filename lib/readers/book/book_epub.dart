import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// One linear spine section for reflow reading.
class BookSection {
  const BookSection({
    required this.href,
    required this.title,
    required this.plainText,
    required this.rawHtml,
  });

  final String href;
  final String title;
  final String plainText;

  /// Original XHTML of this spine item, before tag stripping. Used by
  /// flutter_html rendering engines.
  final String rawHtml;
}

/// Parsed reflow EPUB (text spine). Not for image-only manga packs.
class BookEpubDocument {
  const BookEpubDocument({
    required this.title,
    required this.sections,
    this.coverEntry,
    this.stylesheets = const [],
  });

  final String title;
  final List<BookSection> sections;
  final String? coverEntry;

  /// CSS texts from OPF manifest items, in manifest order.
  final List<String> stylesheets;

  int get sectionCount => sections.length;
}

/// Open and parse reflow EPUB packages.
abstract final class BookEpub {
  static const _imageExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg',
  };
  static Future<BookEpubDocument> open(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return parseArchive(archive);
    } finally {
      await input.close();
    }
  }

  static BookEpubDocument parseArchive(Archive archive) {
    final names = {
      for (final f in archive.files)
        if (f.isFile) f.name,
    };

    final containerName = _findEntry(names, 'META-INF/container.xml');
    if (containerName == null) {
      throw const BookEpubException('不是有效的 EPUB（缺少 container.xml）');
    }
    final containerXml = _readText(archive, containerName);
    if (containerXml == null) {
      throw const BookEpubException('无法读取 container.xml');
    }
    final rootMatch = RegExp(
      r'full-path\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    if (rootMatch == null) {
      throw const BookEpubException('container.xml 缺少 rootfile');
    }

    final opfPath = _normalize(rootMatch.group(1)!);
    final opfXml = _readText(archive, opfPath);
    if (opfXml == null) {
      throw const BookEpubException('无法读取 OPF');
    }
    final opfDir = p.posix.dirname(opfPath);
    final title = _firstXmlText(opfXml, 'dc:title') ??
        _firstXmlText(opfXml, 'title') ??
        '未命名';

    final manifest = <String, _Item>{};
    for (final m in RegExp(
      r'<item\b([^>]+)/?>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final attrs = m.group(1)!;
      final id = _attr(attrs, 'id');
      final href = _attr(attrs, 'href');
      if (id == null || href == null) continue;
      manifest[id] = _Item(
        href: _resolve(opfDir, href),
        mediaType: _attr(attrs, 'media-type')?.toLowerCase() ?? '',
        properties: _attr(attrs, 'properties') ?? '',
      );
    }

    final stylesheets = <String>[];
    for (final item in manifest.values) {
      if (item.mediaType == 'text/css') {
        final css = _readText(archive, item.href);
        if (css != null && css.trim().isNotEmpty) {
          stylesheets.add(css);
        }
      }
    }

    String? coverEntry;

    // 1. EPUB 2 <meta name="cover" content="…"/> → lookup manifest id.
    String? coverId;
    for (final m in RegExp(
      r'<meta\b([^>]+)/?>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final attrs = m.group(1)!;
      if (_attr(attrs, 'name')?.toLowerCase() == 'cover') {
        coverId = _attr(attrs, 'content');
        break;
      }
    }
    if (coverId != null) {
      final coverItem = manifest[coverId];
      if (coverItem != null) {
        coverEntry = _findEntry(names, coverItem.href);
      }
    }

    // 2. EPUB 3 properties="cover-image", or id/href looks like cover.
    if (coverEntry == null) {
      for (final item in manifest.values) {
        if (item.properties.contains('cover-image') ||
            item.idLooksLikeCover) {
          coverEntry = _findEntry(names, item.href);
          if (coverEntry != null) break;
        }
      }
    }

    // 3. Fallback: any image in the manifest.
    if (coverEntry == null) {
      for (final item in manifest.values) {
        if (item.mediaType.startsWith('image/')) {
          coverEntry = _findEntry(names, item.href);
          if (coverEntry != null) break;
        }
      }
    }

    // 4. Last resort: any image file in the archive whose name suggests cover.
    if (coverEntry == null) {
      for (final name in names) {
        final lower = name.toLowerCase();
        final ext = p.extension(name).toLowerCase();
        if ((lower.contains('cover') || lower.contains('title')) &&
            _imageExtensions.contains(ext)) {
          coverEntry = name;
          break;
        }
      }
    }

    final sections = <BookSection>[];
    for (final m in RegExp(
      r'<itemref\b([^>]+)/?>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final idref = _attr(m.group(1)!, 'idref');
      if (idref == null) continue;
      final item = manifest[idref];
      if (item == null) continue;
      if (!_isHtml(item)) continue;
      final html = _readText(archive, item.href);
      if (html == null) continue;
      final plain = _htmlToPlainText(html);
      if (plain.trim().isEmpty) continue;
      final sectionTitle = _firstXmlText(html, 'title') ??
          _headingTitle(html) ??
          '第 ${sections.length + 1} 节';
      sections.add(
        BookSection(
          href: item.href,
          title: sectionTitle.trim().isEmpty
              ? '第 ${sections.length + 1} 节'
              : sectionTitle.trim(),
          plainText: plain.trim(),
          rawHtml: html,
        ),
      );
    }

    if (sections.isEmpty) {
      throw const BookEpubException(
        '未找到可阅读的正文（页图式 EPUB 请使用漫画 App）',
      );
    }

    return BookEpubDocument(
      title: title.trim().isEmpty ? '未命名' : title.trim(),
      sections: List.unmodifiable(sections),
      coverEntry: coverEntry,
      stylesheets: List.unmodifiable(stylesheets),
    );
  }

  static Future<Uint8List?> readEntry(String path, String entry) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final resolved = _findEntry(
        {for (final f in archive.files) if (f.isFile) f.name},
        entry,
      );
      if (resolved == null) return null;
      final file = archive.findFile(resolved);
      final bytes = file?.readBytes();
      return bytes == null ? null : Uint8List.fromList(bytes);
    } finally {
      await input.close();
    }
  }

  static bool _isHtml(_Item item) {
    if (item.mediaType.contains('html') || item.mediaType.contains('xml')) {
      return true;
    }
    final h = item.href.toLowerCase();
    return h.endsWith('.xhtml') ||
        h.endsWith('.html') ||
        h.endsWith('.htm') ||
        h.endsWith('.xml');
  }

  static String _htmlToPlainText(String html) {
    var s = html;
    // Drop scripts/styles.
    s = s.replaceAll(
      RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
      '',
    );
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = _decodeXmlEntities(s);
    s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s;
  }

  static String? _headingTitle(String html) {
    final m = RegExp(
      r'<h[1-3][^>]*>([\s\S]*?)</h[1-3]>',
      caseSensitive: false,
    ).firstMatch(html);
    if (m == null) return null;
    return _htmlToPlainText(m.group(1)!).split('\n').first.trim();
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

  static String _decodeXmlEntities(String s) {
    var out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });
    return out;
  }

  static String? _attr(String attrs, String name) {
    final m = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(attrs);
    return m?.group(1);
  }

  static String _normalize(String path) =>
      path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

  static String _resolve(String baseDir, String href) {
    final cleaned = href.split('?').first.split('#').first;
    final joined = baseDir == '.' || baseDir.isEmpty
        ? cleaned
        : p.posix.normalize(p.posix.join(baseDir, cleaned));
    return _normalize(joined);
  }

  static String? _findEntry(Set<String> names, String want) {
    final n = _normalize(want);
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

class _Item {
  _Item({
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String href;
  final String mediaType;
  final String properties;

  bool get idLooksLikeCover =>
      href.toLowerCase().contains('cover') ||
      mediaType.startsWith('image/');
}

class BookEpubException implements Exception {
  const BookEpubException(this.message);

  final String message;

  @override
  String toString() => message;
}

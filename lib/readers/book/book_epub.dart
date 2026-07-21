import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:epub_pro/epub_pro.dart' as epub;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// One linear spine section for reflow reading.
class BookSection {
  const BookSection({
    required this.href,
    required this.title,
    this.plainText = '',
    this.rawHtml = '',
  });

  final String href;
  final String title;

  /// May be empty when the session is opened lazily.
  final String plainText;

  /// Original XHTML. Empty until [BookEpubSession.readHtml] loads it.
  final String rawHtml;
}

/// One row in the reader TOC, mapped onto the spine.
class BookTocEntry {
  const BookTocEntry({
    required this.title,
    required this.href,
    this.fragment,
    this.sectionIndex,
    this.depth = 0,
  });

  final String title;

  /// OPF-relative path of the target spine HTML (no fragment).
  final String href;

  final String? fragment;
  final int? sectionIndex;
  final int depth;
}

/// Spine index + metadata. HTML bodies are loaded via [BookEpubSession].
class BookEpubDocument {
  const BookEpubDocument({
    required this.title,
    required this.sections,
    this.toc = const [],
    this.coverEntry,
    this.coverBytes,
    this.contentDirectoryPath = '',
  });

  final String title;
  final List<BookSection> sections;
  final List<BookTocEntry> toc;
  final String? coverEntry;
  final Uint8List? coverBytes;

  /// EPUB content root inside the zip (e.g. `OEBPS`), may be empty.
  final String contentDirectoryPath;

  int get sectionCount => sections.length;
}

/// Open EPUB with lazy HTML/image reads (safe for 1000+ spine items).
class BookEpubSession {
  BookEpubSession._(this._ref, this.document);

  final epub.EpubBookRef _ref;
  final BookEpubDocument document;

  List<String>? _stylesheetCache;
  final _htmlCache = <String, String>{};

  static Future<BookEpubSession> open(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BookEpubException('文件不存在');
    }
    return openBytes(await file.readAsBytes());
  }

  static Future<BookEpubSession> openBytes(Uint8List bytes) async {
    try {
      final ref = await epub.EpubReader.openBook(bytes);
      final document = await BookEpub._documentFromRef(ref);
      return BookEpubSession._(ref, document);
    } on BookEpubException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('EPUB') || msg.contains('TOC') || msg.contains('nav')) {
        throw const BookEpubException(
          '未找到可阅读的正文（页图式 EPUB 请使用漫画引擎）',
        );
      }
      throw BookEpubException('无法打开 EPUB：$e');
    }
  }

  /// Loads spine HTML (cached). [href] is OPF-relative.
  Future<String> readHtml(String href) async {
    final key = BookEpub._normalize(href);
    final cached = _htmlCache[key];
    if (cached != null) return cached;

    final htmlFiles = _ref.content?.html;
    if (htmlFiles == null || htmlFiles.isEmpty) {
      _htmlCache[key] = '';
      return '';
    }

    var fileRef = htmlFiles[href] ?? htmlFiles[key];
    if (fileRef == null) {
      final want = key.toLowerCase();
      for (final entry in htmlFiles.entries) {
        if (BookEpub._normalize(entry.key).toLowerCase() == want) {
          fileRef = entry.value;
          break;
        }
      }
    }
    if (fileRef == null) {
      _htmlCache[key] = '';
      return '';
    }
    final text = await fileRef.readContentAsText();
    _htmlCache[key] = text;
    return text;
  }

  /// Package CSS texts (loaded once, shared — not inlined per section).
  Future<List<String>> stylesheets() async {
    if (_stylesheetCache != null) return _stylesheetCache!;
    final cssFiles = _ref.content?.css ?? const {};
    final out = <String>[];
    for (final entry in cssFiles.values) {
      try {
        final text = await entry.readContentAsText();
        if (text.trim().isNotEmpty) out.add(text);
      } catch (_) {
        // Ignore broken CSS entries.
      }
    }
    _stylesheetCache = List.unmodifiable(out);
    return _stylesheetCache!;
  }

  /// Reads one CSS file by OPF-relative or zip path (for section `<link>` tags).
  Future<String?> readCss(String href) async {
    final key = BookEpub._normalize(href);
    if (key.isEmpty) return null;

    final cssFiles = _ref.content?.css ?? const {};
    var fileRef = cssFiles[key] ??
        cssFiles[BookEpub._stripContentDir(key, document.contentDirectoryPath)];
    if (fileRef == null) {
      final want = key.toLowerCase();
      for (final entry in cssFiles.entries) {
        if (BookEpub._normalize(entry.key).toLowerCase() == want) {
          fileRef = entry.value;
          break;
        }
      }
    }
    if (fileRef != null) {
      try {
        final text = await fileRef.readContentAsText();
        return text.trim().isEmpty ? null : text;
      } catch (_) {
        return null;
      }
    }

    final bytes = await readBytes(href);
    if (bytes == null || bytes.isEmpty) return null;
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    return text.isEmpty ? null : text;
  }

  /// Reads a binary entry (images). [entry] may be OPF-relative or zip path.
  Future<Uint8List?> readBytes(String entry) async {
    final want = BookEpub._normalize(entry);
    if (want.isEmpty) return null;

    final all = _ref.content?.allFiles ?? const {};
    var file =
        all[want] ??
        all[entry] ??
        all[BookEpub._stripContentDir(want, document.contentDirectoryPath)];

    if (file == null) {
      final wantLower = want.toLowerCase();
      final base = p.posix.basename(want).toLowerCase();
      for (final e in all.entries) {
        final key = BookEpub._normalize(e.key).toLowerCase();
        if (key == wantLower ||
            key.endsWith('/$wantLower') ||
            p.posix.basename(key) == base) {
          file = e.value;
          break;
        }
      }
    }

    if (file == null) {
      // Fallback: scan zip names with content-dir prefix.
      final names = {
        for (final f in _ref.epubArchive.files)
          if (f.isFile) BookEpub._normalize(f.name),
      };
      final resolved = BookEpub._resolveZipName(
        names,
        want,
        contentDirectoryPath: document.contentDirectoryPath,
      );
      if (resolved == null) return null;
      final archiveFile = _ref.epubArchive.findFile(resolved);
      final bytes = archiveFile?.readBytes();
      return bytes == null ? null : Uint8List.fromList(bytes);
    }

    try {
      final bytes = await file.readContentAsBytes();
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Rough plain-text length for import kind detection (samples first sections).
  Future<int> samplePlainTextLength({int maxSections = 8}) async {
    var total = 0;
    final n = document.sections.length.clamp(0, maxSections);
    for (var i = 0; i < n; i++) {
      final html = await readHtml(document.sections[i].href);
      total += BookEpub._htmlToPlainText(html).trim().length;
    }
    return total;
  }
}

/// Opens reflow EPUB packages via [epub_pro], adapted to KaikaNext models.
abstract final class BookEpub {
  /// Lazy session (preferred for reading).
  static Future<BookEpubSession> openSession(String path) =>
      BookEpubSession.open(path);

  static Future<BookEpubSession> openSessionBytes(Uint8List bytes) =>
      BookEpubSession.openBytes(bytes);

  /// Index-only open (no HTML bodies). Prefer [openSession] when reading.
  static Future<BookEpubDocument> open(String path) async {
    final session = await BookEpubSession.open(path);
    return session.document;
  }

  static Future<BookEpubDocument> openBytes(Uint8List bytes) async {
    final session = await BookEpubSession.openBytes(bytes);
    return session.document;
  }

  /// Compatibility for callers that already hold an [Archive].
  static Future<BookEpubDocument> parseArchive(Archive archive) async {
    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw const BookEpubException('无法编码 EPUB 归档');
    }
    return openBytes(Uint8List.fromList(encoded));
  }

  /// Reads a zip entry from [path]. Prefer [BookEpubSession.readBytes].
  static Future<Uint8List?> readEntry(
    String path,
    String entry, {
    String contentDirectoryPath = '',
  }) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final names = {
        for (final f in archive.files)
          if (f.isFile) _normalize(f.name),
      };
      final resolved = _resolveZipName(
        names,
        entry,
        contentDirectoryPath: contentDirectoryPath,
      );
      if (resolved == null) return null;
      final file = archive.findFile(resolved);
      final bytes = file?.readBytes();
      return bytes == null ? null : Uint8List.fromList(bytes);
    } finally {
      await input.close();
    }
  }

  static ({String path, String? fragment}) resolveHref(
    String baseHref,
    String href,
  ) {
    final cleaned = href.trim();
    if (cleaned.isEmpty) {
      return (path: _normalize(baseHref), fragment: null);
    }

    final hash = cleaned.indexOf('#');
    final pathPart = hash >= 0 ? cleaned.substring(0, hash) : cleaned;
    final fragment = hash >= 0 ? cleaned.substring(hash + 1) : null;
    final frag = (fragment == null || fragment.isEmpty) ? null : fragment;

    if (pathPart.isEmpty) {
      return (path: _normalize(baseHref), fragment: frag);
    }
    if (pathPart.contains(':') &&
        !pathPart.startsWith('file:') &&
        !pathPart.startsWith('/')) {
      return (path: pathPart, fragment: frag);
    }

    if (baseHref.isEmpty) {
      return (path: _normalize(pathPart), fragment: frag);
    }

    final baseDir = p.posix.dirname(baseHref);
    final joined = baseDir == '.' || baseDir.isEmpty
        ? pathPart
        : p.posix.normalize(p.posix.join(baseDir, pathPart));
    return (path: _normalize(joined), fragment: frag);
  }

  static double fragmentProgress(String html, String? fragment) {
    if (fragment == null || fragment.isEmpty || html.isEmpty) return 0;
    final markers = <String>[
      'id="$fragment"',
      "id='$fragment'",
      'name="$fragment"',
      "name='$fragment'",
    ];
    var index = -1;
    for (final marker in markers) {
      index = html.indexOf(marker);
      if (index >= 0) break;
    }
    if (index < 0) return 0;
    return (index / html.length).clamp(0.0, 1.0);
  }

  static Future<BookEpubDocument> _documentFromRef(epub.EpubBookRef ref) async {
    final package = ref.schema?.package;
    final spine = package?.spine?.items ?? const <epub.EpubSpineItemRef>[];
    final manifest =
        package?.manifest?.items ?? const <epub.EpubManifestItem>[];
    final byId = <String, epub.EpubManifestItem>{
      for (final item in manifest)
        if (item.id != null) item.id!: item,
    };
    final contentDir = _normalize(ref.schema?.contentDirectoryPath ?? '');

    final chapters = ref.getChapters();
    final tocTitles = <String, String>{};
    void collectTitles(List<epub.EpubChapterRef> list) {
      for (final chapter in list) {
        final href = chapter.contentFileName;
        final title = _usableTitle(chapter.title);
        if (href != null && href.isNotEmpty && title != null) {
          tocTitles.putIfAbsent(_normalize(href).toLowerCase(), () => title);
        }
        collectTitles(chapter.subChapters);
      }
    }

    collectTitles(chapters);

    final sections = <BookSection>[];
    for (final itemRef in spine) {
      final idRef = itemRef.idRef;
      if (idRef == null) continue;
      final manifestItem = byId[idRef];
      final href = manifestItem?.href;
      if (href == null || href.isEmpty) continue;
      if (!_isHtmlManifest(manifestItem!)) continue;

      final key = _normalize(href).toLowerCase();
      final title =
          tocTitles[key] ??
          _usableTitle(p.basenameWithoutExtension(href)) ??
          '第 ${sections.length + 1} 节';

      sections.add(
        BookSection(
          href: _normalize(href),
          title: title,
        ),
      );
    }

    if (sections.isEmpty) {
      throw const BookEpubException(
        '未找到可阅读的正文（页图式 EPUB 请使用漫画引擎）',
      );
    }

    final hrefIndex = <String, int>{
      for (var i = 0; i < sections.length; i++)
        sections[i].href.toLowerCase(): i,
    };

    final toc = <BookTocEntry>[];
    void walkToc(List<epub.EpubChapterRef> list, int depth) {
      for (final chapter in list) {
        final href = chapter.contentFileName;
        if (href != null && href.isNotEmpty) {
          final normalized = _normalize(href);
          final title =
              _usableTitle(chapter.title) ??
              tocTitles[normalized.toLowerCase()] ??
              p.basenameWithoutExtension(normalized);
          toc.add(
            BookTocEntry(
              title: title,
              href: normalized,
              fragment: chapter.anchor,
              sectionIndex: hrefIndex[normalized.toLowerCase()],
              depth: depth,
            ),
          );
        }
        walkToc(chapter.subChapters, depth + 1);
      }
    }

    walkToc(chapters, 0);

    final cover = await _coverFromRef(ref);

    return BookEpubDocument(
      title: _cleanBookTitle(ref.title),
      sections: List.unmodifiable(sections),
      toc: List.unmodifiable(toc.isEmpty ? _fallbackToc(sections) : toc),
      coverEntry: cover.entry,
      coverBytes: cover.bytes,
      contentDirectoryPath: contentDir,
    );
  }

  static List<BookTocEntry> _fallbackToc(List<BookSection> sections) {
    return [
      for (var i = 0; i < sections.length; i++)
        BookTocEntry(
          title: sections[i].title,
          href: sections[i].href,
          sectionIndex: i,
        ),
    ];
  }

  static Future<({String? entry, Uint8List? bytes})> _coverFromRef(
    epub.EpubBookRef ref,
  ) async {
    try {
      final decoded = await ref.readCover();
      if (decoded != null) {
        final jpg = img.encodeJpg(decoded, quality: 85);
        return (entry: 'cover.jpg', bytes: Uint8List.fromList(jpg));
      }
    } catch (_) {}

    final images = ref.content?.images;
    if (images != null && images.isNotEmpty) {
      for (final entry in images.entries) {
        final name = entry.key.toLowerCase();
        if (name.contains('cover') || name.contains('title')) {
          try {
            final content = await entry.value.readContentAsBytes();
            if (content.isNotEmpty) {
              return (entry: entry.key, bytes: Uint8List.fromList(content));
            }
          } catch (_) {}
        }
      }
      try {
        final first = images.entries.first;
        final content = await first.value.readContentAsBytes();
        if (content.isNotEmpty) {
          return (entry: first.key, bytes: Uint8List.fromList(content));
        }
      } catch (_) {}
    }
    return (entry: null, bytes: null);
  }

  static bool _isHtmlManifest(epub.EpubManifestItem item) {
    final media = (item.mediaType ?? '').toLowerCase();
    if (media.contains('html') || media.contains('xml')) return true;
    final href = (item.href ?? '').toLowerCase();
    return href.endsWith('.xhtml') ||
        href.endsWith('.html') ||
        href.endsWith('.htm') ||
        href.endsWith('.xml');
  }

  static String _cleanBookTitle(String? raw) {
    return _usableTitle(raw) ?? '';
  }

  static String? _usableTitle(String? raw) {
    if (raw == null) return null;
    var t = raw.trim();
    if (t.isEmpty) return null;
    final slash = t.indexOf('/');
    if (slash >= 8) {
      t = t.substring(0, slash).trim();
    }
    if (t.length > 60) return null;
    if (t.contains('。') && t.length > 24) return null;
    return t;
  }

  static String _htmlToPlainText(String html) {
    var s = html;
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

  static String _normalize(String path) =>
      path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

  static String _stripContentDir(String path, String contentDir) {
    final dir = _normalize(contentDir);
    if (dir.isEmpty) return path;
    final prefix = '$dir/';
    final n = _normalize(path);
    if (n.toLowerCase().startsWith(prefix.toLowerCase())) {
      return n.substring(prefix.length);
    }
    return n;
  }

  static String? _resolveZipName(
    Set<String> names,
    String want, {
    String contentDirectoryPath = '',
  }) {
    final n = _normalize(want);
    if (names.contains(n)) return n;

    final dir = _normalize(contentDirectoryPath);
    if (dir.isNotEmpty) {
      final prefixed = _normalize(p.posix.join(dir, n));
      if (names.contains(prefixed)) return prefixed;
    }

    final lower = n.toLowerCase();
    final base = p.posix.basename(n).toLowerCase();
    for (final name in names) {
      final nl = name.toLowerCase();
      if (nl == lower) return name;
      if (nl.endsWith('/$lower')) return name;
      if (p.posix.basename(nl) == base) return name;
    }
    return null;
  }
}

class BookEpubException implements Exception {
  const BookEpubException(this.message);

  final String message;

  @override
  String toString() => message;
}

import 'package:flutter/services.dart';

import 'book_epub.dart';

/// One `@font-face` rule extracted from EPUB CSS.
class EpubFontFace {
  const EpubFontFace({required this.family, required this.src});

  final String family;
  final String src;
}

/// Loads embedded EPUB fonts declared via `@font-face`.
abstract final class BookEpubFonts {
  /// Parses [css] for `@font-face` blocks.
  static List<EpubFontFace> parseFontFaces(String css) {
    final faces = <EpubFontFace>[];
    final blockRe = RegExp(r'@font-face\s*\{([^}]*)\}', caseSensitive: false);
    for (final match in blockRe.allMatches(css)) {
      final body = match.group(1) ?? '';
      if (body.trim().isEmpty) continue;

      final familyMatch = RegExp(
        r'''font-family\s*:\s*(?:['"]([^'"]+)['"]|([^;,]+))''',
        caseSensitive: false,
      ).firstMatch(body);
      final family = _normalizeFamily(
        familyMatch?.group(1) ?? familyMatch?.group(2),
      );
      if (family == null || family.isEmpty) continue;

      final srcMatch = RegExp(
        r'''url\s*\(\s*(?:['"]([^'"]+)['"]|([^)]+))''',
        caseSensitive: false,
      ).firstMatch(body);
      final src = srcMatch?.group(1)?.trim() ?? srcMatch?.group(2)?.trim();
      if (src == null || src.isEmpty) continue;
      if (src.startsWith('data:')) continue;

      faces.add(EpubFontFace(family: family, src: src));
    }
    return faces;
  }

  /// Registers fonts with Flutter so CSS `font-family` can resolve.
  ///
  /// Returns family names successfully loaded. Failures are skipped silently.
  static Future<Set<String>> loadFromStylesheets(
    BookEpubSession session,
    List<String> stylesheets,
  ) async {
    final loaded = <String>{};
    for (final css in stylesheets) {
      for (final face in parseFontFaces(css)) {
        if (loaded.contains(face.family)) continue;
        final bytes = await _loadFontBytes(session, face.src);
        if (bytes == null || bytes.isEmpty) continue;
        try {
          final loader = FontLoader(face.family)
            ..addFont(Future<ByteData>.value(
              bytes.buffer.asByteData(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            ));
          await loader.load();
          loaded.add(face.family);
        } catch (_) {
          // Unsupported or corrupt font — keep reading with system fonts.
        }
      }
    }
    return loaded;
  }

  static String? _normalizeFamily(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final first = trimmed.split(',').first.trim();
    return first.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  }

  static Future<Uint8List?> _loadFontBytes(
    BookEpubSession session,
    String src,
  ) async {
    final cleaned = src.split('?').first.trim();
    final direct = await session.readBytes(cleaned);
    if (direct != null && direct.isNotEmpty) return direct;

    final resolved = BookEpub.resolveHref('', cleaned).path;
    if (resolved.isNotEmpty && resolved != cleaned) {
      return session.readBytes(resolved);
    }
    return null;
  }
}

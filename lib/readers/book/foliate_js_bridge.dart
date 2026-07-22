import 'dart:convert';
import 'dart:typed_data';

class FoliateImportSnapshot {
  const FoliateImportSnapshot({
    required this.title,
    required this.authors,
    required this.sectionCount,
    required this.sampledSections,
    required this.sampledImageOnlySections,
    required this.totalTextLength,
    this.coverBytes,
    this.coverMimeType,
  });

  final String title;
  final List<String> authors;
  final int sectionCount;
  final int sampledSections;
  final int sampledImageOnlySections;
  final int totalTextLength;
  final Uint8List? coverBytes;
  final String? coverMimeType;

  static FoliateImportSnapshot? fromHandlerArguments(List<dynamic> arguments) {
    final payload = _firstMap(arguments);
    if (payload == null) return null;
    final cover = _decodeDataUrl(payload['cover']);
    return FoliateImportSnapshot(
      title: payload['title']?.toString().trim() ?? '',
      authors: _contributors(payload['author']),
      sectionCount: _integer(payload['sectionCount']),
      sampledSections: _integer(payload['sampledSections']),
      sampledImageOnlySections: _integer(payload['sampledImageOnlySections']),
      totalTextLength: _integer(payload['totalTextLength']),
      coverBytes: cover?.bytes,
      coverMimeType: cover?.mimeType,
    );
  }

  static List<String> _contributors(Object? value) {
    final values = value is List ? value : [?value];
    return values
        .map((entry) {
          if (entry is Map) return entry['name']?.toString().trim() ?? '';
          return entry.toString().trim();
        })
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static int _integer(Object? value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text) ?? 0,
    _ => 0,
  };

  static ({String mimeType, Uint8List bytes})? _decodeDataUrl(Object? value) {
    if (value is! String || !value.startsWith('data:')) return null;
    final comma = value.indexOf(',');
    if (comma <= 5) return null;
    final header = value.substring(5, comma);
    final mimeType = header.split(';').first.trim();
    try {
      final body = value.substring(comma + 1);
      final bytes = header.split(';').contains('base64')
          ? base64Decode(body)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
      return (mimeType: mimeType, bytes: bytes);
    } on FormatException {
      return null;
    }
  }
}

/// Typed publication snapshot returned after Foliate finishes opening a book.
class FoliatePublicationSnapshot {
  const FoliatePublicationSnapshot({
    required this.sectionHrefs,
    required this.toc,
  });

  final List<String> sectionHrefs;
  final List<FoliateTocNode> toc;

  factory FoliatePublicationSnapshot.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Foliate publication payload is not a map');
    }
    final rawSections = decoded['sections'];
    if (rawSections is! List) {
      throw const FormatException('Foliate publication has no section list');
    }
    final sections = rawSections
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final rawToc = decoded['toc'];
    return FoliatePublicationSnapshot(
      sectionHrefs: sections,
      toc: rawToc is List
          ? rawToc
                .map(FoliateTocNode.tryParse)
                .whereType<FoliateTocNode>()
                .toList(growable: false)
          : const [],
    );
  }
}

class FoliateTocNode {
  const FoliateTocNode({
    required this.title,
    required this.href,
    this.children = const [],
  });

  final String title;
  final String href;
  final List<FoliateTocNode> children;

  static FoliateTocNode? tryParse(Object? value) {
    if (value is! Map) return null;
    final title = (value['label'] ?? value['title'])?.toString().trim() ?? '';
    final href = value['href']?.toString() ?? '';
    final rawChildren = value['subitems'];
    final children = rawChildren is List
        ? rawChildren
              .map(tryParse)
              .whereType<FoliateTocNode>()
              .toList(growable: false)
        : const <FoliateTocNode>[];
    if (title.isEmpty && href.isEmpty && children.isEmpty) return null;
    return FoliateTocNode(title: title, href: href, children: children);
  }
}

class FoliateRelocation {
  const FoliateRelocation({
    required this.cfi,
    required this.percentage,
    this.chapterHref,
  });

  final String cfi;
  final String? chapterHref;
  final double percentage;

  static FoliateRelocation? fromHandlerArguments(List<dynamic> arguments) {
    final payload = _firstMap(arguments);
    if (payload == null) return null;
    final cfi = payload['cfi']?.toString() ?? '';
    if (cfi.isEmpty) return null;
    final percentage = switch (payload['percentage']) {
      num value => value.toDouble(),
      String value => double.tryParse(value) ?? 0,
      _ => 0.0,
    };
    return FoliateRelocation(
      cfi: cfi,
      chapterHref: payload['chapterHref']?.toString(),
      percentage: percentage.clamp(0.0, 1.0),
    );
  }
}

class FoliateViewportClick {
  const FoliateViewportClick({required this.x, required this.y});

  final double x;
  final double y;

  static FoliateViewportClick? fromHandlerArguments(List<dynamic> arguments) {
    final payload = _firstMap(arguments);
    if (payload == null) return null;
    return FoliateViewportClick(
      x: _coordinate(payload['x'], fallback: 0.5),
      y: _coordinate(payload['y'], fallback: 0.5),
    );
  }

  static double _coordinate(Object? value, {required double fallback}) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    return (parsed ?? fallback).clamp(0.0, 1.0);
  }
}

Map<dynamic, dynamic>? _firstMap(List<dynamic> arguments) {
  if (arguments.isEmpty || arguments.first is! Map) return null;
  return arguments.first as Map<dynamic, dynamic>;
}

/// External `http(s)` / `mailto` link emitted by Foliate's view click handler.
class FoliateExternalLink {
  const FoliateExternalLink({required this.href});

  final String href;

  static FoliateExternalLink? fromHandlerArguments(List<dynamic> arguments) {
    final payload = _firstMap(arguments);
    if (payload == null) return null;
    final href = payload['href']?.toString().trim() ?? '';
    if (href.isEmpty) return null;
    return FoliateExternalLink(href: href);
  }

  Uri? get uri {
    final parsed = Uri.tryParse(href);
    if (parsed == null) return null;
    if (parsed.isScheme('http') ||
        parsed.isScheme('https') ||
        parsed.isScheme('mailto')) {
      return parsed;
    }
    return null;
  }
}

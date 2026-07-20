import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Read-only access to zip-based comic archives (CBZ/ZIP).
///
/// Listing reads only the central directory; entry bytes are decompressed on
/// demand, so hundred-megabyte archives never load fully into memory.
abstract final class ComicArchive {
  static const imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  };

  /// Naturally-sorted image entry names — the comic's page order.
  static Future<List<String>> listPages(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final pages = archive.files
          .where((f) => f.isFile)
          .map((f) => f.name)
          .where(_isImageEntry)
          .toList();
      pages.sort(naturalCompare);
      return pages;
    } finally {
      await input.close();
    }
  }

  /// Decompresses a single entry. Used for covers now and for page reads at
  /// reader time; callers needing many pages should keep one archive open
  /// instead of calling this in a loop.
  static Future<Uint8List?> readEntry(String path, String entry) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final file = archive.findFile(entry);
      final bytes = file?.readBytes();
      return bytes == null ? null : Uint8List.fromList(bytes);
    } finally {
      await input.close();
    }
  }

  static bool _isImageEntry(String name) =>
      imageExtensions.contains(p.extension(name).toLowerCase());

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

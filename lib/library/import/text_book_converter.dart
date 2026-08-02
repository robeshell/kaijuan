import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/reader_models.dart';
import 'import_models.dart';
import 'import_sources.dart';

/// Converts plain text formats into a small, deterministic EPUB understood by
/// the existing Foliate book engine.
///
/// The converter intentionally supports a conservative Markdown subset. It
/// is an import bridge, not a second Markdown renderer; unsupported syntax is
/// escaped and kept readable as text.
abstract final class TextBookConverter {
  static const maxInputBytes = 64 * 1024 * 1024;

  static Future<Uint8List> convert(
    ImportSource source,
    ReaderFormat format,
  ) async {
    if (format != ReaderFormat.txt && format != ReaderFormat.markdown) {
      throw const ImportException('文本转换器收到非文本格式');
    }

    final builder = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in source.openRead()) {
      size += chunk.length;
      if (size > maxInputBytes) {
        throw const ImportException('文本文件过大，暂不支持超过 64 MB 的文件');
      }
      builder.add(chunk);
    }
    final text = _decode(builder.takeBytes());
    final body = format == ReaderFormat.markdown
        ? _markdownBody(text)
        : _plainTextBody(text);
    return _buildEpub(body);
  }

  static String _decode(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    final offset =
        bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? 3
        : 0;
    return utf8.decode(bytes.sublist(offset), allowMalformed: true);
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final value = littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1];
      codeUnits.add(value);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _plainTextBody(String source) {
    final paragraphs = _normalize(source)
        .split(RegExp(r'\n{2,}'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty);
    final html = paragraphs
        .map(
          (paragraph) =>
              '<p>${_escape(paragraph).replaceAll('\n', '<br/>')}</p>',
        )
        .join();
    return html.isEmpty ? '<p></p>' : html;
  }

  static String _markdownBody(String source) {
    final lines = _normalize(source).split('\n');
    final output = StringBuffer();
    var inList = false;
    var inCode = false;

    void closeList() {
      if (!inList) return;
      output.write('</ul>');
      inList = false;
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().startsWith('```')) {
        closeList();
        if (inCode) {
          output.write('</code></pre>');
        } else {
          output.write('<pre><code>');
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        output.write('${_escape(line)}\n');
        continue;
      }
      if (line.trim().isEmpty) {
        closeList();
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line.trim());
      if (heading != null) {
        closeList();
        final level = heading.group(1)!.length;
        output.write('<h$level>${_inline(heading.group(2)!)}</h$level>');
        continue;
      }

      final bullet = RegExp(r'^[-*+]\s+(.+)$').firstMatch(line.trim());
      if (bullet != null) {
        if (!inList) {
          output.write('<ul>');
          inList = true;
        }
        output.write('<li>${_inline(bullet.group(1)!)}</li>');
        continue;
      }

      closeList();
      output.write('<p>${_inline(line.trim())}</p>');
    }
    closeList();
    if (inCode) output.write('</code></pre>');
    return output.length == 0 ? '<p></p>' : output.toString();
  }

  static String _inline(String source) {
    var value = _escape(source);
    value = value.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => '<code>${match.group(1)}</code>',
    );
    value = value.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (match) => '<strong>${match.group(1)}</strong>',
    );
    value = value.replaceAllMapped(
      RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'),
      (match) => '<em>${match.group(1)}</em>',
    );
    return value;
  }

  static String _normalize(String source) =>
      source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  static String _escape(String source) => source
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Uint8List _buildEpub(String body) {
    final archive = Archive();

    void addText(String path, String content) {
      final bytes = utf8.encode(content);
      final file = ArchiveFile(path, bytes.length, bytes)..lastModTime = 0;
      archive.addFile(file);
    }

    // Keep the EPUB package deterministic so re-importing the same text
    // content deduplicates even if the source file was renamed.
    addText('mimetype', 'application/epub+zip');
    addText('META-INF/container.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
    addText('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Imported Text</dc:title>
    <dc:identifier id="uid">urn:kaijuan:imported-text</dc:identifier>
    <dc:language>und</dc:language>
  </metadata>
  <manifest>
    <item id="chapter-1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter-1"/>
  </spine>
</package>''');
    addText('OEBPS/chapter-1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Imported Text</title></head>
  <body>$body</body>
</html>''');
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

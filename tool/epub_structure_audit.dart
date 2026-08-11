import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_structure_supplements.dart';
import 'package:kaijuan/domain/book_structure.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Read-only EPUB structure audit used during structure-index migrations.
///
/// It prints counts and deterministic classification only. No body text is
/// emitted or persisted, so real user books can safely be used as samples.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/epub_structure_audit.dart <file-or-directory> ...',
    );
    exitCode = 64;
    return;
  }

  final files = await _epubs(args);
  if (files.isEmpty) {
    stderr.writeln('No EPUB files found.');
    exitCode = 66;
    return;
  }

  var failures = 0;
  final kinds = <AiBookStructureKind, int>{};
  for (final file in files) {
    try {
      final index = await _EpubStructureReader.read(file.path);
      final manifest = AiBookStructureResolver.resolveIndex(
        index: index,
        isSupplementTitle: _isSupplementTitle,
      );
      kinds.update(manifest.kind, (value) => value + 1, ifAbsent: () => 1);
      final navAnchored = index.navigation
          .where((node) => node.sectionIndex != null)
          .length;
      final headingSections = index.sections
          .where((section) => section.headings.isNotEmpty)
          .length;
      stdout.writeln(
        '${p.basename(file.path)}\t'
        'spine=${index.sections.length}\t'
        'nav=${index.navigation.length}/$navAnchored\t'
        'headingSections=$headingSections\t'
        'headings=${index.headingCount}\t'
        'chars=${index.bodyCharCount}\t'
        'kind=${manifest.kind.name}\t'
        'works=${manifest.works.length}\t'
        'reason=${manifest.reason}',
      );
    } catch (error) {
      failures++;
      stderr.writeln('${p.basename(file.path)}\tERROR\t$error');
    }
  }

  stdout.writeln(
    'SUMMARY\tfiles=${files.length}\tfailures=$failures\t'
    '${kinds.entries.map((entry) => '${entry.key.name}=${entry.value}').join('\t')}',
  );
  if (failures > 0) exitCode = 1;
}

Future<List<File>> _epubs(List<String> inputs) async {
  final result = <File>[];
  for (final input in inputs) {
    final type = await FileSystemEntity.type(input, followLinks: false);
    if (type == FileSystemEntityType.file &&
        p.extension(input).toLowerCase() == '.epub') {
      result.add(File(input));
    } else if (type == FileSystemEntityType.directory) {
      await for (final entity in Directory(
        input,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File &&
            p.extension(entity.path).toLowerCase() == '.epub') {
          result.add(entity);
        }
      }
    }
  }
  result.sort((left, right) => left.path.compareTo(right.path));
  return result;
}

bool _isSupplementTitle(String raw) {
  return matchesAiStructureSupplementTitle(raw);
}

final class _EpubStructureReader {
  static Future<BookStructureIndex> read(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return _readArchive(archive);
    } finally {
      await input.close();
    }
  }

  static BookStructureIndex _readArchive(Archive archive) {
    final entries = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) _normalize(file.name): file,
    };
    final container = _xml(entries, 'META-INF/container.xml');
    final rootfile = container.descendants
        .whereType<XmlElement>()
        .firstWhere((element) => element.name.local == 'rootfile')
        .getAttribute('full-path');
    if (rootfile == null || rootfile.isEmpty) {
      throw const FormatException('EPUB container has no OPF rootfile');
    }

    final opfPath = _normalize(rootfile);
    final opfDir = p.posix.dirname(opfPath);
    final opf = _xml(entries, opfPath);
    final publicationTitle = opf.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'title')
        .map((element) => _text(element.innerText))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final manifest = <String, _ManifestItem>{};
    for (final item in opf.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'item',
    )) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _ManifestItem(
        href: _resolve(opfDir, href),
        mediaType: item.getAttribute('media-type')?.toLowerCase() ?? '',
        properties:
            item.getAttribute('properties')?.split(RegExp(r'\s+')) ?? const [],
      );
    }

    final spine = <_ManifestItem>[];
    for (final itemref in opf.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'itemref',
    )) {
      final item = manifest[itemref.getAttribute('idref')];
      if (item != null && item.isHtml) spine.add(item);
    }
    if (spine.isEmpty) throw const FormatException('EPUB spine is empty');

    final sectionByHref = <String, int>{
      for (var index = 0; index < spine.length; index++)
        _withoutFragment(spine[index].href): index,
    };
    final sections = <BookStructureSection>[];
    for (var index = 0; index < spine.length; index++) {
      final item = spine[index];
      final document = _tryXml(entries, item.href);
      if (document == null) {
        sections.add(
          BookStructureSection(
            sectionIndex: index,
            href: item.href,
            documentTitle: '',
            bodyCharCount: 0,
            headings: const [],
          ),
        );
        continue;
      }
      final title = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'title')
          .map((element) => _text(element.innerText))
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final headings = <BookStructureHeading>[];
      for (final element in document.descendants.whereType<XmlElement>()) {
        final match = RegExp(
          r'^h([1-6])$',
        ).firstMatch(element.name.local.toLowerCase());
        if (match == null) continue;
        final heading = _text(element.innerText);
        if (heading.isEmpty) continue;
        headings.add(
          BookStructureHeading(
            title: heading,
            level: int.parse(match.group(1)!),
            order: headings.length,
            fragment: element.getAttribute('id'),
          ),
        );
      }
      final body = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'body')
          .map((element) => _text(element.innerText))
          .firstWhere((_) => true, orElse: () => '');
      sections.add(
        BookStructureSection(
          sectionIndex: index,
          href: item.href,
          documentTitle: title,
          bodyCharCount: body.length,
          headings: List.unmodifiable(headings),
        ),
      );
    }

    final navItem = manifest.values.cast<_ManifestItem?>().firstWhere(
      (item) => item!.properties.contains('nav'),
      orElse: () => null,
    );
    final navigation = navItem != null
        ? _epub3Navigation(entries, navItem.href, sectionByHref)
        : _ncxNavigation(entries, manifest.values, sectionByHref);
    return BookStructureIndex(
      indexVersion: BookStructureIndex.currentVersion,
      publicationTitle: publicationTitle,
      sections: List.unmodifiable(sections),
      navigation: List.unmodifiable(navigation),
    );
  }

  static List<BookStructureNavigationNode> _epub3Navigation(
    Map<String, ArchiveFile> entries,
    String navPath,
    Map<String, int> sectionByHref,
  ) {
    final document = _tryXml(entries, navPath);
    if (document == null) return const [];
    final nav = document.descendants.whereType<XmlElement>().firstWhere((
      element,
    ) {
      if (element.name.local != 'nav') return false;
      return element.attributes.any(
        (attribute) =>
            attribute.name.local == 'type' &&
            attribute.value.split(RegExp(r'\s+')).contains('toc'),
      );
    }, orElse: () => XmlElement(XmlName('nav')));
    final firstOl = nav.childElements.firstWhere(
      (element) => element.name.local == 'ol',
      orElse: () => XmlElement(XmlName('ol')),
    );
    final nodes = <BookStructureNavigationNode>[];
    _walkHtmlList(
      firstOl,
      parentId: null,
      depth: 0,
      baseDir: p.posix.dirname(navPath),
      sectionByHref: sectionByHref,
      output: nodes,
    );
    return nodes;
  }

  static void _walkHtmlList(
    XmlElement list, {
    required String? parentId,
    required int depth,
    required String baseDir,
    required Map<String, int> sectionByHref,
    required List<BookStructureNavigationNode> output,
  }) {
    for (final li in list.childElements.where(
      (element) => element.name.local == 'li',
    )) {
      final label = li.childElements
          .where(
            (element) =>
                element.name.local == 'a' || element.name.local == 'span',
          )
          .firstOrNull;
      final title = label == null ? '' : _text(label.innerText);
      final rawHref = label?.getAttribute('href') ?? '';
      final href = rawHref.isEmpty ? '' : _resolve(baseDir, rawHref);
      final childList = li.childElements
          .where((element) => element.name.local == 'ol')
          .firstOrNull;
      final id = 'nav-${output.length}';
      if (title.isNotEmpty) {
        output.add(
          BookStructureNavigationNode(
            nodeId: id,
            parentId: parentId,
            title: title,
            depth: depth,
            order: output.length,
            href: href,
            fragment: _fragment(href),
            sectionIndex: sectionByHref[_withoutFragment(href)],
            directChildCount:
                childList?.childElements
                    .where((element) => element.name.local == 'li')
                    .length ??
                0,
          ),
        );
      }
      if (childList != null) {
        _walkHtmlList(
          childList,
          parentId: title.isEmpty ? parentId : id,
          depth: title.isEmpty ? depth : depth + 1,
          baseDir: baseDir,
          sectionByHref: sectionByHref,
          output: output,
        );
      }
    }
  }

  static List<BookStructureNavigationNode> _ncxNavigation(
    Map<String, ArchiveFile> entries,
    Iterable<_ManifestItem> manifest,
    Map<String, int> sectionByHref,
  ) {
    final item = manifest.cast<_ManifestItem?>().firstWhere(
      (candidate) =>
          candidate!.mediaType == 'application/x-dtbncx+xml' ||
          p.extension(candidate.href).toLowerCase() == '.ncx',
      orElse: () => null,
    );
    if (item == null) return const [];
    final document = _tryXml(entries, item.href);
    if (document == null) return const [];
    final navMap = document.descendants.whereType<XmlElement>().firstWhere(
      (element) => element.name.local == 'navMap',
      orElse: () => XmlElement(XmlName('navMap')),
    );
    final output = <BookStructureNavigationNode>[];
    _walkNcx(
      navMap,
      parentId: null,
      depth: 0,
      baseDir: p.posix.dirname(item.href),
      sectionByHref: sectionByHref,
      output: output,
    );
    return output;
  }

  static void _walkNcx(
    XmlElement parent, {
    required String? parentId,
    required int depth,
    required String baseDir,
    required Map<String, int> sectionByHref,
    required List<BookStructureNavigationNode> output,
  }) {
    for (final point in parent.childElements.where(
      (element) => element.name.local == 'navPoint',
    )) {
      final textElement = point.descendants.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == 'text',
        orElse: () => XmlElement(XmlName('text')),
      );
      final content = point.childElements.firstWhere(
        (element) => element.name.local == 'content',
        orElse: () => XmlElement(XmlName('content')),
      );
      final title = _text(textElement.innerText);
      final rawHref = content.getAttribute('src') ?? '';
      final href = rawHref.isEmpty ? '' : _resolve(baseDir, rawHref);
      final children = point.childElements
          .where((element) => element.name.local == 'navPoint')
          .length;
      final id = 'nav-${output.length}';
      if (title.isNotEmpty) {
        output.add(
          BookStructureNavigationNode(
            nodeId: id,
            parentId: parentId,
            title: title,
            depth: depth,
            order: output.length,
            href: href,
            fragment: _fragment(href),
            sectionIndex: sectionByHref[_withoutFragment(href)],
            directChildCount: children,
          ),
        );
      }
      _walkNcx(
        point,
        parentId: title.isEmpty ? parentId : id,
        depth: title.isEmpty ? depth : depth + 1,
        baseDir: baseDir,
        sectionByHref: sectionByHref,
        output: output,
      );
    }
  }

  static XmlDocument _xml(Map<String, ArchiveFile> entries, String path) {
    final document = _tryXml(entries, path);
    if (document == null) {
      throw FormatException('Missing or invalid XML: $path');
    }
    return document;
  }

  static XmlDocument? _tryXml(Map<String, ArchiveFile> entries, String path) {
    final normalized = _normalize(path);
    final entry =
        entries[normalized] ??
        entries.entries
            .where(
              (candidate) =>
                  candidate.key.toLowerCase() == normalized.toLowerCase(),
            )
            .map((candidate) => candidate.value)
            .firstOrNull;
    final bytes = entry?.readBytes();
    if (bytes == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  static String _resolve(String baseDir, String href) {
    final normalizedHref = href.replaceAll('\\', '/');
    String decoded;
    try {
      decoded = Uri.decodeFull(normalizedHref);
    } on ArgumentError {
      decoded = normalizedHref;
    }
    final pathPart = decoded.split('?').first;
    final fragment = _fragment(pathPart);
    final filePart = _withoutFragment(pathPart);
    final resolved = _normalize(
      baseDir == '.' || baseDir.isEmpty
          ? filePart
          : p.posix.join(baseDir, filePart),
    );
    return fragment == null ? resolved : '$resolved#$fragment';
  }

  static String _normalize(String value) => p.posix
      .normalize(value.replaceAll('\\', '/'))
      .replaceFirst(RegExp(r'^/+'), '');

  static String _withoutFragment(String href) => href.split('#').first;

  static String? _fragment(String href) {
    final separator = href.indexOf('#');
    return separator < 0 || separator + 1 >= href.length
        ? null
        : href.substring(separator + 1);
  }

  static String _text(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

final class _ManifestItem {
  const _ManifestItem({
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String href;
  final String mediaType;
  final List<String> properties;

  bool get isHtml {
    if (mediaType == 'image/svg+xml') return false;
    return mediaType.contains('html') ||
        p.extension(href).toLowerCase() == '.html' ||
        p.extension(href).toLowerCase() == '.htm' ||
        p.extension(href).toLowerCase() == '.xhtml';
  }
}

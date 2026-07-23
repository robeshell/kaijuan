import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/import/comic_archive.dart';
import 'package:kaijuan/library/import/epub_import_router.dart';
import 'package:kaijuan/readers/book/book_loopback_server.dart';
import 'package:kaijuan/readers/book/book_rendition_session.dart';
import 'package:kaijuan/readers/book/foliate_import_probe.dart';
import 'package:kaijuan/readers/book/foliate_js_bridge.dart';
import 'package:path/path.dart' as p;

final _pngBytes = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x00,
  0x03,
  0x00,
  0x01,
  0x00,
  0x05,
  0xFE,
  0xD4,
  0xEF,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Future<File> _writeReflowEpubWithCover(Directory dir, String name) async {
  final archive = Archive();
  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
  addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Illustrated Book</dc:title>
    <dc:identifier id="uid">urn:test:illustrated</dc:identifier>
    <dc:language>zh</dc:language>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="cover-image" href="cover.png" media-type="image/png" properties="cover-image"/>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''');
  addText('OEBPS/chap1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Illustrated Book</title></head>
<body>
<p>第一章正文。This reflow chapter has plenty of text.</p>
<p><img src="cover.png" alt="illustration"/></p>
</body>
</html>''');
  archive.addFile(ArchiveFile('OEBPS/cover.png', _pngBytes.length, _pngBytes));

  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

Future<File> _writeImageOnlyEpub(Directory dir, String name) async {
  final archive = Archive();
  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
  addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Image Only</dc:title>
  </metadata>
  <manifest>
    <item id="p1" href="p1.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="p1"/>
  </spine>
</package>''');
  archive.addFile(ArchiveFile('OEBPS/p1.png', _pngBytes.length, _pngBytes));
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  _NetworkTestBinding();

  late Directory tempRoot;
  final sessions = <BookRenditionSession>[];

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kaika_foliate_probe_');
  });

  tearDown(() async {
    for (final session in sessions) {
      await session.close();
    }
    sessions.clear();
    await BookLoopbackServer.debugStop();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<BookRenditionSession> openSession(File bookFile) async {
    final session = await BookRenditionSession.open(bookFile);
    sessions.add(session);
    return session;
  }

  test('metadata probe URL includes Foliate Loader style contract', () async {
    final bookFile = await _writeReflowEpubWithCover(tempRoot, 'style.epub');
    final session = await openSession(bookFile);
    final probeUri = FoliateJsImportProbe.buildProbeUri(session);

    expect(probeUri.queryParameters['url'], isNotNull);
    expect(probeUri.queryParameters['style'], isNotNull);

    final style = jsonDecode(probeUri.queryParameters['style']!) as Map<String, dynamic>;
    expect(style['allowScript'], isFalse);
    expect(jsonDecode(probeUri.queryParameters['url']!), session.bookUri.toString());
  });

  test('epub.js Loader no longer requires style query parameter', () {
    final loaderSource = File(
      'assets/book/foliate-js/src/epub.js',
    ).readAsStringSync();
    expect(loaderSource, contains('styleParam'));
    expect(
      loaderSource,
      isNot(contains("JSON.parse(urlParams.get('style')).allowScript")),
    );
  });

  test('illustrated reflow EPUB metrics classify as book once probe succeeds', () async {
    final bookFile = await _writeReflowEpubWithCover(tempRoot, 'illustrated.epub');
    final snapshot = reflowProbeSnapshot(
      title: 'Illustrated Book',
      sectionCount: 1,
      sampledSections: 1,
      sampledImageOnlySections: 0,
      totalTextLength: 120,
    );
    final imageCount = (await ComicArchive.listPagesDetailed(bookFile.path))
        .pageNames
        .length;

    expect(imageCount, greaterThan(0));
    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: snapshot.sectionCount,
        sampledSectionCount: snapshot.sampledSections,
        sampledImageOnlySectionCount: snapshot.sampledImageOnlySections,
        totalBookText: snapshot.totalTextLength,
        imageCount: imageCount,
      ),
      ReaderKind.book,
    );
  });

  test('image-only EPUB metrics classify as comic once probe succeeds', () async {
    final bookFile = await _writeImageOnlyEpub(tempRoot, 'pages.epub');
    final snapshot = imageProbeSnapshot(sectionCount: 1);
    final imageCount = (await ComicArchive.listPagesDetailed(bookFile.path))
        .pageNames
        .length;

    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: snapshot.sectionCount,
        sampledSectionCount: snapshot.sampledSections,
        sampledImageOnlySectionCount: snapshot.sampledImageOnlySections,
        totalBookText: snapshot.totalTextLength,
        imageCount: imageCount,
      ),
      ReaderKind.comic,
    );
  });
}

FoliateImportSnapshot reflowProbeSnapshot({
  required String title,
  required int sectionCount,
  required int sampledSections,
  required int sampledImageOnlySections,
  required int totalTextLength,
}) => FoliateImportSnapshot(
  title: title,
  authors: const [],
  sectionCount: sectionCount,
  sampledSections: sampledSections,
  sampledImageOnlySections: sampledImageOnlySections,
  totalTextLength: totalTextLength,
);

FoliateImportSnapshot imageProbeSnapshot({required int sectionCount}) =>
    FoliateImportSnapshot(
      title: 'Image Only',
      authors: const [],
      sectionCount: sectionCount,
      sampledSections: sectionCount,
      sampledImageOnlySections: sectionCount,
      totalTextLength: 0,
    );

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

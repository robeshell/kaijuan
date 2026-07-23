import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/import/epub_import_router.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/readers/book/foliate_import_probe.dart';
import 'package:path/path.dart' as p;

import 'support/fake_epub_import_probe.dart';

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

Future<File> _writeReflowEpub(
  Directory dir,
  String name, {
  String title = '测试图书',
}) async {
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
    <dc:title>$title</dc:title>
    <dc:identifier id="uid">urn:test:book</dc:identifier>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''');
  addText('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title></head>
<body><nav><ol><li><a href="chap1.xhtml">$title</a></li></ol></nav></body>
</html>''');
  addText('OEBPS/chap1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title></head>
<body>
<p>第一章正文。Hello book reflow.</p>
</body>
</html>''');

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

Future<File> _writeImageWrapperEpub(Directory dir, String name) async {
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
    <dc:title>Manga Wrapper</dc:title>
  </metadata>
  <manifest>
    <item id="p1" href="p1.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="p1.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="p1"/>
  </spine>
</package>''');
  addText('OEBPS/p1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>1</title></head>
<body><img src="p1.png" alt=""/></body>
</html>''');
  archive.addFile(ArchiveFile('OEBPS/p1.png', _pngBytes.length, _pngBytes));
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

Future<File> _writeUnrecognizableEpub(Directory dir, String name) async {
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
    <dc:title>Empty</dc:title>
  </metadata>
  <manifest>
    <item id="note" href="note.txt" media-type="text/plain"/>
  </manifest>
  <spine>
    <itemref idref="note"/>
  </spine>
</package>''');
  addText('OEBPS/note.txt', 'not a readable chapter');
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  late Directory tempRoot;
  late AppDatabase database;
  late EpubImportRouter router;
  late FakeEpubImportProbe probe;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kaika_epub_router_');
    database = AppDatabase(NativeDatabase.memory());
    probe = FakeEpubImportProbe((path) {
      // Book import probes the staged copy (hash-named), not the source basename.
      final name = p.basename(path);
      if (name == 'manga.epub') return imageSnapshot();
      return reflowSnapshot(title: '小说');
    });
    router = EpubImportRouter(
      comicImport: ComicImportService(
        database: database,
        supportDirectory: tempRoot,
      ),
      bookImport: BookImportService(
        database: database,
        supportDirectory: tempRoot,
        probe: probe,
      ),
    );
  });

  tearDown(() async {
    await database.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('detects reflow EPUB as book', () async {
    final file = await _writeReflowEpub(tempRoot, 'novel.epub');
    expect(await EpubImportRouter.detectKind(file.path), ReaderKind.book);
  });

  test('detects image-only EPUB as comic', () async {
    final file = await _writeImageOnlyEpub(tempRoot, 'manga.epub');
    expect(await EpubImportRouter.detectKind(file.path), ReaderKind.comic);
  });

  test('detects XHTML image-wrapper EPUB as comic', () async {
    final file = await _writeImageWrapperEpub(tempRoot, 'wrapper.epub');
    expect(await EpubImportRouter.detectKind(file.path), ReaderKind.comic);
  });

  test('classifies illustrated boxed set by sampled section count', () {
    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: 270,
        sampledSectionCount: 8,
        sampledImageOnlySectionCount: 1,
        totalBookText: 4041,
        imageCount: 2,
      ),
      ReaderKind.book,
    );
  });

  test('cover or sparse illustrations do not turn a text EPUB into comic', () {
    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: 12,
        sampledSectionCount: 12,
        sampledImageOnlySectionCount: 2,
        totalBookText: 120,
        imageCount: 8,
      ),
      ReaderKind.book,
    );
  });

  test('mostly image-only spine routes to comic', () {
    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: 20,
        sampledSectionCount: 10,
        sampledImageOnlySectionCount: 9,
        totalBookText: 100,
        imageCount: 20,
      ),
      ReaderKind.comic,
    );
  });

  test('probe failure with package images does not route to comic', () {
    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: 0,
        sampledSectionCount: 0,
        sampledImageOnlySectionCount: 0,
        totalBookText: 0,
        imageCount: 19,
      ),
      isNull,
    );
  });

  test('text-only spine routes to book even without listed images', () {
    expect(
      EpubImportRouter.classifyMetrics(
        sectionCount: 8,
        sampledSectionCount: 8,
        sampledImageOnlySectionCount: 0,
        totalBookText: 8000,
        imageCount: 0,
      ),
      ReaderKind.book,
    );
  });

  test('imports reflow EPUB as kind=book', () async {
    final file = await _writeReflowEpub(tempRoot, 'novel.epub', title: '小说');
    final result = await router.importPaths([file.path]);
    expect(result.added, 1);
    expect(result.failures, isEmpty);

    final items = await database.select(database.readingItems).get();
    expect(items, hasLength(1));
    expect(items.single.kind, ReaderKind.book.storageValue);
    expect(items.single.title, '小说');
    expect(
      probe.callCount,
      1,
      reason: 'kind uses Dart; Foliate runs once for book metadata',
    );
  });

  test('imports image-only EPUB as kind=comic', () async {
    final file = await _writeImageOnlyEpub(tempRoot, 'manga.epub');
    final result = await router.importPaths([file.path]);
    expect(result.added, 1);
    expect(result.failures, isEmpty);

    final items = await database.select(database.readingItems).get();
    expect(items, hasLength(1));
    expect(items.single.kind, ReaderKind.comic.storageValue);
    expect(probe.callCount, 0, reason: 'comic path must not open Foliate');
  });

  test('fails unrecognizable EPUB with friendly reason', () async {
    final file = await _writeUnrecognizableEpub(tempRoot, 'empty.epub');
    final result = await router.importPaths([file.path]);
    expect(result.added, 0);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.reason, contains('无法识别'));
  });

  test('book Foliate failure does not fall back to comic', () async {
    final file = await _writeReflowEpub(tempRoot, 'probe-fail.epub');
    final failingProbe = FakeEpubImportProbe(
      (_) => throw const FoliateImportException('Foliate 解析失败：allowScript'),
    );
    final failingRouter = EpubImportRouter(
      comicImport: ComicImportService(
        database: database,
        supportDirectory: tempRoot,
      ),
      bookImport: BookImportService(
        database: database,
        supportDirectory: tempRoot,
        probe: failingProbe,
      ),
    );

    final result = await failingRouter.importPaths([file.path]);
    expect(result.added, 0);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.reason, contains('allowScript'));

    final items = await database.select(database.readingItems).get();
    expect(items, isEmpty);
  });
}

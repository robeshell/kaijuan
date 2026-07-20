import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/import/book_import_service.dart';
import 'package:kaika/library/import/comic_import_service.dart';
import 'package:kaika/library/persistence/app_database.dart';
import 'package:kaika/presentation/controllers/library_controller.dart';
import 'package:kaika/readers/book/book_epub.dart';
import 'package:kaika/readers/book/book_models.dart';
import 'package:path/path.dart' as p;

/// Minimal reflow EPUB: container + OPF + one xhtml chapter.
Future<File> _writeReflowEpub(
  Directory dir,
  String name, {
  String title = '测试图书',
  String body = '第一章正文。Hello book reflow.',
}) async {
  final archive = Archive();

  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
  );
  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:identifier id="uid">urn:test:book</dc:identifier>
  </metadata>
  <manifest>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''',
  );
  addText(
    'OEBPS/chap1.xhtml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title></head>
<body>
<h1>$title</h1>
<p>$body</p>
</body>
</html>''',
  );

  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

/// Image-only EPUB (no text spine) should fail book import.
Future<File> _writeImageOnlyEpub(Directory dir, String name) async {
  final png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
  final archive = Archive();
  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
  );
  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
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
</package>''',
  );
  archive.addFile(ArchiveFile('OEBPS/p1.png', png.length, png));
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  late Directory tempRoot;
  late AppDatabase database;
  late BookImportService importService;
  late LibraryController controller;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kaika_book_');
    database = AppDatabase(NativeDatabase.memory());
    importService = BookImportService(
      database: database,
      supportDirectory: tempRoot,
    );
    controller = LibraryController(
      database: database,
      comicImportService: ComicImportService(
        database: database,
        supportDirectory: tempRoot,
      ),
      bookImportService: importService,
      importExtensions: const ['epub'],
    );
  });

  tearDown(() async {
    await database.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('BookEpub parses reflow spine to plain text sections', () async {
    final file = await _writeReflowEpub(tempRoot, 'plain.epub', title: 'Hello');
    final doc = await BookEpub.open(file.path);
    expect(doc.title, 'Hello');
    expect(doc.sectionCount, 1);
    expect(doc.sections.first.plainText, contains('第一章正文'));
  });

  test('import reflow EPUB as kind=book with content-hash dedup', () async {
    final file = await _writeReflowEpub(tempRoot, 'novel.epub', title: '小说');
    final r1 = await controller.importPaths([file.path]);
    expect(r1.added, 1);
    expect(r1.failures, isEmpty);

    final entries = await controller.watchLibraryEntries().first;
    expect(entries, hasLength(1));
    final item = entries.first.item;
    expect(item.kind, ReaderKind.book.storageValue);
    expect(item.format, ReaderFormat.epub.storageValue);
    expect(item.title, '小说');
    expect(item.pageCount, 1);
    expect(File(item.filePath).existsSync(), isTrue);

    final r2 = await controller.importPaths([file.path]);
    expect(r2.added, 0);
    expect(r2.updated, 1);
    final after = await controller.watchLibraryEntries().first;
    expect(after, hasLength(1));
  });

  test('image-only EPUB fails book import with friendly reason', () async {
    final file = await _writeImageOnlyEpub(tempRoot, 'manga.epub');
    final result = await importService.importPaths([file.path]);
    expect(result.added, 0);
    expect(result.failures, hasLength(1));
    expect(result.failures.first.reason, contains('页图'));
  });

  test('BookLocator encode/decode and validate', () {
    final loc = const BookLocator(sectionIndex: 2, progressInSection: 0.4);
    final decoded = BookLocator.tryDecode(loc.encode());
    expect(decoded, isNotNull);
    expect(decoded!.sectionIndex, 2);
    expect(decoded.progressInSection, closeTo(0.4, 1e-9));
    expect(decoded.validated(sectionCount: 5)!.sectionIndex, 2);
    expect(decoded.validated(sectionCount: 2), isNull);
  });
}

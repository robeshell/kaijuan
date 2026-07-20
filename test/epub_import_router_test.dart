import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/import/book_import_service.dart';
import 'package:kaika/library/import/comic_import_service.dart';
import 'package:kaika/library/import/epub_import_router.dart';
import 'package:kaika/library/persistence/app_database.dart';
import 'package:path/path.dart' as p;

final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
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
<p>第一章正文。Hello book reflow.</p>
</body>
</html>''',
  );

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
    <dc:title>Empty</dc:title>
  </metadata>
  <manifest>
    <item id="note" href="note.txt" media-type="text/plain"/>
  </manifest>
  <spine>
    <itemref idref="note"/>
  </spine>
</package>''',
  );
  addText('OEBPS/note.txt', 'not a readable chapter');
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  late Directory tempRoot;
  late AppDatabase database;
  late EpubImportRouter router;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kaika_epub_router_');
    database = AppDatabase(NativeDatabase.memory());
    router = EpubImportRouter(
      comicImport: ComicImportService(
        database: database,
        supportDirectory: tempRoot,
      ),
      bookImport: BookImportService(
        database: database,
        supportDirectory: tempRoot,
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

  test('imports reflow EPUB as kind=book', () async {
    final file = await _writeReflowEpub(tempRoot, 'novel.epub', title: '小说');
    final result = await router.importPaths([file.path]);
    expect(result.added, 1);
    expect(result.failures, isEmpty);

    final items = await database.select(database.readingItems).get();
    expect(items, hasLength(1));
    expect(items.single.kind, ReaderKind.book.storageValue);
    expect(items.single.title, '小说');
  });

  test('imports image-only EPUB as kind=comic', () async {
    final file = await _writeImageOnlyEpub(tempRoot, 'manga.epub');
    final result = await router.importPaths([file.path]);
    expect(result.added, 1);
    expect(result.failures, isEmpty);

    final items = await database.select(database.readingItems).get();
    expect(items, hasLength(1));
    expect(items.single.kind, ReaderKind.comic.storageValue);
  });

  test('fails unrecognizable EPUB with friendly reason', () async {
    final file = await _writeUnrecognizableEpub(tempRoot, 'empty.epub');
    final result = await router.importPaths([file.path]);
    expect(result.added, 0);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.reason, contains('无法识别'));
  });
}

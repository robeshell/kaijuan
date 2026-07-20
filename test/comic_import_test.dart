import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/import/book_import_service.dart';
import 'package:kaika/library/import/comic_archive.dart';
import 'package:kaika/library/import/comic_import_service.dart';
import 'package:kaika/library/persistence/app_database.dart';
import 'package:kaika/presentation/controllers/library_controller.dart';
import 'package:path/path.dart' as p;

/// Minimal 1x1 PNG (valid for zip entry + cover extract).
final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<File> _writeZip(Directory dir, String name, List<String> pages) async {
  final archive = Archive();
  for (final page in pages) {
    archive.addFile(ArchiveFile(page, _pngBytes.length, _pngBytes));
  }
  final bytes = ZipEncoder().encode(archive);
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void main() {
  late Directory tempRoot;
  late AppDatabase database;
  late ComicImportService importService;
  late LibraryController controller;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kaika_import_');
    database = AppDatabase(NativeDatabase.memory());
    importService = ComicImportService(
      database: database,
      supportDirectory: tempRoot,
    );
    controller = LibraryController(
      database: database,
      comicImportService: importService,
      bookImportService: BookImportService(
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

  test('imports cbz with pageCount and page-order version', () async {
    final source = await _writeZip(tempRoot, 'Demo Comic.cbz', [
      'page10.png',
      'page2.png',
      'page1.png',
    ]);

    final result = await controller.importPaths([source.path]);
    expect(result.added, 1);
    expect(result.updated, 0);
    expect(result.failures, isEmpty);

    final items = await controller.watchLibraryEntries().first;
    expect(items, hasLength(1));
    final item = items.single.item;
    expect(item.title, 'Demo Comic');
    expect(item.kind, ReaderKind.comic.storageValue);
    expect(item.format, ReaderFormat.cbz.storageValue);
    expect(item.pageCount, 3);
    expect(item.pageOrderVersion, ComicPageOrder.version);
    expect(File(item.filePath).existsSync(), isTrue);
    expect(item.coverPath, isNotNull);
    expect(File(item.coverPath!).existsSync(), isTrue);

    // Cover must be the first page under natural order (page1, not page10).
    final pages = await ComicArchive.listPages(item.filePath);
    expect(pages.first, 'page1.png');
  });

  test('re-import of same content updates instead of duplicating', () async {
    final source = await _writeZip(tempRoot, 'same.cbz', ['a.png', 'b.png']);
    final first = await controller.importPaths([source.path]);
    expect(first.added, 1);

    final copy = await source.copy(p.join(tempRoot.path, 'same-copy.cbz'));
    final second = await controller.importPaths([copy.path]);
    expect(second.added, 0);
    expect(second.updated, 1);

    final items = await controller.watchLibraryEntries().first;
    expect(items, hasLength(1));
    expect(items.single.item.pageCount, 2);
  });

  test('delete removes row and content-addressed files', () async {
    final source = await _writeZip(tempRoot, 'gone.cbz', ['x.png']);
    await controller.importPaths([source.path]);
    final item = (await controller.watchLibraryEntries().first).single.item;
    final archivePath = item.filePath;
    final coverPath = item.coverPath!;

    await controller.deleteItem(item.id);

    expect(await controller.watchLibraryEntries().first, isEmpty);
    expect(File(archivePath).existsSync(), isFalse);
    expect(File(coverPath).existsSync(), isFalse);
  });

  test('rejects archives with no image pages', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('readme.txt', 5, Uint8List.fromList('hello'.codeUnits)));
    final bytes = ZipEncoder().encode(archive);
    final file = File(p.join(tempRoot.path, 'empty.zip'));
    await file.writeAsBytes(bytes, flush: true);

    final result = await controller.importPaths([file.path]);
    expect(result.added, 0);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.reason, contains('找不到图片页'));
  });

  test('imports image EPUB using OPF spine order and dc:title', () async {
    final epub = await _writeImageEpub(
      tempRoot,
      'pack.epub',
      title: 'Spine Comic',
      // Intentionally reverse natural names so spine order is proven.
      pages: [
        ('page_b.png', 'OEBPS/images/page_b.png'),
        ('page_a.png', 'OEBPS/images/page_a.png'),
      ],
    );

    final result = await controller.importPaths([epub.path]);
    expect(result.added, 1);
    expect(result.failures, isEmpty);

    final item = (await controller.watchLibraryEntries().first).single.item;
    expect(item.format, ReaderFormat.epub.storageValue);
    expect(item.title, 'Spine Comic');
    expect(item.pageCount, 2);

    final pages = await ComicArchive.listPages(item.filePath);
    expect(pages, [
      'OEBPS/images/page_b.png',
      'OEBPS/images/page_a.png',
    ]);
  });
}

/// Minimal image-based EPUB: container + OPF + XHTML wrappers per page.
Future<File> _writeImageEpub(
  Directory dir,
  String name, {
  required String title,
  required List<(String id, String imagePath)> pages,
}) async {
  final archive = Archive();
  archive.addFile(
    ArchiveFile(
      'mimetype',
      20,
      Uint8List.fromList('application/epub+zip'.codeUnits),
    ),
  );
  const container = '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
  archive.addFile(
    ArchiveFile(
      'META-INF/container.xml',
      container.length,
      Uint8List.fromList(container.codeUnits),
    ),
  );

  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < pages.length; i++) {
    final id = pages[i].$1.replaceAll('.', '_');
    final imgPath = pages[i].$2;
    final htmlName = 'OEBPS/p$i.xhtml';
    final relImg = imgPath.replaceFirst('OEBPS/', '');
    final html = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><img src="$relImg"/></body>
</html>
''';
    archive.addFile(
      ArchiveFile(htmlName, html.length, Uint8List.fromList(html.codeUnits)),
    );
    archive.addFile(ArchiveFile(imgPath, _pngBytes.length, _pngBytes));
    manifest.writeln(
      '    <item id="html_$id" href="p$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    manifest.writeln(
      '    <item id="img_$id" href="$relImg" media-type="image/png"/>',
    );
    spine.writeln('    <itemref idref="html_$id"/>');
  }

  final opf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:identifier id="uid">test-epub</dc:identifier>
  </metadata>
  <manifest>
$manifest
  </manifest>
  <spine>
$spine
  </spine>
</package>
''';
  archive.addFile(
    ArchiveFile(
      'OEBPS/content.opf',
      opf.length,
      Uint8List.fromList(opf.codeUnits),
    ),
  );

  final bytes = ZipEncoder().encode(archive);
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

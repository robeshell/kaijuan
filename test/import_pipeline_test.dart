import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/import/import_sources.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/library_controller.dart';
import 'package:path/path.dart' as p;

import 'support/fake_epub_import_probe.dart';

Future<File> _writeCbz(Directory directory, String name) async {
  final archive = Archive()..addFile(ArchiveFile('001.png', 3, [1, 2, 3]));
  final file = File(p.join(directory.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  late Directory tempRoot;
  Directory? downloadsRoot;
  late AppDatabase database;
  late LibraryController controller;

  setUp(() async {
    downloadsRoot = null;
    tempRoot = await Directory.systemTemp.createTemp('kaijuan_import_');
    database = AppDatabase(NativeDatabase.memory());
    final book = BookImportService(
      database: database,
      supportDirectory: tempRoot,
      probe: FakeEpubImportProbe((_) => reflowSnapshot(title: '通用图书格式')),
    );
    controller = LibraryController(
      database: database,
      documentsDirectoryProvider: () async => tempRoot,
      downloadsDirectoryProvider: () async => downloadsRoot,
      directoryPicker: ({String? initialDirectory}) async => tempRoot.path,
      comicImportService: ComicImportService(
        database: database,
        supportDirectory: tempRoot,
      ),
      bookImportService: book,
    );
  });

  tearDown(() async {
    await database.close();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    if (downloadsRoot != null && await downloadsRoot!.exists()) {
      await downloadsRoot!.delete(recursive: true);
    }
  });

  test('format and method remain independent', () {
    expect(ReaderFormat.fromFileName('novel.FB2'), ReaderFormat.fb2);
    expect(ReaderFormat.fromFileName('novel.fb2.zip'), ReaderFormat.fb2);
    expect(ReaderFormat.fromFileName('novel.AZW3'), ReaderFormat.azw3);
    expect(ReaderFormat.fromFileName('novel.txt'), ReaderFormat.txt);

    final picked = ImportCandidate(
      source: LocalFileImportSource.picked('/tmp/novel.fb2'),
    );
    final scanned = ImportCandidate(
      source: LocalFileImportSource.scanned('/tmp/novel.fb2'),
    );
    expect(picked.format, ReaderFormat.fb2);
    expect(picked.method, ImportMethod.localFile);
    expect(scanned.format, ReaderFormat.fb2);
    expect(scanned.method, ImportMethod.directoryScan);
    final shared = ImportCandidate(
      source: BufferedImportSource(
        bytes: [1, 2, 3],
        displayName: 'shared.txt',
        method: ImportMethod.share,
      ),
    );
    expect(shared.format, ReaderFormat.txt);
    expect(shared.method, ImportMethod.share);
  });

  test(
    'directory scan uses the same comic pipeline and ignores unsupported files',
    () async {
      final nested = Directory(p.join(tempRoot.path, 'nested'))
        ..createSync(recursive: true);
      await _writeCbz(nested, 'scan.cbz');
      await File(p.join(nested.path, 'notes.docx')).writeAsString('ignore me');

      final result = await controller.importDirectory(tempRoot.path);

      expect(result.added, 1);
      expect(result.failures, isEmpty);
      final entries = await controller.watchLibraryEntries().first;
      expect(entries, hasLength(1));
      expect(entries.single.item.format, ReaderFormat.cbz.storageValue);
      final staging = Directory(p.join(tempRoot.path, '.import-staging'));
      expect(
        await staging.exists() ? await staging.list().toList() : const [],
        isEmpty,
      );
    },
  );

  test(
    'directory scan treats missing or empty sources as an empty result',
    () async {
      final missing = p.join(tempRoot.path, 'does-not-exist');
      expect((await controller.importDirectory(missing)).isEmpty, isTrue);
      expect((await controller.importDirectory(tempRoot.path)).isEmpty, isTrue);
      expect((await controller.scanDefaultDirectory()).isEmpty, isTrue);
    },
  );

  test('automatic scan uses the app documents directory', () async {
    await _writeCbz(tempRoot, 'auto.cbz');

    final result = await controller.scanDefaultDirectory();

    expect(result.added, 1);
    expect(result.failures, isEmpty);
  });

  test('automatic scan can review paths before importing them', () async {
    await _writeCbz(tempRoot, 'review.cbz');

    final paths = await controller.discoverDefaultImportPaths();

    expect(paths, hasLength(1));
    expect(await controller.watchLibraryEntries().first, isEmpty);

    final result = await controller.importScannedPaths(paths);

    expect(result.added, 1);
    expect(result.failures, isEmpty);
  });

  test(
    'reports unavailable downloads and can discover an authorized folder',
    () async {
      await _writeCbz(tempRoot, 'authorized.cbz');

      final discovery = await controller.discoverDefaultImport();
      final grantedPaths = await controller.pickDirectoryForReview(
        initialDirectory: discovery.downloadsPath,
      );

      expect(discovery.needsDownloadsAuthorization, isTrue);
      expect(grantedPaths, hasLength(1));
      expect(p.basename(grantedPaths!.single), 'authorized.cbz');
      expect(await controller.watchLibraryEntries().first, isEmpty);
    },
  );

  test('automatic scan also includes the system downloads directory', () async {
    downloadsRoot = await Directory.systemTemp.createTemp('kaijuan_downloads_');
    await _writeCbz(downloadsRoot!, 'downloaded.cbz');

    final result = await controller.scanDefaultDirectory();

    expect(result.added, 1);
    expect(result.failures, isEmpty);
  });

  test('Foliate book formats share one book import route', () async {
    const names = ['book.fb2', 'book.mobi', 'book.azw3', 'book.pdf'];
    final candidates = <ImportCandidate>[];
    for (var i = 0; i < names.length; i++) {
      final file = File(p.join(tempRoot.path, names[i]));
      await file.writeAsBytes([i + 1, 2, 3, 4], flush: true);
      candidates.add(
        ImportCandidate(source: LocalFileImportSource.picked(file.path)),
      );
    }
    final fbz = File(p.join(tempRoot.path, 'boxed.fb2.zip'));
    await fbz.writeAsBytes([9, 8, 7, 6], flush: true);
    candidates.add(
      ImportCandidate(source: LocalFileImportSource.picked(fbz.path)),
    );

    final result = await controller.importCandidates(candidates);

    expect(result.added, names.length + 1);
    expect(result.failures, isEmpty);
    final entries = await controller.watchLibraryEntries().first;
    expect(entries, hasLength(names.length + 1));
    expect(
      entries.map((entry) => entry.item.format),
      containsAll([
        ReaderFormat.fb2.storageValue,
        ReaderFormat.mobi.storageValue,
        ReaderFormat.azw3.storageValue,
        ReaderFormat.pdf.storageValue,
      ]),
    );
    final fbzItem = entries.firstWhere(
      (entry) =>
          entry.item.format == ReaderFormat.fb2.storageValue &&
          entry.item.filePath.endsWith('.fbz'),
    );
    expect(fbzItem.item.filePath, endsWith('.fbz'));
  });

  test('TXT and Markdown convert into the shared book pipeline', () async {
    final txt = File(p.join(tempRoot.path, 'plain.txt'));
    await txt.writeAsString('第一段\n\n第二段 <escaped>');
    final markdown = File(p.join(tempRoot.path, 'notes.md'));
    await markdown.writeAsString('# 标题\n\n**重点** and `code`');

    final result = await controller.importPaths([txt.path, markdown.path]);

    expect(result.added, 2);
    expect(result.failures, isEmpty);
    final entries = await controller.watchLibraryEntries().first;
    expect(entries, hasLength(2));
    final formats = entries.map((entry) => entry.item.format).toSet();
    expect(
      formats,
      containsAll([
        ReaderFormat.txt.storageValue,
        ReaderFormat.markdown.storageValue,
      ]),
    );
    expect(
      entries.every((entry) => entry.item.filePath.endsWith('.epub')),
      isTrue,
    );
    expect(
      entries.map((entry) => entry.item.title),
      containsAll(['plain', 'notes']),
    );
    final plain = entries.firstWhere((entry) => entry.item.format == 'txt');
    final generated = ZipDecoder().decodeBytes(
      await File(plain.item.filePath).readAsBytes(),
    );
    final chapter = generated.findFile('OEBPS/chapter-1.xhtml');
    expect(chapter, isNotNull);
    expect(utf8.decode(chapter!.readBytes()!), contains('第二段 &lt;escaped&gt;'));

    final reimport = await controller.importPaths([txt.path]);
    expect(reimport.added, 0);
    expect(reimport.updated, 1);
  });
}

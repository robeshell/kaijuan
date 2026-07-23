import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/library_controller.dart';
import 'package:path/path.dart' as p;

final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<File> _cbz(Directory dir, String name, String page) async {
  final archive = Archive()
    ..addFile(ArchiveFile(page, _pngBytes.length, _pngBytes));
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  late Directory temp;
  late AppDatabase database;
  late LibraryController controller;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kaika_col_');
    database = AppDatabase(NativeDatabase.memory());
    controller = LibraryController(
      database: database,
      comicImportService: ComicImportService(
        database: database,
        supportDirectory: temp,
      ),
      bookImportService: BookImportService(
        database: database,
        supportDirectory: temp,
      ),
    );
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('collection create, add members, shelf order, single membership',
      () async {
    final a = await _cbz(temp, 'a.cbz', 'a.png');
    final b = await _cbz(temp, 'b.cbz', 'b.png');
    await controller.importPaths([a.path, b.path]);
    final items = await controller.watchLibraryEntries().first;
    expect(items, hasLength(2));

    final colId = await controller.createCollection('系列 A');
    await controller.addItemToCollection(
      collectionId: colId,
      itemId: items[0].item.id,
    );
    await controller.addItemToCollection(
      collectionId: colId,
      itemId: items[1].item.id,
    );

    var allCols = await controller.watchCollections().first;
    expect(allCols, hasLength(1));
    expect(allCols.single.memberCount, 2);
    expect(allCols.single.coverPaths, isNotEmpty);

    // One primary collection: move to another.
    final col2 = await controller.createCollection('系列 B');
    await controller.addItemToCollection(
      collectionId: col2,
      itemId: items[0].item.id,
    );
    final membersA = await controller.watchCollectionMembers(colId).first;
    expect(membersA, hasLength(1));
    final membersB = await controller.watchCollectionMembers(col2).first;
    expect(membersB, hasLength(1));

    allCols = await controller.watchCollections().first;
    expect(allCols, hasLength(2));

    // Library main list should hide singles that are in a collection.
    final inIds = {for (final s in allCols) ...s.memberIds};
    expect(inIds, containsAll([items[0].item.id, items[1].item.id]));
    final visibleSingles = [
      for (final e in items)
        if (!inIds.contains(e.item.id)) e,
    ];
    expect(visibleSingles, isEmpty);
  });
}

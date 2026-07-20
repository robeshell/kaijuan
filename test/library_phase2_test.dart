import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/import/comic_import_service.dart';
import 'package:kaika/library/persistence/app_database.dart';
import 'package:kaika/presentation/controllers/library_controller.dart';
import 'package:path/path.dart' as p;

final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<File> _cbz(Directory dir, String name, {String page = 'p1.png'}) async {
  // Vary entry name so content-hash differs between fixtures.
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
    temp = await Directory.systemTemp.createTemp('kaika_p2_');
    database = AppDatabase(NativeDatabase.memory());
    controller = LibraryController(
      database: database,
      comicImportService: ComicImportService(
        database: database,
        supportDirectory: temp,
      ),
      libraryKind: ReaderKind.comic,
    );
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('rename item updates title', () async {
    final f = await _cbz(temp, 'old.cbz');
    await controller.importPaths([f.path]);
    final item = (await controller.watchLibraryEntries().first).single.item;
    await controller.renameItem(item.id, '  New Title  ');
    final renamed = await controller.itemById(item.id);
    expect(renamed?.title, 'New Title');
  });

  test('reading list create add remove cascade on item delete', () async {
    final a = await _cbz(temp, 'a.cbz', page: 'a.png');
    final b = await _cbz(temp, 'b.cbz', page: 'b.png');
    await controller.importPaths([a.path, b.path]);
    final items = await controller.watchLibraryEntries().first;
    expect(items, hasLength(2));

    final listId = await controller.createReadingList('收藏');
    await controller.addItemToList(listId: listId, itemId: items[0].item.id);
    await controller.addItemToList(listId: listId, itemId: items[1].item.id);

    var members = await controller.watchListMembers(listId).first;
    expect(members, hasLength(2));

    var lists = await controller.watchReadingLists().first;
    expect(lists.single.memberCount, 2);

    await controller.removeItemFromList(
      listId: listId,
      itemId: items[0].item.id,
    );
    members = await controller.watchListMembers(listId).first;
    expect(members, hasLength(1));

    await controller.deleteItem(items[1].item.id);
    members = await controller.watchListMembers(listId).first;
    expect(members, isEmpty);

    lists = await controller.watchReadingLists().first;
    expect(lists.single.memberCount, 0);

    await controller.deleteReadingList(listId);
    lists = await controller.watchReadingLists().first;
    expect(lists, isEmpty);
  });

  test('batch shelf and delete', () async {
    final a = await _cbz(temp, 'ba.cbz', page: 'ba.png');
    final b = await _cbz(temp, 'bb.cbz', page: 'bb.png');
    await controller.importPaths([a.path, b.path]);
    final items = await controller.watchLibraryEntries().first;
    final ids = items.map((e) => e.item.id).toList();
    expect(ids, hasLength(2));

    await controller.setOnShelfMany(ids, onShelf: true);
    final onShelf = await controller.watchOnShelf().first;
    expect(onShelf, hasLength(2));

    final deleted = await controller.deleteItems([ids.first]);
    expect(deleted, 1);
    expect(await controller.watchLibraryEntries().first, hasLength(1));
  });

  test('filter unread and onShelf', () async {
    final f = await _cbz(temp, 'u.cbz');
    await controller.importPaths([f.path]);
    final entry = (await controller.watchLibraryEntries().first).single;
    expect(entry.isUnread, isTrue);

    controller.setReadFilter(LibraryReadFilter.unread);
    expect(
      controller.filterAndSort([entry]),
      hasLength(1),
    );
    controller.setReadFilter(LibraryReadFilter.finished);
    expect(controller.filterAndSort([entry]), isEmpty);

    await controller.setOnShelf(entry.item.id, onShelf: true);
    final pinned = (await controller.watchLibraryEntries().first).single;
    controller
      ..setReadFilter(LibraryReadFilter.all)
      ..setShelfFilter(LibraryShelfFilter.onShelfOnly);
    expect(controller.filterAndSort([pinned]), hasLength(1));
    controller.setShelfFilter(LibraryShelfFilter.notOnShelf);
    expect(controller.filterAndSort([pinned]), isEmpty);
  });
}

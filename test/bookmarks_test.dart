import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/persistence/app_database.dart';
import 'package:kaika/readers/book/book_models.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<ReadingItem> insertBook(String id) async {
    final now = DateTime.utc(2026, 1, 1);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: id,
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: 'Bookmarks',
        filePath: '/tmp/$id.epub',
        contentHash: 'hash-$id',
        pageCount: const Value(3),
        addedAt: now,
        updatedAt: now,
      ),
    );
    return (await database.readingItemById(id))!;
  }

  test('bookmark storage watches, deduplicates, and deletes', () async {
    final item = await insertBook('bookmarks');
    final locator = const BookLocator(
      sectionIndex: 1,
      progressInSection: 0.25,
    ).encode();

    final firstId = await database.addBookmark(
      itemId: item.id,
      locatorJson: locator,
    );
    final duplicateId = await database.addBookmark(
      itemId: item.id,
      locatorJson: locator,
    );

    expect(duplicateId, firstId);
    expect(await database.watchBookmarksFor(item.id).first, hasLength(1));

    await database.deleteBookmark(firstId);
    expect(await database.watchBookmarksFor(item.id).first, isEmpty);
  });

  test('deleting an item cascades to its bookmarks', () async {
    final item = await insertBook('cascade');
    await database.addBookmark(
      itemId: item.id,
      locatorJson: const BookLocator(sectionIndex: 0).encode(),
    );

    await database.deleteReadingItem(item.id);

    expect(await database.watchBookmarksFor(item.id).first, isEmpty);
  });
}

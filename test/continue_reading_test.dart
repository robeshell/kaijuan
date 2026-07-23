import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/readers/comic/comic_models.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertItem({
    required String id,
    required String title,
    DateTime? lastOpenedAt,
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: id,
        kind: ReaderKind.comic.storageValue,
        format: ReaderFormat.cbz.storageValue,
        title: title,
        filePath: '/tmp/$id.cbz',
        contentHash: 'hash-$id',
        pageCount: const Value(10),
        pageOrderVersion: Value(ComicPageOrder.version),
        addedAt: now,
        updatedAt: now,
        lastOpenedAt: Value(lastOpenedAt),
      ),
    );
  }

  test('watchContinueReading orders by lastOpenedAt and joins progress',
      () async {
    await insertItem(
      id: 'a',
      title: 'Older',
      lastOpenedAt: DateTime.utc(2026, 1, 1),
    );
    await insertItem(
      id: 'b',
      title: 'Newer',
      lastOpenedAt: DateTime.utc(2026, 1, 2),
    );
    await insertItem(id: 'c', title: 'Never opened');

    await database.upsertProgress(
      itemId: 'b',
      locatorJson: const ComicLocator(pageIndex: 4).encode(),
      progressFraction: 0.4,
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    final entries = await database.watchContinueReading().first;
    expect(entries, hasLength(2));
    expect(entries[0].item.id, 'b');
    expect(entries[0].item.title, 'Newer');
    expect(entries[0].progressFraction, closeTo(0.4, 1e-9));
    expect(entries[1].item.id, 'a');
    expect(entries[1].progressFraction, isNull);
  });

  test('touchLastOpened surfaces item on shelf stream', () async {
    await insertItem(id: 'x', title: 'Fresh');
    expect(await database.watchContinueReading().first, isEmpty);

    await database.touchLastOpened('x', DateTime.utc(2026, 3, 1));
    final entries = await database.watchContinueReading().first;
    expect(entries, hasLength(1));
    expect(entries.single.item.id, 'x');
  });
}

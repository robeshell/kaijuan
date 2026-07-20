import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/reader_models.dart';

part 'app_database.g.dart';

/// One imported reading item (book or comic). Dedupes on [contentHash] so
/// re-importing the same file updates metadata instead of duplicating.
class ReadingItems extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // ReaderKind.storageValue
  TextColumn get format => text()(); // ReaderFormat.storageValue
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  TextColumn get contentHash => text()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get seriesName => text().nullable()();
  /// Image page count for comics; 0 for books until reflow metrics land.
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  /// [ComicPageOrder.version] frozen at import time. 0 = unknown/legacy.
  IntColumn get pageOrderVersion =>
      integer().withDefault(const Constant(0))();
  BoolColumn get onShelf => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {contentHash},
      ];
}

/// The locator payload is format-owned JSON (see domain/reader_models.dart).
/// The database never interprets it — stable reading-position and annotation
/// identity lives inside the payload.
class ReadingProgress extends Table {
  TextColumn get itemId => text().references(
        ReadingItems,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get locatorJson => text()();
  RealColumn get progressFraction =>
      real().withDefault(const Constant(0.0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}

class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get itemId => text().references(
        ReadingItems,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get locatorJson => text()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [ReadingItems, ReadingProgress, Bookmarks])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults()
      : super(
          driftDatabase(
            name: 'app_library',
            native: const DriftNativeOptions(shareAcrossIsolates: true),
          ),
        );

  @override
  int get schemaVersion => 2;

  // --- Reading items -------------------------------------------------------

  Stream<List<ReadingItem>> watchItemsByKind(ReaderKind kind) {
    final query = select(readingItems)
      ..where((t) => t.kind.equals(kind.storageValue))
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    return query.watch();
  }

  Future<ReadingItem?> readingItemByHash(String contentHash) {
    final query = select(readingItems)
      ..where((t) => t.contentHash.equals(contentHash));
    return query.getSingleOrNull();
  }

  Future<ReadingItem?> readingItemById(String id) {
    final query = select(readingItems)..where((t) => t.id.equals(id));
    return query.getSingleOrNull();
  }

  Future<void> upsertReadingItem(ReadingItemsCompanion item) {
    return into(readingItems).insertOnConflictUpdate(item);
  }

  /// Deletes the row; cascade removes progress/bookmarks. File cleanup is the
  /// caller's job (content-addressed files may be shared later).
  Future<void> deleteReadingItem(String id) {
    return (delete(readingItems)..where((t) => t.id.equals(id))).go();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(readingItems, readingItems.pageCount);
            await migrator.addColumn(
              readingItems,
              readingItems.pageOrderVersion,
            );
          }
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

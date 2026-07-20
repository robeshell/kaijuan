import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// One imported reading item (book or comic). Dedupes on [contentHash] so
/// re-importing the same file updates metadata instead of duplicating.
class ReadingItems extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'book' | 'comic'
  TextColumn get format => text()(); // ReaderFormat.name
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  TextColumn get contentHash => text()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get seriesName => text().nullable()();
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (_) async {
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

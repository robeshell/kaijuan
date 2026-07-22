import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/reader_models.dart';

part 'app_database.g.dart';

/// One row on the shelf "continue reading" surface.
/// Progress fraction is for chrome only; page restore uses opaque locator JSON.
class ContinueReadingEntry {
  const ContinueReadingEntry({required this.item, this.progressFraction});

  final ReadingItem item;
  final double? progressFraction;
}

/// Library grid row: item + optional progress for filters / badges.
class LibraryEntry {
  const LibraryEntry({required this.item, this.progressFraction});

  final ReadingItem item;
  final double? progressFraction;

  bool get isUnread => item.lastOpenedAt == null;

  bool get isFinished => progressFraction != null && progressFraction! >= 0.98;

  bool get isReading => !isUnread && !isFinished;
}

/// Named collection of library items (书单). Not the same as onShelf pin.
class ReadingListSummary {
  const ReadingListSummary({required this.list, required this.memberCount});

  final ReadingList list;
  final int memberCount;
}

/// One imported reading item. Dedupes on [contentHash] so
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
  IntColumn get pageOrderVersion => integer().withDefault(const Constant(0))();
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
  TextColumn get itemId =>
      text().references(ReadingItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text()();
  RealColumn get progressFraction => real().withDefault(const Constant(0.0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}

class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get itemId =>
      text().references(ReadingItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// User-created reading lists (书单) within one brand DB.
class ReadingLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ReadingListMembers extends Table {
  TextColumn get listId =>
      text().references(ReadingLists, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemId =>
      text().references(ReadingItems, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {listId, itemId};
}

/// Visual collection box (合集) — collage card, not a reading queue.
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Legacy pin flag; 合集主展示在书库，默认 false。
  BoolColumn get onShelf => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CollectionMembers extends Table {
  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemId =>
      text().references(ReadingItems, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {collectionId, itemId};
}

/// Collection row + members for collage UI and library filtering.
class CollectionSummary {
  const CollectionSummary({
    required this.collection,
    required this.memberCount,
    this.coverPaths = const [],
    this.memberIds = const [],
  });

  final Collection collection;
  final int memberCount;
  final List<String> coverPaths;

  /// All member item ids — library hides these singles when the 合集 is shown.
  final List<String> memberIds;
}

@DriftDatabase(
  tables: [
    ReadingItems,
    ReadingProgress,
    Bookmarks,
    ReadingLists,
    ReadingListMembers,
    Collections,
    CollectionMembers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults() : this.named('app_library');

  /// Per-brand database file (see [BrandConfig.databaseName]).
  AppDatabase.named(String name)
    : super(
        driftDatabase(
          name: name,
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  @override
  int get schemaVersion => 4;

  // --- Reading items -------------------------------------------------------

  Stream<List<ReadingItem>> watchItemsByKind(ReaderKind kind) {
    final query = select(readingItems)
      ..where((t) => t.kind.equals(kind.storageValue))
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    return query.watch();
  }

  /// Library items with optional progress for library filters.
  ///
  /// Pass [kind] to filter by reader kind; `null` returns all entries mixed
  /// together.
  Stream<List<LibraryEntry>> watchLibraryEntries([ReaderKind? kind]) {
    final query = select(readingItems).join([
      leftOuterJoin(
        readingProgress,
        readingProgress.itemId.equalsExp(readingItems.id),
      ),
    ])..orderBy([OrderingTerm.desc(readingItems.addedAt)]);
    if (kind != null) {
      query.where(readingItems.kind.equals(kind.storageValue));
    }
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          LibraryEntry(
            item: row.readTable(readingItems),
            progressFraction: row
                .readTableOrNull(readingProgress)
                ?.progressFraction,
          ),
      ],
    );
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

  Future<void> renameReadingItem(String id, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return Future.value();
    }
    final at = DateTime.now();
    return (update(readingItems)..where((t) => t.id.equals(id))).write(
      ReadingItemsCompanion(title: Value(trimmed), updatedAt: Value(at)),
    );
  }

  Future<void> touchLastOpened(String id, DateTime at) {
    return (update(readingItems)..where((t) => t.id.equals(id))).write(
      ReadingItemsCompanion(lastOpenedAt: Value(at), updatedAt: Value(at)),
    );
  }

  /// Deletes the row; cascade removes progress/bookmarks/list membership.
  /// File cleanup is the caller's job.
  Future<void> deleteReadingItem(String id) {
    return (delete(readingItems)..where((t) => t.id.equals(id))).go();
  }

  /// Recently opened items for the shelf "continue reading" surface.
  Stream<List<ContinueReadingEntry>> watchContinueReading({int limit = 24}) {
    final query =
        select(readingItems).join([
            leftOuterJoin(
              readingProgress,
              readingProgress.itemId.equalsExp(readingItems.id),
            ),
          ])
          ..where(readingItems.lastOpenedAt.isNotNull())
          ..orderBy([OrderingTerm.desc(readingItems.lastOpenedAt)])
          ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ContinueReadingEntry(
            item: row.readTable(readingItems),
            progressFraction: row
                .readTableOrNull(readingProgress)
                ?.progressFraction,
          ),
      ],
    );
  }

  /// Pinned "我的书架" items (onShelf), newest update first.
  Stream<List<ReadingItem>> watchOnShelf({int limit = 48}) {
    final query = select(readingItems)
      ..where((t) => t.onShelf.equals(true))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    return query.watch();
  }

  Future<void> setOnShelf(String id, {required bool onShelf}) {
    final at = DateTime.now();
    return (update(readingItems)..where((t) => t.id.equals(id))).write(
      ReadingItemsCompanion(onShelf: Value(onShelf), updatedAt: Value(at)),
    );
  }

  // --- Progress ------------------------------------------------------------

  Future<ReadingProgressData?> progressFor(String itemId) {
    final query = select(readingProgress)
      ..where((t) => t.itemId.equals(itemId));
    return query.getSingleOrNull();
  }

  Future<void> upsertProgress({
    required String itemId,
    required String locatorJson,
    required double progressFraction,
    required DateTime updatedAt,
  }) {
    return into(readingProgress).insertOnConflictUpdate(
      ReadingProgressCompanion(
        itemId: Value(itemId),
        locatorJson: Value(locatorJson),
        progressFraction: Value(progressFraction.clamp(0.0, 1.0)),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  // --- Bookmarks -----------------------------------------------------------

  Stream<List<ReaderBookmark>> watchBookmarksFor(String itemId) {
    final query = select(bookmarks)
      ..where((t) => t.itemId.equals(itemId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ReaderBookmark(
            id: row.id,
            locatorJson: row.locatorJson,
            label: row.label,
            createdAt: row.createdAt,
          ),
      ],
    );
  }

  Future<int> addBookmark({
    required String itemId,
    required String locatorJson,
    String? label,
  }) async {
    final existing =
        await (select(bookmarks)..where(
              (t) =>
                  t.itemId.equals(itemId) & t.locatorJson.equals(locatorJson),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    return into(bookmarks).insert(
      BookmarksCompanion.insert(
        itemId: itemId,
        locatorJson: locatorJson,
        label: Value(label),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> deleteBookmark(int id) {
    return (delete(bookmarks)..where((t) => t.id.equals(id))).go();
  }

  // --- Reading lists -------------------------------------------------------

  Stream<List<ReadingListSummary>> watchReadingLists() {
    final memberCount = readingListMembers.itemId.count();
    final query =
        select(readingLists).join([
            leftOuterJoin(
              readingListMembers,
              readingListMembers.listId.equalsExp(readingLists.id),
            ),
          ])
          ..addColumns([memberCount])
          ..groupBy([readingLists.id])
          ..orderBy([
            OrderingTerm.asc(readingLists.sortOrder),
            OrderingTerm.desc(readingLists.updatedAt),
          ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ReadingListSummary(
            list: row.readTable(readingLists),
            memberCount: row.read(memberCount) ?? 0,
          ),
      ],
    );
  }

  Future<ReadingList?> readingListById(String id) {
    final query = select(readingLists)..where((t) => t.id.equals(id));
    return query.getSingleOrNull();
  }

  Future<String> createReadingList(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('书单名称不能为空');
    }
    final now = DateTime.now();
    final id = 'list_${now.microsecondsSinceEpoch}';
    await into(readingLists).insert(
      ReadingListsCompanion.insert(
        id: id,
        name: trimmed,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> renameReadingList(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value();
    final at = DateTime.now();
    return (update(readingLists)..where((t) => t.id.equals(id))).write(
      ReadingListsCompanion(name: Value(trimmed), updatedAt: Value(at)),
    );
  }

  Future<void> deleteReadingList(String id) {
    return (delete(readingLists)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<ReadingItem>> watchListMembers(String listId) {
    final query =
        select(readingItems).join([
            innerJoin(
              readingListMembers,
              readingListMembers.itemId.equalsExp(readingItems.id),
            ),
          ])
          ..where(readingListMembers.listId.equals(listId))
          ..orderBy([OrderingTerm.desc(readingListMembers.addedAt)]);
    return query.watch().map(
      (rows) => [for (final row in rows) row.readTable(readingItems)],
    );
  }

  Future<void> addItemToList({
    required String listId,
    required String itemId,
  }) async {
    final now = DateTime.now();
    await into(readingListMembers).insertOnConflictUpdate(
      ReadingListMembersCompanion.insert(
        listId: listId,
        itemId: itemId,
        addedAt: now,
      ),
    );
    await (update(readingLists)..where((t) => t.id.equals(listId))).write(
      ReadingListsCompanion(updatedAt: Value(now)),
    );
  }

  Future<void> removeItemFromList({
    required String listId,
    required String itemId,
  }) async {
    await (delete(
      readingListMembers,
    )..where((t) => t.listId.equals(listId) & t.itemId.equals(itemId))).go();
    await (update(readingLists)..where((t) => t.id.equals(listId))).write(
      ReadingListsCompanion(updatedAt: Value(DateTime.now())),
    );
  }

  Future<List<String>> listIdsContainingItem(String itemId) async {
    final query = select(readingListMembers)
      ..where((t) => t.itemId.equals(itemId));
    final rows = await query.get();
    return [for (final r in rows) r.listId];
  }

  // --- Collections (合集) ---------------------------------------------------

  Stream<List<CollectionSummary>> watchCollections({bool? onShelfOnly}) {
    final query = select(collections)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    if (onShelfOnly == true) {
      query.where((t) => t.onShelf.equals(true));
    }
    return query.watch().asyncMap((rows) async {
      final out = <CollectionSummary>[];
      for (final c in rows) {
        out.add(await _collectionSummary(c));
      }
      return out;
    });
  }

  /// Shelf strip: on-shelf collections (non-empty preferred first via sort).
  Stream<List<CollectionSummary>> watchShelfCollections() =>
      watchCollections(onShelfOnly: true);

  Future<CollectionSummary> _collectionSummary(Collection c) async {
    final members =
        await (select(collectionMembers).join([
                innerJoin(
                  readingItems,
                  readingItems.id.equalsExp(collectionMembers.itemId),
                ),
              ])
              ..where(collectionMembers.collectionId.equals(c.id))
              ..orderBy([
                OrderingTerm.asc(collectionMembers.sortOrder),
                OrderingTerm.desc(collectionMembers.addedAt),
              ]))
            .get();
    final covers = <String>[];
    final ids = <String>[];
    for (final row in members) {
      final item = row.readTable(readingItems);
      ids.add(item.id);
      final path = item.coverPath;
      if (path != null && path.isNotEmpty && covers.length < 4) {
        covers.add(path);
      }
    }
    return CollectionSummary(
      collection: c,
      memberCount: members.length,
      coverPaths: covers,
      memberIds: ids,
    );
  }

  Future<Collection?> collectionById(String id) {
    final query = select(collections)..where((t) => t.id.equals(id));
    return query.getSingleOrNull();
  }

  /// [onShelf] kept for schema/API; 合集主展示在书库，默认不上架。
  Future<String> createCollection(String name, {bool onShelf = false}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('合集名称不能为空');
    }
    final now = DateTime.now();
    final id = 'col_${now.microsecondsSinceEpoch}';
    await into(collections).insert(
      CollectionsCompanion.insert(
        id: id,
        name: trimmed,
        onShelf: Value(onShelf),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> renameCollection(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value();
    final at = DateTime.now();
    return (update(collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(name: Value(trimmed), updatedAt: Value(at)),
    );
  }

  Future<void> deleteCollection(String id) {
    return (delete(collections)..where((t) => t.id.equals(id))).go();
  }

  Future<void> setCollectionOnShelf(String id, {required bool onShelf}) {
    final at = DateTime.now();
    return (update(collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(onShelf: Value(onShelf), updatedAt: Value(at)),
    );
  }

  Stream<List<ReadingItem>> watchCollectionMembers(String collectionId) {
    final query =
        select(readingItems).join([
            innerJoin(
              collectionMembers,
              collectionMembers.itemId.equalsExp(readingItems.id),
            ),
          ])
          ..where(collectionMembers.collectionId.equals(collectionId))
          ..orderBy([
            OrderingTerm.asc(collectionMembers.sortOrder),
            OrderingTerm.desc(collectionMembers.addedAt),
          ]);
    return query.watch().map(
      (rows) => [for (final row in rows) row.readTable(readingItems)],
    );
  }

  /// v1: one primary collection per item — remove from others when adding.
  Future<void> addItemToCollection({
    required String collectionId,
    required String itemId,
  }) async {
    final now = DateTime.now();
    await (delete(
      collectionMembers,
    )..where((t) => t.itemId.equals(itemId))).go();
    await into(collectionMembers).insertOnConflictUpdate(
      CollectionMembersCompanion.insert(
        collectionId: collectionId,
        itemId: itemId,
        addedAt: now,
      ),
    );
    await (update(collections)..where((t) => t.id.equals(collectionId))).write(
      CollectionsCompanion(updatedAt: Value(now)),
    );
  }

  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) async {
    await (delete(collectionMembers)..where(
          (t) => t.collectionId.equals(collectionId) & t.itemId.equals(itemId),
        ))
        .go();
    await (update(collections)..where((t) => t.id.equals(collectionId))).write(
      CollectionsCompanion(updatedAt: Value(DateTime.now())),
    );
  }

  Future<String?> collectionIdForItem(String itemId) async {
    final row = await (select(
      collectionMembers,
    )..where((t) => t.itemId.equals(itemId))).getSingleOrNull();
    return row?.collectionId;
  }

  Future<List<Collection>> collectionsSnapshot() {
    final query = select(collections)
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    return query.get();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(readingItems, readingItems.pageCount);
        await migrator.addColumn(readingItems, readingItems.pageOrderVersion);
      }
      if (from < 3) {
        await migrator.createTable(readingLists);
        await migrator.createTable(readingListMembers);
      }
      if (from < 4) {
        await migrator.createTable(collections);
        await migrator.createTable(collectionMembers);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

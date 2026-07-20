import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../domain/reader_models.dart';
import '../../library/import/comic_import_service.dart';
import '../../library/persistence/app_database.dart';

/// How the library grid orders items (client-side after stream).
enum LibrarySort {
  addedDesc,
  titleAsc,
  lastOpenedDesc,
}

/// Reading-state filter for library grid.
enum LibraryReadFilter {
  all,
  unread,
  reading,
  finished,
}

/// On-shelf pin filter.
enum LibraryShelfFilter {
  all,
  onShelfOnly,
  notOnShelf,
}

/// Presentation-facing library state. Screens subscribe to this; they do not
/// touch drift or the import service directly.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required AppDatabase database,
    required ComicImportService importService,
    this.importExtensions = const ['cbz', 'zip', 'epub'],
  })  // Public names stay database/importService for call sites.
      : _database = database, // ignore: prefer_initializing_formals
        _importService = importService; // ignore: prefer_initializing_formals

  final AppDatabase _database;
  final ComicImportService _importService;

  /// File picker extensions (no dots), from [BrandConfig].
  final List<String> importExtensions;

  /// Exposed for reader entry (progress / item load). Screens still go through
  /// controllers for business actions; the reader opens with its own controller.
  AppDatabase get database => _database;

  bool _importing = false;
  bool get isImporting => _importing;

  LibrarySort _sort = LibrarySort.addedDesc;
  LibrarySort get sort => _sort;

  LibraryReadFilter _readFilter = LibraryReadFilter.all;
  LibraryReadFilter get readFilter => _readFilter;

  LibraryShelfFilter _shelfFilter = LibraryShelfFilter.all;
  LibraryShelfFilter get shelfFilter => _shelfFilter;

  /// null = all formats; otherwise ReaderFormat.storageValue.
  String? _formatFilter;
  String? get formatFilter => _formatFilter;

  void setSort(LibrarySort sort) {
    if (_sort == sort) return;
    _sort = sort;
    notifyListeners();
  }

  void setReadFilter(LibraryReadFilter filter) {
    if (_readFilter == filter) return;
    _readFilter = filter;
    notifyListeners();
  }

  void setShelfFilter(LibraryShelfFilter filter) {
    if (_shelfFilter == filter) return;
    _shelfFilter = filter;
    notifyListeners();
  }

  void setFormatFilter(String? format) {
    if (_formatFilter == format) return;
    _formatFilter = format;
    notifyListeners();
  }

  void clearFilters() {
    var changed = false;
    if (_readFilter != LibraryReadFilter.all) {
      _readFilter = LibraryReadFilter.all;
      changed = true;
    }
    if (_shelfFilter != LibraryShelfFilter.all) {
      _shelfFilter = LibraryShelfFilter.all;
      changed = true;
    }
    if (_formatFilter != null) {
      _formatFilter = null;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  bool get hasActiveFilters =>
      _readFilter != LibraryReadFilter.all ||
      _shelfFilter != LibraryShelfFilter.all ||
      _formatFilter != null;

  /// Live library entries with progress (for filters / badges).
  Stream<List<LibraryEntry>> watchLibraryEntries() =>
      _database.watchLibraryEntries(ReaderKind.comic);

  /// Apply filters + sort + title [query].
  List<LibraryEntry> filterAndSort(
    List<LibraryEntry> entries, {
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    var list = List<LibraryEntry>.of(entries);

    if (q.isNotEmpty) {
      list = [
        for (final e in list)
          if (e.item.title.toLowerCase().contains(q)) e,
      ];
    }

    if (_formatFilter != null) {
      list = [
        for (final e in list)
          if (e.item.format == _formatFilter) e,
      ];
    }

    switch (_shelfFilter) {
      case LibraryShelfFilter.all:
        break;
      case LibraryShelfFilter.onShelfOnly:
        list = [for (final e in list) if (e.item.onShelf) e];
      case LibraryShelfFilter.notOnShelf:
        list = [for (final e in list) if (!e.item.onShelf) e];
    }

    switch (_readFilter) {
      case LibraryReadFilter.all:
        break;
      case LibraryReadFilter.unread:
        list = [for (final e in list) if (e.isUnread) e];
      case LibraryReadFilter.reading:
        list = [for (final e in list) if (e.isReading) e];
      case LibraryReadFilter.finished:
        list = [for (final e in list) if (e.isFinished) e];
    }

    switch (_sort) {
      case LibrarySort.addedDesc:
        list.sort((a, b) => b.item.addedAt.compareTo(a.item.addedAt));
      case LibrarySort.titleAsc:
        list.sort(
          (a, b) =>
              a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase()),
        );
      case LibrarySort.lastOpenedDesc:
        list.sort((a, b) {
          final ao = a.item.lastOpenedAt;
          final bo = b.item.lastOpenedAt;
          if (ao == null && bo == null) {
            return b.item.addedAt.compareTo(a.item.addedAt);
          }
          if (ao == null) return 1;
          if (bo == null) return -1;
          return bo.compareTo(ao);
        });
    }
    return list;
  }

  /// Shelf "continue reading": opened items + progress fraction for chrome.
  Stream<List<ContinueReadingEntry>> watchContinueReading({int limit = 24}) =>
      _database.watchContinueReading(limit: limit);

  /// Shelf "我的书架" pins.
  Stream<List<ReadingItem>> watchOnShelf({int limit = 48}) =>
      _database.watchOnShelf(limit: limit);

  Future<void> setOnShelf(String id, {required bool onShelf}) =>
      _database.setOnShelf(id, onShelf: onShelf);

  Future<void> renameItem(String id, String title) =>
      _database.renameReadingItem(id, title);

  Future<ReadingItem?> itemById(String id) => _database.readingItemById(id);

  Future<ReadingProgressData?> progressFor(String itemId) =>
      _database.progressFor(itemId);

  /// Opens the system file picker and imports comics (CBZ/ZIP/EPUB).
  /// Returns null when the user cancels.
  Future<ImportResult?> pickAndImportComics() async {
    final typeGroup = XTypeGroup(
      label: '漫画',
      extensions: importExtensions,
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return null;
    return importPaths([for (final f in files) f.path]);
  }

  /// Import entry point used by tests and by [pickAndImportComics].
  Future<ImportResult> importPaths(List<String> paths) async {
    if (_importing) {
      return const ImportResult(
        failures: [
          ImportFailure(path: '', reason: '已有导入任务在进行'),
        ],
      );
    }
    _importing = true;
    notifyListeners();
    try {
      return await _importService.importPaths(paths);
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  Future<void> deleteItem(String id) => _importService.deleteItem(id);

  /// Batch delete (content files + rows).
  Future<int> deleteItems(Iterable<String> ids) async {
    var n = 0;
    for (final id in ids) {
      await _importService.deleteItem(id);
      n++;
    }
    return n;
  }

  Future<void> setOnShelfMany(
    Iterable<String> ids, {
    required bool onShelf,
  }) async {
    for (final id in ids) {
      await _database.setOnShelf(id, onShelf: onShelf);
    }
  }

  Future<void> addItemsToList({
    required String listId,
    required Iterable<String> itemIds,
  }) async {
    for (final id in itemIds) {
      await _database.addItemToList(listId: listId, itemId: id);
    }
  }

  // --- Reading lists -------------------------------------------------------

  Stream<List<ReadingListSummary>> watchReadingLists() =>
      _database.watchReadingLists();

  Stream<List<ReadingItem>> watchListMembers(String listId) =>
      _database.watchListMembers(listId);

  Future<String> createReadingList(String name) =>
      _database.createReadingList(name);

  Future<void> renameReadingList(String id, String name) =>
      _database.renameReadingList(id, name);

  Future<void> deleteReadingList(String id) =>
      _database.deleteReadingList(id);

  Future<void> addItemToList({
    required String listId,
    required String itemId,
  }) =>
      _database.addItemToList(listId: listId, itemId: itemId);

  Future<void> removeItemFromList({
    required String listId,
    required String itemId,
  }) =>
      _database.removeItemFromList(listId: listId, itemId: itemId);

  Future<List<ReadingListSummary>> readingListsSnapshot() async {
    return watchReadingLists().first;
  }

  // --- Collections (合集) ---------------------------------------------------

  Stream<List<CollectionSummary>> watchCollections() =>
      _database.watchCollections();

  /// Shelf strip: collections pinned to shelf (default true).
  Stream<List<CollectionSummary>> watchShelfCollections() =>
      _database.watchShelfCollections();

  Stream<List<ReadingItem>> watchCollectionMembers(String collectionId) =>
      _database.watchCollectionMembers(collectionId);

  Future<String> createCollection(String name, {bool onShelf = false}) =>
      _database.createCollection(name, onShelf: onShelf);

  Future<void> renameCollection(String id, String name) =>
      _database.renameCollection(id, name);

  Future<void> deleteCollection(String id) =>
      _database.deleteCollection(id);

  Future<void> setCollectionOnShelf(String id, {required bool onShelf}) =>
      _database.setCollectionOnShelf(id, onShelf: onShelf);

  Future<void> addItemToCollection({
    required String collectionId,
    required String itemId,
  }) =>
      _database.addItemToCollection(
        collectionId: collectionId,
        itemId: itemId,
      );

  Future<void> addItemsToCollection({
    required String collectionId,
    required Iterable<String> itemIds,
  }) async {
    for (final id in itemIds) {
      await _database.addItemToCollection(
        collectionId: collectionId,
        itemId: id,
      );
    }
  }

  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) =>
      _database.removeItemFromCollection(
        collectionId: collectionId,
        itemId: itemId,
      );

  Future<List<Collection>> collectionsSnapshot() =>
      _database.collectionsSnapshot();

  Future<String?> collectionIdForItem(String itemId) =>
      _database.collectionIdForItem(itemId);
}

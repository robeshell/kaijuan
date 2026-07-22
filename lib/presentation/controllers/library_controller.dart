import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../../library/import/book_import_service.dart';
import '../../library/import/comic_import_service.dart';
import '../../library/import/epub_import_router.dart';
import '../../library/import/import_models.dart';
import '../../library/persistence/app_database.dart';

/// How the library grid orders items (client-side after stream).
enum LibrarySort { addedDesc, titleAsc, lastOpenedDesc }

/// Reading-state filter for library grid.
enum LibraryReadFilter { all, unread, reading, finished }

/// On-shelf pin filter.
enum LibraryShelfFilter { all, onShelfOnly, notOnShelf }

/// Kind filter for the library grid.
enum LibraryKindFilter {
  all,
  comic,
  book;

  ReaderKind? get readerKind => switch (this) {
    all => null,
    comic => ReaderKind.comic,
    book => ReaderKind.book,
  };
}

/// Presentation-facing library state. Screens subscribe to this; they do not
/// touch drift or the import service directly.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.database,
    required ComicImportService comicImportService,
    required BookImportService bookImportService,
    this.importExtensions = const ['cbz', 'zip', 'epub'],
  }) : _comicImport = comicImportService,
       _bookImport = bookImportService,
       _epubRouter = EpubImportRouter(
         comicImport: comicImportService,
         bookImport: bookImportService,
       );

  final AppDatabase database;
  final ComicImportService _comicImport;
  final BookImportService _bookImport;
  final EpubImportRouter _epubRouter;

  /// File picker extensions (no dots), from [BrandConfig].
  final List<String> importExtensions;

  bool _importing = false;
  bool get isImporting => _importing;

  LibrarySort _sort = LibrarySort.addedDesc;
  LibrarySort get sort => _sort;

  LibraryReadFilter _readFilter = LibraryReadFilter.all;
  LibraryReadFilter get readFilter => _readFilter;

  LibraryShelfFilter _shelfFilter = LibraryShelfFilter.all;
  LibraryShelfFilter get shelfFilter => _shelfFilter;

  LibraryKindFilter _kindFilter = LibraryKindFilter.all;
  LibraryKindFilter get kindFilter => _kindFilter;

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

  void setKindFilter(LibraryKindFilter filter) {
    if (_kindFilter == filter) return;
    _kindFilter = filter;
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
    if (_kindFilter != LibraryKindFilter.all) {
      _kindFilter = LibraryKindFilter.all;
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
      _kindFilter != LibraryKindFilter.all ||
      _formatFilter != null;

  /// Live library entries with progress (for filters / badges).
  Stream<List<LibraryEntry>> watchLibraryEntries() =>
      database.watchLibraryEntries(_kindFilter.readerKind);

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
        list = [
          for (final e in list)
            if (e.item.onShelf) e,
        ];
      case LibraryShelfFilter.notOnShelf:
        list = [
          for (final e in list)
            if (!e.item.onShelf) e,
        ];
    }

    switch (_readFilter) {
      case LibraryReadFilter.all:
        break;
      case LibraryReadFilter.unread:
        list = [
          for (final e in list)
            if (e.isUnread) e,
        ];
      case LibraryReadFilter.reading:
        list = [
          for (final e in list)
            if (e.isReading) e,
        ];
      case LibraryReadFilter.finished:
        list = [
          for (final e in list)
            if (e.isFinished) e,
        ];
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
      database.watchContinueReading(limit: limit);

  /// Shelf "我的书架" pins.
  Stream<List<ReadingItem>> watchOnShelf({int limit = 48}) =>
      database.watchOnShelf(limit: limit);

  Future<void> setOnShelf(String id, {required bool onShelf}) =>
      database.setOnShelf(id, onShelf: onShelf);

  Future<void> renameItem(String id, String title) =>
      database.renameReadingItem(id, title);

  Future<ReadingItem?> itemById(String id) => database.readingItemById(id);

  Future<ReadingProgressData?> progressFor(String itemId) =>
      database.progressFor(itemId);

  /// Opens the system file picker. Returns null when the user cancels.
  Future<ImportResult?> pickAndImport() async {
    // Several Android document providers don't register application/epub+zip,
    // so extension -> MIME conversion hides valid EPUBs as "not an archive".
    // Let SAF browse all files there; [importPaths] remains the source of truth
    // and rejects every unsupported extension after selection.
    final typeGroup = defaultTargetPlatform == TargetPlatform.android
        ? const XTypeGroup(label: '图书与漫画')
        : XTypeGroup(label: '图书与漫画', extensions: importExtensions);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return null;
    return importPaths([for (final f in files) f.path]);
  }

  /// Import entry point used by tests and by [pickAndImport].
  ///
  /// Routes by extension: cbz/zip → image archive service, epub → auto-detect,
  /// others fail.
  Future<ImportResult> importPaths(List<String> paths) async {
    if (_importing) {
      return const ImportResult(
        failures: [ImportFailure(path: '', reason: '已有导入任务在进行')],
      );
    }
    _importing = true;
    notifyListeners();
    try {
      final comicPaths = <String>[];
      final bookPaths = <String>[];
      final epubPaths = <String>[];
      final failures = <ImportFailure>[];

      for (final path in paths) {
        final format = ReaderFormat.fromExtension(p.extension(path));
        if (format == ReaderFormat.cbz || format == ReaderFormat.zip) {
          comicPaths.add(path);
        } else if (format == ReaderFormat.epub) {
          epubPaths.add(path);
        } else {
          failures.add(ImportFailure(path: path, reason: '不支持的格式：$path'));
        }
      }

      var added = 0;
      var updated = 0;

      if (comicPaths.isNotEmpty) {
        final comicResult = await _comicImport.importPaths(comicPaths);
        added += comicResult.added;
        updated += comicResult.updated;
        failures.addAll(comicResult.failures);
      }

      if (bookPaths.isNotEmpty) {
        final bookResult = await _bookImport.importPaths(bookPaths);
        added += bookResult.added;
        updated += bookResult.updated;
        failures.addAll(bookResult.failures);
      }

      if (epubPaths.isNotEmpty) {
        final epubResult = await _epubRouter.importPaths(epubPaths);
        added += epubResult.added;
        updated += epubResult.updated;
        failures.addAll(epubResult.failures);
      }

      return ImportResult(added: added, updated: updated, failures: failures);
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  Future<void> deleteItem(String id) async {
    final item = await database.readingItemById(id);
    if (item == null) return;
    final kind = ReaderKind.fromStorage(item.kind);
    if (kind == ReaderKind.book) {
      await _bookImport.deleteItem(id);
    } else {
      await _comicImport.deleteItem(id);
    }
  }

  /// Batch delete (content files + rows).
  Future<int> deleteItems(Iterable<String> ids) async {
    var n = 0;
    for (final id in ids) {
      await deleteItem(id);
      n++;
    }
    return n;
  }

  Future<void> setOnShelfMany(
    Iterable<String> ids, {
    required bool onShelf,
  }) async {
    for (final id in ids) {
      await database.setOnShelf(id, onShelf: onShelf);
    }
  }

  Future<void> addItemsToList({
    required String listId,
    required Iterable<String> itemIds,
  }) async {
    for (final id in itemIds) {
      await database.addItemToList(listId: listId, itemId: id);
    }
  }

  // --- Reading lists -------------------------------------------------------

  Stream<List<ReadingListSummary>> watchReadingLists() =>
      database.watchReadingLists();

  Stream<List<ReadingItem>> watchListMembers(String listId) =>
      database.watchListMembers(listId);

  Future<String> createReadingList(String name) =>
      database.createReadingList(name);

  Future<void> renameReadingList(String id, String name) =>
      database.renameReadingList(id, name);

  Future<void> deleteReadingList(String id) => database.deleteReadingList(id);

  Future<void> addItemToList({
    required String listId,
    required String itemId,
  }) => database.addItemToList(listId: listId, itemId: itemId);

  Future<void> removeItemFromList({
    required String listId,
    required String itemId,
  }) => database.removeItemFromList(listId: listId, itemId: itemId);

  Future<List<ReadingListSummary>> readingListsSnapshot() async {
    return watchReadingLists().first;
  }

  // --- Collections (合集) ---------------------------------------------------

  Stream<List<CollectionSummary>> watchCollections() =>
      database.watchCollections();

  /// Shelf strip: collections pinned to shelf (default true).
  Stream<List<CollectionSummary>> watchShelfCollections() =>
      database.watchShelfCollections();

  Stream<List<ReadingItem>> watchCollectionMembers(String collectionId) =>
      database.watchCollectionMembers(collectionId);

  Future<String> createCollection(String name, {bool onShelf = false}) =>
      database.createCollection(name, onShelf: onShelf);

  Future<void> renameCollection(String id, String name) =>
      database.renameCollection(id, name);

  Future<void> deleteCollection(String id) => database.deleteCollection(id);

  Future<void> setCollectionOnShelf(String id, {required bool onShelf}) =>
      database.setCollectionOnShelf(id, onShelf: onShelf);

  Future<void> addItemToCollection({
    required String collectionId,
    required String itemId,
  }) =>
      database.addItemToCollection(collectionId: collectionId, itemId: itemId);

  Future<void> addItemsToCollection({
    required String collectionId,
    required Iterable<String> itemIds,
  }) async {
    for (final id in itemIds) {
      await database.addItemToCollection(
        collectionId: collectionId,
        itemId: id,
      );
    }
  }

  Future<void> removeItemFromCollection({
    required String collectionId,
    required String itemId,
  }) => database.removeItemFromCollection(
    collectionId: collectionId,
    itemId: itemId,
  );

  Future<List<Collection>> collectionsSnapshot() =>
      database.collectionsSnapshot();

  Future<String?> collectionIdForItem(String itemId) =>
      database.collectionIdForItem(itemId);
}

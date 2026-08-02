import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/reader_models.dart';
import '../../library/import/book_import_service.dart';
import '../../library/import/comic_import_service.dart';
import '../../library/import/import_models.dart';
import '../../library/import/import_pipeline.dart';
import '../../library/import/import_sources.dart';
import '../../library/persistence/app_database.dart';

/// How the library grid orders items (client-side after stream).
enum LibrarySort { addedDesc, titleAsc, lastOpenedDesc }

/// Reading-state filter for library grid.
enum LibraryReadFilter { all, unread, reading, finished }

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

typedef ImportDirectoryPicker =
    Future<String?> Function({String? initialDirectory});

Future<String?> _defaultImportDirectoryPicker({String? initialDirectory}) {
  return getDirectoryPath(initialDirectory: initialDirectory);
}

/// Presentation-facing library state. Screens subscribe to this; they do not
/// touch drift or the import service directly.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.database,
    required ComicImportService comicImportService,
    required BookImportService bookImportService,
    ImportPipeline? importPipeline,
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<Directory?> Function()? downloadsDirectoryProvider,
    ImportDirectoryPicker? directoryPicker,
    this.importExtensions = const [
      'cbz',
      'zip',
      'epub',
      'fb2',
      'fbz',
      'mobi',
      'azw3',
      'pdf',
      'txt',
      'md',
      'markdown',
    ],
  }) : _comicImport = comicImportService,
       _bookImport = bookImportService,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _downloadsDirectoryProvider =
           downloadsDirectoryProvider ?? getDownloadsDirectory,
       _directoryPicker = directoryPicker ?? _defaultImportDirectoryPicker,
       _importPipeline =
           importPipeline ??
           ImportPipeline(
             comicImport: comicImportService,
             bookImport: bookImportService,
           );

  final AppDatabase database;
  final ComicImportService _comicImport;
  final BookImportService _bookImport;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<Directory?> Function() _downloadsDirectoryProvider;
  final ImportDirectoryPicker _directoryPicker;
  final ImportPipeline _importPipeline;

  /// File picker extensions (no dots), from [BrandConfig].
  final List<String> importExtensions;

  bool _importing = false;
  bool get isImporting => _importing;

  LibrarySort _sort = LibrarySort.addedDesc;
  LibrarySort get sort => _sort;

  LibraryReadFilter _readFilter = LibraryReadFilter.all;
  LibraryReadFilter get readFilter => _readFilter;

  LibraryKindFilter _kindFilter = LibraryKindFilter.all;
  LibraryKindFilter get kindFilter => _kindFilter;

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

  void setKindFilter(LibraryKindFilter filter) {
    if (_kindFilter == filter) return;
    _kindFilter = filter;
    notifyListeners();
  }

  void clearFilters() {
    var changed = false;
    if (_readFilter != LibraryReadFilter.all) {
      _readFilter = LibraryReadFilter.all;
      changed = true;
    }
    if (_kindFilter != LibraryKindFilter.all) {
      _kindFilter = LibraryKindFilter.all;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  bool get hasActiveFilters =>
      _readFilter != LibraryReadFilter.all ||
      _kindFilter != LibraryKindFilter.all;

  int get activeFilterCount => [
    _readFilter != LibraryReadFilter.all,
    _kindFilter != LibraryKindFilter.all,
  ].where((active) => active).length;

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
    final paths = await pickFilesForReview();
    if (paths == null) return null;
    if (paths.isEmpty) {
      return const ImportResult(
        failures: [
          ImportFailure(path: '', reason: '无法读取所选文件路径，请换一本或换一个文件管理器再试'),
        ],
      );
    }
    return importCandidates([
      for (final path in paths)
        ImportCandidate(source: LocalFileImportSource.picked(path)),
    ]);
  }

  /// Opens the system file picker and returns paths for the review screen.
  /// Mobile platforms use file selection rather than traversing a directory
  /// path: Android's SAF and iOS Files can grant individual files reliably,
  /// while a raw public-folder path is not guaranteed to be readable.
  Future<List<String>?> pickFilesForReview() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _pickAndroidPathsForReview();
    }
    // Desktop uses extensions; iOS ignores them and requires UTIs
    // (file_selector_ios throws without uniformTypeIdentifiers).
    // CBZ often has no dedicated UTI — include zip + public.data; extension
    // filtering still happens in [importPaths].
    final typeGroup = XTypeGroup(
      label: '图书与漫画',
      extensions: importExtensions,
      uniformTypeIdentifiers: const [
        'org.idpf.epub-container', // .epub
        'public.zip-archive', // .zip / many .cbz
        'com.pkware.zip-archive',
        'public.data', // Files app / cloud providers without typed UTIs
      ],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return null;
    return [for (final f in files) f.path];
  }

  /// Android SAF via [FilePicker] without loading whole-file bytes.
  ///
  /// Upstream [file_selector] Android impl allocates `byte[size]` for every
  /// pick and OOMs on large CBZ/EPUB (flutter/flutter#141002). We only need a
  /// filesystem path for staging; [importPaths] still rejects bad extensions.
  Future<List<String>?> _pickAndroidPathsForReview() async {
    // Several document providers omit application/epub+zip, so do not filter
    // by MIME/extension in the picker — reject after selection instead.
    final result = await FilePicker.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return null;
    final paths = <String>[
      for (final f in result.files)
        if (f.path != null && f.path!.isNotEmpty) f.path!,
    ];
    return paths;
  }

  /// Opens a directory picker and recursively imports supported files.
  Future<ImportResult?> pickDirectoryAndImport() async {
    String? directory;
    try {
      directory = await _directoryPicker();
    } catch (_) {
      // Directory selection is optional on platforms without a native folder
      // picker. The explicit action remains cancellable rather than turning a
      // picker limitation into an import failure.
      return null;
    }
    if (directory == null || directory.isEmpty) return null;
    return importDirectory(directory);
  }

  /// Scans the app Documents directory and the platform Downloads directory
  /// without opening a folder picker. This is the source used by the
  /// library's "自动扫描" action.
  Future<ImportResult> scanDefaultDirectory() {
    return _runImport(
      () async {
        final discovery = await _discoverDefaultImport();
        return _importScannedPaths(discovery.paths);
      },
      busyResult: const ImportResult(
        failures: [ImportFailure(path: '', reason: '已有导入任务在进行')],
      ),
    );
  }

  /// Finds supported files in the app Documents and platform Downloads
  /// directories without importing them. The caller presents these paths for
  /// confirmation before handing selected files to [importScannedPaths].
  Future<ImportDiscoveryResult> discoverDefaultImport() {
    return _runImport(
      _discoverDefaultImport,
      busyResult: const ImportDiscoveryResult(),
    );
  }

  Future<List<String>> discoverDefaultImportPaths() {
    return _runImport(
      () async => (await _discoverDefaultImport()).paths,
      busyResult: const <String>[],
    );
  }

  /// Lets the user grant access to a directory through the platform picker,
  /// then discovers supported files inside it. The picker is important on
  /// sandboxed macOS and mobile platforms where a public Downloads path cannot
  /// be read directly.
  Future<List<String>?> pickDirectoryForReview({
    String? initialDirectory,
  }) async {
    String? directory;
    try {
      directory = await _directoryPicker(initialDirectory: initialDirectory);
    } catch (_) {
      return null;
    }
    if (directory == null || directory.isEmpty) return null;
    return discoverImportPaths(directory);
  }

  Future<List<String>> discoverImportPaths(String directoryPath) {
    return _runImport(
      () => _discoverImportPaths([directoryPath]),
      busyResult: const <String>[],
    );
  }

  /// Recursively finds supported files and feeds them into the same pipeline
  /// used by local file selection.
  Future<ImportResult> importDirectory(String directoryPath) {
    return _runImport(
      () async {
        final paths = await _discoverImportPaths([directoryPath]);
        return _importScannedPaths(paths);
      },
      busyResult: const ImportResult(
        failures: [ImportFailure(path: '', reason: '已有导入任务在进行')],
      ),
    );
  }

  Future<ImportResult> importScannedPaths(Iterable<String> paths) {
    return _runImport(
      () => _importScannedPaths(paths),
      busyResult: const ImportResult(
        failures: [ImportFailure(path: '', reason: '已有导入任务在进行')],
      ),
    );
  }

  Future<ImportDiscoveryResult> _discoverDefaultImport() async {
    final paths = <String>[];
    try {
      paths.addAll(
        await _discoverImportPaths([
          (await _documentsDirectoryProvider()).path,
        ]),
      );
    } catch (_) {
      // Keep scanning if the platform documents directory is unavailable.
    }

    // iOS and Android intentionally do not use path_provider's downloads
    // result here. On iOS it is not a public Files location, and on Android it
    // is the app-specific external files directory rather than the user's
    // shared Download folder. Both platforms must use a system picker grant.
    if (Platform.isIOS || Platform.isAndroid) {
      return ImportDiscoveryResult(
        paths: paths,
        downloadsAvailability: ImportDirectoryAvailability.needsAuthorization,
      );
    }

    String? downloadsPath;
    var downloadsAvailability = ImportDirectoryAvailability.unavailable;
    try {
      final directory = await _downloadsDirectoryProvider();
      if (directory != null) {
        downloadsPath = directory.path;
        final scan = await _discoverImportDirectory(directory.path);
        if (scan.readable) {
          paths.addAll(scan.paths);
          downloadsAvailability = ImportDirectoryAvailability.available;
        } else {
          downloadsAvailability =
              ImportDirectoryAvailability.needsAuthorization;
        }
      } else {
        downloadsAvailability = ImportDirectoryAvailability.needsAuthorization;
      }
    } catch (_) {
      downloadsAvailability = ImportDirectoryAvailability.needsAuthorization;
    }

    return ImportDiscoveryResult(
      paths: paths.toSet().toList()..sort(),
      downloadsAvailability: downloadsAvailability,
      downloadsPath: downloadsPath,
    );
  }

  Future<List<String>> _discoverImportPaths(
    Iterable<String> directoryPaths,
  ) async {
    final paths = <String>{};
    for (final directoryPath in directoryPaths) {
      final scan = await _discoverImportDirectory(directoryPath);
      paths.addAll(scan.paths);
    }
    final sortedPaths = paths.toList()..sort();
    return sortedPaths;
  }

  Future<({List<String> paths, bool readable})> _discoverImportDirectory(
    String directoryPath,
  ) async {
    final directory = Directory(directoryPath);
    final paths = <String>{};
    try {
      if (!await directory.exists()) {
        return (paths: const <String>[], readable: false);
      }
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (_isSupportedImportFile(entity.path)) {
          paths.add(p.normalize(p.absolute(entity.path)));
        }
      }
      return (paths: paths.toList()..sort(), readable: true);
    } catch (_) {
      // A permission error in one source must not block another source, but it
      // must be surfaced so the UI can ask the user for a picker grant.
      return (paths: const <String>[], readable: false);
    }
  }

  Future<ImportResult> _importScannedPaths(Iterable<String> paths) {
    final sortedPaths = paths.toList()..sort();
    if (sortedPaths.isEmpty) return Future.value(const ImportResult());
    return _importPipeline.importCandidates([
      for (final path in sortedPaths)
        ImportCandidate(source: LocalFileImportSource.scanned(path)),
    ]);
  }

  bool _isSupportedImportFile(String path) {
    final format = ReaderFormat.fromFileName(p.basename(path));
    return format != null &&
        (ComicImportService.supportedFormats.contains(format) ||
            BookImportService.supportedFormats.contains(format));
  }

  /// Compatibility entry point used by tests and existing callers. Paths are
  /// adapted to the local-file method and then share the common pipeline.
  Future<ImportResult> importPaths(List<String> paths) async {
    return importCandidates([
      for (final path in paths)
        ImportCandidate(source: LocalFileImportSource.picked(path)),
    ]);
  }

  /// Import entry point for every current and future source adapter.
  Future<ImportResult> importCandidates(
    Iterable<ImportCandidate> candidates,
  ) async {
    return _runImport(
      () => _importPipeline.importCandidates(candidates),
      busyResult: const ImportResult(
        failures: [ImportFailure(path: '', reason: '已有导入任务在进行')],
      ),
    );
  }

  Future<T> _runImport<T>(
    Future<T> Function() operation, {
    required T busyResult,
  }) async {
    if (_importing) {
      return busyResult;
    }
    _importing = true;
    notifyListeners();
    try {
      return await operation();
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

  /// Reading-list ids that already contain [itemId].
  Future<List<String>> listIdsContainingItem(String itemId) =>
      database.listIdsContainingItem(itemId);

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

  Future<void> removeItemsFromCollection({
    required String collectionId,
    required Iterable<String> itemIds,
  }) => database.removeItemsFromCollection(
    collectionId: collectionId,
    itemIds: itemIds,
  );

  Future<List<Collection>> collectionsSnapshot() =>
      database.collectionsSnapshot();

  Future<String?> collectionIdForItem(String itemId) =>
      database.collectionIdForItem(itemId);
}

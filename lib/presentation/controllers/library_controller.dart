import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../domain/reader_models.dart';
import '../../library/import/comic_import_service.dart';
import '../../library/persistence/app_database.dart';

/// Presentation-facing library state. Screens subscribe to this; they do not
/// touch drift or the import service directly.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required AppDatabase database,
    required ComicImportService importService,
  }) : this._(database, importService);

  LibraryController._(this._database, this._importService);

  final AppDatabase _database;
  final ComicImportService _importService;

  bool _importing = false;
  bool get isImporting => _importing;

  /// Live comic list, newest import first.
  Stream<List<ReadingItem>> watchComics() =>
      _database.watchItemsByKind(ReaderKind.comic);

  /// Opens the system file picker and imports CBZ/ZIP comics.
  /// Returns null when the user cancels.
  Future<ImportResult?> pickAndImportComics() async {
    const typeGroup = XTypeGroup(
      label: '漫画',
      extensions: ['cbz', 'zip'],
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
}

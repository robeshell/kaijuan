import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../persistence/app_database.dart';
import 'comic_archive.dart';

class ImportFailure {
  const ImportFailure({required this.path, required this.reason});

  final String path;
  final String reason;
}

class ImportResult {
  const ImportResult({
    this.added = 0,
    this.updated = 0,
    this.failures = const [],
  });

  final int added;
  final int updated;
  final List<ImportFailure> failures;

  bool get isEmpty => added == 0 && updated == 0 && failures.isEmpty;
}

/// Imports comic files into content-addressed storage:
///
///   `<appSupport>/library/<contentHash>.<ext>` — the source file
///   `<appSupport>/covers/<contentHash>.<ext>`  — extracted first page
///
/// Content addressing makes re-imports idempotent and dedup free.
class ComicImportService {
  ComicImportService({required this.database, required this.supportDirectory});

  final AppDatabase database;
  final Directory supportDirectory;

  Future<ImportResult> importPaths(List<String> paths) async {
    var added = 0;
    var updated = 0;
    final failures = <ImportFailure>[];
    for (final path in paths) {
      try {
        final outcome = await _importOne(path);
        outcome == _Outcome.added ? added++ : updated++;
      } on ImportException catch (e) {
        failures.add(ImportFailure(path: path, reason: e.message));
      } catch (e) {
        failures.add(ImportFailure(path: path, reason: e.toString()));
      }
    }
    return ImportResult(added: added, updated: updated, failures: failures);
  }

  /// Removes the library row and best-effort deletes stored archive + cover.
  Future<void> deleteItem(String id) async {
    final item = await database.readingItemById(id);
    if (item == null) return;
    await database.deleteReadingItem(id);
    await _deleteIfExists(item.filePath);
    if (item.coverPath != null) {
      await _deleteIfExists(item.coverPath!);
    }
  }

  Future<_Outcome> _importOne(String path) async {
    final format = ReaderFormat.fromExtension(p.extension(path));
    if (format == null ||
        (format != ReaderFormat.cbz && format != ReaderFormat.zip)) {
      throw ImportException('不支持的漫画格式：${p.extension(path)}');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ImportException('文件不存在');
    }

    final hash = (await sha256.bind(file.openRead()).first).toString();
    final storedPath = p.join(_libraryDir.path, '$hash${p.extension(path)}');
    if (!await File(storedPath).exists()) {
      await _libraryDir.create(recursive: true);
      await file.copy(storedPath);
    }

    final pages = await ComicArchive.listPages(storedPath);
    if (pages.isEmpty) {
      await File(storedPath).delete().catchError((_) => File(storedPath));
      throw ImportException('压缩包里找不到图片页');
    }

    final coverPath = await _ensureCover(hash, storedPath, pages.first);
    final title = p.basenameWithoutExtension(path);

    final existing = await database.readingItemByHash(hash);
    final now = DateTime.now();
    await database.upsertReadingItem(
      ReadingItemsCompanion(
        id: Value(existing?.id ?? hash),
        kind: Value(ReaderKind.comic.storageValue),
        format: Value(format.storageValue),
        title: Value(existing?.title ?? title),
        filePath: Value(storedPath),
        contentHash: Value(hash),
        coverPath: Value(coverPath),
        pageCount: Value(pages.length),
        pageOrderVersion: const Value(ComicPageOrder.version),
        addedAt: Value(existing?.addedAt ?? now),
        updatedAt: Value(now),
      ),
    );
    return existing == null ? _Outcome.added : _Outcome.updated;
  }

  Future<String> _ensureCover(
    String hash,
    String archivePath,
    String firstPage,
  ) async {
    final ext = p.extension(firstPage).toLowerCase();
    final coverPath = p.join(_coversDir.path, '$hash$ext');
    if (await File(coverPath).exists()) return coverPath;
    final bytes = await ComicArchive.readEntry(archivePath, firstPage);
    if (bytes == null) throw ImportException('封面提取失败');
    await _coversDir.create(recursive: true);
    await File(coverPath).writeAsBytes(bytes, flush: true);
    return coverPath;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Directory get _libraryDir =>
      Directory(p.join(supportDirectory.path, 'library'));
  Directory get _coversDir =>
      Directory(p.join(supportDirectory.path, 'covers'));
}

enum _Outcome { added, updated }

class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

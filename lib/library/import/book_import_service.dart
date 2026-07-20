import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../../readers/book/book_epub.dart';
import '../persistence/app_database.dart';
import 'import_models.dart';

/// Imports reflow EPUB into content-addressed storage for the book app.
class BookImportService {
  BookImportService({required this.database, required this.supportDirectory});

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
      } on BookEpubException catch (e) {
        failures.add(ImportFailure(path: path, reason: e.message));
      } catch (e) {
        failures.add(ImportFailure(path: path, reason: e.toString()));
      }
    }
    return ImportResult(added: added, updated: updated, failures: failures);
  }

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
    if (format != ReaderFormat.epub) {
      throw ImportException('图书目前仅支持 EPUB：${p.extension(path)}');
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

    final doc = await BookEpub.open(storedPath);
    final coverPath = await _ensureCover(hash, storedPath, doc);
    final fallbackTitle = p.basenameWithoutExtension(path);
    final title =
        doc.title.trim().isNotEmpty ? doc.title.trim() : fallbackTitle;

    final existing = await database.readingItemByHash(hash);
    final now = DateTime.now();
    await database.upsertReadingItem(
      ReadingItemsCompanion(
        id: Value(existing?.id ?? hash),
        kind: Value(ReaderKind.book.storageValue),
        format: Value(ReaderFormat.epub.storageValue),
        title: Value(existing?.title ?? title),
        filePath: Value(storedPath),
        contentHash: Value(hash),
        coverPath: Value(coverPath),
        pageCount: Value(doc.sectionCount),
        pageOrderVersion: const Value(0),
        addedAt: Value(existing?.addedAt ?? now),
        updatedAt: Value(now),
      ),
    );
    return existing == null ? _Outcome.added : _Outcome.updated;
  }

  Future<String?> _ensureCover(
    String hash,
    String epubPath,
    BookEpubDocument doc,
  ) async {
    if (doc.coverEntry == null) return null;
    final bytes = await BookEpub.readEntry(epubPath, doc.coverEntry!);
    if (bytes == null || bytes.isEmpty) return null;
    final ext = p.extension(doc.coverEntry!).toLowerCase();
    final safe = (ext.isEmpty || ext == '.xml') ? '.jpg' : ext;
    final coverPath = p.join(_coversDir.path, '$hash$safe');
    if (await File(coverPath).exists()) return coverPath;
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

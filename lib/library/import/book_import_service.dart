import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../../readers/book/foliate_import_probe.dart';
import '../../readers/book/foliate_js_bridge.dart';
import '../persistence/app_database.dart';
import 'import_models.dart';
import 'import_staging.dart';

/// Imports reflow EPUB into content-addressed storage for the book app.
class BookImportService {
  BookImportService({
    required this.database,
    required this.supportDirectory,
    EpubImportProbe? probe,
    this.onTiming,
  }) : _probe = probe ?? const FoliateJsImportProbe(),
       _staging = ImportStagingArea(supportDirectory);

  final AppDatabase database;
  final Directory supportDirectory;
  final ImportTimingListener? onTiming;
  final EpubImportProbe _probe;
  final ImportStagingArea _staging;

  EpubImportProbe get probe => _probe;

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
      } on FoliateImportException catch (e) {
        failures.add(ImportFailure(path: path, reason: e.message));
      } catch (e) {
        failures.add(ImportFailure(path: path, reason: e.toString()));
      }
    }
    return ImportResult(added: added, updated: updated, failures: failures);
  }

  Future<ImportResult> importOne(
    String path, {
    FoliateImportSnapshot? snapshot,
  }) async {
    try {
      final outcome = await _importOne(path, snapshot: snapshot);
      return ImportResult(
        added: outcome == _Outcome.added ? 1 : 0,
        updated: outcome == _Outcome.updated ? 1 : 0,
        failures: const [],
      );
    } on ImportException catch (e) {
      return ImportResult(
        added: 0,
        updated: 0,
        failures: [ImportFailure(path: path, reason: e.message)],
      );
    } on FoliateImportException catch (e) {
      return ImportResult(
        added: 0,
        updated: 0,
        failures: [ImportFailure(path: path, reason: e.message)],
      );
    } catch (e) {
      return ImportResult(
        added: 0,
        updated: 0,
        failures: [ImportFailure(path: path, reason: e.toString())],
      );
    }
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

  Future<_Outcome> _importOne(
    String path, {
    FoliateImportSnapshot? snapshot,
  }) async {
    final trace = ImportPipelineTrace(
      pipeline: 'book',
      sourcePath: path,
      onTiming: onTiming,
    );
    final format = ReaderFormat.fromExtension(p.extension(path));
    if (format != ReaderFormat.epub) {
      throw ImportException('图书目前仅支持 EPUB：${p.extension(path)}');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ImportException('文件不存在');
    }
    trace.mark('validated');

    StagedContentFile? content;
    StagedImportFile? cover;
    try {
      content = await _staging.stageContent(file);
      final hash = content.hash;
      trace.mark('content-staged');

      final metadata =
          snapshot ?? await _probe.inspect(content.file.stagedPath);
      if (metadata.sectionCount <= 0) {
        throw const FoliateImportException('EPUB 没有可阅读的正文');
      }
      trace.mark('metadata-ready');
      cover = await _stageCover(hash, metadata);
      trace.mark('cover-staged');
      final fallbackTitle = p.basenameWithoutExtension(path);
      final title = metadata.title.trim().isNotEmpty
          ? metadata.title.trim()
          : fallbackTitle;

      final existing = await database.readingItemByHash(hash);

      final storedPath = await content.file.commit();
      final coverPath = await cover?.commit();
      trace.mark('files-committed');
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
          pageCount: Value(metadata.sectionCount),
          pageOrderVersion: const Value(0),
          addedAt: Value(existing?.addedAt ?? now),
          updatedAt: Value(now),
        ),
      );
      trace.mark('database-committed');
      return existing == null ? _Outcome.added : _Outcome.updated;
    } catch (_) {
      await rollbackStagedFiles([cover, content?.file]);
      trace.mark('rolled-back');
      rethrow;
    }
  }

  Future<StagedImportFile?> _stageCover(
    String hash,
    FoliateImportSnapshot metadata,
  ) async {
    final bytes = metadata.coverBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final extension = switch (metadata.coverMimeType?.toLowerCase()) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'image/svg+xml' => '.svg',
      _ => '.jpg',
    };
    return _staging.stageCover(hash: hash, extension: extension, bytes: bytes);
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

enum _Outcome { added, updated }

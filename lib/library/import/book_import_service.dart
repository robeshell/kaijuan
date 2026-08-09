import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../../readers/book/foliate_import_probe.dart';
import '../../readers/book/foliate_js_bridge.dart';
import '../persistence/app_database.dart';
import '../storage/library_paths.dart';
import 'import_models.dart';
import 'import_sources.dart';
import 'import_staging.dart';
import 'default_cover_generator.dart';

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

  static const supportedFormats = {
    ReaderFormat.epub,
    ReaderFormat.fb2,
    ReaderFormat.mobi,
    ReaderFormat.azw3,
    ReaderFormat.pdf,
    ReaderFormat.txt,
    ReaderFormat.markdown,
  };

  ImportStagingArea get stagingArea => _staging;

  EpubImportProbe get probe => _probe;

  /// Backfills the deterministic cover for books imported by older versions.
  ///
  /// New imports go through [_stageCover], but older rows may legitimately
  /// have no cover path because the source did not contain artwork. Keeping
  /// the repair here means every import entry point and the startup migration
  /// use exactly the same cover generation and storage rules.
  Future<int> ensureDefaultCovers() async {
    final query = database.select(database.readingItems)
      ..where(
        (t) =>
            t.kind.equals(ReaderKind.book.storageValue) &
            (t.coverPath.isNull() | t.coverPath.equals('')),
      );
    final items = await query.get();
    var repaired = 0;
    for (final item in items) {
      try {
        final staged = await _staging.stageCover(
          hash: DefaultCoverGenerator.storageKey(item.contentHash),
          extension: '.png',
          bytes: await DefaultCoverGenerator.png(
            seed: item.contentHash,
            title: item.title,
          ),
        );
        final coverPath = await staged.commit();
        try {
          await (database.update(database.readingItems)
                ..where((t) => t.id.equals(item.id)))
              .write(ReadingItemsCompanion(coverPath: Value(coverPath)));
        } catch (_) {
          await rollbackStagedFiles([staged]);
          rethrow;
        }
        repaired++;
      } catch (error) {
        // A legacy row must not prevent the library from opening. The next
        // launch can retry a failed repair after the storage becomes writable.
        debugPrint(
          '[Library] default cover repair skipped for ${item.id}: $error',
        );
      }
    }
    return repaired;
  }

  Future<ImportResult> importPaths(List<String> paths) async {
    var added = 0;
    var updated = 0;
    final failures = <ImportFailure>[];
    for (final path in paths) {
      try {
        final outcome = await _importOne(path);
        outcome == ImportCommitOutcome.added ? added++ : updated++;
      } on ImportException catch (e) {
        failures.add(ImportFailure(path: path, reason: e.message));
      } on FoliateImportException catch (e) {
        failures.add(ImportFailure(path: path, reason: e.message));
      } catch (e) {
        debugPrint('[Import] book import failed for $path: $e');
        failures.add(ImportFailure(path: path, reason: '导入失败，请确认文件完整且格式受支持'));
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
        added: outcome == ImportCommitOutcome.added ? 1 : 0,
        updated: outcome == ImportCommitOutcome.updated ? 1 : 0,
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
      debugPrint('[Import] book import failed for $path: $e');
      return ImportResult(
        added: 0,
        updated: 0,
        failures: [ImportFailure(path: path, reason: '导入失败，请确认文件完整且格式受支持')],
      );
    }
  }

  Future<void> deleteItem(String id) async {
    final item = await database.readingItemById(id);
    if (item == null) return;
    await database.deleteReadingItem(id);
    final paths = LibraryPaths(supportDirectory);
    final file = await paths.resolveExisting(
      item.filePath,
      contentHash: item.contentHash,
    );
    await _deleteIfExists(file?.path ?? item.filePath);
    if (item.coverPath != null) {
      final cover = await paths.resolveExisting(
        item.coverPath!,
        contentHash: item.contentHash,
        cover: true,
      );
      await _deleteIfExists(cover?.path ?? item.coverPath!);
    }
  }

  Future<ImportCommitOutcome> _importOne(
    String path, {
    FoliateImportSnapshot? snapshot,
  }) async {
    final candidate = ImportCandidate(
      source: LocalFileImportSource.picked(path),
    );
    final format = candidate.format;
    if (format == null || !supportedFormats.contains(format)) {
      throw ImportException('图书暂不支持此格式：${p.extension(path)}');
    }
    if (format == ReaderFormat.txt || format == ReaderFormat.markdown) {
      throw const ImportException('TXT / Markdown 请通过统一导入管线转换');
    }
    final file = candidate.localFile!;
    if (!await file.exists()) {
      throw ImportException('文件不存在');
    }
    final content = await _staging.stageContent(file);
    return importStaged(
      candidate: candidate,
      format: format,
      content: content,
      snapshot: snapshot,
    );
  }

  /// Completes the book half of the shared pipeline after source bytes have
  /// already been staged and hashed.
  Future<ImportCommitOutcome> importStaged({
    required ImportCandidate candidate,
    required ReaderFormat format,
    required StagedContentFile content,
    FoliateImportSnapshot? snapshot,
    String? titleOverride,
  }) async {
    if (!supportedFormats.contains(format)) {
      throw ImportException('图书暂不支持此格式：${candidate.displayName}');
    }
    final trace = ImportPipelineTrace(
      pipeline: 'book',
      sourcePath: candidate.displayName,
      onTiming: onTiming,
    );
    trace.mark('validated');

    StagedImportFile? cover;
    try {
      final hash = content.hash;
      trace.mark('content-staged');

      final metadata =
          snapshot ?? await _probe.inspect(content.file.stagedPath);
      if (metadata.sectionCount <= 0) {
        throw const FoliateImportException('图书没有可阅读的正文');
      }
      trace.mark('metadata-ready');
      final fallbackTitle = p.basenameWithoutExtension(candidate.displayName);
      final title = titleOverride?.trim().isNotEmpty == true
          ? titleOverride!.trim()
          : metadata.title.trim().isNotEmpty
          ? metadata.title.trim()
          : fallbackTitle;

      final existing = await database.readingItemByHash(hash);
      cover = await _stageCover(
        hash,
        metadata,
        title: existing?.title ?? title,
      );
      trace.mark('cover-staged');

      final storedPath = await content.file.commit();
      final coverPath = await cover?.commit();
      trace.mark('files-committed');
      final now = DateTime.now();
      await database.upsertReadingItem(
        ReadingItemsCompanion(
          id: Value(existing?.id ?? hash),
          kind: Value(ReaderKind.book.storageValue),
          format: Value(format.storageValue),
          title: Value(existing?.title ?? title),
          // Absolute under current support root; [LibraryPaths.rebindDatabase]
          // rewrites container UUID after iOS reinstall.
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
      return existing == null
          ? ImportCommitOutcome.added
          : ImportCommitOutcome.updated;
    } catch (_) {
      await rollbackStagedFiles([cover, content.file]);
      trace.mark('rolled-back');
      rethrow;
    }
  }

  Future<StagedImportFile?> _stageCover(
    String hash,
    FoliateImportSnapshot metadata, {
    required String title,
  }) async {
    final bytes = metadata.coverBytes;
    if (bytes == null || bytes.isEmpty) {
      return _staging.stageCover(
        hash: DefaultCoverGenerator.storageKey(hash),
        extension: '.png',
        bytes: await DefaultCoverGenerator.png(seed: hash, title: title),
      );
    }
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

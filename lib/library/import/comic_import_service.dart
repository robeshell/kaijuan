import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../persistence/app_database.dart';
import '../storage/library_paths.dart';
import 'comic_archive.dart';
import 'import_models.dart';
import 'import_sources.dart';
import 'import_staging.dart';

/// Imports comic files into content-addressed storage:
///
///   `<appSupport>/library/<contentHash>.<ext>` — the source file
///   `<appSupport>/covers/<contentHash>.<ext>`  — extracted first page
///
/// Supports CBZ/ZIP and **image-based EPUB** (OPF spine → images).
/// Content addressing makes re-imports idempotent and dedup free.
class ComicImportService {
  ComicImportService({
    required this.database,
    required this.supportDirectory,
    this.onTiming,
  }) : _staging = ImportStagingArea(supportDirectory);

  final AppDatabase database;
  final Directory supportDirectory;
  final ImportTimingListener? onTiming;
  final ImportStagingArea _staging;

  ImportStagingArea get stagingArea => _staging;

  static const supportedFormats = {
    ReaderFormat.cbz,
    ReaderFormat.zip,
    ReaderFormat.epub,
  };

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

  Future<ImportCommitOutcome> _importOne(String path) async {
    final candidate = ImportCandidate(
      source: LocalFileImportSource.picked(path),
    );
    final format = candidate.format;
    if (format == null || !supportedFormats.contains(format)) {
      throw ImportException('不支持的漫画格式：${p.extension(path)}');
    }
    final file = candidate.localFile!;
    if (!await file.exists()) {
      throw ImportException('文件不存在');
    }
    final content = await _staging.stageContent(file);
    return importStaged(candidate: candidate, format: format, content: content);
  }

  /// Completes the comic half of the shared pipeline after the source bytes
  /// have already been staged and hashed.
  Future<ImportCommitOutcome> importStaged({
    required ImportCandidate candidate,
    required ReaderFormat format,
    required StagedContentFile content,
  }) async {
    if (!supportedFormats.contains(format)) {
      throw ImportException('不支持的漫画格式：${candidate.displayName}');
    }
    final trace = ImportPipelineTrace(
      pipeline: 'comic',
      sourcePath: candidate.displayName,
      onTiming: onTiming,
    );
    trace.mark('validated');

    StagedImportFile? cover;
    try {
      final hash = content.hash;
      trace.mark('content-staged');

      final listing = await ComicArchive.listPagesDetailed(
        content.file.stagedPath,
      );
      if (listing.pageNames.isEmpty) {
        throw ImportException(
          format == ReaderFormat.epub
              ? 'EPUB 里找不到可用的图片页（仅支持页图式 / 固定版式漫画 EPUB）'
              : '压缩包里找不到图片页',
        );
      }
      trace.mark('page-list-ready');

      final coverEntry = listing.pageNames.firstWhere(
        (entry) => ComicArchive.imageExtensions.contains(
          p.extension(entry).toLowerCase(),
        ),
        orElse: () => listing.pageNames.first,
      );
      final coverBytes = await ComicArchive.readEntry(
        content.file.stagedPath,
        coverEntry,
      );
      if (coverBytes == null) throw ImportException('封面提取失败');
      final coverExtension = p.extension(coverEntry).toLowerCase();
      cover = await _staging.stageCover(
        hash: hash,
        extension: coverExtension.isEmpty ? '.img' : coverExtension,
        bytes: coverBytes,
      );
      trace.mark('cover-staged');

      final fallbackTitle = p.basenameWithoutExtension(candidate.displayName);
      final title = (listing.title?.trim().isNotEmpty ?? false)
          ? listing.title!.trim()
          : fallbackTitle;
      final existing = await database.readingItemByHash(hash);
      final storedPath = await content.file.commit();
      final coverPath = await cover.commit();
      trace.mark('files-committed');
      final now = DateTime.now();
      await database.upsertReadingItem(
        ReadingItemsCompanion(
          id: Value(existing?.id ?? hash),
          kind: Value(ReaderKind.comic.storageValue),
          format: Value(format.storageValue),
          title: Value(existing?.title ?? title),
          // Absolute under current support root; rebound after iOS reinstall.
          filePath: Value(storedPath),
          contentHash: Value(hash),
          coverPath: Value(coverPath),
          pageCount: Value(listing.pageNames.length),
          pageOrderVersion: const Value(ComicPageOrder.version),
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

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

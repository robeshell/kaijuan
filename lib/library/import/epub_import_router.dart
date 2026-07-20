import 'dart:io';

import 'package:archive/archive_io.dart';

import '../../domain/reader_models.dart';
import '../../readers/book/book_epub.dart';
import 'comic_archive.dart';
import 'comic_import_service.dart';
import 'book_import_service.dart';
import 'import_models.dart';

/// Decides whether an EPUB should be treated as a reflow book or a page-image
/// comic, then imports it through the right service.
///
/// Detection rule:
/// 1. Book wins if the OPF spine contains at least one section with readable
///    plain text.
/// 2. Otherwise, if the package has page-image spine entries (or fallback
///    images), it is imported as a comic.
/// 3. Otherwise the import fails with a Chinese reason.
class EpubImportRouter {
  EpubImportRouter({
    required this.comicImport,
    required this.bookImport,
  });

  final ComicImportService comicImport;
  final BookImportService bookImport;

  /// Imports a single EPUB file using the detected reader kind.
  ///
  /// Returns an [ImportResult] representing exactly one file (added/updated
  /// will be at most 1).
  Future<ImportResult> importOne(String path) async {
    final kind = await detectKind(path);
    if (kind == ReaderKind.book) {
      return bookImport.importPaths([path]);
    }
    return comicImport.importPaths([path]);
  }

  /// Imports a list of EPUB files, routing each one independently.
  Future<ImportResult> importPaths(List<String> paths) async {
    var added = 0;
    var updated = 0;
    final failures = <ImportFailure>[];
    for (final path in paths) {
      try {
        final result = await importOne(path);
        added += result.added;
        updated += result.updated;
        failures.addAll(result.failures);
      } on ImportException catch (e) {
        failures.add(ImportFailure(path: path, reason: e.message));
      } catch (e) {
        failures.add(ImportFailure(path: path, reason: e.toString()));
      }
    }
    return ImportResult(added: added, updated: updated, failures: failures);
  }

  /// Opens the EPUB once and inspects its contents.
  static Future<ReaderKind> detectKind(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ImportException('文件不存在');
    }

    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);

      // 1. Prefer reflow book if there is readable text in the spine.
      try {
        final doc = BookEpub.parseArchive(archive);
        final hasText = doc.sections.any(
          (s) => s.plainText.trim().isNotEmpty,
        );
        if (hasText) return ReaderKind.book;
      } on BookEpubException catch (_) {
        // Not a readable reflow EPUB; continue to page-image detection.
      }

      // 2. Fall back to page-image comic if the spine yields images.
      final listing = ComicArchive.listFromArchive(archive);
      if (listing.pageNames.isNotEmpty) return ReaderKind.comic;

      throw const ImportException(
        '无法识别：页图请用 CBZ/ZIP 等图包格式，正文 EPUB 需含可读章节',
      );
    } finally {
      await input.close();
    }
  }
}

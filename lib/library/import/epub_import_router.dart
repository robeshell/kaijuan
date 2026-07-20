import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

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
/// 1. Open the zip once; try both the book parser and the page-image listing.
/// 2. Book wins only when the total plain-text length across all spine sections
///    exceeds a threshold (currently 500 chars). Short text — chapter titles,
///    page-number wrappers — does not turn a page-image EPUB into a book.
/// 3. Otherwise, if the package has page-image spine entries (or fallback
///    images), it is imported as a comic.
/// 4. Otherwise the import fails with a Chinese reason.
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

  /// If the average plain-text per section is under this threshold, the EPUB
  /// is treated as page-image (comic) even when the book parser finds some
  /// text. Manga EPUBs often have XHTML wrappers carrying only chapter titles
  /// or page numbers — a few dozen chars per section.
  static const _maxTextPerSectionForComic = 80;

  /// Opens the EPUB once and inspects its contents.
  static Future<ReaderKind> detectKind(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ImportException('文件不存在');
    }

    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);

      // --- Book parser ---------------------------------------------------
      int totalBookText = 0;
      int sectionCount = 0;
      try {
        final doc = BookEpub.parseArchive(archive);
        sectionCount = doc.sections.length;
        for (final s in doc.sections) {
          totalBookText += s.plainText.length;
        }
      } on BookEpubException catch (_) {
        // Not a readable reflow EPUB; continue to page-image detection.
      }

      // --- Image listing -------------------------------------------------
      final listing = ComicArchive.listFromArchive(archive);
      final imageCount = listing.pageNames.length;

      // --- Decision ------------------------------------------------------
      // Average text per section lets us tell reflow books (hundreds of
      // chars per section) from page-image wrappers (a few chars of title /
      // page number per section).
      final avgTextPerSection =
          sectionCount > 0 ? totalBookText / sectionCount : 0.0;

      debugPrint(
        '[EpubImportRouter] $path\n'
        '  book sections=$sectionCount totalText=$totalBookText'
        ' avgText=${avgTextPerSection.toStringAsFixed(0)}\n'
        '  images=$imageCount',
      );

      if (sectionCount > 0 && imageCount > 0) {
        // Both engines found content. Use text-per-section average.
        if (avgTextPerSection <= _maxTextPerSectionForComic) {
          debugPrint('[EpubImportRouter] → comic (low text per section)');
          return ReaderKind.comic;
        }
        debugPrint('[EpubImportRouter] → book (substantial text)');
        return ReaderKind.book;
      }

      if (imageCount > 0) {
        debugPrint('[EpubImportRouter] → comic (images, no text sections)');
        return ReaderKind.comic;
      }
      if (sectionCount > 0) {
        debugPrint('[EpubImportRouter] → book (text, no images)');
        return ReaderKind.book;
      }

      throw const ImportException(
        '无法识别：页图请用 CBZ/ZIP 等图包格式，正文 EPUB 需含可读章节',
      );
    } finally {
      await input.close();
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';
import '../../readers/book/foliate_import_probe.dart';
import '../../readers/book/foliate_js_bridge.dart';
import 'comic_archive.dart';
import 'comic_import_service.dart';
import 'book_import_service.dart';
import 'import_models.dart';

/// Decides whether an EPUB should be treated as a reflow book or a page-image
/// comic, then imports it through the right service.
///
/// Detection rule:
/// 1. Probe the package through file-backed readers; never materialize the
///    complete EPUB as a Dart byte array.
/// 2. A parsed EPUB defaults to book. Cover art and occasional illustrations
///    are valid book resources and must not route it to the comic engine.
/// 3. It becomes comic only when at least 80% of sampled spine sections are
///    image-only wrappers with very little text.
/// 4. Otherwise the import fails with a Chinese reason.
class EpubImportRouter {
  EpubImportRouter({
    required this.comicImport,
    required this.bookImport,
    this.onTiming,
  });

  final ComicImportService comicImport;
  final BookImportService bookImport;
  final ImportTimingListener? onTiming;

  /// Imports a single EPUB file using the detected reader kind.
  ///
  /// Returns an [ImportResult] representing exactly one file (added/updated
  /// will be at most 1).
  Future<ImportResult> importOne(String path) async {
    final detection = await _detectKind(
      path,
      probe: bookImport.probe,
      onTiming: onTiming,
    );
    if (detection.kind == ReaderKind.book) {
      return bookImport.importOne(path, snapshot: detection.snapshot);
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
  static const _minimumImageOnlySampleRatio = 0.8;

  /// Inspects the EPUB through bounded, file-backed probes.
  static Future<ReaderKind> detectKind(
    String path, {
    EpubImportProbe? probe,
    ImportTimingListener? onTiming,
  }) async => (await _detectKind(
    path,
    probe: probe ?? const FoliateJsImportProbe(),
    onTiming: onTiming,
  )).kind;

  static Future<({ReaderKind kind, FoliateImportSnapshot? snapshot})>
  _detectKind(
    String path, {
    required EpubImportProbe probe,
    ImportTimingListener? onTiming,
  }) async {
    final trace = ImportPipelineTrace(
      pipeline: 'foliate-probe',
      sourcePath: path,
      onTiming: onTiming,
    );
    final file = File(path);
    if (!await file.exists()) {
      throw const ImportException('文件不存在');
    }
    trace.mark('validated');

    FoliateImportSnapshot? snapshot;
    Object? probeError;
    try {
      snapshot = await probe.inspect(path);
    } catch (error) {
      probeError = error;
      // Not a readable reflow EPUB; continue to page-image detection.
    }
    trace.mark('text-sampled');

    // --- Image listing -------------------------------------------------
    final listing = await ComicArchive.listPagesDetailed(path);
    final imageCount = listing.pageNames.length;
    trace.mark('images-listed');

    // --- Decision ------------------------------------------------------
    final sectionCount = snapshot?.sectionCount ?? 0;
    final sampledSectionCount = snapshot?.sampledSections ?? 0;
    final sampledImageOnlySectionCount =
        snapshot?.sampledImageOnlySections ?? 0;
    final totalBookText = snapshot?.totalTextLength ?? 0;
    final avgTextPerSection = sampledSectionCount > 0
        ? totalBookText / sampledSectionCount
        : 0.0;

    if (kDebugMode) {
      debugPrint(
        '[EpubImportRouter] ${p.basename(path)}\n'
        '  book sections=$sectionCount sampled=$sampledSectionCount '
        'imageOnly=$sampledImageOnlySectionCount totalText=$totalBookText'
        ' avgText=${avgTextPerSection.toStringAsFixed(0)}\n'
        '  images=$imageCount',
      );
    }

    final kind = classifyMetrics(
      sectionCount: sectionCount,
      sampledSectionCount: sampledSectionCount,
      sampledImageOnlySectionCount: sampledImageOnlySectionCount,
      totalBookText: totalBookText,
      imageCount: imageCount,
    );
    if (kind != null) {
      if (kDebugMode) {
        debugPrint(
          kind == ReaderKind.book
              ? '[EpubImportRouter] → book'
              : '[EpubImportRouter] → comic',
        );
      }
      trace.mark('classified');
      return (kind: kind, snapshot: snapshot);
    }

    trace.mark('unrecognized');
    if (probeError is FoliateImportException) {
      throw ImportException('无法识别 EPUB：${probeError.message}');
    }
    throw const ImportException('无法识别：页图请用 CBZ/ZIP 等图包格式，正文 EPUB 需含可读章节');
  }

  /// Pure classification boundary kept explicit for regression tests.
  static ReaderKind? classifyMetrics({
    required int sectionCount,
    required int sampledSectionCount,
    required int sampledImageOnlySectionCount,
    required int totalBookText,
    required int imageCount,
  }) {
    if (sectionCount > 0) {
      if (imageCount <= 0) return ReaderKind.book;
      final average = sampledSectionCount > 0
          ? totalBookText / sampledSectionCount
          : 0.0;
      final imageOnlyRatio = sampledSectionCount > 0
          ? sampledImageOnlySectionCount / sampledSectionCount
          : 0.0;
      final isPageImagePublication =
          sampledImageOnlySectionCount > 0 &&
          imageOnlyRatio >= _minimumImageOnlySampleRatio &&
          average <= _maxTextPerSectionForComic;
      return isPageImagePublication ? ReaderKind.comic : ReaderKind.book;
    }
    return null;
  }
}

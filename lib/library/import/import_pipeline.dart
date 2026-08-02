import '../../domain/reader_models.dart';
import '../../readers/book/foliate_import_probe.dart';
import 'book_import_service.dart';
import 'comic_import_service.dart';
import 'epub_import_router.dart';
import 'import_models.dart';
import 'import_sources.dart';
import 'import_staging.dart';

/// The single hand-off between import methods and format services.
///
/// Every source is staged exactly once here. Format services receive the
/// staged file and only own format-specific parsing, cover extraction and DB
/// commit. This keeps a future WiFi/WebDAV/OPDS adapter from growing a second
/// copy of the local import rules.
class ImportPipeline {
  ImportPipeline({
    required ComicImportService comicImport,
    required BookImportService bookImport,
    ImportStagingArea? staging,
    EpubImportRouter? epubRouter,
  }) : _comicImport = comicImport,
       _bookImport = bookImport,
       _staging = staging ?? comicImport.stagingArea,
       _epubRouter =
           epubRouter ??
           EpubImportRouter(
             comicImport: comicImport,
             bookImport: bookImport,
             staging: staging ?? comicImport.stagingArea,
           );

  final ComicImportService _comicImport;
  final BookImportService _bookImport;
  final ImportStagingArea _staging;
  final EpubImportRouter _epubRouter;

  Future<ImportResult> importCandidates(
    Iterable<ImportCandidate> candidates,
  ) async {
    var result = const ImportResult();
    for (final candidate in candidates) {
      result += await _importOne(candidate);
    }
    return result;
  }

  Future<ImportResult> _importOne(ImportCandidate candidate) async {
    final format = candidate.format;
    if (format == null) {
      return ImportResult(
        failures: [
          ImportFailure(
            path: candidate.displayName,
            reason: '无法从文件名识别格式：${candidate.displayName}',
          ),
        ],
      );
    }

    final route = _routeFor(format);
    if (route == _ImportRoute.unsupported) {
      return ImportResult(
        failures: [
          ImportFailure(
            path: candidate.displayName,
            reason: '暂不支持的导入格式：${candidate.displayName}',
          ),
        ],
      );
    }

    StagedContentFile? content;
    try {
      content = await _staging.stageContentStream(
        sourceName: candidate.displayName,
        bytes: candidate.source.openRead(),
      );
    } catch (error) {
      return ImportResult(
        failures: [
          ImportFailure(path: candidate.displayName, reason: error.toString()),
        ],
      );
    }

    try {
      final outcome = switch (route) {
        _ImportRoute.comic => await _comicImport.importStaged(
          candidate: candidate,
          format: format,
          content: content,
        ),
        _ImportRoute.epub => await _epubRouter.importStaged(
          candidate: candidate,
          format: format,
          content: content,
        ),
        _ImportRoute.book => await _bookImport.importStaged(
          candidate: candidate,
          format: format,
          content: content,
        ),
        _ImportRoute.unsupported => throw StateError('unreachable route'),
      };
      return ImportResult(
        added: outcome == ImportCommitOutcome.added ? 1 : 0,
        updated: outcome == ImportCommitOutcome.updated ? 1 : 0,
      );
    } on ImportException catch (e) {
      return ImportResult(
        failures: [
          ImportFailure(path: candidate.displayName, reason: e.message),
        ],
      );
    } on FoliateImportException catch (e) {
      return ImportResult(
        failures: [
          ImportFailure(path: candidate.displayName, reason: e.message),
        ],
      );
    } catch (error) {
      return ImportResult(
        failures: [
          ImportFailure(path: candidate.displayName, reason: error.toString()),
        ],
      );
    }
  }

  _ImportRoute _routeFor(ReaderFormat format) {
    if (ComicImportService.supportedFormats.contains(format)) {
      return format == ReaderFormat.epub
          ? _ImportRoute.epub
          : _ImportRoute.comic;
    }
    if (BookImportService.supportedFormats.contains(format)) {
      return _ImportRoute.book;
    }
    return _ImportRoute.unsupported;
  }
}

enum _ImportRoute { comic, epub, book, unsupported }

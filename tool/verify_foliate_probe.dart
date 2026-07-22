import 'package:flutter/widgets.dart';
import 'package:kaika/domain/reader_models.dart';
import 'package:kaika/library/import/epub_import_router.dart';
import 'package:kaika/readers/book/foliate_import_probe.dart';

/// Runs Foliate metadata probe + EpubImportRouter on a real EPUB path.
///
/// Usage:
/// flutter run -d <device> -t tool/verify_foliate_probe.dart \
///   --dart-define=EPUB_PATH=/path/to/book.epub
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const epubPath = String.fromEnvironment('EPUB_PATH');
  if (epubPath.isEmpty) {
    throw StateError('Set --dart-define=EPUB_PATH=/path/to/book.epub');
  }

  final probe = const FoliateJsImportProbe(timeout: Duration(seconds: 45));
  debugPrint('[verify] probing $epubPath');
  final snapshot = await probe.inspect(epubPath);
  debugPrint(
    '[verify] probe ok title=${snapshot.title} sections=${snapshot.sectionCount} '
    'sampled=${snapshot.sampledSections} imageOnly=${snapshot.sampledImageOnlySections} '
    'text=${snapshot.totalTextLength}',
  );

  final kind = await EpubImportRouter.detectKind(epubPath, probe: probe);
  debugPrint('[verify] router -> ${kind.name}');
  if (kind != ReaderKind.book) {
    throw StateError('Expected book route, got ${kind.name}');
  }
  debugPrint('[verify] PASS');
}

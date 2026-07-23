import 'package:flutter/widgets.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/import/epub_import_router.dart';
import 'package:kaijuan/library/import/epub_kind_probe.dart';
import 'package:kaijuan/readers/book/foliate_import_probe.dart';

/// Runs Dart kind probe (+ optional Foliate metadata) on a real EPUB path.
///
/// Usage:
/// flutter run -d device -t tool/verify_foliate_probe.dart \
///   --dart-define=EPUB_PATH=/path/to/book.epub
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const epubPath = String.fromEnvironment('EPUB_PATH');
  if (epubPath.isEmpty) {
    throw StateError('Set --dart-define=EPUB_PATH=/path/to/book.epub');
  }

  debugPrint('[verify] dart kind probe $epubPath');
  final dart = await EpubKindProbe.inspect(epubPath);
  debugPrint(
    '[verify] dart sections=${dart.sectionCount} sampled=${dart.sampledSectionCount} '
    'imageOnly=${dart.sampledImageOnlySections} text=${dart.totalTextLength} '
    'images=${dart.imageCount}',
  );

  final kind = await EpubImportRouter.detectKind(epubPath);
  debugPrint('[verify] router -> ${kind.name}');

  if (kind == ReaderKind.book) {
    final probe = const FoliateJsImportProbe(timeout: Duration(seconds: 45));
    final snapshot = await probe.inspect(epubPath);
    debugPrint(
      '[verify] foliate title=${snapshot.title} sections=${snapshot.sectionCount} '
      'sampled=${snapshot.sampledSections} imageOnly=${snapshot.sampledImageOnlySections} '
      'text=${snapshot.totalTextLength}',
    );
  }

  debugPrint('[verify] PASS kind=${kind.name}');
}

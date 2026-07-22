import 'dart:async';

import 'package:kaika/readers/book/foliate_import_probe.dart';
import 'package:kaika/readers/book/foliate_js_bridge.dart';

class FakeEpubImportProbe implements EpubImportProbe {
  FakeEpubImportProbe(this.handler);

  FutureOr<FoliateImportSnapshot> Function(String path) handler;
  int callCount = 0;

  @override
  Future<FoliateImportSnapshot> inspect(String path) async {
    callCount++;
    return handler(path);
  }
}

FoliateImportSnapshot reflowSnapshot({
  String title = '测试图书',
  int sectionCount = 1,
}) => FoliateImportSnapshot(
  title: title,
  authors: const [],
  sectionCount: sectionCount,
  sampledSections: sectionCount.clamp(0, 12),
  sampledImageOnlySections: 0,
  totalTextLength: sectionCount * 500,
);

FoliateImportSnapshot imageSnapshot({
  String title = 'Image Only',
  int sectionCount = 1,
}) => FoliateImportSnapshot(
  title: title,
  authors: const [],
  sectionCount: sectionCount,
  sampledSections: sectionCount.clamp(0, 12),
  sampledImageOnlySections: sectionCount.clamp(0, 12),
  totalTextLength: 0,
);

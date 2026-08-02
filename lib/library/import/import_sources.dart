import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/reader_models.dart';

/// How a file is handed to the import pipeline.
///
/// This is deliberately independent from [ReaderFormat]. A local file, a
/// dragged file, and a WebDAV download can all carry the same EPUB or CBZ.
enum ImportMethod {
  localFile,
  directoryScan,
  dragDrop,
  share,
  wifi,
  webDav,
  opds,
}

extension ImportMethodLabel on ImportMethod {
  String get label => switch (this) {
    ImportMethod.localFile => '本地文件',
    ImportMethod.directoryScan => '文件夹扫描',
    ImportMethod.dragDrop => '拖拽',
    ImportMethod.share => '系统分享',
    ImportMethod.wifi => 'WiFi 传书',
    ImportMethod.webDav => 'WebDAV',
    ImportMethod.opds => 'OPDS',
  };
}

/// A source adapter exposes bytes and a stable display name, but never knows
/// which reader engine will consume the file.
abstract interface class ImportSource {
  ImportMethod get method;

  String get displayName;

  String? get mimeType;

  Stream<List<int>> openRead();
}

/// File-backed source used by the current picker and directory scanner.
class LocalFileImportSource implements ImportSource {
  LocalFileImportSource(
    this.file, {
    required this.method,
    String? displayName,
    this.mimeType,
  }) : displayName = displayName ?? p.basename(file.path);

  factory LocalFileImportSource.picked(String path) =>
      LocalFileImportSource(File(path), method: ImportMethod.localFile);

  factory LocalFileImportSource.scanned(String path) =>
      LocalFileImportSource(File(path), method: ImportMethod.directoryScan);

  final File file;
  @override
  final ImportMethod method;
  @override
  final String displayName;
  @override
  final String? mimeType;

  @override
  Stream<List<int>> openRead() => file.openRead();
}

/// The value passed from a source method into the common import pipeline.
class ImportCandidate {
  const ImportCandidate({required this.source, this.declaredFormat});

  final ImportSource source;

  /// A source may provide a format discovered from MIME or a container. When
  /// absent, the pipeline uses [ReaderFormat.fromFileName].
  final ReaderFormat? declaredFormat;

  String get displayName => source.displayName;
  ImportMethod get method => source.method;
  String? get mimeType => source.mimeType;

  ReaderFormat? get format =>
      declaredFormat ?? ReaderFormat.fromFileName(displayName);

  File? get localFile => switch (source) {
    LocalFileImportSource local => local.file,
    _ => null,
  };
}

import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../library/import/comic_archive.dart';

/// One open comic archive for a reading session.
///
/// Holds the decoded zip directory so page reads do not re-open the file.
/// Dispose with [close] when leaving the reader.
class ComicSession {
  ComicSession._(
    this.path,
    this.pageNames,
    this._input,
    this._archive,
  );

  final String path;
  final List<String> pageNames;
  final InputFileStream _input;
  final Archive _archive;
  bool _closed = false;

  int get pageCount => pageNames.length;

  static Future<ComicSession> open(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final pages = archive.files
          .where((f) => f.isFile)
          .map((f) => f.name)
          .where(_isImageEntry)
          .toList()
        ..sort(ComicArchive.naturalCompare);
      if (pages.isEmpty) {
        await input.close();
        throw ComicSessionException('压缩包里找不到图片页');
      }
      return ComicSession._(
        path,
        List.unmodifiable(pages),
        input,
        archive,
      );
    } catch (e) {
      await input.close();
      if (e is ComicSessionException) rethrow;
      throw ComicSessionException('无法打开漫画：$e');
    }
  }

  /// Decompresses one page. Safe to call repeatedly; callers should cache
  /// decoded images at the UI layer.
  Uint8List readPage(int index) {
    _ensureOpen();
    if (index < 0 || index >= pageNames.length) {
      throw RangeError.index(index, pageNames, 'pageIndex');
    }
    final file = _archive.findFile(pageNames[index]);
    final bytes = file?.readBytes();
    if (bytes == null) {
      throw ComicSessionException('页面读取失败：${pageNames[index]}');
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _input.close();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('ComicSession is closed');
    }
  }

  static bool _isImageEntry(String name) =>
      ComicArchive.imageExtensions.contains(p.extension(name).toLowerCase());
}

class ComicSessionException implements Exception {
  const ComicSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

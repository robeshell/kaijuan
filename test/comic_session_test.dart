import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/comic/comic_session.dart';
import 'package:path/path.dart' as p;

final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kaika_session_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('opens archive once and reads pages in natural order', () async {
    final archive = Archive();
    for (final name in ['page10.png', 'page2.png', 'page1.png']) {
      archive.addFile(ArchiveFile(name, _pngBytes.length, _pngBytes));
    }
    final zipPath = p.join(temp.path, 'comic.cbz');
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);

    final session = await ComicSession.open(zipPath);
    addTearDown(session.close);

    expect(session.pageCount, 3);
    expect(session.pageNames, ['page1.png', 'page2.png', 'page10.png']);
    final bytes = session.readPage(0);
    expect(bytes.length, _pngBytes.length);
    expect(session.readPage(2).length, _pngBytes.length);
  });

  test('throws when archive has no images', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile('note.txt', 4, Uint8List.fromList('hi\n'.codeUnits)),
      );
    final zipPath = p.join(temp.path, 'empty.zip');
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);

    await expectLater(
      ComicSession.open(zipPath),
      throwsA(isA<ComicSessionException>()),
    );
  });
}

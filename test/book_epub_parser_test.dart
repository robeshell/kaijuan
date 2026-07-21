import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_epub.dart';
import 'package:path/path.dart' as p;

Future<File> _writeReflowEpub(
  Directory dir,
  String name, {
  String title = 'Test Book',
  String body = '<p>第一章正文。Hello book reflow.</p>',
  String? css,
}) async {
  final archive = Archive();

  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
  );

  final manifestItems = '''
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    ${css != null ? '<item id="style" href="style.css" media-type="text/css"/>' : ''}
  ''';

  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:identifier id="uid">urn:test:book</dc:identifier>
  </metadata>
  <manifest>
    $manifestItems
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''',
  );

  addText(
    'OEBPS/chap1.xhtml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title></head>
<body>
$body
</body>
</html>''',
  );

  if (css != null) {
    addText('OEBPS/style.css', css);
  }

  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kaika_book_epub_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('BookEpub keeps rawHtml and extracts plainText', () async {
    final file = await _writeReflowEpub(
      tempRoot,
      'raw.epub',
      body: '<p>Hello <b>world</b>.</p>',
    );
    final doc = await BookEpub.open(file.path);
    expect(doc.sections, hasLength(1));
    expect(doc.sections.first.rawHtml, contains('<p>Hello'));
    expect(doc.sections.first.rawHtml, contains('<b>world</b>'));
    expect(doc.sections.first.plainText, contains('Hello world'));
  });

  test('BookEpub collects stylesheets from manifest', () async {
    final file = await _writeReflowEpub(
      tempRoot,
      'styled.epub',
      css: 'p { font-size: 18px; }',
      body: '<p>Styled.</p>',
    );
    final doc = await BookEpub.open(file.path);
    expect(doc.stylesheets, hasLength(1));
    expect(doc.stylesheets.first, contains('font-size: 18px'));
  });

  test('BookEpub preserves multiple stylesheets in manifest order', () async {
    final archive = Archive();

    void addText(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');

    addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Multi</dc:title></metadata>
  <manifest>
    <item id="style1" href="a.css" media-type="text/css"/>
    <item id="style2" href="b.css" media-type="text/css"/>
    <item id="c1" href="chap.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''');

    addText('OEBPS/a.css', '.a { color: red; }');
    addText('OEBPS/b.css', '.b { color: blue; }');
    addText('OEBPS/chap.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Text.</p></body></html>''');

    final file = File(p.join(tempRoot.path, 'multi.epub'));
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);

    final doc = await BookEpub.open(file.path);
    expect(doc.stylesheets, hasLength(2));
    expect(doc.stylesheets.first, contains('color: red'));
    expect(doc.stylesheets.last, contains('color: blue'));
  });
}

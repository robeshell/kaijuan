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

  final cssItem = css != null
      ? '<item id="style" href="style.css" media-type="text/css"/>'
      : '';

  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:identifier id="uid">urn:test:book</dc:identifier>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    $cssItem
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>''',
  );

  addText(
    'OEBPS/nav.xhtml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>$title</title></head>
<body>
<nav epub:type="toc">
  <ol>
    <li><a href="chap1.xhtml">第一章</a></li>
  </ol>
</nav>
</body>
</html>''',
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

  test('BookEpubSession lazy-loads rawHtml', () async {
    final file = await _writeReflowEpub(
      tempRoot,
      'raw.epub',
      body: '<p>Hello <b>world</b>.</p>',
    );
    final session = await BookEpub.openSession(file.path);
    expect(session.document.sections, hasLength(1));
    expect(session.document.sections.first.rawHtml, isEmpty);
    final html = await session.readHtml(session.document.sections.first.href);
    expect(html, contains('<p>Hello'));
    expect(html, contains('<b>world</b>'));
    expect(html, contains('Hello'));
  });

  test('BookEpubSession readCss loads linked stylesheet by href', () async {
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
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Linked</dc:title>
    <dc:identifier id="uid">urn:test:linked</dc:identifier>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="local" href="local.css" media-type="text/css"/>
    <item id="c1" href="chap.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''');

    addText('OEBPS/nav.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Linked</title></head>
<body><nav><ol><li><a href="chap.xhtml">Chap</a></li></ol></nav></body></html>''');
    addText('OEBPS/local.css', '.indent { text-indent: 2em; }');
    addText('OEBPS/chap.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<link rel="stylesheet" href="local.css"/>
</head><body><p>Text.</p></body></html>''');

    final file = File(p.join(tempRoot.path, 'linked-css.epub'));
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);

    final session = await BookEpub.openSession(file.path);
    final css = await session.readCss('local.css');
    expect(css, contains('text-indent: 2em'));
  });

  test('BookEpubSession loads stylesheets on demand', () async {
    final file = await _writeReflowEpub(
      tempRoot,
      'styled.epub',
      css: 'p { font-size: 18px; }',
      body: '<p>Styled.</p>',
    );
    final session = await BookEpub.openSession(file.path);
    final sheets = await session.stylesheets();
    expect(sheets, hasLength(1));
    expect(sheets.first, contains('font-size: 18px'));
  });

  test('BookEpubSession preserves multiple stylesheets in manifest order', () async {
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
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Multi</dc:title>
    <dc:identifier id="uid">urn:test:multi</dc:identifier>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="style1" href="a.css" media-type="text/css"/>
    <item id="style2" href="b.css" media-type="text/css"/>
    <item id="c1" href="chap.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''');

    addText('OEBPS/nav.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Multi</title></head>
<body><nav><ol><li><a href="chap.xhtml">Chap</a></li></ol></nav></body></html>''');
    addText('OEBPS/a.css', '.a { color: red; }');
    addText('OEBPS/b.css', '.b { color: blue; }');
    addText('OEBPS/chap.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Text.</p></body></html>''');

    final file = File(p.join(tempRoot.path, 'multi.epub'));
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);

    final session = await BookEpub.openSession(file.path);
    final sheets = await session.stylesheets();
    expect(sheets, hasLength(2));
    expect(sheets.first, contains('color: red'));
    expect(sheets.last, contains('color: blue'));
  });

  test('BookEpub reads NCX toc labels instead of repeated HTML titles', () async {
    final archive = Archive();

    void addText(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');

    addText('content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>全集</dc:title>
    <dc:identifier id="uid">urn:test:ncx</dc:identifier>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c0" href="a.html" media-type="application/xhtml+xml"/>
    <item id="c1" href="b.html" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c0"/>
    <itemref idref="c1"/>
  </spine>
</package>''');

    addText('toc.ncx', '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:test:ncx"/>
  </head>
  <docTitle><text>全集</text></docTitle>
  <navMap>
    <navPoint id="n1" playOrder="1">
      <navLabel><text>活着</text></navLabel>
      <content src="a.html"/>
    </navPoint>
    <navPoint id="n2" playOrder="2">
      <navLabel><text>许三观卖血记</text></navLabel>
      <content src="b.html#filepos9"/>
    </navPoint>
  </navMap>
</ncx>''');

    addText('a.html', '''<html><head><title>全集</title></head>
<body><p>第一章</p></body></html>''');
    addText('b.html', '''<html><head><title>全集</title></head>
<body><p id="filepos9">第二章</p></body></html>''');

    final file = File(p.join(tempRoot.path, 'ncx.epub'));
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);

    final session = await BookEpub.openSession(file.path);
    final doc = session.document;
    expect(doc.toc, hasLength(2));
    expect(doc.toc[0].title, '活着');
    expect(doc.toc[0].sectionIndex, 0);
    expect(doc.toc[1].title, '许三观卖血记');
    expect(doc.toc[1].sectionIndex, 1);
    expect(doc.toc[1].fragment, 'filepos9');
    expect(doc.sections[0].title, '活着');
    expect(doc.sections[1].title, '许三观卖血记');

    final html = await session.readHtml(doc.sections[1].href);
    final progress = BookEpub.fragmentProgress(html, 'filepos9');
    expect(progress, greaterThan(0));
  });

  test('readBytes resolves OPF-relative image under content directory', () async {
    final archive = Archive();

    void addText(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    // 1x1 PNG
    final png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];

    addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
    addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Img</dc:title>
    <dc:identifier id="uid">urn:test:img</dc:identifier>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text.html" media-type="application/xhtml+xml"/>
    <item id="i1" href="Image00002.jpg" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''');
    addText('OEBPS/nav.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Img</title></head>
<body><nav><ol><li><a href="text.html">t</a></li></ol></nav></body></html>''');
    addText('OEBPS/text.html', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<p>图</p><img src="Image00002.jpg" alt="x"/>
</body></html>''');
    archive.addFile(ArchiveFile('OEBPS/Image00002.jpg', png.length, png));

    final file = File(p.join(tempRoot.path, 'img.epub'));
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);

    final session = await BookEpub.openSession(file.path);
    expect(session.document.contentDirectoryPath, 'OEBPS');
    final bytes = await session.readBytes('Image00002.jpg');
    expect(bytes, isNotNull);
    expect(bytes!.length, png.length);
  });

  group('resolveHref', () {
    test('resolves relative cross-section Calibre-style path with fragment', () {
      final resolved = BookEpub.resolveHref(
        'Text/index_split_010.html',
        'index_split_015.html#filepos390607',
      );
      expect(resolved.path, 'Text/index_split_015.html');
      expect(resolved.fragment, 'filepos390607');
    });

    test('keeps same-section fragment-only href', () {
      final resolved = BookEpub.resolveHref(
        'Text/index_split_015.html',
        '#filepos390607',
      );
      expect(resolved.path, 'Text/index_split_015.html');
      expect(resolved.fragment, 'filepos390607');
    });

    test('normalizes bare spine-relative path without base', () {
      final resolved = BookEpub.resolveHref(
        '',
        'index_split_015.html#filepos390607',
      );
      expect(resolved.path, 'index_split_015.html');
      expect(resolved.fragment, 'filepos390607');
    });

    test('resolves parent-relative path', () {
      final resolved = BookEpub.resolveHref(
        'OEBPS/Text/chap.xhtml',
        '../notes/end.xhtml#note1',
      );
      expect(resolved.path, 'OEBPS/notes/end.xhtml');
      expect(resolved.fragment, 'note1');
    });
  });

  group('fragmentProgress', () {
    test('finds Calibre filepos id markers', () {
      final prefix = '<p>' * 200;
      final html = '$prefix<p id="filepos390607">余华</p>';
      final progress = BookEpub.fragmentProgress(html, 'filepos390607');
      expect(progress, greaterThan(0.5));
      expect(progress, lessThan(1.0));
    });

    test('returns zero when fragment id is missing', () {
      final html = '<p id="filepos1">hello</p>';
      expect(BookEpub.fragmentProgress(html, 'filepos999'), 0);
    });
  });
}

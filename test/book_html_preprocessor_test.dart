import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_html_preprocessor.dart';

void main() {
  test('wrapWithStylesheets prepends package and section CSS once', () {
    final wrapped = BookHtmlPreprocessor.wrapWithStylesheets(
      html: '<p>Body.</p>',
      packageStylesheets: ['.pkg { color: red; }'],
      sectionStylesheets: ['.sec { margin: 1em; }'],
    );
    expect(wrapped, startsWith('<style>'));
    expect(wrapped, contains('.pkg { color: red; }'));
    expect(wrapped, contains('.sec { margin: 1em; }'));
    expect(wrapped, endsWith('<p>Body.</p>'));
  });

  test('wrapWithStylesheets returns html unchanged when no css', () {
    expect(
      BookHtmlPreprocessor.wrapWithStylesheets(html: '<p>x</p>'),
      '<p>x</p>',
    );
  });

  test('linkedStylesheetHrefs extracts head link tags', () {
    final hrefs = BookHtmlPreprocessor.linkedStylesheetHrefs('''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <link rel="stylesheet" href="../Styles/main.css" type="text/css"/>
  <link rel="stylesheet" href="local.css"/>
  <link rel="alternate" href="feed.xml"/>
</head>
<body><p>Text.</p></body>
</html>''');
    expect(hrefs, ['../Styles/main.css', 'local.css']);
  });

  test('prepareSection extracts body and inlines CSS', () {
    final result = BookHtmlPreprocessor.prepareSection(
      rawHtml: '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Ch1</title></head>
<body><p>Hello.</p></body>
</html>''',
      baseHref: 'OEBPS/chap1.xhtml',
      stylesheets: ['p { font-size: 18px; }'],
    );
    expect(result.html, contains('<p>Hello.</p>'));
    expect(result.html, contains('<style>'));
    expect(result.html, contains('font-size: 18px'));
    expect(result.html, isNot(contains('<html>')));
    expect(result.html, isNot(contains('<head>')));
  });

  test('prepareSection removes scripts and iframes', () {
    final result = BookHtmlPreprocessor.prepareSection(
      rawHtml: '''
<body>
<p>Before</p>
<script>alert(1);</script>
<iframe src="x"></iframe>
<video></video>
<audio></audio>
<object></object>
<form><input/></form>
<p>After</p>
</body>''',
      baseHref: 'OEBPS/chap1.xhtml',
      stylesheets: const [],
    );
    expect(result.html, contains('Before'));
    expect(result.html, contains('After'));
    expect(result.html, isNot(contains('<script>')));
    expect(result.html, isNot(contains('<iframe>')));
    expect(result.html, isNot(contains('<video>')));
    expect(result.html, isNot(contains('<audio>')));
    expect(result.html, isNot(contains('<object>')));
    expect(result.html, isNot(contains('<form>')));
  });

  test('prepareSection strips xmlns and epub:type attributes', () {
    final result = BookHtmlPreprocessor.prepareSection(
      rawHtml: '''<body xmlns:epub="http://www.idpf.org/2007/ops" epub:type="chapter">
<p xmlns:custom="http://example.com">Text.</p>
</body>''',
      baseHref: 'OEBPS/chap1.xhtml',
      stylesheets: const [],
    );
    expect(result.html, contains('<p>Text.</p>'));
    expect(result.html, isNot(contains('xmlns')));
    expect(result.html, isNot(contains('epub:type')));
  });
}

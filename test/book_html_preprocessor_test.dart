import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_html_preprocessor.dart';

void main() {
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
    expect(result, contains('<p>Hello.</p>'));
    expect(result, contains('<style>'));
    expect(result, contains('font-size: 18px'));
    expect(result, isNot(contains('<html>')));
    expect(result, isNot(contains('<head>')));
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
    expect(result, contains('Before'));
    expect(result, contains('After'));
    expect(result, isNot(contains('<script>')));
    expect(result, isNot(contains('<iframe>')));
    expect(result, isNot(contains('<video>')));
    expect(result, isNot(contains('<audio>')));
    expect(result, isNot(contains('<object>')));
    expect(result, isNot(contains('<form>')));
  });

  test('prepareSection strips xmlns and epub:type attributes', () {
    final result = BookHtmlPreprocessor.prepareSection(
      rawHtml: '''<body xmlns:epub="http://www.idpf.org/2007/ops" epub:type="chapter">
<p xmlns:custom="http://example.com">Text.</p>
</body>''',
      baseHref: 'OEBPS/chap1.xhtml',
      stylesheets: const [],
    );
    expect(result, contains('<p>Text.</p>'));
    expect(result, isNot(contains('xmlns')));
    expect(result, isNot(contains('epub:type')));
  });
}

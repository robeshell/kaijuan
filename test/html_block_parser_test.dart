import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_css_rules.dart';
import 'package:kaika/readers/book/pagination/html_block_parser.dart';
import 'package:kaika/readers/book/pagination/page_block.dart';

void main() {
  test('css class applies bold in page parser', () {
    final css = BookCssRules.parseAll(['.emph { font-weight: bold; }']);
    final parser = HtmlBlockParser(
      fontSize: 18,
      lineHeight: 1.6,
      textColor: const Color(0xFF000000),
      cssRules: css,
    );

    final blocks = parser.parse('<p class="emph">bold line</p>');
    final text = blocks.whereType<TextBlock>().single;
    expect(text.runs.first.style.fontWeight, FontWeight.bold);
  });

  test('css text-indent on paragraph becomes TextBlock.textIndent', () {
    final css = BookCssRules.parseAll(['p { text-indent: 2em; }']);
    final parser = HtmlBlockParser(
      fontSize: 20,
      lineHeight: 1.6,
      textColor: const Color(0xFF000000),
      cssRules: css,
    );

    final blocks = parser.parse('<p>Indented.</p>');
    expect(blocks.whereType<TextBlock>().single.textIndent, 40);
  });

  test('nested img inside div becomes ImageBlock, not [图片] text', () {
    final parser = HtmlBlockParser(
      fontSize: 18,
      lineHeight: 1.6,
      textColor: const Color(0xFF000000),
    );

    final blocks = parser.parse('''
      <div class="wrap">
        <p>hello</p>
        <div><img src="../images/a.png" width="100" height="50" /></div>
      </div>
    ''');

    expect(blocks.whereType<TextBlock>(), isNotEmpty);
    expect(blocks.whereType<ImageBlock>(), hasLength(1));
    expect(blocks.whereType<ImageBlock>().single.src, '../images/a.png');
    expect(
      blocks.whereType<TextBlock>().any((b) => b.plainText.contains('[图片]')),
      isFalse,
    );
  });
}

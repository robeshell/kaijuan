import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_css_rules.dart';

void main() {
  test('parseAll maps class bold and text-indent', () {
    final rules = BookCssRules.parseAll([
      '.calibre1 { font-weight: bold; }',
      'p { text-indent: 2em; }',
    ]);
    expect(rules.classProperties['calibre1']?['font-weight'], 'bold');
    expect(rules.tagProperties['p']?['text-indent'], '2em');

    final style = rules.applyToStyle(
      const TextStyle(fontSize: 16),
      classes: ['calibre1'],
      baseFontSize: 16,
    );
    expect(style.fontWeight, FontWeight.bold);

    expect(
      rules.textIndent(tag: 'p', baseFontSize: 16),
      32,
    );
  });

  test('headingScale reads em from CSS', () {
    final rules = BookCssRules.parseAll(['h2 { font-size: 1.8em; }']);
    expect(rules.headingScale('h2'), closeTo(1.8, 0.001));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/pagination/paginator.dart';
import 'package:kaika/readers/book/prepared_section.dart';

void main() {
  testWidgets('packs multiple short paragraphs onto one page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

    final html = StringBuffer();
    for (var i = 0; i < 10; i++) {
      html.writeln('<p>第${i + 1}段。这是一段比较短的文字。​</p>');
    }

    final paginator = Paginator(
      pageSize: const Size(320, 480),
      fontSize: 18,
      lineHeight: 1.6,
      textColor: Colors.black,
      readBytes: (_) async => null,
    );

    final result = await paginator.paginate([
      PreparedSection(
        href: 'OEBPS/chap1.xhtml',
        title: 'Ch1',
        html: html.toString(),
      ),
    ]);

    expect(result.pages, isNotEmpty);
    expect(result.pages.length, lessThan(10));
    expect(result.sectionStartPageIndices, [0]);
  });
}

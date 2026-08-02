import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/reader/book_excerpt_card.dart';
import 'package:kaijuan/readers/book/book_excerpt_style.dart';

void main() {
  Widget host(BookExcerptLayout layout) {
    return MaterialApp(
      theme: AppTheme.light(AppColors.defaultAccent),
      home: Scaffold(
        body: Center(
          child: BookExcerptCard(
            quote: '这是一段摘录文字。',
            bookTitle: '书名',
            chapterTitle: '第二章 不再显示在第一种排版中',
            layout: layout,
            palette: BookExcerptPalette.paper,
          ),
        ),
      ),
    );
  }

  testWidgets('classic layout does not render the chapter name', (
    tester,
  ) async {
    await tester.pumpWidget(host(BookExcerptLayout.classic));

    expect(find.text('第二章 不再显示在第一种排版中'), findsNothing);
    expect(find.text('这是一段摘录文字。'), findsOneWidget);
  });

  testWidgets('large quote closing mark has no extra background mask', (
    tester,
  ) async {
    await tester.pumpWidget(host(BookExcerptLayout.largeQuote));

    final closingMark = find.text('”');
    expect(closingMark, findsOneWidget);
    expect(
      find.ancestor(of: closingMark, matching: find.byType(DecoratedBox)),
      findsOneWidget,
    );
  });
}

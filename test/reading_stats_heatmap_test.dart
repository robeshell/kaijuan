import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/library_controller.dart';
import 'package:kaijuan/presentation/screens/reading_stats_screen.dart';

void main() {
  late AppDatabase database;
  late LibraryController libraryController;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    libraryController = LibraryController(
      database: database,
      comicImportService: ComicImportService(
        database: database,
        supportDirectory: Directory.systemTemp,
      ),
      bookImportService: BookImportService(
        database: database,
        supportDirectory: Directory.systemTemp,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('empty library still paints the complete heatmap on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: ReadingStatsScreen(libraryController: libraryController),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读足迹'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reading-heatmap-scroll')),
      findsOneWidget,
    );
    final heatCells = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'reading-heat-cell-',
          ),
    );
    expect(heatCells, findsNWidgets(53 * 7));
    expect(tester.getSize(heatCells.first), const Size.square(10));
    expect(find.text('向左滑动查看更早日期'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reading-heatmap-details')),
      findsOneWidget,
    );

    final paint = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'reading-heat-cell-paint-',
          ),
    );
    final paintedCell = tester.widget<DecoratedBox>(paint.first);
    final decoration = paintedCell.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    final renderedBorder = _composite(border.top.color, decoration.color!);
    expect(
      _contrastRatio(renderedBorder, decoration.color!),
      greaterThanOrEqualTo(3),
    );

    await tester.tap(find.byKey(const ValueKey('reading-heatmap-details')));
    await tester.pumpAndSettle();
    expect(find.text('阅读日期明细'), findsOneWidget);
    expect(find.text('近一年暂无阅读时长'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('heatmap stays visible in a short landscape viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppColors.defaultAccent),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ReadingStatsScreen(libraryController: libraryController),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读足迹'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reading-heatmap-scroll')),
      findsOneWidget,
    );
    final paint = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'reading-heat-cell-paint-',
          ),
    );
    final paintedCell = tester.widget<DecoratedBox>(paint.first);
    final decoration = paintedCell.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    final renderedBorder = _composite(border.top.color, decoration.color!);
    expect(
      _contrastRatio(renderedBorder, decoration.color!),
      greaterThanOrEqualTo(3),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('wide layout gives the year grid a dedicated chart column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: ReadingStatsScreen(libraryController: libraryController),
      ),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const ValueKey('reading-heatmap-summary'));
    final scroll = find.byKey(const ValueKey('reading-heatmap-scroll'));
    final cells = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'reading-heat-cell-',
          ),
    );
    expect(summary, findsOneWidget);
    expect(scroll, findsOneWidget);
    expect(
      tester.getTopLeft(scroll).dx,
      greaterThan(tester.getTopRight(summary).dx),
    );
    expect(tester.getSize(cells.first).width, greaterThanOrEqualTo(20));
    expect(find.text('向左滑动查看更早日期'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Color _composite(Color foreground, Color background) {
  final a = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * a + background.r * (1 - a),
    green: foreground.g * a + background.g * (1 - a),
    blue: foreground.b * a + background.b * (1 - a),
  );
}

double _contrastRatio(Color a, Color b) {
  final aL = a.computeLuminance();
  final bL = b.computeLuminance();
  final lighter = aL > bL ? aL : bL;
  final darker = aL > bL ? bL : aL;
  return (lighter + 0.05) / (darker + 0.05);
}

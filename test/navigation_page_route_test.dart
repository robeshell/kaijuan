import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/brand/brand_config.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/library_controller.dart';
import 'package:kaijuan/presentation/navigation/app_page_route.dart';
import 'package:kaijuan/presentation/screens/collections_screen.dart';
import 'package:kaijuan/presentation/screens/lists_screen.dart';

void main() {
  late AppDatabase database;
  late LibraryController controller;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    controller = LibraryController(
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

  test('library subpage route is opaque and has no heavy transition', () {
    final route =
        appPageRoute<void>((_) => const SizedBox.shrink()) as PageRoute<void>;

    expect(route.opaque, isTrue);
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  testWidgets('lists and collections pages paint the app canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListsScreen(brand: BrandConfig.app, controller: controller),
      ),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      isNot(Colors.transparent),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionsScreen(brand: BrandConfig.app, controller: controller),
      ),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      isNot(Colors.transparent),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

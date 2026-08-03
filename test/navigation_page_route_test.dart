import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/brand/brand_config.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/library/import/book_import_service.dart';
import 'package:kaijuan/library/import/comic_import_service.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/library_controller.dart';
import 'package:kaijuan/presentation/navigation/app_page_route.dart';
import 'package:kaijuan/presentation/screens/collections_screen.dart';
import 'package:kaijuan/presentation/screens/lists_screen.dart';
import 'package:kaijuan/presentation/widgets/settings_components.dart';

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

  testWidgets('library subpages constrain content and keep actions visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: ListsScreen(brand: BrandConfig.app, controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('按顺序整理待读内容'), findsNothing);
    expect(find.text('新建书单'), findsNWidgets(2));
    expect(tester.getTopLeft(find.text('书单')).dx, greaterThan(300));
    final header = tester.widget<Text>(find.text('书单'));
    expect(
      header.style?.fontSize,
      tester.element(find.text('书单')).appSectionTitleSize,
    );
    expect(tester.getCenter(find.text('还没有书单')).dy, lessThan(400));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('desktop back control is interactive and keeps heading aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const edgeKey = ValueKey('content-edge');
    const backKey = ValueKey('page-back');
    var didGoBack = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: AppSettingsContent(
            padding: const EdgeInsets.all(64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSettingsPageHeader(
                  title: '云端存储',
                  backButtonKey: backKey,
                  onBack: () => didGoBack = true,
                ),
                const SizedBox(height: 24),
                const SizedBox(key: edgeKey, width: 120, child: Text('正文')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('云端存储')).dx,
      tester.getTopLeft(find.byKey(edgeKey)).dx,
    );
    expect(
      tester.getTopLeft(find.byKey(backKey)).dx,
      tester.getTopLeft(find.text('云端存储')).dx,
    );
    expect(
      tester.getSize(find.byKey(backKey)).height,
      greaterThanOrEqualTo(40),
    );
    // Back row sits flush against the title — no spacer band between them.
    expect(
      tester.getTopLeft(find.text('云端存储')).dy,
      closeTo(tester.getBottomLeft(find.byKey(backKey)).dy, 1),
    );
    final backButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(backKey),
        matching: find.byType(TextButton),
      ),
    );
    for (final states in [
      <WidgetState>{},
      {WidgetState.hovered},
      {WidgetState.pressed},
    ]) {
      expect(
        backButton.style?.backgroundColor?.resolve(states),
        Colors.transparent,
      );
      expect(
        backButton.style?.overlayColor?.resolve(states),
        Colors.transparent,
      );
    }

    await tester.tap(find.byKey(backKey));
    expect(didGoBack, isTrue);
  });

  testWidgets('subpage opens inside content navigator and keeps sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Row(
          children: [
            const SizedBox(width: 220, child: Text('固定侧边栏')),
            Expanded(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (nestedContext) => Scaffold(
                    body: FilledButton(
                      onPressed: () => ListsScreen.open(
                        nestedContext,
                        brand: BrandConfig.app,
                        controller: controller,
                      ),
                      child: const Text('打开书单'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('打开书单'));
    await tester.pumpAndSettle();

    expect(find.text('固定侧边栏'), findsOneWidget);
    expect(find.text('书单'), findsOneWidget);
    expect(find.text('按顺序整理待读内容'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('list and collection management is discoverable without hold', (
    tester,
  ) async {
    await controller.createReadingList('周末待读');
    await controller.createCollection('科幻系列');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: ListsScreen(brand: BrandConfig.app, controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('周末待读'), findsOneWidget);
    expect(find.byTooltip('管理书单'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: CollectionsScreen(brand: BrandConfig.app, controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('科幻系列'), findsOneWidget);
    expect(find.byTooltip('管理合集'), findsOneWidget);
  });

  testWidgets('collection subpage survives a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.createCollection('很长的系列合集名称用于检查窄屏布局');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: CollectionsScreen(brand: BrandConfig.app, controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新建合集'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

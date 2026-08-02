import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/app_components.dart';
import 'package:kaijuan/presentation/widgets/app_overlays.dart';

void main() {
  testWidgets('empty state uses the shared loading size and optional action', (
    tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: AppEmptyState(
            icon: Icons.error_outline,
            title: '加载失败',
            message: '请重试。',
            loading: true,
            actionLabel: '重试',
            onAction: () => retried = true,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(24, 24),
    );
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('请重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });

  testWidgets('empty state fits a short bounded viewport', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: SizedBox(
            height: 138,
            child: AppEmptyState(
              icon: Icons.library_books_outlined,
              title: '书库还是空的',
              message: '导入 CBZ、ZIP 或 EPUB 后会显示在这里。',
              actionLabel: '导入',
              onAction: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('书库还是空的'), findsOneWidget);
  });

  testWidgets('App menu becomes a bottom sheet in compact windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: Center(
            child: AppMenuButton<String>(
              key: const ValueKey('compact-app-menu'),
              tooltip: '筛选',
              menuTitle: '筛选',
              actions: const [
                AppMenuAction(
                  value: 'all',
                  label: '全部',
                  icon: Icons.filter_list,
                  selected: true,
                ),
                AppMenuAction(
                  value: 'reading',
                  label: '在读',
                  icon: Icons.filter_list,
                ),
              ],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('compact-app-menu')));
    await tester.pumpAndSettle();

    expect(find.byType(AppBottomSheet), findsOneWidget);
    expect(find.byType(PopupMenuItem), findsNothing);
    await tester.tap(find.text('在读'));
    await tester.pumpAndSettle();
    expect(selected, 'reading');
  });

  testWidgets(
    'choice dialog uses the shared dialog surface and returns value',
    (tester) async {
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.defaultAccent),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  selected = await showAppChoiceDialog<String>(
                    context,
                    title: '加入书单',
                    choices: const [
                      AppDialogChoice(
                        value: 'one',
                        label: '书单一',
                        subtitle: '3 本',
                      ),
                      AppDialogChoice(
                        value: 'new',
                        label: '新建书单…',
                        icon: Icons.add,
                      ),
                    ],
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-dialog')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('app-dialog'))).width,
        360,
      );
      await tester.tap(find.text('书单一'));
      await tester.pumpAndSettle();
      expect(selected, 'one');
    },
  );

  testWidgets('list rows remain usable at 200 percent text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: AppListRow(
            title: const Text('一本标题非常长、需要正确截断的测试图书'),
            subtitle: const Text('这里是同样很长的作者与阅读进度说明'),
            leading: const Icon(Icons.book_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppListRow)).height, greaterThan(54));
    expect(tester.takeException(), isNull);
  });
}

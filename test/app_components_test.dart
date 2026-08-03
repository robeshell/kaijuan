import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/kaijuan_icons.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/app_components.dart';
import 'package:kaijuan/presentation/widgets/app_overlays.dart';
import 'package:kaijuan/presentation/widgets/settings_components.dart';

void main() {
  testWidgets('light settings use a white canvas and clean field surfaces', (
    tester,
  ) async {
    late Color canvas;
    late Color groupSurface;
    late ThemeData theme;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Builder(
          builder: (context) {
            canvas = context.settingsCanvas;
            groupSurface = context.settingsGroupSurface;
            theme = Theme.of(context);
            return const Scaffold(body: AppTextField());
          },
        ),
      ),
    );

    expect(canvas, Colors.white);
    expect(groupSurface, theme.colorScheme.surfaceContainerLow);
    expect(
      theme.inputDecorationTheme.fillColor,
      theme.colorScheme.surfaceContainer,
    );
    expect(
      theme.dropdownMenuTheme.inputDecorationTheme?.fillColor,
      theme.colorScheme.surfaceContainer,
    );
  });

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
              message: '导入图书或漫画文件后会显示在这里。',
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

  testWidgets('icon buttons expose their tooltip as an accessible name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: AppIconButton(
            icon: Icons.more_horiz,
            tooltip: '管理合集',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(tester.getSemantics(find.byType(IconButton)).label, '管理合集');
  });

  testWidgets('icon+label buttons share a vertical center line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: Center(
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(KaijuanIcons.cloud),
              label: const Text('立即备份'),
            ),
          ),
        ),
      ),
    );

    final iconCenter = tester.getCenter(find.byIcon(KaijuanIcons.cloud));
    final labelCenter = tester.getCenter(find.text('立即备份'));
    expect(iconCenter.dy, closeTo(labelCenter.dy, 1.0));

    final buttonStyle = Theme.of(
      tester.element(find.text('立即备份')),
    ).filledButtonTheme.style;
    expect(buttonStyle?.textStyle?.resolve(const {})?.height, 1.0);
    expect(buttonStyle?.iconSize?.resolve(const {}), 16);
  });

  testWidgets('progress snackbar shows a persistent scanning status', (
    tester,
  ) async {
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? progress;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                progress = showAppProgressSnackBar(context, '扫描中');
              },
              child: const Text('开始扫描'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始扫描'));
    await tester.pump();
    expect(find.text('扫描中'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppGlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);

    progress!.close();
    await tester.pumpAndSettle();
    expect(find.text('扫描中'), findsNothing);
  });

  testWidgets('floating snackbar fits above a compact settings action bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAppSnackBar(context, '连接失败'),
              child: const Text('提示'),
            ),
          ),
          bottomNavigationBar: AppSettingsBottomBar(
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('保存连接'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('提示'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(AppSettingsBottomBar)).height,
      lessThan(200),
    );
    expect(find.text('连接失败'), findsOneWidget);
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

  testWidgets('select field uses the branded anchored menu on desktop', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: AppSelectField<String>(
                value: 'nas',
                tooltip: '选择 WebDAV 连接',
                options: const [
                  AppSelectOption(
                    value: 'nas',
                    label: '家用 NAS',
                    subtitle: 'https://example.com/dav',
                    icon: Icons.cloud_outlined,
                  ),
                  AppSelectOption(
                    value: 'cloud',
                    label: '云端备份',
                    icon: Icons.cloud_outlined,
                  ),
                ],
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    debugDefaultTargetPlatformOverride = null;

    await tester.tap(find.byType(AppSelectField<String>));
    await tester.pumpAndSettle();

    expect(find.byType(AppGlassSurface), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('WebDAV 连接'), findsNothing);
    expect(find.text('家用 NAS'), findsNWidgets(2));
    expect(find.byIcon(KaijuanIcons.check), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppGlassSurface)).width,
      lessThanOrEqualTo(280),
    );
    final subtitleBottom = tester
        .getBottomLeft(find.text('https://example.com/dav'))
        .dy;
    final nextLabelTop = tester.getTopLeft(find.text('云端备份')).dy;
    expect(nextLabelTop - subtitleBottom, greaterThanOrEqualTo(8));

    await tester.tap(find.text('云端备份'));
    await tester.pumpAndSettle();
    expect(selected, 'cloud');
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

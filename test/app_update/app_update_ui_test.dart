import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/app_update/app_update_models.dart';
import 'package:kaijuan/app_update/app_update_ui.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/app_components.dart';

void main() {
  testWidgets('update feedback uses the shared dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppColors.defaultAccent),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              showAppUpdateFlow(
                context,
                result: const AppUpdateUpToDate(currentVersion: '0.1.1'),
              );
            },
            child: const Text('检查'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('已是最新版本（0.1.1）'), findsOneWidget);

    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_settings_store.dart';
import 'package:kaijuan/presentation/controllers/ai_settings_controller.dart';
import 'package:kaijuan/presentation/screens/ai_graph_rules_screen.dart';

Future<AiSettingsController> _controller() async {
  final controller = AiSettingsController(
    settingsStore: MemoryAiSettingsStore(),
    credentialStore: MemoryAiCredentialStore(),
  );
  await controller.load();
  return controller;
}

Widget _host(AiSettingsController controller) {
  return MaterialApp(
    theme: ThemeData(
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AiGraphRulesScreen(controller: controller),
              ),
            ),
            child: const Text('打开规则'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('graph-rule draft is discarded unless explicitly saved', (
    tester,
  ) async {
    final controller = await _controller();
    final original = controller.settings.graphRuleWords.appendixUnits;
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.text('打开规则'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('graph-rule-appendix')),
      '测试辅文',
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('放弃图谱规则修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();

    expect(find.text('打开规则'), findsOneWidget);
    expect(controller.settings.graphRuleWords.appendixUnits, original);
  });

  testWidgets('graph rules are persisted by the save action', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.text('打开规则'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('graph-rule-appendix')),
      '测试辅文\n!测试正文',
    );
    await tester.pump();
    final save = tester.widget<TextButton>(
      find.byKey(const ValueKey('graph-rules-save-top')),
    );
    expect(save.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('graph-rules-save-top')));
    await tester.pumpAndSettle();

    expect(controller.settings.graphRuleWords.appendixUnits, ['测试辅文', '!测试正文']);
    expect(find.text('图谱规则已保存'), findsOneWidget);
  });
}

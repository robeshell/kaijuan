import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_settings_store.dart';
import 'package:kaijuan/presentation/controllers/ai_settings_controller.dart';
import 'package:kaijuan/presentation/screens/ai_content_rules_screen.dart';

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
                builder: (_) => AiContentRulesScreen(controller: controller),
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
  testWidgets('AI-rule draft is discarded unless explicitly saved', (
    tester,
  ) async {
    final controller = await _controller();
    final original = controller.settings.contentRuleWords.appendixUnits;
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.text('打开规则'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('graph-rule-appendix')),
      '测试辅文',
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('放弃 AI 规则修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();

    expect(find.text('打开规则'), findsOneWidget);
    expect(controller.settings.contentRuleWords.appendixUnits, original);
  });

  testWidgets('content and graph rules persist together on explicit save', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.text('打开规则'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('graph-rule-appendix')),
      '测试辅文\n!测试正文',
    );
    await tester.enterText(
      find.byKey(const ValueKey('content-rule-mind-map-excluded-titles')),
      '附录*\n*出版始末*',
    );
    await tester.pump();
    final save = tester.widget<TextButton>(
      find.byKey(const ValueKey('ai-rules-save-top')),
    );
    expect(save.onPressed, isNotNull);
    save.onPressed!();
    await tester.pumpAndSettle();

    expect(controller.settings.contentRuleWords.appendixUnits, [
      '测试辅文',
      '!测试正文',
    ]);
    expect(controller.settings.contentRuleWords.mindMapExcludedTitlePatterns, [
      '附录*',
      '*出版始末*',
    ]);
    expect(find.text('AI 规则已保存'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_settings_store.dart';
import 'package:kaijuan/presentation/controllers/ai_settings_controller.dart';
import 'package:kaijuan/presentation/screens/ai_settings_screen.dart';
import 'package:kaijuan/presentation/widgets/settings_components.dart';

Future<AiSettingsController> _controller() async {
  final controller = AiSettingsController(
    settingsStore: MemoryAiSettingsStore(),
    credentialStore: MemoryAiCredentialStore(),
  );
  await controller.load();
  return controller;
}

Widget _host(AiSettingsController controller) =>
    MaterialApp(home: AiSettingsScreen(controller: controller));

void main() {
  testWidgets('settings exposes general AI rules outside graph-only naming', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('高级 AI 规则'), findsOneWidget);
    expect(find.text('思维导图内容范围、图谱关系与别名'), findsOneWidget);
    expect(find.text('高级图谱规则'), findsNothing);
  });

  testWidgets('providers expose a persistent deep-thinking switch', (
    tester,
  ) async {
    final controller = await _controller();
    await controller.setProviderKind(AiProviderKind.deepseek);
    await controller.setEnabled(true);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final switchFinder = find.widgetWithText(AppSettingsSwitchRow, '默认开启深度思考');
    expect(switchFinder, findsOneWidget);
    final row = tester.widget<AppSettingsSwitchRow>(switchFinder);
    expect(row.value, isFalse);

    row.onChanged!(true);
    await tester.pumpAndSettle();

    expect(controller.settings.reasoningEnabled, isTrue);
    expect(tester.widget<AppSettingsSwitchRow>(switchFinder).value, isTrue);
  });

  testWidgets('all provider presets expose reasoning when supported', (
    tester,
  ) async {
    for (final provider in AiProviderKind.values) {
      final controller = await _controller();
      await controller.setProviderKind(provider);
      await controller.setEnabled(true);
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      expect(find.text('默认开启深度思考'), findsOneWidget, reason: provider.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

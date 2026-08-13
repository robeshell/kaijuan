import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/text_editing_focus.dart';

void main() {
  Future<void> runOnDesktop(
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('desktop Enter submits when IME is idle', (tester) async {
    await runOnDesktop(() async {
      var submitted = 0;
      final controller = TextEditingController(text: '问这本书');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: withDesktopChatSubmit(
              controller: controller,
              onSubmit: () => submitted++,
              TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(submitted, 1);
    });
  });

  testWidgets('desktop Shift+Enter does not submit', (tester) async {
    await runOnDesktop(() async {
      var submitted = 0;
      final controller = TextEditingController(text: '问这本书');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: withDesktopChatSubmit(
              controller: controller,
              onSubmit: () => submitted++,
              TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      expect(submitted, 0);
    });
  });

  testWidgets('desktop Enter is ignored while composing', (tester) async {
    await runOnDesktop(() async {
      var submitted = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: withDesktopChatSubmit(
              controller: controller,
              onSubmit: () => submitted++,
              TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(submitted, 0);
    });
  });
}

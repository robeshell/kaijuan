import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/presentation/widgets/reader/reader_tool_strip_shared.dart';

void main() {
  testWidgets('fraction track exposes a complete adjustable semantics value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ReaderFractionTrack(
              fraction: 0.5,
              trackColor: Colors.grey,
              fillColor: Colors.orange,
              thumbColor: Colors.orange,
              semanticLabel: '阅读进度',
              semanticValue: '50%',
              semanticValueForFraction: (value) => '${(value * 100).round()}%',
              onDragStart: (_) {},
              onDragUpdate: (_) {},
              onDragEnd: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final node = tester.getSemantics(find.bySemanticsLabel('阅读进度'));
    expect(node.value, '50%');
    expect(node.increasedValue, '55%');
    expect(node.decreasedValue, '45%');
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    semantics.dispose();
  });
}

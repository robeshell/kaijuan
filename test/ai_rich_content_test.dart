import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/presentation/widgets/reader/ai_result_body.dart';
import 'package:kaijuan/presentation/widgets/reader/ai_rich_blocks.dart';

void main() {
  group('AI rich content', () {
    testWidgets(
      'dispatches fenced code, diff, ASCII tree, and callout blocks',
      (tester) async {
        const markdown = r'''
```dart
final answer = 42;
```

```diff
- old
+ new
```

根节点 ├── 分支一 | └── 分支二

> [!NOTE]
> 这是需要留意的说明。
''';
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: AiResultBody(text: markdown)),
            ),
          ),
        );

        expect(find.byType(AiCodeBlock), findsNWidgets(3));
        expect(find.text('DART'), findsOneWidget);
        expect(find.text('差异'), findsOneWidget);
        expect(find.text('文本结构图'), findsOneWidget);
        expect(find.text('说明'), findsOneWidget);
        expect(find.textContaining('需要留意'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders LaTeX and footnotes without exposing source markers', (
      tester,
    ) async {
      const markdown = r'''
欧拉公式是 $e^{i\pi}+1=0$。

```latex
\int_0^1 x^2 dx
```

这句话有出处。[^source]

[^source]: 这里是脚注内容。
''';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiResultBody(text: markdown)),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining(r'$e^{i\pi}'), findsNothing);
      expect(find.byType(AiLatexBlock), findsNWidgets(2));
      expect(find.textContaining('脚注内容'), findsOneWidget);
      expect(find.textContaining('[^source]'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'holds an incomplete streaming diagram until its fence closes',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AiResultBody(
                streaming: true,
                text: '前文\n\n```mermaid\nmindmap\n  root((书))',
              ),
            ),
          ),
        );

        expect(find.byType(AiRichPendingBlock), findsOneWidget);
        expect(find.text('正在生成图表'), findsOneWidget);
        expect(find.textContaining('mindmap'), findsNothing);
      },
    );

    testWidgets('renders Mermaid SVG through an injectable offline renderer', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiMermaidBlock(
              source: 'mindmap\n  root((阅读))',
              label: '思维导图',
              renderer: _FakeMermaidRenderer(),
              surfaceBuilder: _testSvgSurface,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('思维导图'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses a native SVG surface for diagram previews', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiMermaidBlock(
              source: 'mindmap\n  root((阅读))',
              label: '思维导图',
              renderer: _FakeMermaidRenderer(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a diagram failure degrades to friendly copyable source', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiMermaidBlock(
              source: 'mindmap\n  broken',
              label: '思维导图',
              renderer: _FailingMermaidRenderer(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('暂时无法绘制'), findsOneWidget);
      expect(find.text('复制原始内容'), findsOneWidget);
      expect(find.textContaining('FormatException'), findsNothing);
    });

    testWidgets('does not fetch a remote image before explicit consent', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiResultBody(text: '![人物关系图](https://example.com/graph.png)'),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('人物关系图'), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });

  group('AiChartAdapter', () {
    test('converts a simple bar chart to Mermaid xychart', () {
      final result = AiChartAdapter.toMermaid('''
{"type":"bar","title":"阅读时长","labels":["周一","周二"],"series":[{"name":"分钟","values":[12,18]}]}
''');
      expect(result, startsWith('xychart-beta'));
      expect(result, contains('bar [12, 18]'));
      expect(result, contains('周一'));
    });

    test('converts a Vega-Lite pie subset to Mermaid', () {
      final result = AiChartAdapter.toMermaid('''
{"mark":"arc","data":{"values":[{"kind":"小说","count":3},{"kind":"散文","count":2}]},"encoding":{"theta":{"field":"count"},"color":{"field":"kind"}}}
''');
      expect(result, startsWith('pie showData'));
      expect(result, contains('"小说" : 3'));
      expect(result, contains('"散文" : 2'));
    });

    test('rejects executable or unsupported chart schemas', () {
      expect(
        () => AiChartAdapter.toMermaid(
          '{"mark":"script","data":{"url":"https://example.com"}}',
        ),
        throwsFormatException,
      );
    });
  });

  group('AiMermaidTheme', () {
    test('maps the active light ColorScheme into Merman semantic colors', () {
      final colors = AppTheme.light(AppColors.defaultAccent).colorScheme;
      final options =
          jsonDecode(AiMermaidTheme.fromColorScheme(colors).optionsJson)
              as Map<String, dynamic>;
      final presentation = options['presentation'] as Map<String, dynamic>;
      final theme = presentation['theme'] as Map<String, dynamic>;
      final siteConfig = options['site_config'] as Map<String, dynamic>;
      final variables = siteConfig['themeVariables'] as Map<String, dynamic>;

      expect(theme['appearance'], 'light');
      expect(variables['cScale0'], _hex(colors.primaryContainer));
      expect(variables['cScaleLabel0'], _hex(colors.onPrimaryContainer));
      expect(
        (options['svg'] as Map<String, dynamic>)['scoped_css'],
        contains(_hex(colors.primary)),
      );
    });

    test('uses an independent dark appearance palette', () {
      final colors = AppTheme.dark(AppColors.defaultAccent).colorScheme;
      final options =
          jsonDecode(AiMermaidTheme.fromColorScheme(colors).optionsJson)
              as Map<String, dynamic>;
      final presentation = options['presentation'] as Map<String, dynamic>;
      final theme = presentation['theme'] as Map<String, dynamic>;
      final roles = theme['roles'] as Map<String, dynamic>;

      expect(theme['appearance'], 'dark');
      expect(roles['canvas'], _hex(colors.surface));
      expect(roles['text'], _hex(colors.onSurface));
    });

    test('keeps node text pairs at WCAG AA contrast in both appearances', () {
      for (final colors in [
        AppTheme.light(AppColors.defaultAccent).colorScheme,
        AppTheme.dark(AppColors.defaultAccent).colorScheme,
      ]) {
        for (final pair in [
          (colors.primary, colors.onPrimary),
          (colors.primaryContainer, colors.onPrimaryContainer),
          (colors.secondaryContainer, colors.onSecondaryContainer),
          (colors.tertiaryContainer, colors.onTertiaryContainer),
        ]) {
          expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
      }
    });
  });
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

class _FakeMermaidRenderer implements AiMermaidRenderer {
  const _FakeMermaidRenderer();

  @override
  Future<String> render(String source, {required AiMermaidTheme theme}) async =>
      '<svg viewBox="0 0 120 80" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="2" y="2" width="116" height="76" fill="#fff"/>'
      '</svg>';
}

Widget _testSvgSurface(String svg) => SvgPicture.string(svg);

class _FailingMermaidRenderer implements AiMermaidRenderer {
  const _FailingMermaidRenderer();

  @override
  Future<String> render(String source, {required AiMermaidTheme theme}) =>
      Future.error(const FormatException('model-authored parse details'));
}

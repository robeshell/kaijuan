import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighting/flutter_highlighting.dart';
import 'package:flutter_highlighting/themes/github-dark.dart';
import 'package:flutter_highlighting/themes/github.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:highlighting/languages/all.dart';
import 'package:merman/merman.dart';
import 'package:xml/xml.dart';

import '../../../core/theme.dart';
import '../ai_typography.dart';

String normalizeAiCodeLanguage(String raw) {
  final value = raw.trim().toLowerCase();
  return const {
        'c++': 'cpp',
        'cs': 'csharp',
        'c#': 'csharp',
        'html': 'xml',
        'js': 'javascript',
        'jsx': 'javascript',
        'kt': 'kotlin',
        'md': 'markdown',
        'objective-c': 'objectivec',
        'py': 'python',
        'rb': 'ruby',
        'rs': 'rust',
        'sh': 'bash',
        'shell': 'bash',
        'ts': 'typescript',
        'tsx': 'typescript',
        'yml': 'yaml',
      }[value] ??
      value;
}

class AiCodeBlock extends StatelessWidget {
  const AiCodeBlock({
    super.key,
    required this.source,
    this.language = '',
    this.label,
  });

  final String source;
  final String language;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeAiCodeLanguage(language);
    final canHighlight =
        normalized.isNotEmpty &&
        normalized != 'text' &&
        normalized != 'plaintext' &&
        normalized != 'ascii' &&
        normalized != 'tree' &&
        allLanguages.containsKey(normalized);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xff0d1117) : const Color(0xffffffff);
    final foreground = isDark
        ? const Color(0xffc9d1d9)
        : const Color(0xff24292e);
    final displayLabel = label ?? _languageLabel(normalized);

    return Semantics(
      container: true,
      label: '$displayLabel，代码块',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BlockToolbar(
              label: displayLabel,
              onCopy: () => copyAiRichSource(context, source),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SelectionArea(
                child: canHighlight
                    ? HighlightView(
                        source,
                        languageId: normalized,
                        theme: isDark ? githubDarkTheme : githubTheme,
                        padding: EdgeInsets.zero,
                        textStyle: TextStyle(
                          fontSize: context.aiDetailSize,
                          height: 1.52,
                          fontFamily: 'monospace',
                        ),
                      )
                    : Text(
                        source,
                        softWrap: false,
                        style: TextStyle(
                          color: foreground,
                          fontSize: context.aiDetailSize,
                          height: 1.52,
                          fontFamily: 'monospace',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _languageLabel(String language) {
    if (language == 'diff') return '差异';
    if (language == 'tree' || language == 'ascii') return '文本结构图';
    if (language.isEmpty || language == 'text' || language == 'plaintext') {
      return '文本';
    }
    return language.toUpperCase();
  }
}

class AiCalloutBlock extends StatelessWidget {
  const AiCalloutBlock({super.key, required this.source, required this.kind});

  final String source;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final config = _CalloutConfig.from(kind, context);
    return Semantics(
      container: true,
      label: '${config.label}：$source',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: config.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appDivider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: config.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Icon(config.icon, size: 18, color: config.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.label,
                      style: TextStyle(
                        fontSize: context.aiLabelSize,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: context.appPrimaryText,
                      ),
                    ),
                    if (source.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(
                        source.trim(),
                        style: TextStyle(
                          fontSize: context.aiDetailSize,
                          height: 1.5,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AiLatexBlock extends StatelessWidget {
  const AiLatexBlock({super.key, required this.source, this.display = true});

  final String source;
  final bool display;

  @override
  Widget build(BuildContext context) {
    final fallback = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          display ? '公式暂时无法显示' : source,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: context.aiDetailSize,
            color: context.appSecondaryText,
          ),
        ),
        if (display)
          IconButton(
            tooltip: '复制公式源码',
            onPressed: () => copyAiRichSource(context, source),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
          ),
      ],
    );
    return Semantics(
      label: '数学公式：$source',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          source,
          mathStyle: display ? MathStyle.display : MathStyle.text,
          textStyle: TextStyle(
            fontSize: context.aiBodySize,
            color: context.appPrimaryText,
          ),
          onErrorFallback: (_) => fallback,
        ),
      ),
    );
  }
}

class _CalloutConfig {
  const _CalloutConfig(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  factory _CalloutConfig.from(String raw, BuildContext context) {
    switch (raw.toLowerCase()) {
      case 'tip':
        return _CalloutConfig(
          '提示',
          Icons.lightbulb_outline,
          context.appColors.primary,
        );
      case 'important':
        return const _CalloutConfig(
          '重要',
          Icons.priority_high,
          Color(0xff7c3aed),
        );
      case 'warning':
        return const _CalloutConfig(
          '注意',
          Icons.warning_amber_rounded,
          Color(0xffb45309),
        );
      case 'caution':
        return const _CalloutConfig(
          '警告',
          Icons.error_outline,
          Color(0xffb42318),
        );
      default:
        return _CalloutConfig(
          '说明',
          Icons.info_outline,
          context.appColors.primary,
        );
    }
  }
}

abstract interface class AiMermaidRenderer {
  Future<String> render(String source, {required AiMermaidTheme theme});
}

@immutable
class AiMermaidTheme {
  const AiMermaidTheme({
    required this.optionsJson,
    required this.rootFill,
    required this.rootText,
    required this.branchFills,
    required this.branchTexts,
  });

  final String optionsJson;
  final String rootFill;
  final String rootText;
  final List<String> branchFills;
  final List<String> branchTexts;

  factory AiMermaidTheme.fromColorScheme(ColorScheme colors) {
    String hex(Color color) =>
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    final dark = colors.brightness == Brightness.dark;
    final branches = <(Color, Color)>[
      (colors.primaryContainer, colors.onPrimaryContainer),
      (colors.secondaryContainer, colors.onSecondaryContainer),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
      (colors.surfaceContainerHighest, colors.onSurface),
    ];
    final themeVariables = <String, Object>{
      'background': hex(colors.surface),
      'mainBkg': hex(colors.surfaceContainer),
      'primaryColor': hex(colors.primaryContainer),
      'primaryTextColor': hex(colors.onPrimaryContainer),
      'primaryBorderColor': hex(colors.primary),
      'secondaryColor': hex(colors.secondaryContainer),
      'secondaryTextColor': hex(colors.onSecondaryContainer),
      'secondaryBorderColor': hex(colors.secondary),
      'tertiaryColor': hex(colors.tertiaryContainer),
      'tertiaryTextColor': hex(colors.onTertiaryContainer),
      'tertiaryBorderColor': hex(colors.tertiary),
      'lineColor': hex(colors.outline),
      'nodeTextColor': hex(colors.onSurface),
      'nodeBorder': hex(colors.outlineVariant),
      'clusterBkg': hex(colors.surfaceContainerLow),
      'clusterBorder': hex(colors.outlineVariant),
      'edgeLabelBackground': hex(colors.surface),
      for (var index = 0; index < 12; index++) ...{
        'cScale$index': hex(branches[index % branches.length].$1),
        'cScaleLabel$index': hex(branches[index % branches.length].$2),
      },
    };
    final root = hex(colors.primary);
    final onRoot = hex(colors.onPrimary);
    final scopedCss = [
      '.section-root rect,.section-root path,.section-root circle,.section-root polygon{fill:$root!important;stroke:$root!important}',
      '.section-root text{fill:$onRoot!important}',
      '.section-root span{color:$onRoot!important}',
    ].join();

    return AiMermaidTheme(
      rootFill: root,
      rootText: onRoot,
      branchFills: [for (final branch in branches) hex(branch.$1)],
      branchTexts: [for (final branch in branches) hex(branch.$2)],
      optionsJson: jsonEncode({
        'version': 2,
        'presentation': {
          'theme': {
            'appearance': dark ? 'dark' : 'light',
            'font_family':
                '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
            'roles': {
              'canvas': hex(colors.surface),
              'surface': hex(colors.surfaceContainer),
              'surface-alt': hex(colors.surfaceContainerHigh),
              'text': hex(colors.onSurface),
              'subtle-text': hex(colors.onSurfaceVariant),
              'border': hex(colors.outlineVariant),
              'line': hex(colors.outline),
              'edge-label-background': hex(colors.surface),
            },
            'series_palette': [
              hex(colors.primary),
              hex(colors.secondary),
              hex(colors.tertiary),
              hex(colors.onSurfaceVariant),
            ],
          },
        },
        'site_config': {'theme': 'base', 'themeVariables': themeVariables},
        'svg': {
          'pipeline': 'resvg-safe',
          'root_background_color': 'transparent',
          'scoped_css': scopedCss,
          'css_override_policy': 'strip-existing-important',
        },
      }),
    );
  }
}

class MermanAiMermaidRenderer implements AiMermaidRenderer {
  const MermanAiMermaidRenderer();

  static final Map<String, Future<String>> _cache = {};
  static const _nativeSvgRevision = 2;
  static const _maxSourceChars = 40000;
  static const _maxSvgChars = 1500000;

  @override
  Future<String> render(String source, {required AiMermaidTheme theme}) {
    if (source.trim().isEmpty || source.length > _maxSourceChars) {
      return Future.error(const FormatException('diagram size is invalid'));
    }
    final cacheKey =
        'native-svg-$_nativeSvgRevision\u0000$source\u0000${theme.optionsJson}';
    if (_cache.length > 12) _cache.remove(_cache.keys.first);
    return _cache.putIfAbsent(cacheKey, () {
      final optionsJson = theme.optionsJson;
      final pending = Isolate.run(() {
        // Merman is a native, headless Mermaid renderer. It does not execute
        // model-authored HTML or JavaScript.
        final renderer = Merman.open();
        final svg = renderer.renderSvg(source, optionsJson: optionsJson);
        if (svg.length > _maxSvgChars) {
          throw const FormatException('rendered diagram is too large');
        }
        return materializeAiMindmapNativeStyles(svg, theme);
      });
      return pending.catchError((Object error) {
        _cache.remove(cacheKey);
        throw error;
      });
    });
  }
}

/// `flutter_svg` deliberately supports only a subset of browser CSS. Merman's
/// mindmap output still places the node and edge palette in descendant class
/// selectors, so an unsupported `<style>` block leaves every shape at SVG's
/// default black fill. Materialize the semantic palette as attributes while
/// the SVG is still in the rendering isolate.
@visibleForTesting
String materializeAiMindmapNativeStyles(String svg, AiMermaidTheme theme) {
  XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } on XmlParserException {
    return svg;
  }
  final root = document.rootElement;
  final rootClasses = _svgClasses(root);
  if (root.getAttribute('id') != 'mindmap' &&
      !rootClasses.contains('mindmapDiagram')) {
    return _stripUnsupportedAiNativeSvg(document);
  }

  ({String fill, String text}) paletteFor(Set<String> classes) {
    if (classes.contains('section-root')) {
      return (fill: theme.rootFill, text: theme.rootText);
    }
    for (final className in classes) {
      final match = RegExp(r'^section-(\d+)$').firstMatch(className);
      if (match == null) continue;
      final index = int.parse(match.group(1)!);
      return (
        fill: theme.branchFills[index % theme.branchFills.length],
        text: theme.branchTexts[index % theme.branchTexts.length],
      );
    }
    return (fill: theme.branchFills.first, text: theme.branchTexts.first);
  }

  for (final element in root.descendants.whereType<XmlElement>()) {
    final classes = _svgClasses(element);
    if (classes.contains('edge')) {
      final palette = paletteFor({
        for (final className in classes)
          if (className.startsWith('section-edge-'))
            className.replaceFirst('section-edge-', 'section-'),
      });
      element
        ..setAttribute('fill', 'none')
        ..setAttribute('stroke', palette.fill)
        ..setAttribute('stroke-width', '3')
        ..setAttribute('stroke-linecap', 'round');
    }
    if (!classes.contains('mindmap-node')) continue;
    final palette = paletteFor(classes);
    for (final child in element.descendants.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'rect':
        case 'path':
        case 'circle':
        case 'polygon':
          child
            ..setAttribute('fill', palette.fill)
            ..setAttribute('stroke', palette.fill)
            ..setAttribute('stroke-width', '1');
        case 'line':
          child
            ..setAttribute('stroke', palette.fill)
            ..setAttribute('stroke-width', '3');
        case 'text':
          child.setAttribute('fill', palette.text);
      }
    }
  }
  return _stripUnsupportedAiNativeSvg(document);
}

String _stripUnsupportedAiNativeSvg(XmlDocument document) {
  final root = document.rootElement;
  const unsupportedElements = {'style', 'marker', 'filter'};
  for (final element in root.descendants.whereType<XmlElement>().toList(
    growable: false,
  )) {
    if (unsupportedElements.contains(element.name.local)) {
      element.parent?.children.remove(element);
    }
  }
  for (final element in <XmlElement>[
    root,
    ...root.descendants.whereType<XmlElement>(),
  ]) {
    element
      ..removeAttribute('filter')
      ..removeAttribute('marker-start')
      ..removeAttribute('marker-mid')
      ..removeAttribute('marker-end');
  }
  return document.toXmlString();
}

Set<String> _svgClasses(XmlElement element) => element
    .getAttribute('class')
    .toString()
    .split(RegExp(r'\s+'))
    .where((value) => value.isNotEmpty && value != 'null')
    .toSet();

class AiMermaidBlock extends StatefulWidget {
  const AiMermaidBlock({
    super.key,
    required this.source,
    this.label = '图表',
    this.renderer = const MermanAiMermaidRenderer(),
    this.surfaceBuilder,
  });

  final String source;
  final String label;
  final AiMermaidRenderer renderer;
  final Widget Function(String svg)? surfaceBuilder;

  @override
  State<AiMermaidBlock> createState() => _AiMermaidBlockState();
}

class _AiMermaidBlockState extends State<AiMermaidBlock> {
  late Future<String> _svg;
  AiMermaidTheme? _theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextTheme = AiMermaidTheme.fromColorScheme(context.appColors);
    if (_theme?.optionsJson == nextTheme.optionsJson) return;
    _theme = nextTheme;
    _svg = widget.renderer.render(widget.source, theme: nextTheme);
  }

  @override
  void didUpdateWidget(covariant AiMermaidBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.renderer != widget.renderer) {
      final theme = _theme;
      if (theme != null) {
        _svg = widget.renderer.render(widget.source, theme: theme);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${widget.label}，可打开后缩放查看',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BlockToolbar(
              label: widget.label,
              onCopy: () => copyAiRichSource(context, widget.source),
            ),
            FutureBuilder<String>(
              future: _svg,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _RichLoading(label: '正在绘制图表');
                }
                final svg = snapshot.data;
                if (snapshot.hasError || svg == null || svg.trim().isEmpty) {
                  return _RichFallback(
                    message: '这张图暂时无法绘制，你仍可以查看或复制原始内容。',
                    source: widget.source,
                  );
                }
                return _DiagramPreview(
                  svg: svg,
                  label: widget.label,
                  onOpen: () => _showDiagram(context, svg),
                  surfaceBuilder: widget.surfaceBuilder,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDiagram(BuildContext context, String svg) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(widget.label),
            actions: [
              IconButton(
                tooltip: '复制源码',
                onPressed: () => copyAiRichSource(dialogContext, widget.source),
                icon: const Icon(Icons.content_copy_outlined),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) => Semantics(
              label: '${widget.label}，双指或滚轮缩放，拖动查看',
              child: InteractiveViewer(
                minScale: 0.35,
                maxScale: 6,
                boundaryMargin: const EdgeInsets.all(240),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        widget.surfaceBuilder?.call(svg) ??
                        IgnorePointer(child: _MermaidNativeSurface(svg: svg)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AiDeclarativeChartBlock extends StatelessWidget {
  const AiDeclarativeChartBlock({
    super.key,
    required this.source,
    this.renderer = const MermanAiMermaidRenderer(),
  });

  final String source;
  final AiMermaidRenderer renderer;

  @override
  Widget build(BuildContext context) {
    try {
      final mermaid = AiChartAdapter.toMermaid(source);
      return AiMermaidBlock(source: mermaid, label: '数据图表', renderer: renderer);
    } on FormatException {
      return _RichFallback(
        message: '这组数据暂时无法绘制，你仍可以查看或复制原始内容。',
        source: source,
      );
    }
  }
}

class AiChartAdapter {
  const AiChartAdapter._();

  static String toMermaid(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('chart must be an object');
    final json = decoded.cast<String, dynamic>();
    if (json.containsKey('mark') || json.containsKey('encoding')) {
      return _fromVegaLite(json);
    }
    return _fromSimpleChart(json);
  }

  static String _fromSimpleChart(Map<String, dynamic> json) {
    final type = '${json['type'] ?? json['mark'] ?? ''}'.toLowerCase();
    final labels = _stringList(json['labels']);
    final rawSeries = json['series'];
    if (type == 'pie') {
      final values =
          rawSeries is List && rawSeries.isNotEmpty && rawSeries.first is Map
          ? _numberList((rawSeries.first as Map)['values'])
          : _numberList(json['values']);
      return _pie(labels, values, '${json['title'] ?? ''}');
    }
    if (type != 'bar' && type != 'line') {
      throw const FormatException('unsupported chart type');
    }
    if (rawSeries is! List || rawSeries.isEmpty || rawSeries.length > 8) {
      throw const FormatException('invalid series');
    }
    final series = <({String name, List<double> values})>[];
    for (final item in rawSeries) {
      if (item is! Map) throw const FormatException('invalid series');
      series.add((
        name: '${item['name'] ?? '数据'}',
        values: _numberList(item['values']),
      ));
    }
    return _xy(labels, series, '${json['title'] ?? ''}', type == 'line');
  }

  static String _fromVegaLite(Map<String, dynamic> json) {
    final markValue = json['mark'];
    final mark = (markValue is Map ? markValue['type'] : markValue)
        .toString()
        .toLowerCase();
    final data = json['data'];
    final values = data is Map ? data['values'] : null;
    final encoding = json['encoding'];
    if (values is! List ||
        values.isEmpty ||
        values.length > 64 ||
        encoding is! Map) {
      throw const FormatException('invalid vega-lite data');
    }
    String? field(String channel) {
      final value = encoding[channel];
      return value is Map ? value['field']?.toString() : null;
    }

    final title = '${json['title'] ?? ''}';
    if (mark == 'arc' || mark == 'pie') {
      final labelField = field('color') ?? field('x');
      final valueField = field('theta') ?? field('y');
      if (labelField == null || valueField == null) {
        throw const FormatException('invalid pie');
      }
      return _pie(
        values.map((e) => _mapValue(e, labelField).toString()).toList(),
        values.map((e) => _asNumber(_mapValue(e, valueField))).toList(),
        title,
      );
    }
    if (mark != 'bar' && mark != 'line' && mark != 'area') {
      throw const FormatException('unsupported vega-lite mark');
    }
    final xField = field('x');
    final yField = field('y');
    final colorField = field('color');
    if (xField == null || yField == null) {
      throw const FormatException('invalid xy chart');
    }
    final labels = <String>[];
    final grouped = <String, Map<String, double>>{};
    for (final row in values) {
      final x = _mapValue(row, xField).toString();
      if (!labels.contains(x)) labels.add(x);
      final seriesName = colorField == null
          ? '数据'
          : _mapValue(row, colorField).toString();
      grouped.putIfAbsent(seriesName, () => {})[x] = _asNumber(
        _mapValue(row, yField),
      );
    }
    final series = grouped.entries
        .map(
          (entry) => (
            name: entry.key,
            values: labels.map((label) => entry.value[label] ?? 0).toList(),
          ),
        )
        .toList();
    return _xy(labels, series, title, mark != 'bar');
  }

  static dynamic _mapValue(dynamic row, String field) {
    if (row is! Map || !row.containsKey(field)) {
      throw const FormatException('missing field');
    }
    return row[field];
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List || value.isEmpty || value.length > 64) {
      throw const FormatException('invalid labels');
    }
    return value.map((e) => e.toString()).toList();
  }

  static List<double> _numberList(dynamic value) {
    if (value is! List || value.isEmpty || value.length > 64) {
      throw const FormatException('invalid values');
    }
    return value.map(_asNumber).toList();
  }

  static double _asNumber(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) {
      throw const FormatException('invalid number');
    }
    return number;
  }

  static String _pie(List<String> labels, List<double> values, String title) {
    if (labels.length != values.length || labels.isEmpty) {
      throw const FormatException('invalid pie');
    }
    final lines = <String>['pie showData'];
    if (title.trim().isNotEmpty) lines.add('    title ${_clean(title)}');
    for (var index = 0; index < labels.length; index++) {
      lines.add('    "${_quote(labels[index])}" : ${_format(values[index])}');
    }
    return lines.join('\n');
  }

  static String _xy(
    List<String> labels,
    List<({String name, List<double> values})> series,
    String title,
    bool line,
  ) {
    if (labels.isEmpty ||
        series.isEmpty ||
        series.any((e) => e.values.length != labels.length)) {
      throw const FormatException('invalid xy chart');
    }
    final all = series.expand((e) => e.values).toList();
    var min = all.reduce((a, b) => a < b ? a : b);
    var max = all.reduce((a, b) => a > b ? a : b);
    if (min == max) {
      min = min > 0 ? 0 : min - 1;
      max += 1;
    }
    final lines = <String>['xychart-beta'];
    if (title.trim().isNotEmpty) lines.add('    title "${_quote(title)}"');
    lines.add('    x-axis [${labels.map((e) => '"${_quote(e)}"').join(', ')}]');
    lines.add('    y-axis ${_format(min)} --> ${_format(max)}');
    for (final item in series) {
      // Mermaid xychart has no series label syntax yet. A comment keeps the
      // label in copyable source while remaining valid Mermaid.
      lines
        ..add('    %% ${_clean(item.name)}')
        ..add(
          '    ${line ? 'line' : 'bar'} [${item.values.map(_format).join(', ')}]',
        );
    }
    return lines.join('\n');
  }

  static String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');

  static String _quote(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', ' ');
  static String _clean(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
}

class AiRichPendingBlock extends StatelessWidget {
  const AiRichPendingBlock({super.key, this.label = '正在生成内容'});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appOverlay.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.appDivider),
    ),
    child: _RichLoading(label: label),
  );
}

class _DiagramPreview extends StatelessWidget {
  const _DiagramPreview({
    required this.svg,
    required this.label,
    required this.onOpen,
    this.surfaceBuilder,
  });

  final String svg;
  final String label;
  final VoidCallback onOpen;
  final Widget Function(String svg)? surfaceBuilder;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 140, maxHeight: 380),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child:
                    surfaceBuilder?.call(svg) ??
                    _MermaidNativeSurface(svg: svg),
              ),
            ),
            PositionedDirectional(
              top: 0,
              end: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appColors.surface.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: context.appDivider),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.open_in_full, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Displays Merman's `resvg-safe` output without creating a platform WebView.
/// Keeping diagrams in Flutter's render tree makes list scrolling and
/// InteractiveViewer transforms substantially cheaper and interruptible.
class _MermaidNativeSurface extends StatelessWidget {
  const _MermaidNativeSurface({required this.svg});

  final String svg;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.string(
      svg,
      key: ValueKey<int>(Object.hashAll([svg.length, svg.hashCode])),
      fit: BoxFit.contain,
      placeholderBuilder: (_) => const _RichLoading(label: '正在绘制图表'),
    ),
  );
}

class _BlockToolbar extends StatelessWidget {
  const _BlockToolbar({required this.label, required this.onCopy});

  final String label;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: context.appIsCompact ? 44 : 40),
    padding: const EdgeInsetsDirectional.only(start: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.appDivider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: context.aiDetailSize,
              color: context.appSecondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: '复制源码',
          constraints: BoxConstraints.tightFor(
            width: context.appIsCompact ? 44 : 40,
            height: context.appIsCompact ? 44 : 40,
          ),
          onPressed: onCopy,
          icon: const Icon(Icons.content_copy_outlined, size: 18),
        ),
      ],
    ),
  );
}

class _RichLoading extends StatelessWidget {
  const _RichLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: context.aiDetailSize,
              color: context.appSecondaryText,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RichFallback extends StatelessWidget {
  const _RichFallback({required this.message, required this.source});

  final String message;
  final String source;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appOverlay.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.appDivider),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: context.aiDetailSize,
              height: 1.45,
              color: context.appSecondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => copyAiRichSource(context, source),
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('复制原始内容'),
              ),
              TextButton.icon(
                onPressed: () => _showSource(context, source),
                icon: const Icon(Icons.code, size: 18),
                label: const Text('查看原始内容'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> copyAiRichSource(BuildContext context, String source) async {
  await Clipboard.setData(ClipboardData(text: source));
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('已复制')));
}

Future<void> _showSource(BuildContext context, String source) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('原始内容'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
          child: SingleChildScrollView(
            child: SelectableText(
              source,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: dialogContext.aiDetailSize,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => copyAiRichSource(dialogContext, source),
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

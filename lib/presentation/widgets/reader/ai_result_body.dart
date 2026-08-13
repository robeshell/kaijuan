import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../ai/ai_rich_content_inspector.dart';
import '../ai_typography.dart';
import 'ai_rich_blocks.dart';

/// Reader-oriented GitHub Flavored Markdown rendering for AI output.
///
/// Remote images are represented by an explicit link instead of being fetched
/// automatically. This prevents model-authored Markdown from silently loading
/// third-party tracking resources inside a local reading session.
class AiResultBody extends StatelessWidget {
  const AiResultBody({
    super.key,
    required this.text,
    this.selectable = true,
    this.compact = false,
    this.streaming = false,
    this.onOpenLink,
  });

  final String text;
  final bool selectable;
  final bool compact;
  final bool streaming;

  /// Optional test/host override. Normal UI opens safe web links externally.
  final ValueChanged<Uri>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final data = _prepareRichMarkdown(text, streaming: streaming);
    if (data.trim().isEmpty) return const SizedBox.shrink();

    final baseStyle = TextStyle(
      fontSize: context.aiBodySize,
      height: compact ? 1.55 : 1.6,
      color: context.appPrimaryText,
      fontWeight: FontWeight.w400,
    );
    final detailStyle = baseStyle.copyWith(
      fontSize: context.aiDetailSize,
      height: 1.5,
    );
    final headingBase = baseStyle.copyWith(
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
    final codeSurface = context.appOverlay.withValues(alpha: 0.72);
    final tableHeaderSurface = context.appOverlay.withValues(alpha: 0.9);

    return MarkdownBody(
      data: data,
      selectable: selectable,
      fitContent: false,
      extensionSet: md.ExtensionSet(
        [LatexBlockSyntax(), ...md.ExtensionSet.gitHubWeb.blockSyntaxes],
        [LatexInlineSyntax(), ...md.ExtensionSet.gitHubWeb.inlineSyntaxes],
      ),
      builders: {
        'latex': _SafeLatexElementBuilder(),
        // When selectable:false, a parent SelectionArea owns selection; nested
        // SelectionArea/SelectableText in custom blocks fight ListView drag.
        'pre': _AiPreElementBuilder(ownSelection: selectable),
        'div': _AiAlertElementBuilder(ownSelection: selectable),
      },
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      onTapLink: (_, href, _) => _handleLink(context, href),
      imageBuilder: (uri, title, alt) => _ControlledMarkdownImage(
        uri: uri,
        label: alt?.trim().isNotEmpty == true ? alt!.trim() : title?.trim(),
        safe: _isSafeWebUri(uri),
      ),
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        pPadding: EdgeInsets.zero,
        a: baseStyle.copyWith(
          color: context.appColors.primary,
          decoration: TextDecoration.underline,
          decorationColor: context.appColors.primary.withValues(alpha: 0.65),
          decorationThickness: 1,
        ),
        strong: baseStyle.copyWith(fontWeight: FontWeight.w600),
        em: baseStyle.copyWith(fontStyle: FontStyle.italic),
        del: baseStyle.copyWith(
          color: context.appSecondaryText,
          decoration: TextDecoration.lineThrough,
        ),
        code: detailStyle.copyWith(
          fontFamily: 'monospace',
          height: 1.45,
          backgroundColor: codeSurface,
        ),
        // Chat hierarchy is weight + spacing, not a magazine type scale.
        // h4–h6 stay at body size so deeper headings never look like captions.
        h1: headingBase.copyWith(fontSize: context.aiBodySize + 1),
        h2: headingBase,
        h3: headingBase,
        h4: headingBase.copyWith(fontWeight: FontWeight.w500),
        h5: headingBase.copyWith(
          fontWeight: FontWeight.w500,
          color: context.appSecondaryText,
        ),
        h6: headingBase.copyWith(
          fontWeight: FontWeight.w500,
          color: context.appSecondaryText,
        ),
        h1Padding: EdgeInsets.only(top: compact ? 8 : 10, bottom: 2),
        h2Padding: EdgeInsets.only(top: compact ? 7 : 9, bottom: 2),
        h3Padding: EdgeInsets.only(top: compact ? 6 : 8, bottom: 1),
        h4Padding: const EdgeInsets.only(top: 6),
        h5Padding: const EdgeInsets.only(top: 5),
        h6Padding: const EdgeInsets.only(top: 5),
        blockSpacing: compact ? 8 : 10,
        listIndent: compact ? 20 : 22,
        listBullet: baseStyle.copyWith(
          color: context.appSecondaryText,
          fontWeight: FontWeight.w600,
        ),
        listBulletPadding: const EdgeInsets.only(right: 6),
        checkbox: detailStyle.copyWith(color: context.appColors.primary),
        blockquote: baseStyle.copyWith(color: context.appSecondaryText),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        blockquoteDecoration: BoxDecoration(
          color: context.appOverlay.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(6),
          border: BorderDirectional(
            start: BorderSide(
              color: context.appColors.primary.withValues(alpha: 0.7),
              width: 3,
            ),
          ),
        ),
        codeblockPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appDivider),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.appDivider)),
        ),
        tableHead: detailStyle.copyWith(fontWeight: FontWeight.w600),
        tableBody: detailStyle,
        tableHeadAlign: TextAlign.start,
        tableVerticalAlignment: TableCellVerticalAlignment.middle,
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: false,
        tablePadding: const EdgeInsets.only(bottom: 2),
        tableBorder: TableBorder.all(color: context.appDivider, width: 0.8),
        tableCellsPadding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 7,
        ),
        tableCellsDecoration: const BoxDecoration(),
        tableHeadCellsDecoration: BoxDecoration(color: tableHeaderSurface),
      ),
    );
  }

  void _handleLink(BuildContext context, String? href) {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || !_isSafeWebUri(uri)) {
      _showLinkMessage(context, '仅支持打开网页链接');
      return;
    }
    _openUri(context, uri);
  }

  void _openUri(BuildContext context, Uri uri) {
    final override = onOpenLink;
    if (override != null) {
      override(uri);
      return;
    }
    unawaited(_launchExternal(context, uri));
  }

  static Future<void> _launchExternal(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        _showLinkMessage(context, '无法打开链接');
      }
    } catch (_) {
      if (context.mounted) _showLinkMessage(context, '无法打开链接');
    }
  }

  static void _showLinkMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static bool _isSafeWebUri(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

  static String _prepareRichMarkdown(String raw, {required bool streaming}) {
    var value = _normalizeLegacySections(raw);
    value = _normalizeAsciiTrees(value);
    value = _normalizeLooseStrong(value);
    if (streaming) value = _guardIncompleteRichFence(value);
    return value;
  }

  /// Models sometimes put spaces just inside `**` or leave the final marker
  /// open while streaming. CommonMark intentionally treats those markers as
  /// literal text, but the reader should see stable prose rather than syntax.
  /// Fenced source is never rewritten.
  static String _normalizeLooseStrong(String raw) {
    final output = <String>[];
    var inFence = false;
    String? fence;
    final marker = RegExp(r'(?<!\*)\*\*(?!\*)');
    final loose = RegExp(r'\*\*[ \t]+(.+?)[ \t]+\*\*');

    for (final original in raw.split('\n')) {
      final fenceMatch = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(original);
      if (fenceMatch != null) {
        final nextFence = fenceMatch.group(1)![0];
        if (!inFence) {
          inFence = true;
          fence = nextFence;
        } else if (nextFence == fence) {
          inFence = false;
          fence = null;
        }
        output.add(original);
        continue;
      }
      if (inFence) {
        output.add(original);
        continue;
      }

      final inlineCode = <String>[];
      var line = original.replaceAllMapped(RegExp(r'(`+)(.*?)\1'), (match) {
        inlineCode.add(match.group(0)!);
        return '\uE000${inlineCode.length - 1}\uE001';
      });
      line = line.replaceAllMapped(
        loose,
        (match) => '**${match.group(1)!.trim()}**',
      );
      final markers = marker.allMatches(line).toList(growable: false);
      if (markers.length.isOdd) {
        final dangling = markers.last;
        line = line.replaceRange(dangling.start, dangling.end, '');
      }
      line = line.replaceAllMapped(RegExp(r'\uE000(\d+)\uE001'), (match) {
        final index = int.parse(match.group(1)!);
        return inlineCode[index];
      });
      output.add(line);
    }
    return output.join('\n');
  }

  /// Converts model-authored box-drawing trees into a preformatted block.
  /// Ordinary prose and Markdown tables are unaffected.
  static String _normalizeAsciiTrees(String raw) {
    final lines = raw.split('\n');
    final output = <String>[];
    var inFence = false;
    String? fence;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final marker = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line)?.group(1);
      if (marker != null) {
        if (!inFence) {
          inFence = true;
          fence = marker[0];
        } else if (marker[0] == fence) {
          inFence = false;
          fence = null;
        }
        output.add(line);
        continue;
      }
      if (!inFence && _looksLikeAsciiTree(line)) {
        final treeLines = <String>[];
        var cursor = index;
        while (cursor < lines.length &&
            (lines[cursor].trim().isEmpty ||
                _looksLikeAsciiTree(lines[cursor]))) {
          if (lines[cursor].trim().isNotEmpty) {
            treeLines.add(
              lines[cursor].replaceAllMapped(
                RegExp(r'\s+\|\s+(?=[│├└┬┼])'),
                (_) => '\n',
              ),
            );
          }
          cursor++;
        }
        output
          ..add('```tree')
          ..addAll(treeLines)
          ..add('```');
        index = cursor - 1;
        continue;
      }
      output.add(line);
    }
    return output.join('\n');
  }

  static bool _looksLikeAsciiTree(String line) {
    final branches = RegExp(r'[├└┬┼]').allMatches(line).length;
    return branches >= 1 && RegExp(r'[─│]').hasMatch(line);
  }

  /// A half-written Mermaid/chart fence should not flash parser errors while
  /// tokens are still arriving. Completed blocks render on the next update.
  static String _guardIncompleteRichFence(String raw) {
    final lines = raw.split('\n');
    int? openingIndex;
    String? marker;
    String? language;
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(
        r'^\s*(`{3,}|~{3,})\s*([^\s`]*)',
      ).firstMatch(lines[index]);
      if (match == null) continue;
      if (openingIndex == null) {
        openingIndex = index;
        marker = match.group(1)![0];
        language = (match.group(2) ?? '').toLowerCase();
      } else if (match.group(1)![0] == marker) {
        openingIndex = null;
        marker = null;
        language = null;
      }
    }
    if (openingIndex == null ||
        !const {
          'mermaid',
          'chart',
          'vega-lite',
          'vegalite',
        }.contains(language)) {
      return raw;
    }
    return [
      ...lines.take(openingIndex),
      '```rich-pending',
      language == 'mermaid' ? '正在生成图表' : '正在生成数据图表',
      '```',
    ].join('\n');
  }

  /// Keeps the compact headings used by dictionary/translation results that
  /// predate Markdown output. Fenced code is deliberately left untouched.
  static String _normalizeLegacySections(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final output = <String>[];
    var inFence = false;
    String? fence;
    final section = RegExp(r'^(释义|词性|例句|注|译文|原文)[：:]?$');
    final inlineSection = RegExp(r'^(释义|词性|例句|注|译文|原文)[：:]\s*(.+)$');

    for (final line in lines) {
      final trimmed = line.trim();
      final fenceMatch = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
      if (fenceMatch != null) {
        final marker = fenceMatch.group(1)!;
        if (!inFence) {
          inFence = true;
          fence = marker[0];
        } else if (marker[0] == fence) {
          inFence = false;
          fence = null;
        }
        output.add(line);
        continue;
      }
      if (!inFence) {
        final exact = section.firstMatch(trimmed);
        if (exact != null) {
          output.add('### ${exact.group(1)}');
          continue;
        }
        final inline = inlineSection.firstMatch(trimmed);
        if (inline != null) {
          output
            ..add('### ${inline.group(1)}')
            ..add('')
            ..add(inline.group(2)!.trim());
          continue;
        }
      }
      output.add(line);
    }
    return output.join('\n');
  }
}

class _AiPreElementBuilder extends MarkdownElementBuilder {
  _AiPreElementBuilder({this.ownSelection = true});

  final bool ownSelection;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    md.Element? code;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        code = child;
        break;
      }
    }
    final rawClass = code?.attributes['class'] ?? '';
    final language = rawClass
        .replaceFirst(RegExp(r'^language-'), '')
        .trim()
        .toLowerCase();
    final source = (code?.textContent ?? element.textContent).replaceFirst(
      RegExp(r'\n$'),
      '',
    );
    switch (language) {
      case 'mermaid':
        return AiMermaidBlock(source: source, label: _diagramLabel(source));
      case 'chart':
      case 'vega-lite':
      case 'vegalite':
        return AiDeclarativeChartBlock(source: source);
      case 'rich-pending':
        return AiRichPendingBlock(label: source.trim());
      case 'latex':
      case 'tex':
      case 'math':
        return AiLatexBlock(source: source);
      default:
        return AiCodeBlock(
          source: source,
          language: language,
          ownSelection: ownSelection,
        );
    }
  }

  static String _diagramLabel(String source) {
    return switch (inspectAiMermaidDiagram(source)) {
      AiMermaidDiagramKind.mindMap => '思维导图',
      AiMermaidDiagramKind.sequence => '时序图',
      AiMermaidDiagramKind.classDiagram => '类图',
      AiMermaidDiagramKind.stateDiagram => '状态图',
      AiMermaidDiagramKind.entityRelationship => '实体关系图',
      AiMermaidDiagramKind.gantt => '甘特图',
      AiMermaidDiagramKind.timeline => '时间线',
      AiMermaidDiagramKind.gitGraph => 'Git 分支图',
      AiMermaidDiagramKind.journey => '旅程图',
      AiMermaidDiagramKind.chart => '数据图表',
      AiMermaidDiagramKind.other => '图表',
    };
  }
}

class _SafeLatexElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return AiLatexBlock(
      source: element.textContent,
      display: element.attributes['MathStyle'] == 'display',
    );
  }
}

class _AiAlertElementBuilder extends MarkdownElementBuilder {
  _AiAlertElementBuilder({this.ownSelection = true});

  final bool ownSelection;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final className = element.attributes['class'] ?? '';
    final match = RegExp(
      r'markdown-alert-(note|tip|important|warning|caution)',
    ).firstMatch(className);
    if (match == null) return null;
    final kind = match.group(1)!;
    final englishLabel = switch (kind) {
      'tip' => 'Tip',
      'important' => 'Important',
      'warning' => 'Warning',
      'caution' => 'Caution',
      _ => 'Note',
    };
    final source = element.textContent.replaceFirst(
      RegExp('^$englishLabel\\s*'),
      '',
    );
    return AiCalloutBlock(
      source: source,
      kind: kind,
      ownSelection: ownSelection,
    );
  }
}

class _ControlledMarkdownImage extends StatefulWidget {
  const _ControlledMarkdownImage({
    required this.uri,
    required this.safe,
    this.label,
  });

  final Uri uri;
  final bool safe;
  final String? label;

  @override
  State<_ControlledMarkdownImage> createState() =>
      _ControlledMarkdownImageState();
}

class _ControlledMarkdownImageState extends State<_ControlledMarkdownImage> {
  var _load = false;

  @override
  Widget build(BuildContext context) {
    final description = widget.label?.isNotEmpty == true ? widget.label! : '图片';
    if (_load && widget.safe) {
      final image = Image.network(
        widget.uri.toString(),
        fit: BoxFit.contain,
        semanticLabel: description,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const _ImageLoading(),
        errorBuilder: (context, error, stackTrace) =>
            _ImageFailure(onRetry: () => setState(() => _load = false)),
      );
      return Semantics(
        button: true,
        label: '$description，打开后可缩放查看',
        child: InkWell(
          onTap: () => _showImage(context, description),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              child: image,
            ),
          ),
        ),
      );
    }
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appOverlay.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.appDivider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                size: 16,
                color: context.appSecondaryText,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.aiDetailSize,
                    height: 1.35,
                    color: !widget.safe
                        ? context.appSecondaryText
                        : context.appColors.primary,
                  ),
                ),
              ),
              if (widget.safe) ...[
                const SizedBox(width: 8),
                Text(
                  '加载图片',
                  style: TextStyle(
                    fontSize: context.aiDetailSize,
                    color: context.appColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!widget.safe) return content;
    return Tooltip(
      message: '点击后加载外部图片',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _load = true),
        child: content,
      ),
    );
  }

  Future<void> _showImage(BuildContext context, String description) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(description),
            actions: [
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Center(
              child: Image.network(
                widget.uri.toString(),
                fit: BoxFit.contain,
                semanticLabel: description,
                errorBuilder: (context, error, stackTrace) =>
                    const Center(child: Text('图片加载失败')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageLoading extends StatelessWidget {
  const _ImageLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 120,
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _ImageFailure extends StatelessWidget {
  const _ImageFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('图片加载失败，重新选择'),
      ),
    ),
  );
}

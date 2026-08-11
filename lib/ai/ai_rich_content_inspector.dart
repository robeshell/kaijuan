import 'package:markdown/markdown.dart' as md;

/// Rich artifacts that ordinary chat Markdown can contain.
///
/// These are presentation artifacts, not App-owned workflow artifacts. In
/// particular, a Mermaid mind map must never be treated as an [AiBookMindMap]
/// or parsed back into book-mind-map business data.
enum AiRichArtifactKind {
  mermaidMindMap;

  static AiRichArtifactKind? fromStorage(Object? value) {
    final name = value is String ? value : '';
    return AiRichArtifactKind.values
        .where((kind) => kind.name == name)
        .firstOrNull;
  }
}

enum AiMermaidDiagramKind {
  mindMap,
  sequence,
  classDiagram,
  stateDiagram,
  entityRelationship,
  gantt,
  timeline,
  gitGraph,
  journey,
  chart,
  other,
}

/// Uses the same Markdown AST shape consumed by [AiResultBody]'s code-block
/// builder, so routing and rendering cannot disagree about whether a fenced
/// block is Mermaid.
AiRichArtifactKind? inspectAiRichArtifact(String markdown) {
  if (markdown.trim().isEmpty) return null;
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);
  final nodes = document.parseLines(
    markdown.replaceAll('\r\n', '\n').split('\n'),
  );
  for (final node in nodes) {
    final result = _inspectNode(node);
    if (result != null) return result;
  }
  return null;
}

AiRichArtifactKind? _inspectNode(md.Node node) {
  if (node is! md.Element) return null;
  if (node.tag == 'code') {
    final language = (node.attributes['class'] ?? '')
        .replaceFirst(RegExp(r'^language-'), '')
        .trim()
        .toLowerCase();
    if (language == 'mermaid' &&
        inspectAiMermaidDiagram(node.textContent) ==
            AiMermaidDiagramKind.mindMap) {
      return AiRichArtifactKind.mermaidMindMap;
    }
  }
  for (final child in node.children ?? const <md.Node>[]) {
    final result = _inspectNode(child);
    if (result != null) return result;
  }
  return null;
}

/// Finds the Mermaid declaration while allowing the headers Mermaid accepts
/// before it: YAML front matter, comments, and init/config directives.
AiMermaidDiagramKind inspectAiMermaidDiagram(String source) {
  var inFrontMatter = false;
  var frontMatterSeen = false;
  for (final rawLine in source.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (!frontMatterSeen && line == '---') {
      frontMatterSeen = true;
      inFrontMatter = true;
      continue;
    }
    if (inFrontMatter) {
      if (line == '---') inFrontMatter = false;
      continue;
    }
    if (line.startsWith('%%')) continue;

    final declaration = line.split(RegExp(r'\s+')).first.toLowerCase();
    return switch (declaration) {
      'mindmap' => AiMermaidDiagramKind.mindMap,
      'sequencediagram' => AiMermaidDiagramKind.sequence,
      'classdiagram' => AiMermaidDiagramKind.classDiagram,
      'statediagram' || 'statediagram-v2' => AiMermaidDiagramKind.stateDiagram,
      'erdiagram' => AiMermaidDiagramKind.entityRelationship,
      'gantt' => AiMermaidDiagramKind.gantt,
      'timeline' => AiMermaidDiagramKind.timeline,
      'gitgraph' => AiMermaidDiagramKind.gitGraph,
      'journey' => AiMermaidDiagramKind.journey,
      'pie' || 'xychart-beta' => AiMermaidDiagramKind.chart,
      _ => AiMermaidDiagramKind.other,
    };
  }
  return AiMermaidDiagramKind.other;
}

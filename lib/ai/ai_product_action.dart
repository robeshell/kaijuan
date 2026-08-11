import 'ai_model_adapter.dart';

abstract final class AiProductToolNames {
  static const createBookMindMap = 'create_book_mind_map';
  static const reviseBookMindMap = 'revise_book_mind_map';

  static const all = <String>{createBookMindMap, reviseBookMindMap};
}

enum AiBookMindMapActionScope {
  currentChapter,
  currentWork,
  wholePublication,
  unspecified,
}

sealed class AiProductActionRequest {
  const AiProductActionRequest({required this.instruction});

  final String instruction;
}

final class AiCreateBookMindMapAction extends AiProductActionRequest {
  const AiCreateBookMindMapAction({
    required super.instruction,
    required this.scope,
  });

  final AiBookMindMapActionScope scope;
}

final class AiReviseBookMindMapAction extends AiProductActionRequest {
  const AiReviseBookMindMapAction({
    required super.instruction,
    required this.artifactAlias,
    required this.artifactId,
  });

  final String artifactAlias;
  final String artifactId;
}

class AiProductArtifactAlias {
  const AiProductArtifactAlias({
    required this.alias,
    required this.artifactId,
    required this.title,
    required this.revision,
    this.isAdjacent = false,
    this.isPreferred = false,
  });

  final String alias;
  final String artifactId;
  final String title;
  final int revision;
  final bool isAdjacent;
  final bool isPreferred;
}

class AiChatProductContext {
  const AiChatProductContext({this.artifacts = const []});

  final List<AiProductArtifactAlias> artifacts;

  List<AiModelToolDefinition> get toolDefinitions => [
    const AiModelToolDefinition(
      name: AiProductToolNames.createBookMindMap,
      description:
          'Create a native book mind map when the reader asks to generate, '
          'draw, make, or obtain one. This is a terminal product action and '
          'must be the only tool call in the response. Do not call it for '
          'discussion, critique, instructions, or an explicit Mermaid request.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'scope': {
            'type': 'string',
            'enum': [
              'currentChapter',
              'currentWork',
              'wholePublication',
              'unspecified',
            ],
          },
          'instruction': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
        },
        'required': ['scope', 'instruction'],
      },
    ),
    if (artifacts.isNotEmpty)
      AiModelToolDefinition(
        name: AiProductToolNames.reviseBookMindMap,
        description:
            'Revise one existing native book mind map when the reader asks '
            'for a content change. Use the temporary artifactRef exactly as '
            'listed in trusted product context. This is a terminal product '
            'action and must be the only tool call in the response. Do not '
            'call it merely to discuss or evaluate the map.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'artifactRef': {
              'type': 'string',
              'enum': [for (final artifact in artifacts) artifact.alias],
            },
            'instruction': {
              'type': 'string',
              'minLength': 1,
              'maxLength': 2000,
            },
          },
          'required': ['artifactRef', 'instruction'],
        },
      ),
  ];

  String get trustedPrompt {
    if (artifacts.isEmpty) {
      return 'There are no native mind-map artifacts in this conversation.';
    }
    final lines = <String>[
      'Native mind-map artifacts available in this conversation:',
    ];
    for (final artifact in artifacts) {
      lines.add(
        '- ${artifact.alias}: title=${_singleLine(artifact.title)}, '
        'revision=${artifact.revision}, adjacent=${artifact.isAdjacent}, '
        'preferred=${artifact.isPreferred}',
      );
    }
    lines.add(
      'These aliases are App-authored capabilities. Never invent another alias.',
    );
    return lines.join('\n');
  }

  AiProductActionRequest parse(AiModelToolCall call) {
    if (!AiProductToolNames.all.contains(call.name)) {
      throw const FormatException('Unknown product tool');
    }
    final instruction = '${call.arguments['instruction'] ?? ''}'.trim();
    if (instruction.isEmpty || instruction.length > 2000) {
      throw const FormatException('Invalid product instruction');
    }
    if (call.name == AiProductToolNames.createBookMindMap) {
      final rawScope = '${call.arguments['scope'] ?? 'unspecified'}';
      final scope = AiBookMindMapActionScope.values.where(
        (value) => value.name == rawScope,
      );
      if (scope.isEmpty) throw const FormatException('Invalid mind-map scope');
      return AiCreateBookMindMapAction(
        instruction: instruction,
        scope: scope.single,
      );
    }
    final alias = '${call.arguments['artifactRef'] ?? ''}'.trim();
    final matches = artifacts.where((artifact) => artifact.alias == alias);
    if (matches.length != 1) {
      throw const FormatException('Unknown mind-map artifact alias');
    }
    final artifact = matches.single;
    return AiReviseBookMindMapAction(
      instruction: instruction,
      artifactAlias: alias,
      artifactId: artifact.artifactId,
    );
  }

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

import 'ai_product_action_protocol.dart';

abstract final class AiBookMindMapProductActions {
  static const create = AiProductActionDefinition(
    actionKind: 'create_book_mind_map',
    definitionVersion: 1,
    proposalSchemaVersion: 1,
    commandSchemaVersion: 1,
    workflowVersion: 1,
    riskClass: AiActionRiskClass.reversible,
    supportedSources: {
      AiActionProposalSource.modelTool,
      AiActionProposalSource.explicitUi,
    },
    requiredCapabilities: {'book.read', 'structuredOutput'},
    toolName: 'create_book_mind_map',
    toolDescription: 'Create a native book mind map from frozen book content.',
    argumentSchema: {
      'type': 'object',
      'properties': {
        'scope': {
          'type': 'string',
          'enum': [
            'currentChapter',
            'currentWork',
            'specificWork',
            'wholePublication',
            'unspecified',
          ],
        },
        'workRef': {'type': 'string'},
        'instruction': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
      },
      'required': ['scope', 'instruction'],
    },
    artifactKind: 'book_mind_map',
    artifactSchemaVersion: 1,
    displayNameKey: 'ai.action.createBookMindMap',
  );

  static const revise = AiProductActionDefinition(
    actionKind: 'revise_book_mind_map',
    definitionVersion: 1,
    proposalSchemaVersion: 1,
    commandSchemaVersion: 1,
    workflowVersion: 1,
    riskClass: AiActionRiskClass.reversible,
    supportedSources: {
      AiActionProposalSource.modelTool,
      AiActionProposalSource.explicitUi,
    },
    requiredCapabilities: {'book.read', 'structuredOutput'},
    toolName: 'revise_book_mind_map',
    toolDescription:
        'Revise an existing native book mind map in this conversation. '
        'Omit artifactRef to revise the preferred/latest map. Use when the '
        'reader asks to expand, detail, restructure, or change that map.',
    argumentSchema: {
      'type': 'object',
      'properties': {
        'artifactRef': {
          'type': 'string',
          'description':
              'Optional temporary alias (artifact_n). Defaults to preferred/latest.',
        },
        'instruction': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
      },
      'required': ['instruction'],
    },
    artifactKind: 'book_mind_map',
    artifactSchemaVersion: 1,
    displayNameKey: 'ai.action.reviseBookMindMap',
  );

  static AiProductActionRegistry get registry =>
      AiProductActionRegistry([create, revise]);
}

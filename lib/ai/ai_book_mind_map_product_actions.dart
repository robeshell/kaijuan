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
    toolName: 'create_book_mind_map',
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
    toolName: 'revise_book_mind_map',
    displayNameKey: 'ai.action.reviseBookMindMap',
  );

  static AiProductActionRegistry get registry =>
      AiProductActionRegistry([create, revise]);
}

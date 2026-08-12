import 'ai_book_mind_map_product_actions.dart';
import 'ai_mind_map.dart';
import 'ai_workflow_contract.dart';

/// Strong-typed domain payload for a book mind map inside [AiArtifactEnvelope].
/// Used by tests and any remaining heavy Workflow projection helpers.
abstract final class AiBookMindMapArtifactCodec {
  static const kind = 'book_mind_map';

  static Map<String, Object?> encode(AiBookMindMap map) => map.toJson();

  static AiBookMindMap? decode(Map<String, Object?> payload) =>
      AiBookMindMap.fromJson(payload);

  static AiArtifactEnvelope envelopeFor({
    required AiBookMindMap map,
    required String artifactId,
    required String lineageRootId,
    required int revision,
    required DateTime createdAt,
  }) {
    final body = map.copyWith(artifactId: artifactId, revision: revision);
    return AiArtifactEnvelope(
      artifactId: artifactId,
      kind: kind,
      schemaVersion:
          AiBookMindMapProductActions.create.artifactSchemaVersion ?? 1,
      revision: revision,
      contentHash: body.contentHash,
      payload: encode(body),
      createdAt: createdAt,
      lineageRootId: lineageRootId,
    );
  }

  static String lineageRootOf(AiBookMindMap map) =>
      map.sourceArtifactId ??
      map.artifactId ??
      'mind-map:${map.scopeFingerprint}';
}


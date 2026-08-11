enum AiIntentObject { chat, mindMap, outline, knowledgeGraph, translation }

enum AiIntentAction { create, edit, regenerate, export, cancel, discuss }

/// Accepted App command stored with the user turn.
///
/// Retry reuses this frozen target instead of interpreting the text again.
class AiConversationCommand {
  const AiConversationCommand({
    required this.object,
    required this.action,
    required this.originalText,
    this.targetArtifactId,
  });

  final AiIntentObject object;
  final AiIntentAction action;
  final String originalText;
  final String? targetArtifactId;

  Map<String, Object?> toJson() => {
    'object': object.name,
    'action': action.name,
    'originalText': originalText,
    if (targetArtifactId != null) 'targetArtifactId': targetArtifactId,
  };

  static AiConversationCommand? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, Object?>.from(value);
    final objectName = json['object'] as String?;
    final actionName = json['action'] as String?;
    final text = json['originalText'] as String?;
    if (objectName == null || actionName == null || text == null) return null;
    final object = AiIntentObject.values
        .where((candidate) => candidate.name == objectName)
        .firstOrNull;
    final action = AiIntentAction.values
        .where((candidate) => candidate.name == actionName)
        .firstOrNull;
    if (object == null || action == null) return null;
    return AiConversationCommand(
      object: object,
      action: action,
      originalText: text,
      targetArtifactId: json['targetArtifactId'] as String?,
    );
  }
}

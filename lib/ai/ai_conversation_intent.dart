/// Product objects that can be addressed from the book conversation.
///
/// This is an App contract, not a provider/tool schema. A provider may later
/// propose one of these values, but the App remains the authority that accepts
/// and executes it.
enum AiIntentObject { chat, mindMap, outline, knowledgeGraph, translation }

enum AiIntentAction { create, edit, regenerate, export, cancel, discuss }

enum AiIntentScope {
  unspecified,
  currentChapter,
  currentWork,
  wholeBook,
  namedWork,
  existingArtifact,
}

/// Stable reference to a structured product result in the conversation.
///
/// [messageTurnId] deliberately points at the App conversation identity
/// rather than a provider session or model response ID.
class AiArtifactRef {
  const AiArtifactRef({
    required this.artifactId,
    required this.messageTurnId,
    required this.object,
    this.revision = 1,
  });

  final String artifactId;
  final String messageTurnId;
  final AiIntentObject object;
  final int revision;
}

/// Trusted facts made available to the intent layer for one conversation turn.
///
/// It contains identity and recent product artifacts only. It must not contain
/// the book body or provider-specific objects.
class AiConversationContext {
  const AiConversationContext({
    this.contentHash,
    this.currentSectionIndex,
    this.currentChapterTitle = '',
    this.currentWorkKey,
    this.recentArtifacts = const [],
    this.activeRunId,
  });

  final String? contentHash;
  final int? currentSectionIndex;
  final String currentChapterTitle;
  final String? currentWorkKey;
  final List<AiArtifactRef> recentArtifacts;
  final String? activeRunId;

  AiArtifactRef? get latestMindMap => recentArtifacts
      .where((artifact) => artifact.object == AiIntentObject.mindMap)
      .lastOrNull;
}

class AiConversationIntent {
  const AiConversationIntent({
    required this.object,
    required this.action,
    required this.scope,
    required this.originalText,
    this.target,
    this.modifiers = const {},
  });

  final AiIntentObject object;
  final AiIntentAction action;
  final AiIntentScope scope;
  final AiArtifactRef? target;
  final Map<String, Object?> modifiers;
  final String originalText;
}

sealed class AiConversationRoute {
  const AiConversationRoute();
}

class AiOrdinaryChatRoute extends AiConversationRoute {
  const AiOrdinaryChatRoute();
}

class AiWorkflowRoute extends AiConversationRoute {
  const AiWorkflowRoute(this.intent);

  final AiConversationIntent intent;
}

class AiClarificationRoute extends AiConversationRoute {
  const AiClarificationRoute({
    required this.intent,
    required this.missingSlots,
  });

  final AiConversationIntent intent;
  final List<String> missingSlots;
}

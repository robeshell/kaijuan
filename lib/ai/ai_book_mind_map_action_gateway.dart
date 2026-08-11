import 'ai_book_structure.dart';
import 'ai_chat.dart';
import 'ai_chat_retrieve.dart';
import 'ai_mind_map.dart';
import 'ai_models.dart';
import 'ai_product_action.dart';

class AiBookMindMapTurnSnapshot {
  const AiBookMindMapTurnSnapshot({
    required this.conversationWorkKey,
    required this.currentWork,
    required this.availableWorks,
    required this.currentChapter,
    required this.manifest,
  });

  final String? conversationWorkKey;
  final AiBookWork? currentWork;
  final List<AiBookWork> availableWorks;
  final AiBookSectionSlice? currentChapter;
  final AiBookStructureManifest? manifest;
}

typedef AiBookMindMapCreateInput = ({
  AiBookWork? work,
  AiBookSectionSlice? frozenCurrentChapter,
  AiMindMapRequestScope scope,
});

class AiBookMindMapProductTurn {
  const AiBookMindMapProductTurn({
    required this.modelContext,
    required this.scopeSnapshot,
    required this.artifactsById,
  });

  final AiChatProductContext modelContext;
  final AiBookMindMapTurnSnapshot scopeSnapshot;
  final Map<String, AiBookMindMap> artifactsById;
}

/// Validates terminal Agent actions against App-frozen product capabilities.
///
/// The model supplies only a requested action and temporary aliases. This
/// gateway resolves them against the immutable turn snapshot and never reads
/// the live reader position, database IDs or Widget state.
abstract final class AiBookMindMapActionGateway {
  static AiBookMindMapProductTurn prepareProductTurn({
    required List<AiChatMessage> history,
    required AiBookMindMapTurnSnapshot scopeSnapshot,
    String? preferredArtifactId,
  }) {
    final nativeMessages = history
        .where((message) => message.mindMap != null)
        .toList(growable: false);
    final adjacentMessage = history.isEmpty ? null : history.last;
    final aliases = <AiProductArtifactAlias>[];
    final artifactsById = <String, AiBookMindMap>{};
    for (var index = 0; index < nativeMessages.length; index++) {
      final message = nativeMessages[index];
      final map = message.mindMap!;
      final artifactId =
          map.artifactId ??
          message.turnId ??
          'mind-map:${map.scopeFingerprint}';
      artifactsById[artifactId] = map;
      aliases.add(
        AiProductArtifactAlias(
          alias: 'artifact_${index + 1}',
          artifactId: artifactId,
          title: map.root.title,
          revision: map.revision,
          isAdjacent: identical(message, adjacentMessage),
          isPreferred: artifactId == preferredArtifactId,
        ),
      );
    }
    final workAliases = <AiProductWorkAlias>[];
    for (var index = 0; index < scopeSnapshot.availableWorks.length; index++) {
      final work = scopeSnapshot.availableWorks[index];
      workAliases.add(
        AiProductWorkAlias(
          alias: 'work_${index + 1}',
          workId: work.id,
          title: work.title,
          isCurrent: work.id == scopeSnapshot.currentWork?.id,
        ),
      );
    }
    return AiBookMindMapProductTurn(
      modelContext: AiChatProductContext(
        artifacts: List.unmodifiable(aliases),
        works: List.unmodifiable(workAliases),
      ),
      scopeSnapshot: scopeSnapshot,
      artifactsById: Map.unmodifiable(artifactsById),
    );
  }

  static AiBookMindMapTurnSnapshot freeze({
    required String? conversationWorkKey,
    required AiBookWork? currentWork,
    required AiBookStructureManifest? manifest,
    required AiChatContextBundle context,
  }) {
    final chapterText = context.chapterText.trim();
    final chapterIndex = context.chapterSectionIndex;
    final chapter = chapterText.isEmpty || chapterIndex == null
        ? null
        : AiBookSectionSlice(
            index: chapterIndex,
            sourceSectionIndex: chapterIndex,
            label: context.chapterTitle.trim().isEmpty
                ? '当前章节'
                : context.chapterTitle.trim(),
            text: chapterText,
          );
    return AiBookMindMapTurnSnapshot(
      conversationWorkKey: conversationWorkKey,
      currentWork: currentWork,
      availableWorks: List.unmodifiable(
        manifest?.works ?? const <AiBookWork>[],
      ),
      currentChapter: chapter,
      manifest: manifest,
    );
  }

  static AiBookMindMapCreateInput resolveCreate(
    AiCreateBookMindMapAction action,
    AiBookMindMapTurnSnapshot snapshot,
  ) {
    switch (action.scope) {
      case AiBookMindMapActionScope.currentChapter:
      case AiBookMindMapActionScope.unspecified:
        final chapter = snapshot.currentChapter;
        if (chapter == null) {
          throw AiProviderException('发送问题时的章节正文尚未就绪，请重试');
        }
        return (
          work: snapshot.currentWork,
          frozenCurrentChapter: chapter,
          scope: AiMindMapRequestScope.currentChapter,
        );
      case AiBookMindMapActionScope.currentWork:
        return (
          work: snapshot.currentWork,
          frozenCurrentChapter: null,
          scope: AiMindMapRequestScope.currentWork,
        );
      case AiBookMindMapActionScope.specificWork:
        final workId = action.workId;
        final matches = snapshot.availableWorks.where(
          (work) => work.id == workId,
        );
        if (workId == null || matches.length != 1) {
          throw AiProviderException('所选作品范围已经变化，请重新选择');
        }
        return (
          work: matches.single,
          frozenCurrentChapter: null,
          scope: AiMindMapRequestScope.currentWork,
        );
      case AiBookMindMapActionScope.wholePublication:
        return (
          work: null,
          frozenCurrentChapter: null,
          scope: AiMindMapRequestScope.wholeBook,
        );
    }
  }

  static AiBookMindMap resolveRevision(
    AiReviseBookMindMapAction action,
    Map<String, AiBookMindMap> artifactsById,
  ) {
    final target = artifactsById[action.artifactId];
    if (target == null) {
      throw AiProviderException('这张导图已不在当前对话中，请重新选择后再修改');
    }
    return target;
  }
}

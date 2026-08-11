import 'ai_conversation_intent.dart';

/// Deterministic first-pass router for product commands in book chat.
///
/// It intentionally does not call a model. The router only recognizes product
/// intent and extracts small, stable slots; book scope resolution and actual
/// execution remain with the reader controller and its Workflows.
class AiConversationRouter {
  const AiConversationRouter({this.mindMapEditingEnabled = false});

  final bool mindMapEditingEnabled;

  AiConversationRoute resolve(
    String text, {
    AiConversationContext context = const AiConversationContext(),
  }) {
    final intent = classify(text, context: context);
    if (intent == null || intent.action == AiIntentAction.discuss) {
      return const AiOrdinaryChatRoute();
    }
    if (intent.object == AiIntentObject.mindMap &&
        intent.action == AiIntentAction.edit &&
        !mindMapEditingEnabled) {
      // Callers that have not opted into the edit Workflow retain the legacy
      // ordinary-chat behavior. The book chat sheet enables it explicitly.
      return const AiOrdinaryChatRoute();
    }
    final needsArtifact =
        intent.action == AiIntentAction.edit ||
        (intent.action == AiIntentAction.regenerate &&
            intent.scope == AiIntentScope.existingArtifact);
    if (needsArtifact && intent.target == null) {
      return AiClarificationRoute(
        intent: intent,
        missingSlots: const ['targetArtifact'],
      );
    }
    return AiWorkflowRoute(intent);
  }

  /// Returns the best App-level interpretation without executing it.
  AiConversationIntent? classify(
    String text, {
    AiConversationContext context = const AiConversationContext(),
  }) {
    final original = text.trim();
    if (original.isEmpty) return null;
    final normalized = _normalize(original);
    final asksForMap =
        normalized.contains('思维导图') ||
        normalized.contains('脑图') ||
        normalized.contains('mindmap');
    if (!asksForMap || normalized.contains('mermaid')) return null;

    if (_containsAny(normalized, const [
      '不要',
      '不需要',
      '不想要',
      '不想看',
      '不想生成',
      '不想做',
      '不想画',
      '无需',
      '不用',
      '不必',
      '别生成',
      '别创建',
      '别制作',
      '别画',
      '别做',
      '别给我',
    ])) {
      return null;
    }
    if (_containsAny(normalized, const [
      '为什么',
      '为何',
      '怎么',
      '如何',
      'howto',
      'why',
      '比较',
      '区别',
      '差别',
    ])) {
      return null;
    }

    final hasGenerationAction = _containsAny(normalized, const [
      '重新生成',
      '再生成',
      '重做',
      '生成',
      '创建',
      '制作',
      '绘制',
      '做一个',
      '做个',
      '做一份',
      '做份',
      '做张',
      '做成',
      '帮我做',
      '为我做',
      '画一个',
      '画个',
      '画一份',
      '画张',
      '帮我画',
      '为我画',
      '画本章',
      '画当前章',
      '画这本书',
      '画本书',
      '画全书',
      '画思维导图',
      '画脑图',
      '整理成',
      '梳理成',
      'generate',
      'create',
      'draw',
      'make',
    ]);
    final hasAcquisitionIntent = _containsAny(normalized, const [
      '我需要',
      '需要一',
      '我想要',
      '想要一',
      '给我',
      '请给',
      '来一份',
      '想看',
      '输出',
      '展示',
      'ineed',
      'iwant',
      'giveme',
      'showme',
    ]);
    final hasExistingMapOperation = _containsAny(normalized, const [
      '修改',
      '调整',
      '优化',
      '改得',
      '改成',
      '补充',
      '删除',
      '展开',
      '精简',
      '评价',
      '点评',
      '解释',
      '分析',
      '不够',
      '有问题',
      '不专业',
      '做得',
      '画得',
      '制作得',
      '生成的',
    ]);
    final hasExplicitEditVerb = _containsAny(normalized, const [
      '修改',
      '调整',
      '改得',
      '改成',
      '补充',
      '删除',
      '展开',
      '精简',
    ]);
    final hasReplacementAction = _containsAny(normalized, const [
      '重新生成',
      '再生成',
      '重做',
    ]);
    final refersToExistingArtifact = _containsAny(normalized, const [
      '这张',
      '刚才那张',
      '上一张',
      '当前导图',
      '这份导图',
    ]);
    final isBareMapCommand = RegExp(
      r'^(本章|当前章|当前章节|这一章|这章|当前作品|这部作品|当前这部|这一部|这本书|本书|整本书|全书|合集|全部作品|整部合集)的?(思维导图|脑图|mindmap)$',
    ).hasMatch(normalized);

    if (hasExistingMapOperation && !hasReplacementAction) {
      final wantsEdit =
          hasAcquisitionIntent || hasGenerationAction || hasExplicitEditVerb;
      return AiConversationIntent(
        object: AiIntentObject.mindMap,
        action: wantsEdit ? AiIntentAction.edit : AiIntentAction.discuss,
        scope: AiIntentScope.existingArtifact,
        target: context.latestMindMap,
        originalText: original,
      );
    }
    if (!hasGenerationAction && !hasAcquisitionIntent && !isBareMapCommand) {
      return null;
    }

    final action = hasReplacementAction
        ? AiIntentAction.regenerate
        : AiIntentAction.create;
    final scope = hasReplacementAction && refersToExistingArtifact
        ? AiIntentScope.existingArtifact
        : _scopeFor(normalized);
    return AiConversationIntent(
      object: AiIntentObject.mindMap,
      action: action,
      scope: scope,
      target: scope == AiIntentScope.existingArtifact
          ? context.latestMindMap
          : null,
      originalText: original,
    );
  }

  static AiIntentScope _scopeFor(String normalized) {
    if (_containsAny(normalized, const ['当前章', '当前章节', '这一章', '这章', '本章'])) {
      return AiIntentScope.currentChapter;
    }
    if (_containsAny(normalized, const ['当前作品', '这部作品', '当前这部', '这一部'])) {
      return AiIntentScope.currentWork;
    }
    if (_containsAny(normalized, const [
      '这本书',
      '本书',
      '整本书',
      '全书',
      '合集',
      '全部作品',
      '整部合集',
    ])) {
      return AiIntentScope.wholeBook;
    }
    return AiIntentScope.unspecified;
  }

  static bool _containsAny(String value, List<String> candidates) =>
      candidates.any(value.contains);

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，。！？、,.!?]'), '');
}

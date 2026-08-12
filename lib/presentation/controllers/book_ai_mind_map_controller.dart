import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/ai_book_structure.dart';
import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_conversation_intent.dart';
import '../../ai/ai_mind_map.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_product_action_protocol.dart';
import 'book_ai_conversation_controller.dart';

typedef BookAiMindMapGenerationUnit = ({
  AiBookWork? work,
  String label,
  List<AiBookSectionSlice>? frozenSections,
  int estimatedSections,
});

typedef BookAiMindMapSectionLoader =
    Future<List<AiBookSectionSlice>> Function(BookAiMindMapGenerationUnit unit);
typedef BookAiMindMapGenerator =
    Future<AiBookMindMap?> Function(
      BookAiMindMapGenerationUnit unit,
      List<AiBookSectionSlice> sections,
      String progressLabel,
    );

class BookAiMindMapBatchOutcome {
  const BookAiMindMapBatchOutcome({
    required this.completed,
    required this.total,
    required this.cancelled,
    this.failedUnit,
    this.error,
    this.userMessage,
  });

  final int completed;
  final int total;
  final bool cancelled;
  final BookAiMindMapGenerationUnit? failedUnit;
  final Object? error;
  final String? userMessage;

  bool get succeeded => !cancelled && completed == total;
}

/// Owns the deterministic native mind-map product turn inside chat.
///
/// Scope selection remains a user interaction. Once the view supplies frozen
/// units and an authorized command, this controller owns the pending user turn,
/// artifact lineage, progress, terminal status, retry identity and session
/// persistence. Production execution goes through
/// [BookAiWorkspaceController.runMindMapProductAction]; this class still
/// validates commands and projects durable conversation messages.
class BookAiMindMapController extends ChangeNotifier {
  BookAiMindMapController(this._conversation);

  final BookAiConversationController _conversation;
  bool _disposed = false;

  String? _activeTurnId;
  String? get activeTurnId => _activeTurnId;

  String? _progress;
  String? get progress => _progress;

  bool get isRunning => _activeTurnId != null;

  String? _attachedArtifactId;
  String? get attachedArtifactId => _attachedArtifactId;

  void attachArtifact(String artifactId) {
    if (_attachedArtifactId == artifactId) return;
    _attachedArtifactId = artifactId;
    notifyListeners();
  }

  void detachArtifact() {
    if (_attachedArtifactId == null) return;
    _attachedArtifactId = null;
    notifyListeners();
  }

  void validateActionCommand({
    required AiAuthorizedCommand actionCommand,
    required List<BookAiMindMapGenerationUnit> units,
    AiBookMindMap? baseMap,
  }) {
    if (actionCommand.actionKind == 'revise_book_mind_map' && baseMap == null) {
      throw StateError('Revision command requires a target mind map');
    }
    if (actionCommand.actionKind != 'create_book_mind_map' &&
        actionCommand.actionKind != 'revise_book_mind_map') {
      throw StateError('Unsupported mind-map action command');
    }
    if (actionCommand.scopeSectionIndices.isEmpty) {
      throw StateError('Mind-map action command has no frozen scope');
    }
    final frozenScope = actionCommand.scopeSectionIndices.toSet();
    final requestedSections = <int>{};
    for (final unit in units) {
      for (final section in unit.frozenSections ?? const []) {
        requestedSections.add(section.index);
      }
    }
    if (requestedSections.isEmpty ||
        requestedSections.length != frozenScope.length ||
        !requestedSections.every(frozenScope.contains)) {
      throw StateError('Mind-map action command scope does not match input');
    }
    if (actionCommand.actionKind == 'revise_book_mind_map') {
      final targetId = baseMap?.artifactId;
      if (targetId == null || actionCommand.targetArtifactId != targetId) {
        throw StateError('Mind-map revision target does not match command');
      }
      if (actionCommand.expectedRevision != baseMap?.revision) {
        throw StateError('Mind-map revision is stale');
      }
    }
  }

  void beginProductTurn({
    required String turnId,
    required String? workKey,
    required String text,
    String? retryTurnId,
    AiConversationCommand? command,
  }) {
    if (_activeTurnId != null) {
      throw StateError('A mind-map product turn is already active');
    }
    _activeTurnId = turnId;
    _conversation.beginTurn(
      turnId: turnId,
      workKey: workKey,
      text: text,
      wantsWebSearch: false,
      retryTurnId: retryTurnId,
      command:
          command ??
          AiConversationCommand(
            object: AiIntentObject.mindMap,
            action: AiIntentAction.create,
            originalText: text,
          ),
    );
  }

  void setProgress(String? value) {
    if (_progress == value) return;
    _progress = value;
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> projectArtifact({
    required String turnId,
    required String? workKey,
    required String unitLabel,
    required int sectionCount,
    required AiBookMindMap artifact,
  }) async {
    final artifactTurnId =
        artifact.artifactId ??
        '$turnId-mind-map-${DateTime.now().microsecondsSinceEpoch}';
    _conversation.appendMessage(
      AiChatMessage(
        role: AiMessageRole.assistant,
        content: '已根据《$unitLabel》的 $sectionCount 章内容生成思维导图。',
        createdAt: DateTime.now(),
        turnId: artifactTurnId,
        status: AiChatTurnStatus.completed,
        mindMap: artifact,
      ),
      workKey: workKey,
    );
    await _conversation.persist();
  }

  void finishProductTurn({
    required String turnId,
    required String? workKey,
    required AiChatTurnStatus status,
    Object? error,
    bool allowRetry = false,
  }) {
    if (_owns(turnId, workKey)) {
      _conversation.finishProductTurn(
        turnId: turnId,
        workKey: workKey,
        status: status,
        error: error,
        allowRetry: allowRetry,
      );
    }
    if (_activeTurnId == turnId) {
      _activeTurnId = null;
      setProgress(null);
    }
  }

  /// Local batch runner used by unit tests and by callers that already hold a
  /// validated [actionCommand]. Production chat goes through the workspace
  /// product executor so journal, checkpoints and receipts stay consistent.
  Future<BookAiMindMapBatchOutcome> generate({
    required String turnId,
    required String? workKey,
    required String text,
    required String publicationTitle,
    required List<BookAiMindMapGenerationUnit> units,
    required BookAiMindMapSectionLoader loadSections,
    required BookAiMindMapGenerator generateMap,
    required bool Function() isCancelled,
    String? Function()? generationError,
    AiBookMindMap? baseMap,
    String? retryTurnId,
    AiConversationCommand? command,
    bool segmentedPublication = false,
    required AiAuthorizedCommand actionCommand,
    void Function(AiBookMindMap artifact)? onArtifact,
  }) async {
    validateActionCommand(
      actionCommand: actionCommand,
      units: units,
      baseMap: baseMap,
    );
    beginProductTurn(
      turnId: turnId,
      workKey: workKey,
      text: text,
      retryTurnId: retryTurnId,
      command: command,
    );
    final totalSections = units.fold<int>(
      0,
      (total, unit) => total + unit.estimatedSections,
    );
    final unitKind = segmentedPublication ? '卷' : '部作品';
    setProgress(
      units.length == 1
          ? '正在为你生成${_scopeText(publicationTitle, units.single)}的思维导图，共 $totalSections 章'
          : '本书分为 ${units.length} $unitKind，共 $totalSections 章，准备依次生成',
    );

    var completed = 0;
    Object? failure;
    String? failureMessage;
    BookAiMindMapGenerationUnit? failedUnit;
    try {
      for (var index = 0; index < units.length; index++) {
        final unit = units[index];
        if (!_owns(turnId, workKey) || isCancelled()) break;
        setProgress(
          units.length == 1
              ? '正在读取${_scopeText(publicationTitle, unit)}正文，预计 ${unit.estimatedSections} 章'
              : '本书共 ${units.length} $unitKind，正在读取第 ${index + 1}/${units.length} 个范围《${unit.label}》',
        );
        late List<AiBookSectionSlice> sections;
        try {
          sections = unit.frozenSections ?? await loadSections(unit);
        } catch (error) {
          failure = error;
          failedUnit = unit;
          break;
        }
        if (!_owns(turnId, workKey) || isCancelled()) break;
        final progress = units.length == 1
            ? '正在为你生成${_scopeText(publicationTitle, unit)}的思维导图，共 ${sections.length} 章'
            : '本书共 ${units.length} $unitKind，正在生成第 ${index + 1}/${units.length} 个范围《${unit.label}》，共 ${sections.length} 章';
        setProgress(progress);
        AiBookMindMap? result;
        try {
          result = await generateMap(unit, sections, progress);
        } catch (error) {
          failure = error;
          failedUnit = unit;
          break;
        }
        if (!_owns(turnId, workKey) || isCancelled()) break;
        if (result == null) {
          failureMessage = generationError?.call();
          failure = StateError(failureMessage ?? '生成思维导图失败');
          failedUnit = unit;
          break;
        }
        completed++;
        final artifactTurnId = '$turnId-mind-map-${index + 1}';
        final artifact = result.copyWith(
          artifactId: artifactTurnId,
          sourceArtifactId: baseMap == null
              ? null
              : baseMap.artifactId ?? 'mind-map:${baseMap.scopeFingerprint}',
          revision: baseMap == null ? 1 : baseMap.revision + 1,
        );
        try {
          await projectArtifact(
            turnId: turnId,
            workKey: workKey,
            unitLabel: unit.label,
            sectionCount: sections.length,
            artifact: artifact,
          );
        } catch (error) {
          failure = error;
          failedUnit = unit;
          break;
        }
        try {
          onArtifact?.call(artifact);
        } catch (_) {
          // Artifact presentation is best-effort.
        }
      }

      final cancelled = isCancelled() || !_owns(turnId, workKey);
      finishProductTurn(
        turnId: turnId,
        workKey: workKey,
        status: cancelled
            ? AiChatTurnStatus.cancelled
            : completed == units.length
            ? AiChatTurnStatus.completed
            : AiChatTurnStatus.failed,
        error: failure,
        allowRetry: !cancelled && completed == 0,
      );
      return BookAiMindMapBatchOutcome(
        completed: completed,
        total: units.length,
        cancelled: cancelled,
        failedUnit: failedUnit,
        error: failure,
        userMessage: failureMessage,
      );
    } finally {
      if (_activeTurnId == turnId) {
        _activeTurnId = null;
        setProgress(null);
      }
    }
  }

  bool _owns(String turnId, String? workKey) =>
      _activeTurnId == turnId &&
      _conversation.activeTurnId == turnId &&
      _conversation.activeTurnWorkKey == workKey;

  String _scopeText(
    String publicationTitle,
    BookAiMindMapGenerationUnit unit,
  ) => unit.label == publicationTitle
      ? '《${unit.label}》'
      : '《$publicationTitle》中的《${unit.label}》';

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

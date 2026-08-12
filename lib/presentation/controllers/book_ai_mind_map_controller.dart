import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/ai_book_structure.dart';
import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_conversation_intent.dart';
import '../../ai/ai_mind_map.dart';
import '../../ai/ai_models.dart';
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

  /// True only when every unit projected durably and no failure was recorded.
  bool get succeeded =>
      !cancelled && error == null && completed == total && total > 0;
}

/// Owns a native mind-map **session turn** inside chat (not a Journal job).
///
/// After the view freezes generation units, this controller owns the pending
/// user turn, progress, projection into conversation messages, and session
/// persistence. No Product Action Command / Receipt is required.
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

  void beginProductTurn({
    required String turnId,
    required String? workKey,
    required String text,
    String? retryTurnId,
    AiConversationCommand? command,
  }) {
    if (_activeTurnId != null) {
      throw StateError('A mind-map session turn is already active');
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

  /// Projects one mind-map artifact into conversation and durably persists it.
  ///
  /// If the message is already in memory but a previous [persist] failed, this
  /// retries the durable write instead of no-opping. Only a successful persist
  /// counts as a completed projection.
  Future<void> projectArtifact({
    required String turnId,
    required String? workKey,
    required String unitLabel,
    required int sectionCount,
    required AiBookMindMap artifact,
  }) async {
    final artifactId = artifact.artifactId;
    final alreadyInMemory =
        artifactId != null &&
        _conversation.hasMindMapArtifact(artifactId, workKey: workKey);
    if (!alreadyInMemory) {
      final artifactTurnId =
          artifactId ??
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
    }
    // Always attempt durable write. A failed previous persist leaves the
    // in-memory message; retry must re-run persist rather than skip.
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

  /// Session batch: freeze units → generate → project messages. No Journal.
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
    void Function(AiBookMindMap artifact)? onArtifact,
  }) async {
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
        final artifactTurnId = '$turnId-mind-map-${index + 1}';
        final artifact = result.copyWith(
          artifactId: artifactTurnId,
          sourceArtifactId: baseMap == null
              ? null
              : baseMap.artifactId ?? 'mind-map:${baseMap.scopeFingerprint}',
          revision: baseMap == null ? 1 : baseMap.revision + 1,
        );
        try {
          // Count only after durable projection; a write failure must not look
          // like a successful unit.
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
        completed++;
        try {
          onArtifact?.call(artifact);
        } catch (_) {
          // Artifact presentation is best-effort.
        }
      }

      final cancelled = isCancelled() || !_owns(turnId, workKey);
      final ok =
          !cancelled &&
          failure == null &&
          completed == units.length &&
          units.isNotEmpty;
      finishProductTurn(
        turnId: turnId,
        workKey: workKey,
        status: cancelled
            ? AiChatTurnStatus.cancelled
            : ok
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

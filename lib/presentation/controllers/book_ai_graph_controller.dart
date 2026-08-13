import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/ai_book_structure.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_graph.dart';
import '../../ai/ai_graph_scope.dart';
import '../../ai/ai_graph_service.dart';
import '../../ai/ai_graph_store.dart';
import '../../ai/ai_log.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_run_orchestrator.dart';
import '../../ai/ai_user_error.dart';
import 'book_ai_workspace_controller.dart';

/// Owns one book's knowledge-graph cache, generation, and checkpoints.
///
/// Does not hold the reading engine. The reader supplies section text,
/// structure, and unread-gate facts through callbacks.
class BookAiGraphController extends ChangeNotifier {
  BookAiGraphController({
    required this.contentHash,
    required this.bookTitle,
    required this.workspace,
    required String Function() bookAuthorsLabel,
    required bool Function() canUseAi,
    required bool Function() allowUnread,
    required int Function() readThrough,
    required Future<List<AiBookSectionSlice>> Function(
      AiGraphWorkCandidate? work,
    )
    loadSections,
    required Future<List<AiBookWork>?> Function({CancelToken? cancel})
    resolveWorks,
    required List<AiBookWork>? Function() resolvedWorks,
    required bool Function(String title) isSuggestedSupplement,
  }) : _bookAuthorsLabel = bookAuthorsLabel,
       _canUseAi = canUseAi,
       _allowUnread = allowUnread,
       _readThrough = readThrough,
       _loadSections = loadSections,
       _resolveWorks = resolveWorks,
       _resolvedWorks = resolvedWorks,
       _isSuggestedSupplement = isSuggestedSupplement;

  final String contentHash;
  final String bookTitle;
  final BookAiWorkspaceController workspace;
  final String Function() _bookAuthorsLabel;
  final bool Function() _canUseAi;
  final bool Function() _allowUnread;
  final int Function() _readThrough;
  final Future<List<AiBookSectionSlice>> Function(AiGraphWorkCandidate? work)
  _loadSections;
  final Future<List<AiBookWork>?> Function({CancelToken? cancel}) _resolveWorks;
  final List<AiBookWork>? Function() _resolvedWorks;
  final bool Function(String title) _isSuggestedSupplement;

  AiGraphStore? _store;
  AiBookGraph? _current;
  AiGraphWorkCandidate? _activeWork;
  Map<String, AiBookGraph> _workGraphs = {};
  AiGraphProgress? _progress;
  String? _error;
  CancelToken? _cancel;
  Future<void>? _generation;
  AiGraphWorkCandidate? _generatingWork;
  bool _disposed = false;

  AiBookGraph? get current => _current;
  AiBookGraph? get visible {
    final graph = _current;
    if (graph == null) return null;
    final display = graph.verifiedForDisplay();
    if (display.entities.isEmpty && display.relations.isEmpty) return null;
    return display;
  }

  bool get hasUsableGraph => hasDisplayData(_current);
  AiGraphWorkCandidate? get activeWork => _activeWork;
  bool get hasActiveWork => _activeWork != null;
  AiGraphProgress? get progress => _progress;
  String? get error => _error;
  bool get isGenerating => _generation != null;
  AiGraphWorkCandidate? get generatingWork => _generatingWork;

  static String workKeyFor(AiBookWork work) => work.id;

  static bool hasDisplayData(AiBookGraph? graph) {
    if (graph == null) return false;
    final display = graph.verifiedForDisplay();
    return display.entities.isNotEmpty || display.relations.isNotEmpty;
  }

  static bool canResumeIncrementally(AiBookGraph? graph) =>
      hasDisplayData(graph);

  static int? readThroughForGeneration({
    required bool userConfirmedScope,
    required bool resettingEmptySnapshot,
    required bool existingIncludesUnread,
    required bool allowUnread,
    required int readThrough,
  }) {
    final applyAutomaticReadGate =
        !userConfirmedScope &&
        !resettingEmptySnapshot &&
        !existingIncludesUnread &&
        !allowUnread;
    return applyAutomaticReadGate ? readThrough : null;
  }

  static List<AiBookSectionSlice> excludeSections(
    List<AiBookSectionSlice> sections,
    Set<int> excluded,
  ) {
    if (excluded.isEmpty) return sections;
    final kept = [
      for (final section in sections)
        if (!excluded.contains(section.index)) section,
    ];
    if (kept.isEmpty) {
      throw AiProviderException('所选章节都被排除了，请至少保留一节正文');
    }
    return kept;
  }

  void attachStore(AiGraphStore? store) {
    _store = store;
  }

  bool hasWorkGraph(AiGraphWorkCandidate work) =>
      hasDisplayData(_workGraphs[workKeyFor(work)]);

  bool workGraphHasNarration(AiGraphWorkCandidate work) =>
      _workGraphs[workKeyFor(work)]?.narration != null;

  AiBookGraph? workGraphFor(AiGraphWorkCandidate work) =>
      _workGraphs[workKeyFor(work)];

  void openWorkGraph(AiGraphWorkCandidate work) {
    final graph = _workGraphs[workKeyFor(work)];
    if (graph == null) return;
    _current = graph;
    _activeWork = work;
    _notify();
  }

  void closeActiveWorkGraph() {
    if (_activeWork == null && _current == null) return;
    _activeWork = null;
    _current = null;
    _notify();
  }

  Future<void> load() async {
    final store = _store;
    if (store == null) return;
    final graph = await store.read(contentHash);
    final works = await store.readAllFor(contentHash);
    _workGraphs = works;
    if (graph != null && !identical(graph, _current)) {
      _current = graph;
      _activeWork = null;
      await _migrateLegacyWholeBookGraph(graph);
      _notify();
    }
  }

  Future<void> generate({
    AiGraphWorkCandidate? only,
    bool force = false,
    AiNarrationPlan? narrationOverride,
    AiNarrationPlanMode narrationMode = AiNarrationPlanMode.autoAnalyze,
    Set<int>? excludedGraphSectionIndices,
  }) {
    final active = _generation;
    if (active != null) return active;
    _generatingWork = only ?? _activeWork;
    final done = Completer<void>();
    _generation = done.future;
    unawaited(() async {
      try {
        await _generate(
          only: only,
          force: force,
          narrationOverride: narrationOverride,
          narrationMode: narrationMode,
          excludedGraphSectionIndices: excludedGraphSectionIndices,
        );
        done.complete();
      } catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }());
    unawaited(
      done.future.whenComplete(() {
        _generation = null;
        _cancel = null;
        _generatingWork = null;
        _notify();
      }),
    );
    return done.future;
  }

  Future<AiGraphScopePlan> scopePlan(AiGraphWorkCandidate? work) async {
    final sections = await _loadSections(work);
    return AiGraphScopePlanner.build(
      sections: sections,
      work: work,
      isSuggestedSupplement: _isSuggestedSupplement,
    );
  }

  Future<List<AiBookSectionSlice>> sectionChoices(
    AiGraphWorkCandidate? work,
  ) async => (await scopePlan(
    work,
  )).choices.map((choice) => choice.section).toList(growable: false);

  Future<AiNarrationPlan?> analyzeNarration({
    AiGraphWorkCandidate? work,
  }) async {
    final service = workspace.graph;
    if (service == null || !_canUseAi()) return null;
    try {
      await _resolveWorks();
      final sections = await _loadSections(work);
      return await service.analyzeNarration(
        bookTitle: work?.title ?? bookTitle,
        bookAuthor: _bookAuthorsLabel().isEmpty ? null : _bookAuthorsLabel(),
        sections: sections,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> delete() async {
    if (isGenerating) return;
    final store = _store;
    final work = _activeWork;
    final workKey = work == null ? null : workKeyFor(work);
    if (store != null) {
      await store.delete(contentHash, workKey: workKey);
    }
    if (workKey == null) {
      _current = null;
    } else {
      _workGraphs.remove(workKey);
      _current = null;
      _activeWork = null;
    }
    _error = null;
    _notify();
  }

  Future<void> hideEntity(String entityId) async {
    if (isGenerating) return;
    final graph = _current;
    if (graph == null || graph.hiddenEntityIds.contains(entityId)) return;
    final hidden = [...graph.hiddenEntityIds, entityId];
    final updated = graph.copyWith(hiddenEntityIds: hidden);
    _current = updated;
    final work = _activeWork;
    await _save(
      updated,
      workKey: work == null ? null : workKeyFor(work),
    );
    _notify();
  }

  void cancel() {
    _cancel?.cancel();
  }

  Future<void> _migrateLegacyWholeBookGraph(AiBookGraph graph) async {
    final store = _store;
    if (store == null) return;
    try {
      final works = _resolvedWorks();
      if (works == null || works.length < 2) return;
      final target = matchingWorkForGraph(works, graph);
      if (target == null) return;
      final key = workKeyFor(target);
      if (_workGraphs.containsKey(key)) return;
      await store.write(
        graph.copyWith(contentHash: contentHash),
        workKey: key,
      );
      await store.delete(contentHash);
      _workGraphs[key] = graph;
      _current = null;
    } catch (_) {}
  }

  @visibleForTesting
  static AiGraphWorkCandidate? matchingWorkForGraph(
    List<AiGraphWorkCandidate> works,
    AiBookGraph graph,
  ) {
    if (works.length < 2 || graph.entities.isEmpty) return null;
    var first = graph.entities.first.firstSection;
    var last = graph.entities.first.lastSection;
    for (final entity in graph.entities.skip(1)) {
      if (entity.firstSection < first) first = entity.firstSection;
      if (entity.lastSection > last) last = entity.lastSection;
    }
    final candidates = works
        .where((work) => work.contains(first) && work.contains(last))
        .toList(growable: false);
    return candidates.length == 1 ? candidates.single : null;
  }

  Future<void> _generate({
    AiGraphWorkCandidate? only,
    bool force = false,
    AiNarrationPlan? narrationOverride,
    AiNarrationPlanMode narrationMode = AiNarrationPlanMode.autoAnalyze,
    Set<int>? excludedGraphSectionIndices,
  }) async {
    var carryExcluded = const <int>[];
    final service = workspace.graph;
    if (service == null || !_canUseAi()) {
      _error = 'AI 未启用或未配置';
      _notify();
      return;
    }
    final work = only ?? _activeWork;
    final workKey = work == null ? null : workKeyFor(work);
    final previous = workKey == null ? _current : _workGraphs[workKey];
    final resettingEmptySnapshot =
        previous != null && !canResumeIncrementally(previous);
    final existing = force || resettingEmptySnapshot ? null : previous;
    final hiddenEntityIds = previous?.hiddenEntityIds ?? const <String>[];
    _error = null;
    final cancel = CancelToken();
    _cancel = cancel;
    _notify();
    try {
      await _resolveWorks(cancel: cancel);
      final allowUnread = _allowUnread();
      final deduped = await _loadSections(work);
      final effectiveExcluded =
          excludedGraphSectionIndices ??
          existing?.excludedGraphSections.toSet() ??
          const <int>{};
      final sections = excludeSections(deduped, effectiveExcluded)
          .where((s) => s.text.trim().isNotEmpty)
          .toList(growable: false);
      if (sections.isEmpty) {
        throw AiProviderException('所选章节都被排除了，请至少保留一节正文');
      }
      final readThrough = _readThrough();
      final userConfirmedScope = excludedGraphSectionIndices != null;
      final selectedIncludesUnread = sections.any(
        (section) => section.originSectionIndex > readThrough,
      );
      final includesUnread =
          allowUnread ||
          selectedIncludesUnread ||
          (existing?.includesUnread ?? false);
      final effectiveReadThrough = readThroughForGeneration(
        userConfirmedScope: userConfirmedScope,
        resettingEmptySnapshot: resettingEmptySnapshot,
        existingIncludesUnread: existing?.includesUnread ?? false,
        allowUnread: allowUnread,
        readThrough: readThrough,
      );
      carryExcluded = (effectiveExcluded.toList()..sort()).toList(
        growable: false,
      );
      final graph = await workspace.executeWorkflow<AiBookGraph>(
        descriptor: AiRunDescriptor(
          runId: AiRunIds.next(),
          task: AiRunTask.bookGraph,
          scope: AiRunScope(
            contentHash: contentHash,
            workKey: workKey,
            label: work?.title,
          ),
        ),
        budget: AiRunBudget(
          maxModelCalls: (sections.length * 12 + 64).clamp(128, 4096),
        ),
        cancelToken: cancel,
        checkpointWriter: (checkpoint) async {
          final partial = checkpoint.payload;
          if (partial is! AiBookGraph) return;
          _current = partial;
          if (work != null) _activeWork = work;
          await _save(partial, workKey: workKey);
        },
        body: (execution) => service.generate(
          bookTitle: work?.title ?? bookTitle,
          bookAuthor: _bookAuthorsLabel().isEmpty ? null : _bookAuthorsLabel(),
          sections: sections,
          sectionScheme: 'spine',
          includesUnread: includesUnread,
          readThroughSection: effectiveReadThrough,
          existing: existing,
          plannedNarration: narrationOverride,
          narrationMode: narrationMode,
          cancelToken: execution.cancelToken,
          onModelStarted: execution.modelStarted,
          onUsage: ({inputTokens, outputTokens}) => execution.reportTokens(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          ),
          onProgress: (progress) {
            execution.progress(progress.label);
            _progress = progress;
            _notify();
          },
          onCheckpoint: (partial) => execution.checkpoint(
            partial.copyWith(
              contentHash: contentHash,
              excludedGraphSections: carryExcluded,
              hiddenEntityIds: hiddenEntityIds,
            ),
          ),
        ),
      );
      final saved = graph.copyWith(
        excludedGraphSections: carryExcluded,
        hiddenEntityIds: hiddenEntityIds,
      );
      _current = saved;
      if (work != null) _activeWork = work;
      _progress = null;
      await _save(saved, workKey: workKey);
      _notify();
    } on AiGraphGenerationException catch (error) {
      _progress = null;
      if (!cancel.isCancelled) {
        AiLog.d('graph failed: ${error.message}');
        final partial = error.partial;
        if (partial != null && !identical(partial, _current)) {
          final savedPartial = partial.copyWith(
            excludedGraphSections: carryExcluded,
            hiddenEntityIds: hiddenEntityIds,
          );
          _current = savedPartial;
          await _save(savedPartial, workKey: workKey);
        }
        _error = aiUserErrorMessage(error, operation: AiUserOperation.graph);
      }
      _notify();
    } catch (error, stack) {
      _progress = null;
      if (!cancel.isCancelled) {
        AiLog.d('graph failed: $error\n$stack');
        _error = '生成图谱失败，请稍后重试';
      }
      _notify();
    }
  }

  Future<void> _save(AiBookGraph graph, {String? workKey}) async {
    final store = _store;
    if (store == null) return;
    await store.write(
      graph.copyWith(contentHash: contentHash),
      workKey: workKey,
    );
    if (workKey != null) _workGraphs[workKey] = graph;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}

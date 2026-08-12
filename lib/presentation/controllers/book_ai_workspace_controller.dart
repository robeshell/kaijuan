import '../../ai/ai_agent_runtime.dart';
import '../../ai/ai_agent_runtime_gate.dart';
import '../../ai/ai_book_mind_map_service.dart';
import '../../ai/ai_book_mind_map_product_actions.dart';
import '../../ai/ai_book_mind_map_workflow.dart';
import '../../ai/ai_book_structure.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_conversation_intent.dart';
import '../../ai/ai_graph_service.dart';
import '../../ai/ai_language_service.dart';
import '../../ai/ai_log.dart';
import '../../ai/ai_mind_map.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_outline.dart';
import '../../ai/ai_product_action_controller.dart';
import '../../ai/ai_product_action_protocol.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_run_orchestrator.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_translation.dart';
import '../../ai/ai_user_error.dart';
import '../../ai/ai_workflow_contract.dart';
import '../../ai/ai_workflow_executor.dart';
import '../../ai/legacy_ai_agent_runtime.dart';
import 'ai_settings_controller.dart';
import 'book_ai_conversation_controller.dart';
import 'book_ai_mind_map_controller.dart';

/// AI services and runtime state for one open book workspace.
///
/// This controller deliberately has no reading-engine callbacks, database, or
/// Widget state. [BookReaderController] remains a compatibility facade while
/// chat UI and deterministic workflows migrate to this boundary.
class BookAiWorkspaceController {
  BookAiWorkspaceController({
    required AiChatSessionWriter saveChatSession,
    AiActionJournalStore? actionJournal,
    AiWorkflowCheckpointStore? workflowCheckpoints,
    AiArtifactRepository? artifactRepository,
    this.agentRuntimeFactory = createLegacyAiAgentRuntime,
    this.genkitAgentRuntimeFactory,
    this.requestedAgentRuntime = AiAgentRuntimeKind.compatible,
    this.genkitAgentCapabilities = AiAgentRuntimeCapabilities.genkitDart0151,
    this.onChanged,
  }) : conversation = BookAiConversationController(saveChatSession),
       actionController = AiProductActionController(
         registry: AiBookMindMapProductActions.registry,
         journal: actionJournal ?? MemoryAiActionJournalStore(),
       ),
       artifactRepository = artifactRepository ?? MemoryAiArtifactRepository(),
       workflowCheckpoints =
           workflowCheckpoints ?? MemoryAiWorkflowCheckpointStore() {
    mindMapConversation = BookAiMindMapController(conversation);
    createMindMapAdapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.create.actionKind,
      artifacts: this.artifactRepository,
    );
    reviseMindMapAdapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.revise.actionKind,
      artifacts: this.artifactRepository,
    );
    workflowAdapters = AiWorkflowAdapterRegistry([
      createMindMapAdapter,
      reviseMindMapAdapter,
    ]);
    workflowExecutor = AiProductWorkflowExecutor(
      actions: actionController,
      adapters: workflowAdapters,
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({}),
        checkpoints: this.workflowCheckpoints,
        now: DateTime.now,
      ),
    );
    agentRuntimeDecision = AiAgentRuntimeGate.decide(
      requested: requestedAgentRuntime,
      genkitCapabilities: genkitAgentCapabilities,
      hasGenkitRuntimeFactory: genkitAgentRuntimeFactory != null,
    );
  }

  final AiAgentRuntimeFactory agentRuntimeFactory;
  final AiAgentRuntimeFactory? genkitAgentRuntimeFactory;
  final AiAgentRuntimeKind requestedAgentRuntime;
  final AiAgentRuntimeCapabilities genkitAgentCapabilities;
  final void Function()? onChanged;
  final BookAiConversationController conversation;
  late final BookAiMindMapController mindMapConversation;
  late final AiAgentRuntimeDecision agentRuntimeDecision;
  final AiProductActionController actionController;
  AiArtifactRepository artifactRepository;
  AiWorkflowCheckpointStore workflowCheckpoints;
  late AiBookMindMapWorkflowAdapter createMindMapAdapter;
  late AiBookMindMapWorkflowAdapter reviseMindMapAdapter;
  late AiWorkflowAdapterRegistry workflowAdapters;
  late AiProductWorkflowExecutor workflowExecutor;

  void replaceActionJournal(AiActionJournalStore store) {
    actionController.replaceJournal(store);
  }

  void replaceWorkflowStores({
    required AiWorkflowCheckpointStore checkpoints,
    required AiArtifactRepository artifacts,
  }) {
    artifactRepository = artifacts;
    workflowCheckpoints = checkpoints;
    createMindMapAdapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.create.actionKind,
      artifacts: artifacts,
    );
    reviseMindMapAdapter = AiBookMindMapWorkflowAdapter(
      actionKind: AiBookMindMapProductActions.revise.actionKind,
      artifacts: artifacts,
    );
    workflowAdapters = AiWorkflowAdapterRegistry([
      createMindMapAdapter,
      reviseMindMapAdapter,
    ]);
    _rebuildExecutor();
  }

  void registerExtraAdapters(Iterable<AiWorkflowAdapter> extra) {
    workflowAdapters = workflowAdapters.extended(extra);
    _rebuildExecutor();
  }

  void _rebuildExecutor() {
    workflowExecutor = AiProductWorkflowExecutor(
      actions: actionController,
      adapters: workflowAdapters,
      environment: AiWorkflowEnvironment(
        capabilities: const AiCapabilitySet({}),
        checkpoints: workflowCheckpoints,
        now: DateTime.now,
      ),
    );
  }

  AiBookMindMapWorkflowAdapter mindMapAdapterFor(String actionKind) {
    if (actionKind == AiBookMindMapProductActions.revise.actionKind) {
      return reviseMindMapAdapter;
    }
    if (actionKind == AiBookMindMapProductActions.create.actionKind) {
      return createMindMapAdapter;
    }
    throw StateError('Unsupported mind-map action: $actionKind');
  }

  /// Projects receipt artifact refs into conversation and returns refs that
  /// were durably written. Safe to call again after a partial failure.
  ///
  /// Each successful durable write is journaled immediately so a later crash
  /// only retries remaining refs.
  Future<List<String>> projectReceiptArtifacts({
    required String proposalId,
    required List<String> receiptRefs,
    required String turnId,
    required String? workKey,
    required String publicationTitle,
    List<String> unitLabels = const [],
    List<int> unitSectionCounts = const [],
    void Function(AiBookMindMap artifact)? onArtifact,
  }) async {
    final projectedRefs = <String>[];
    for (var index = 0; index < receiptRefs.length; index++) {
      final ref = receiptRefs[index];
      final envelope = await artifactRepository.read(ref);
      if (envelope == null) continue;
      final map = AiBookMindMapArtifactCodec.decode(envelope.payload);
      if (map == null) continue;
      final unitLabel = index < unitLabels.length
          ? unitLabels[index]
          : publicationTitle;
      final sectionCount = index < unitSectionCounts.length
          ? unitSectionCounts[index]
          : map.scopeSectionIndices.length;
      await mindMapConversation.projectArtifact(
        turnId: turnId,
        workKey: workKey,
        unitLabel: unitLabel,
        sectionCount: sectionCount,
        artifact: map,
      );
      // Persist projection progress only after durable chat write succeeds.
      await actionController.markProjected(proposalId: proposalId, refs: [ref]);
      projectedRefs.add(ref);
      onArtifact?.call(map);
    }
    return projectedRefs;
  }

  /// Completes conversation projection for a terminal success entry that was
  /// interrupted after Receipt commit.
  Future<BookAiMindMapBatchOutcome> reconcilePendingProjection(
    AiActionJournalEntry entry, {
    required String turnId,
    required String? workKey,
    required String publicationTitle,
    void Function(AiBookMindMap artifact)? onArtifact,
  }) async {
    final pending = entry.pendingProjectionRefs;
    if (pending.isEmpty) {
      return const BookAiMindMapBatchOutcome(
        completed: 0,
        total: 0,
        cancelled: false,
      );
    }
    final labels =
        (entry.command?.arguments['unitLabels'] as List?)
            ?.map((value) => '$value')
            .toList(growable: false) ??
        const <String>[];
    final counts =
        (entry.command?.arguments['unitSectionCounts'] as List?)
            ?.whereType<num>()
            .map((value) => value.toInt())
            .toList(growable: false) ??
        const <int>[];
    final projected = <AiBookMindMap>[];
    await projectReceiptArtifacts(
      proposalId: entry.proposal.proposalId,
      receiptRefs: pending,
      turnId: turnId,
      workKey: workKey,
      publicationTitle: publicationTitle,
      unitLabels: labels,
      unitSectionCounts: counts,
      onArtifact: (map) {
        projected.add(map);
        onArtifact?.call(map);
      },
    );
    return BookAiMindMapBatchOutcome(
      completed: projected.length,
      total: pending.length,
      cancelled: false,
    );
  }

  /// Runs an authorized mind-map command through the generic product executor.
  ///
  /// Order is fixed: generate → Artifact commit → checkpoint → Receipt →
  /// conversation projection. Projection never runs before Receipt.
  Future<BookAiMindMapBatchOutcome> runMindMapProductAction({
    required String proposalId,
    required AiAuthorizedCommand actionCommand,
    required String turnId,
    required String? workKey,
    required String text,
    required String publicationTitle,
    required List<BookAiMindMapGenerationUnit> units,
    required BookAiMindMapSectionLoader loadSections,
    required BookAiMindMapGenerator generateMap,
    required CancelToken cancelToken,
    AiBookMindMap? baseMap,
    String? retryTurnId,
    AiConversationCommand? command,
    bool segmentedPublication = false,
    void Function(AiBookMindMap artifact)? onArtifact,
    int? attempt,
  }) async {
    mindMapConversation.validateActionCommand(
      actionCommand: actionCommand,
      units: units,
      baseMap: baseMap,
    );

    final preparedUnits =
        <
          ({AiBookWork? work, String label, List<AiBookSectionSlice> sections})
        >[];
    for (final unit in units) {
      final sections = unit.frozenSections ?? await loadSections(unit);
      preparedUnits.add((
        work: unit.work,
        label: unit.label,
        sections: sections,
      ));
    }

    final adapter = mindMapAdapterFor(actionCommand.actionKind);
    mindMapConversation.beginProductTurn(
      turnId: turnId,
      workKey: workKey,
      text: text,
      retryTurnId: retryTurnId,
      command: command,
    );

    adapter.stage(
      actionCommand.commandId,
      AiBookMindMapStagedRun(
        units: preparedUnits,
        userInstruction: text,
        publicationTitle: publicationTitle,
        baseMap: baseMap,
        generateUnit:
            ({
              required work,
              required label,
              required sections,
              required progressLabel,
              required cancelToken,
            }) async {
              mindMapConversation.setProgress(progressLabel);
              return generateMap(
                (
                  work: work,
                  label: label,
                  frozenSections: sections,
                  estimatedSections: sections.length,
                ),
                sections,
                progressLabel,
              );
            },
        onProgress: mindMapConversation.setProgress,
      ),
    );

    try {
      final entry = await workflowExecutor.execute(
        proposalId,
        cancelToken: cancelToken,
        attempt: attempt ?? 1,
      );
      final cancelled =
          entry.status == AiActionJournalStatus.cancelled ||
          cancelToken.isCancelled;
      final succeeded = entry.status == AiActionJournalStatus.succeeded;
      final partially =
          entry.status == AiActionJournalStatus.partiallySucceeded;

      final projected = <AiBookMindMap>[];
      // Projection is App-owned and happens only after a non-cancelled Receipt.
      if (!cancelled &&
          (succeeded || partially) &&
          entry.receipt != null &&
          entry.receipt!.artifactRefs.isNotEmpty) {
        try {
          await projectReceiptArtifacts(
            proposalId: proposalId,
            receiptRefs: entry.receipt!.artifactRefs,
            turnId: turnId,
            workKey: workKey,
            publicationTitle: publicationTitle,
            unitLabels: [for (final unit in preparedUnits) unit.label],
            unitSectionCounts: [
              for (final unit in preparedUnits) unit.sections.length,
            ],
            onArtifact: (map) {
              projected.add(map);
              onArtifact?.call(map);
            },
          );
        } catch (projectionError) {
          // Durable Workflow already succeeded. Projection is retryable and
          // must not rewrite the journal terminal state as a generation failure.
          AiLog.d('mind map projection failed: $projectionError');
          mindMapConversation.finishProductTurn(
            turnId: turnId,
            workKey: workKey,
            status: AiChatTurnStatus.completed,
            allowRetry: false,
          );
          return BookAiMindMapBatchOutcome(
            completed: projected.length,
            total: preparedUnits.length,
            cancelled: false,
            userMessage: 'mind_map_projection_failed',
            error: projectionError,
          );
        }
      }

      mindMapConversation.finishProductTurn(
        turnId: turnId,
        workKey: workKey,
        status: cancelled
            ? AiChatTurnStatus.cancelled
            : succeeded || partially
            ? AiChatTurnStatus.completed
            : AiChatTurnStatus.failed,
        allowRetry: !cancelled && projected.isEmpty && !succeeded,
      );
      return BookAiMindMapBatchOutcome(
        completed: projected.length,
        total: preparedUnits.length,
        cancelled: cancelled,
        failedUnit: succeeded || partially || cancelled
            ? null
            : (units.isEmpty ? null : units.first),
        userMessage: succeeded || partially || cancelled
            ? null
            : entry.receipt?.publicErrorCode,
      );
    } catch (error) {
      mindMapConversation.finishProductTurn(
        turnId: turnId,
        workKey: workKey,
        status: cancelToken.isCancelled
            ? AiChatTurnStatus.cancelled
            : AiChatTurnStatus.failed,
        error: error,
        allowRetry: !cancelToken.isCancelled,
      );
      return BookAiMindMapBatchOutcome(
        completed: 0,
        total: preparedUnits.length,
        cancelled: cancelToken.isCancelled,
        error: error,
      );
    }
  }

  AiSettingsController? _settings;
  AiLanguageService? _language;
  AiAgentRuntime? _agentRuntime;
  AiBookOutlineService? _outline;
  AiBookMindMapService? _mindMap;
  AiBookGraphService? _graph;
  String? _mindMapProgress;
  String? _mindMapError;
  CancelToken? _mindMapCancel;
  Future<AiBookMindMap?>? _mindMapGeneration;

  final Map<String, AiRunState> _runStates = {};
  String? _latestRunId;

  /// Rebuilds provider-bound services when the settings controller identity
  /// changes. Returns true when consumers should rebuild.
  bool bindSettings(AiSettingsController? settings) {
    if (identical(_settings, settings) &&
        (settings == null) == (_language == null) &&
        (settings == null) == (_agentRuntime == null) &&
        (settings == null) == (_outline == null) &&
        (settings == null) == (_mindMap == null) &&
        (settings == null) == (_graph == null)) {
      return false;
    }
    _settings = settings;
    _language = settings == null
        ? null
        : AiLanguageService(
            isAvailable: () => settings.isReadyForRequests,
            openModelAdapter: () => settings.openModelAdapter(),
            settings: () => settings.settings,
          );
    final selectedAgentFactory =
        agentRuntimeDecision.effective == AiAgentRuntimeKind.genkitAgent
        ? genkitAgentRuntimeFactory!
        : agentRuntimeFactory;
    _agentRuntime = settings == null
        ? null
        : selectedAgentFactory(
            isAvailable: () => settings.isReadyForRequests,
            openModelAdapter: ({reasoningEnabled}) =>
                settings.openModelAdapter(reasoningEnabled: reasoningEnabled),
          );
    _outline = settings == null
        ? null
        : AiBookOutlineService(
            isAvailable: () => settings.isReadyForRequests,
            openModelAdapter: () => settings.openModelAdapter(),
            settings: () => settings.settings,
          );
    _mindMap = settings == null
        ? null
        : AiBookMindMapService(
            isAvailable: () => settings.isReadyForRequests,
            openModelAdapter: () => settings.openModelAdapter(),
            settings: () => settings.settings,
          );
    _graph = settings == null
        ? null
        : AiBookGraphService(
            isAvailable: () => settings.isReadyForRequests,
            openModelAdapter: () => settings.openModelAdapter(),
            settings: () => settings.settings,
          );
    return true;
  }

  AiSettingsController? get settingsController => _settings;
  AiLanguageService? get language => _language;
  AiAgentRuntime? get agentRuntime => _agentRuntime;
  AiBookOutlineService? get outline => _outline;
  AiBookMindMapService? get mindMap => _mindMap;
  AiBookGraphService? get graph => _graph;
  String? get mindMapProgress => _mindMapProgress;
  String? get mindMapError => _mindMapError;
  bool get isGeneratingMindMap => _mindMapGeneration != null;

  bool get canUseLanguage => _language?.isAvailable ?? false;
  bool get canUseChat => _agentRuntime?.isAvailable ?? false;
  bool get canUseWebSearch => _settings?.isSearchReady ?? false;

  bool get supportsDeepThinking {
    final value = _settings?.settings;
    return value != null &&
        value.providerKind.reasoningCapabilities(value.resolvedModel).supported;
  }

  bool get defaultDeepThinkingEnabled =>
      _settings?.settings.reasoningEnabled ?? false;

  bool get allowUnreadGraphContext =>
      _settings?.settings.allowUnreadContext ?? false;

  AiTranslationPreferences get translationPreferences =>
      _settings?.settings.translation ?? const AiTranslationPreferences();

  AiContentRuleWords get contentRuleWords =>
      _settings?.settings.contentRuleWords ?? const AiContentRuleWords();

  Map<String, AiRunState> get runStates => Map.unmodifiable(_runStates);

  AiRunState? get activeRunState =>
      _latestRunId == null ? null : _runStates[_latestRunId];

  void recordRunEvent(AiRunEvent event) {
    if (event case AiRunStarted(:final descriptor)) {
      _latestRunId = descriptor.runId;
      _runStates[descriptor.runId] = AiRunState.initial(descriptor);
      while (_runStates.length > 20) {
        _runStates.remove(_runStates.keys.first);
      }
    }
    final current = _runStates[event.runId];
    if (current == null) return;
    final next = current.apply(event);
    _runStates[event.runId] = next;
    if (event is AiRunStarted || next.isTerminal) onChanged?.call();
  }

  Future<T> executeWorkflow<T>({
    required AiRunDescriptor descriptor,
    required AiRunBudget budget,
    required CancelToken cancelToken,
    required Future<T> Function(AiRunExecution execution) body,
    AiRunCheckpointWriter? checkpointWriter,
  }) async {
    late T result;
    var hasResult = false;
    Object? failure;
    StackTrace? failureStack;
    await for (final event in const AiRunOrchestrator().run(
      descriptor: descriptor,
      budget: budget,
      cancelToken: cancelToken,
      checkpointWriter: checkpointWriter,
      body: (execution) async {
        result = await body(execution);
        hasResult = true;
      },
    )) {
      recordRunEvent(event);
      switch (event) {
        case AiRunFailed():
          failure = event.error;
          failureStack = event.stackTrace;
        case AiRunCancelled():
          failure = AiProviderException('已取消');
          failureStack = StackTrace.current;
        default:
          break;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
    if (!hasResult) throw StateError('AI workflow ended without a result');
    return result;
  }

  Future<AiBookMindMap?> generateMindMap({
    required String contentHash,
    required String? workKey,
    required String publicationTitle,
    required String? publicationAuthor,
    required String scopeLabel,
    required String userInstruction,
    required List<AiBookSectionSlice> sections,
    required AiBookMindMap? existingMindMap,
    String? progressLabel,
    String emptyScopeMessage = '所选范围没有可用于生成思维导图的正文',
  }) async {
    if (_mindMapGeneration != null) {
      _mindMapError = '已有思维导图正在生成，请稍后再试';
      onChanged?.call();
      return null;
    }
    final future = _runMindMap(
      contentHash: contentHash,
      workKey: workKey,
      publicationTitle: publicationTitle,
      publicationAuthor: publicationAuthor,
      scopeLabel: scopeLabel,
      userInstruction: userInstruction,
      sections: sections,
      existingMindMap: existingMindMap,
      progressLabel: progressLabel,
      emptyScopeMessage: emptyScopeMessage,
    );
    _mindMapGeneration = future;
    try {
      return await future;
    } finally {
      if (identical(_mindMapGeneration, future)) {
        _mindMapGeneration = null;
        _mindMapCancel = null;
        onChanged?.call();
      }
    }
  }

  Future<AiBookMindMap?> _runMindMap({
    required String contentHash,
    required String? workKey,
    required String publicationTitle,
    required String? publicationAuthor,
    required String scopeLabel,
    required String userInstruction,
    required List<AiBookSectionSlice> sections,
    required AiBookMindMap? existingMindMap,
    String? progressLabel,
    required String emptyScopeMessage,
  }) async {
    final service = _mindMap;
    if (service == null || !service.isAvailable()) {
      _mindMapError = 'AI 未启用或未配置';
      onChanged?.call();
      return null;
    }
    if (sections.isEmpty) {
      _mindMapError = emptyScopeMessage;
      onChanged?.call();
      return null;
    }
    _mindMapError = null;
    _mindMapProgress = progressLabel ?? '正在生成思维导图';
    final cancel = CancelToken();
    _mindMapCancel = cancel;
    onChanged?.call();
    try {
      final result = await executeWorkflow<AiBookMindMap>(
        descriptor: AiRunDescriptor(
          runId: AiRunIds.next(),
          task: AiRunTask.bookMindMap,
          scope: AiRunScope(
            contentHash: contentHash,
            workKey: workKey,
            label: scopeLabel,
          ),
        ),
        budget: const AiRunBudget(
          maxModelCalls: 1,
          maxElapsed: Duration(minutes: 10),
        ),
        cancelToken: cancel,
        body: (execution) => service.generate(
          contentHash: contentHash,
          workKey: workKey,
          bookTitle: publicationTitle,
          bookAuthor: publicationAuthor,
          scopeLabel: scopeLabel,
          userInstruction: userInstruction,
          sections: sections,
          existingMindMap: existingMindMap,
          cancelToken: execution.cancelToken,
          onModelStarted: execution.modelStarted,
          onUsage: ({inputTokens, outputTokens}) => execution.reportTokens(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          ),
        ),
      );
      _mindMapProgress = null;
      _mindMapError = null;
      onChanged?.call();
      return result;
    } on AiProviderException catch (error) {
      _mindMapProgress = null;
      AiLog.d('mind map failed: ${error.message}');
      if (!cancel.isCancelled) {
        _mindMapError = aiUserErrorMessage(
          error,
          operation: AiUserOperation.mindMap,
        );
      }
      onChanged?.call();
      return null;
    } catch (error, stackTrace) {
      _mindMapProgress = null;
      AiLog.d('mind map failed: $error\n$stackTrace');
      if (!cancel.isCancelled) {
        _mindMapError = '生成思维导图失败，请稍后重试';
      }
      onChanged?.call();
      return null;
    }
  }

  void cancelMindMapGeneration() {
    if (_mindMapGeneration == null) return;
    _mindMapError = '已停止';
    _mindMapCancel?.cancel();
    onChanged?.call();
  }

  void dispose() {
    _mindMapCancel?.cancel();
    mindMapConversation.dispose();
    conversation.dispose();
  }
}

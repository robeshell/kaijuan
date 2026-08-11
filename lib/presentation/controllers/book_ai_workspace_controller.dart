import '../../ai/ai_agent_runtime.dart';
import '../../ai/ai_book_mind_map_service.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_chat_retrieve.dart';
import '../../ai/ai_graph_service.dart';
import '../../ai/ai_language_service.dart';
import '../../ai/ai_log.dart';
import '../../ai/ai_mind_map.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_outline.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_run_orchestrator.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_translation.dart';
import '../../ai/ai_user_error.dart';
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
    this.agentRuntimeFactory = createLegacyAiAgentRuntime,
    this.onChanged,
  }) : conversation = BookAiConversationController(saveChatSession) {
    mindMapConversation = BookAiMindMapController(conversation);
  }

  final AiAgentRuntimeFactory agentRuntimeFactory;
  final void Function()? onChanged;
  final BookAiConversationController conversation;
  late final BookAiMindMapController mindMapConversation;

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
    _agentRuntime = settings == null
        ? null
        : agentRuntimeFactory(
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

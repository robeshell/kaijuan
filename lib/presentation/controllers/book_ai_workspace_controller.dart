import '../../ai/ai_agent_runtime.dart';
import '../../ai/ai_book_mind_map_service.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_graph_service.dart';
import '../../ai/ai_language_service.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_outline.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_run_orchestrator.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_translation.dart';
import '../../ai/legacy_ai_agent_runtime.dart';
import 'ai_settings_controller.dart';

/// AI services and runtime state for one open book workspace.
///
/// This controller deliberately has no reading-engine callbacks, database, or
/// Widget state. [BookReaderController] remains a compatibility facade while
/// chat UI and deterministic workflows migrate to this boundary.
class BookAiWorkspaceController {
  BookAiWorkspaceController({
    this.agentRuntimeFactory = createLegacyAiAgentRuntime,
    this.onChanged,
  });

  final AiAgentRuntimeFactory agentRuntimeFactory;
  final void Function()? onChanged;

  AiSettingsController? _settings;
  AiLanguageService? _language;
  AiAgentRuntime? _agentRuntime;
  AiBookOutlineService? _outline;
  AiBookMindMapService? _mindMap;
  AiBookGraphService? _graph;

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
}

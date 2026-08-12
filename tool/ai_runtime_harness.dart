import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kaijuan/ai/adapters/genkit_openai_model_adapter.dart';
import 'package:kaijuan/ai/ai_agent_runtime.dart';
import 'package:kaijuan/ai/ai_book_mind_map_service.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_chat_tools.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_model_adapter_factory.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_product_action_controller.dart';
import 'package:kaijuan/ai/ai_product_action_protocol.dart';
import 'package:kaijuan/ai/ai_workflow_contract.dart';
import 'package:kaijuan/ai/ai_workflow_executor.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_settings.dart';
import 'package:kaijuan/ai/legacy_ai_agent_runtime.dart';

/// Headless acceptance harness for the App-owned conversational Runtime and
/// deterministic mind-map Workflow.
///
/// Default (credential-free, deterministic):
///   flutter test tool/ai_runtime_harness.dart --reporter expanded
///
/// Explicit live BYOK mode:
///   AI_HARNESS_MODE=live \
///   AI_HARNESS_PROVIDER=deepseek \
///   AI_HARNESS_BASE_URL=https://api.deepseek.com/v1 \
///   AI_HARNESS_MODEL=deepseek-chat \
///   AI_HARNESS_API_KEY=... \
///   flutter test tool/ai_runtime_harness.dart --reporter expanded
///
/// The report never includes credentials, prompts, book text or raw model
/// responses. Live output records only terminal states and aggregate counts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'AI runtime harness',
    _executeHarness,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _executeHarness() async {
  // Flutter's test binding installs a 400-only HttpOverrides by default.
  // This executable is itself an explicit network harness, so restore the
  // real client before starting the loopback server or a live BYOK request.
  HttpOverrides.global = null;
  final environment = Platform.environment;
  final live = environment['AI_HARNESS_MODE']?.trim().toLowerCase() == 'live';
  _LocalHarnessServer? local;
  try {
    final _HarnessConfig config;
    if (live) {
      config = _HarnessConfig.fromEnvironment(environment);
    } else {
      local = await _LocalHarnessServer.start();
      config = _HarnessConfig.local(local);
    }
    final report = await _runHarness(config, verifyDeterministic: !live);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } finally {
    await local?.close();
  }
}

Future<Map<String, Object?>> _runHarness(
  _HarnessConfig config, {
  required bool verifyDeterministic,
}) async {
  final scenarios = <String, Map<String, Object?>>{};
  scenarios['bookTool'] = await _runBookToolScenario(config);
  scenarios['productAction'] = await _runProductActionScenario(config);
  scenarios['productActionControlPlane'] =
      await _runProductActionControlPlaneScenario();
  scenarios['mindMapWorkflow'] = await _runMindMapScenario(config);
  scenarios['continuation'] = await _runContinuationScenario(
    config,
    strict: verifyDeterministic,
  );
  scenarios['transportCancellation'] = await _runCancellationScenario(config);
  final failed = scenarios.entries
      .where((entry) => entry.value['passed'] != true)
      .map((entry) => entry.key)
      .toList(growable: false);
  if (failed.isNotEmpty) {
    throw StateError('AI runtime harness failed: ${failed.join(', ')}');
  }
  return {
    'version': 1,
    'mode': config.live ? 'live' : 'local',
    'provider': config.provider.storageValue,
    'model': config.model,
    'passed': true,
    'scenarios': scenarios,
  };
}

Future<Map<String, Object?>> _runProductActionControlPlaneScenario() async {
  final now = DateTime.utc(2026, 8, 12);
  final journal = MemoryAiActionJournalStore();
  final controller = AiProductActionController(
    registry: AiProductActionRegistry([
      const AiProductActionDefinition(
        actionKind: 'harness_workflow',
        definitionVersion: 1,
        proposalSchemaVersion: 1,
        commandSchemaVersion: 1,
        workflowVersion: 1,
        riskClass: AiActionRiskClass.reversible,
        supportedSources: {AiActionProposalSource.explicitUi},
      ),
    ]),
    journal: journal,
    now: () => now,
    idGenerator: () => 'harness-command',
  );
  final proposal = AiActionProposal(
    protocolVersion: 1,
    proposalId: 'harness-proposal',
    parentRunId: null,
    conversationId: 'harness',
    turnId: 'turn',
    actionKind: 'harness_workflow',
    definitionVersion: 1,
    proposalSchemaVersion: 1,
    source: AiActionProposalSource.explicitUi,
    sourceSubmissionId: 'ui',
    originalUserText: 'harness',
    requestedArguments: const {},
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
  );
  await controller.propose(proposal);
  final adapter = _HarnessWorkflowAdapter();
  final executor = AiProductWorkflowExecutor(
    actions: controller,
    adapters: AiWorkflowAdapterRegistry([adapter]),
    environment: AiWorkflowEnvironment(
      capabilities: const AiCapabilitySet({}),
      checkpoints: MemoryAiWorkflowCheckpointStore(),
      now: () => now,
    ),
  );
  final completed = await executor.execute(proposal.proposalId);
  final passed =
      completed.status == AiActionJournalStatus.succeeded &&
      completed.receipt?.artifactRefs.contains('harness-artifact') == true &&
      adapter.started == 1;
  return {
    'passed': passed,
    'terminal': completed.status.name,
    'artifactRefs': completed.receipt?.artifactRefs.length ?? 0,
  };
}

class _HarnessWorkflowAdapter implements AiWorkflowAdapter {
  var started = 0;

  @override
  String get actionKind => 'harness_workflow';

  @override
  Future<AiWorkflowPreflightResult> preflight(
    AiAuthorizedCommand command,
    AiWorkflowEnvironment environment,
  ) async => const AiWorkflowPreflightResult.accepted();

  @override
  Stream<AiWorkflowEvent> start(
    AiAuthorizedCommand command,
    AiWorkflowRunContext context,
  ) async* {
    started++;
    yield AiWorkflowArtifactReady(
      workflowRunId: context.workflowRunId,
      sequence: 1,
      attempt: context.attempt,
      artifactRef: 'harness-artifact',
    );
    yield AiWorkflowSucceeded(
      workflowRunId: context.workflowRunId,
      sequence: 2,
      attempt: context.attempt,
      artifactRefs: const [],
    );
  }

  @override
  Stream<AiWorkflowEvent> recover(AiWorkflowRecoveryRequest request) =>
      const Stream.empty();

  @override
  Future<void> requestCancel(String workflowRunId, String reason) async {}

  @override
  Future<AiWorkflowInspection> inspect(String workflowRunId) async =>
      AiWorkflowInspection(workflowRunId: workflowRunId, active: false);
}

Future<Map<String, Object?>> _runBookToolScenario(_HarnessConfig config) async {
  final host = _HarnessToolHost();
  final events = await _runTurn(
    config,
    userText: '请先调用 search_book 查找张居正，再根据结果用中文回答他是谁。',
    tools: host,
  );
  final completed = events.whereType<AiRunCompleted>().lastOrNull;
  final passed =
      completed != null &&
      events.whereType<AiRunToolStarted>().isNotEmpty &&
      events.whereType<AiRunToolCompleted>().isNotEmpty &&
      host.queries.isNotEmpty;
  return {
    'passed': passed,
    'terminal': _terminalName(events),
    'toolRounds': events.whereType<AiRunToolCompleted>().length,
    'answerChars': completed?.text.length ?? 0,
  };
}

Future<Map<String, Object?>> _runProductActionScenario(
  _HarnessConfig config,
) async {
  final events = await _runTurn(
    config,
    userText: '请为当前章生成思维导图。',
    tools: _HarnessToolHost(),
    productContext: const AiChatProductContext(),
  );
  final actions = events.whereType<AiRunProductActionRequested>().toList();
  final passed =
      actions.length == 1 &&
      actions.single.request is AiCreateBookMindMapAction &&
      (actions.single.request as AiCreateBookMindMapAction).scope ==
          AiBookMindMapActionScope.currentChapter;
  return {
    'passed': passed,
    'terminal': _terminalName(events),
    'action': passed ? 'createBookMindMap' : 'none',
  };
}

Future<Map<String, Object?>> _runMindMapScenario(_HarnessConfig config) async {
  final settings = AiSettings(
    enabled: true,
    providerKind: config.provider,
    baseUrl: config.baseUrl,
    model: config.model,
  );
  final map =
      await AiBookMindMapService(
        isAvailable: () => true,
        openModelAdapter: () => config.openAdapter(),
        settings: () => settings,
      ).generate(
        contentHash: 'harness-book',
        workKey: null,
        bookTitle: '运行时测试书',
        scopeLabel: '测试章节',
        userInstruction: '整理问题、机制与结论。',
        sections: const [
          AiBookSectionSlice(
            index: 1,
            label: '问题与机制',
            text: '新增道路会诱发更多汽车出行，拥堵会在短期改善后再次出现。',
          ),
          AiBookSectionSlice(
            index: 2,
            label: '方案与边界',
            text: '公共交通、停车管理和拥堵定价需要配合，并照顾低收入通勤者。',
          ),
        ],
      );
  final passed =
      map.nodes.length >= 3 &&
      map.nodes.any((node) => node.parentId == map.root.nodeId) &&
      map.organizingPrinciple.isNotEmpty;
  return {
    'passed': passed,
    'nodes': map.nodes.length,
    'contentKind': map.contentKind.name,
    'evidence': map.nodes.fold<int>(
      0,
      (total, node) => total + node.evidence.length,
    ),
  };
}

Future<Map<String, Object?>> _runContinuationScenario(
  _HarnessConfig config, {
  required bool strict,
}) async {
  final events = await _runTurn(
    config,
    userText: '续写测试：请用中文分两句说明供给扩张与需求管理的关系。',
    tools: _HarnessToolHost(),
  );
  final completed = events.whereType<AiRunCompleted>().lastOrNull;
  final continuations = events.whereType<AiRunContinuationStarted>().length;
  final passed = completed != null && (!strict || continuations > 0);
  return {
    'passed': passed,
    'terminal': _terminalName(events),
    'continuations': continuations,
    'answerChars': completed?.text.length ?? 0,
    if (!strict && continuations == 0)
      'note': 'live model completed without transport truncation',
  };
}

Future<Map<String, Object?>> _runCancellationScenario(
  _HarnessConfig config,
) async {
  final cancel = CancelToken();
  final events = <AiRunEvent>[];
  final done = Completer<void>();
  final subscription = _runtime(config, cancellationProbe: true)
      .stream(
        _turn(
          userText: '取消测试：请生成一篇很长的中文分析。',
          tools: _HarnessToolHost(),
          cancelToken: cancel,
        ),
      )
      .listen(
        events.add,
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
  try {
    final waitForRequest = config.waitForCancellationRequest;
    if (waitForRequest != null) {
      await waitForRequest().timeout(const Duration(seconds: 2));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    config.armCancellationTransportProbe?.call();
    cancel.cancel();
    await done.future.timeout(const Duration(seconds: 3));
  } finally {
    await subscription.cancel();
  }
  var transportClosed = config.live;
  final waitForTransportClose = config.waitForCancellationTransportClose;
  if (waitForTransportClose != null) {
    await waitForTransportClose().timeout(const Duration(seconds: 3));
    transportClosed = true;
  }
  final passed =
      events.whereType<AiRunCancelled>().isNotEmpty &&
      events.whereType<AiRunCompleted>().isEmpty &&
      transportClosed;
  return {
    'passed': passed,
    'terminal': _terminalName(events),
    'cancelledEvents': events.whereType<AiRunCancelled>().length,
    'transportClosed': transportClosed,
  };
}

Future<List<AiRunEvent>> _runTurn(
  _HarnessConfig config, {
  required String userText,
  required AiChatToolHost tools,
  AiChatProductContext productContext = const AiChatProductContext(),
}) => _runtime(config)
    .stream(
      _turn(userText: userText, tools: tools, productContext: productContext),
    )
    .toList();

LegacyAiAgentRuntime _runtime(
  _HarnessConfig config, {
  bool cancellationProbe = false,
}) => LegacyAiAgentRuntime(
  isAvailable: () => true,
  openModelAdapter: ({reasoningEnabled}) =>
      config.openAdapter(cancellationProbe: cancellationProbe),
);

AiAgentTurn _turn({
  required String userText,
  required AiChatToolHost tools,
  AiChatProductContext productContext = const AiChatProductContext(),
  CancelToken? cancelToken,
}) => AiAgentTurn(
  run: AiRunDescriptor(
    runId: AiRunIds.next(),
    task: AiRunTask.bookChat,
    scope: const AiRunScope(contentHash: 'harness-book'),
  ),
  userText: userText,
  history: const [],
  context: const AiChatContextBundle(
    chapterTitle: '测试章节',
    chapterText: '张居正推行考成法。道路扩张需要与需求管理配合。',
    tocOutline: ['测试章节'],
    chapterSectionIndex: 1,
  ),
  bookTitle: '运行时测试书',
  tools: tools,
  productContext: productContext,
  cancelToken: cancelToken,
);

String _terminalName(List<AiRunEvent> events) {
  if (events.whereType<AiRunCompleted>().isNotEmpty) return 'completed';
  if (events.whereType<AiRunProductActionRequested>().isNotEmpty) {
    return 'productActionRequested';
  }
  if (events.whereType<AiRunCancelled>().isNotEmpty) return 'cancelled';
  if (events.whereType<AiRunFailed>().isNotEmpty) return 'failed';
  return 'none';
}

class _HarnessConfig {
  const _HarnessConfig({
    required this.live,
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.waitForCancellationRequest,
    this.waitForCancellationTransportClose,
    this.armCancellationTransportProbe,
    this.cancellationAdapterOverride,
  });

  factory _HarnessConfig.local(_LocalHarnessServer server) {
    final probe = _TransportCancellationProbe();
    return _HarnessConfig(
      live: false,
      provider: AiProviderKind.custom,
      baseUrl: server.baseUrl,
      apiKey: 'local-harness',
      model: 'local-harness-model',
      waitForCancellationRequest: () => server.cancellationRequestStarted,
      waitForCancellationTransportClose: () => probe.closed,
      armCancellationTransportProbe: probe.arm,
      cancellationAdapterOverride: () => GenkitOpenAiModelAdapter(
        baseUrl: server.baseUrl,
        apiKey: 'local-harness',
        model: 'local-harness-model',
        providerKind: AiProviderKind.custom,
        httpClient: _CancellationTrackingClient(probe),
        maxAttempts: 1,
      ),
    );
  }

  factory _HarnessConfig.fromEnvironment(Map<String, String> environment) {
    final provider = AiProviderKind.fromStorage(
      environment['AI_HARNESS_PROVIDER']?.trim() ?? 'deepseek',
    );
    final baseUrl = environment['AI_HARNESS_BASE_URL']?.trim() ?? '';
    final apiKey = environment['AI_HARNESS_API_KEY']?.trim() ?? '';
    final model = environment['AI_HARNESS_MODEL']?.trim() ?? '';
    if (baseUrl.isEmpty || model.isEmpty) {
      throw StateError('AI_HARNESS_BASE_URL and AI_HARNESS_MODEL are required');
    }
    if (!Uri.parse(baseUrl).isScheme('https')) {
      throw StateError('Live AI harness endpoints must use HTTPS');
    }
    return _HarnessConfig(
      live: true,
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
  }

  final bool live;
  final AiProviderKind provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final Future<void> Function()? waitForCancellationRequest;
  final Future<void> Function()? waitForCancellationTransportClose;
  final void Function()? armCancellationTransportProbe;
  final AiModelAdapter Function()? cancellationAdapterOverride;

  AiModelAdapter openAdapter({bool cancellationProbe = false}) {
    final override = cancellationAdapterOverride;
    if (cancellationProbe && override != null) return override();
    final adapter = const DefaultAiModelAdapterFactory().create(
      providerKind: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      reasoningEnabled: false,
    );
    if (adapter == null) throw StateError('AI harness adapter is unavailable');
    return adapter;
  }
}

class _HarnessToolHost implements AiChatToolHost {
  final queries = <String>[];

  @override
  Future<String> toolGetToc() async => '§1 测试章节';

  @override
  Future<String> toolGetCurrentChapter({int maxChars = 10000}) async =>
      '张居正推行考成法。道路扩张需要与需求管理配合。';

  @override
  Future<String> toolGetChapter(
    int sectionIndex1Based, {
    int maxChars = 10000,
  }) async => '张居正推行考成法。';

  @override
  Future<String> toolSearchBook(String query, {int maxChars = 12000}) async {
    queries.add(query);
    return '书内命中：张居正推行考成法。';
  }

  @override
  Future<String> toolSampleBook({int maxChars = 36000}) async =>
      '道路供给扩张需要与需求管理共同实施。';
}

class _TransportCancellationProbe {
  final _closed = Completer<void>();
  var _armed = false;

  Future<void> get closed => _closed.future;

  void arm() => _armed = true;

  void recordClose() {
    if (_armed && !_closed.isCompleted) _closed.complete();
  }
}

class _CancellationTrackingClient extends http.BaseClient {
  _CancellationTrackingClient(this._probe) : _delegate = http.Client();

  final _TransportCancellationProbe _probe;
  final http.Client _delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _delegate.send(request);

  @override
  void close() {
    _probe.recordClose();
    _delegate.close();
  }
}

class _LocalHarnessServer {
  _LocalHarnessServer._(this._server);

  final HttpServer _server;
  final _cancellationRequestStarted = Completer<void>();

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/v1';
  Future<void> get cancellationRequestStarted =>
      _cancellationRequestStarted.future;

  static Future<_LocalHarnessServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final harness = _LocalHarnessServer._(server);
    server.listen(harness._handle);
    return harness;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final encoded = jsonEncode(body);
    if (encoded.contains('取消测试')) {
      if (!_cancellationRequestStarted.isCompleted) {
        _cancellationRequestStarted.complete();
      }
      await Future<void>.delayed(const Duration(seconds: 10));
      try {
        await _sendText(request, '不应完成');
      } on Object {
        // The tracked client is expected to close before this delayed reply.
      }
      return;
    }
    if (body['stream'] != true) {
      await _sendJson(request, _mindMapJson);
      return;
    }
    if (encoded.contains('create_book_mind_map') &&
        encoded.contains('请为当前章生成思维导图')) {
      await _sendTool(
        request,
        name: 'create_book_mind_map',
        arguments: '{"scope":"currentChapter","instruction":"请为当前章生成思维导图。"}',
      );
      return;
    }
    if (encoded.contains('续写测试')) {
      final continuation = encoded.contains('Continue the previous answer');
      await _sendText(
        request,
        continuation ? '也必须配合需求管理。' : '供给扩张只能暂时缓解拥堵，',
        finishReason: continuation ? 'stop' : 'length',
      );
      return;
    }
    if (encoded.contains('"role":"tool"')) {
      await _sendText(request, '张居正是万历初年的内阁首辅。');
      return;
    }
    await _sendTool(request, name: 'search_book', arguments: '{"query":"张居正"}');
  }

  Future<void> _sendText(
    HttpRequest request,
    String text, {
    String finishReason = 'stop',
  }) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.write('''
data: {"id":"harness","object":"chat.completion.chunk","created":1,"model":"local-harness-model","choices":[{"index":0,"delta":{"role":"assistant","content":${jsonEncode(text)}},"finish_reason":null}]}

data: {"id":"harness","object":"chat.completion.chunk","created":1,"model":"local-harness-model","choices":[{"index":0,"delta":{},"finish_reason":"$finishReason"}]}

data: [DONE]

''');
    await request.response.close();
  }

  Future<void> _sendTool(
    HttpRequest request, {
    required String name,
    required String arguments,
  }) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.write('''
data: {"id":"harness-tool","object":"chat.completion.chunk","created":1,"model":"local-harness-model","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_harness","type":"function","function":{"name":"$name","arguments":${jsonEncode(arguments)}}}]},"finish_reason":null}]}

data: {"id":"harness-tool","object":"chat.completion.chunk","created":1,"model":"local-harness-model","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

''');
    await request.response.close();
  }

  Future<void> _sendJson(
    HttpRequest request,
    Map<String, Object?> value,
  ) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'id': 'harness-json',
        'object': 'chat.completion',
        'created': 1,
        'model': 'local-harness-model',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': jsonEncode(value)},
            'finish_reason': 'stop',
          },
        ],
      }),
    );
    await request.response.close();
  }
}

const _mindMapJson = <String, Object?>{
  'contentKind': 'argumentative',
  'organizingPrinciple': '围绕交通治理的因果与对策',
  'nodes': [
    {
      'tempId': 'root',
      'parentTempId': null,
      'order': 0,
      'title': '交通治理',
      'summary': '从诱导需求解释拥堵，并组合供给与需求管理。',
      'evidence': <Object?>[],
    },
    {
      'tempId': 'cause',
      'parentTempId': 'root',
      'order': 0,
      'title': '诱导需求',
      'summary': '道路扩张会吸引新增汽车出行，使拥堵再次出现。',
      'evidence': [
        {'sectionId': 1, 'quote': '新增道路会诱发更多汽车出行'},
      ],
    },
    {
      'tempId': 'solution',
      'parentTempId': 'root',
      'order': 1,
      'title': '组合治理',
      'summary': '公共交通、停车管理和定价需要协同实施。',
      'evidence': [
        {'sectionId': 2, 'quote': '公共交通、停车管理和拥堵定价需要配合'},
      ],
    },
  ],
};

extension<T> on Iterable<T> {
  T? get lastOrNull => this.isEmpty ? null : last;
}

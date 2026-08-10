/// Built-in LLM service presets shown in AI settings.
///
/// Anthropic uses Messages API; every other preset uses OpenAI Compatible.
enum AiProviderKind {
  openai,
  anthropic,
  deepseek,

  /// xAI Grok — OpenAI-compatible Chat Completions at api.x.ai.
  xai,

  /// User-supplied OpenAI Compatible base URL.
  custom,

  /// Local Ollama — OpenAI-compatible endpoint on localhost, no API key.
  ollama;

  String get storageValue => name;

  static AiProviderKind fromStorage(String? value) {
    for (final kind in AiProviderKind.values) {
      if (kind.storageValue == value) return kind;
    }
    return AiProviderKind.openai;
  }

  /// Local backends run on the user's machine and need no API key.
  bool get isLocalBackend => this == AiProviderKind.ollama;

  String get displayName => switch (this) {
    AiProviderKind.openai => 'OpenAI',
    AiProviderKind.anthropic => 'Anthropic',
    AiProviderKind.deepseek => 'DeepSeek',
    AiProviderKind.xai => 'Grok',
    AiProviderKind.custom => '自定义',
    AiProviderKind.ollama => 'Ollama（本地）',
  };

  /// Default public base URL for the preset. Empty for [custom].
  String get defaultBaseUrl => switch (this) {
    AiProviderKind.openai => 'https://api.openai.com/v1',
    AiProviderKind.anthropic => 'https://api.anthropic.com',
    AiProviderKind.deepseek => 'https://api.deepseek.com/v1',
    AiProviderKind.xai => 'https://api.x.ai/v1',
    AiProviderKind.custom => '',
    AiProviderKind.ollama => 'http://localhost:11434/v1',
  };

  /// Suggested model id when the user picks this preset.
  ///
  /// Prefer current cost-efficient chat IDs for reading assist (dict / translate).
  /// Users can still override via settings or 「获取模型」.
  String get defaultModel => switch (this) {
    // OpenAI API: GPT-5.4 mini — strong small model for everyday tasks.
    AiProviderKind.openai => 'gpt-5.4-mini',
    // Current balanced Sonnet generation; the Models API remains authoritative.
    AiProviderKind.anthropic => 'claude-sonnet-5',
    // DeepSeek Chat Completions: V4 Flash (auto-tracks latest Flash revision).
    AiProviderKind.deepseek => 'deepseek-v4-flash',
    // xAI Grok flagship chat / coding model.
    AiProviderKind.xai => 'grok-4.5',
    // Custom: leave empty; fill via 获取模型 or manual entry.
    AiProviderKind.custom => '',
    // Local models depend on what the user has pulled; resolve via 获取模型.
    AiProviderKind.ollama => '',
  };

  /// Product-level reasoning capability for the selected provider/model.
  ///
  /// This deliberately describes behavior rather than exposing vendor request
  /// fields to controllers or widgets.
  AiReasoningCapabilities reasoningCapabilities(String model) => switch (this) {
    AiProviderKind.openai => AiReasoningCapabilities(
      supported: _isOpenAiReasoningModel(model),
      visibleKind: AiReasoningContentKind.summary,
      disabledLabel: '关闭或使用最低推理强度',
      enabledLabel: '使用高推理强度',
    ),
    AiProviderKind.anthropic => const AiReasoningCapabilities(
      supported: true,
      visibleKind: AiReasoningContentKind.summary,
      disabledLabel: '关闭扩展思考',
      enabledLabel: '使用自适应思考',
    ),
    AiProviderKind.deepseek => const AiReasoningCapabilities(
      supported: true,
      visibleKind: AiReasoningContentKind.process,
      disabledLabel: '关闭思考模式',
      enabledLabel: '开启思考模式',
    ),
    AiProviderKind.xai => const AiReasoningCapabilities(
      supported: true,
      visibleKind: AiReasoningContentKind.summary,
      disabledLabel: '使用低推理强度',
      enabledLabel: '使用高推理强度',
    ),
    AiProviderKind.custom => const AiReasoningCapabilities(
      supported: true,
      visibleKind: AiReasoningContentKind.process,
      disabledLabel: '不发送兼容扩展字段',
      enabledLabel: '尝试使用高推理强度',
    ),
    AiProviderKind.ollama => const AiReasoningCapabilities(
      supported: true,
      visibleKind: AiReasoningContentKind.process,
      disabledLabel: '关闭或使用模型最低强度',
      enabledLabel: '使用高推理强度',
    ),
  };

  static bool _isOpenAiReasoningModel(String value) {
    final model = value.trim().toLowerCase();
    return RegExp(
      r'^(gpt-5(?:[.-]|$)|o1(?:[.-]|$)|o3(?:[.-]|$)|o4(?:[.-]|$))',
    ).hasMatch(model);
  }
}

/// What a provider actually exposes for optional display.
///
/// `summary` is not a hidden chain of thought. It is a provider-authored,
/// user-visible synopsis and must be labelled accordingly.
enum AiReasoningContentKind {
  process,
  summary;

  String get storageValue => name;

  static AiReasoningContentKind fromStorage(Object? value) =>
      AiReasoningContentKind.values.firstWhere(
        (kind) => kind.storageValue == value,
        orElse: () => AiReasoningContentKind.process,
      );
}

class AiReasoningCapabilities {
  const AiReasoningCapabilities({
    required this.supported,
    required this.visibleKind,
    required this.disabledLabel,
    required this.enabledLabel,
  });

  final bool supported;
  final AiReasoningContentKind visibleKind;
  final String disabledLabel;
  final String enabledLabel;
}

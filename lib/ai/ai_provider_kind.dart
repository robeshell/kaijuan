/// Wire format for chat / models HTTP APIs.
enum AiApiProtocol {
  /// OpenAI Chat Completions + GET /models (DeepSeek, xAI, many proxies).
  openai,

  /// Anthropic Messages API + GET /v1/models (`x-api-key`).
  anthropic;

  String get storageValue => name;

  static AiApiProtocol fromStorage(String? value) {
    for (final protocol in AiApiProtocol.values) {
      if (protocol.storageValue == value) return protocol;
    }
    return AiApiProtocol.openai;
  }

  String get displayName => switch (this) {
    AiApiProtocol.openai => 'OpenAI 兼容',
    AiApiProtocol.anthropic => 'Anthropic',
  };

  String get shortHint => switch (this) {
    AiApiProtocol.openai => 'Chat Completions',
    AiApiProtocol.anthropic => 'Messages API',
  };
}

/// Built-in LLM service presets shown in AI settings.
///
/// OpenAI and DeepSeek share the OpenAI-compatible chat/completions wire
/// format. Anthropic uses the Messages API with different headers.
/// [custom] requires the user to pick [AiApiProtocol] separately.
enum AiProviderKind {
  openai,
  anthropic,
  deepseek,
  /// xAI Grok — OpenAI-compatible Chat Completions at api.x.ai.
  xai,
  /// User-supplied base URL; protocol is [AiSettings.customProtocol].
  custom;

  String get storageValue => name;

  static AiProviderKind fromStorage(String? value) {
    for (final kind in AiProviderKind.values) {
      if (kind.storageValue == value) return kind;
    }
    return AiProviderKind.openai;
  }

  String get displayName => switch (this) {
    AiProviderKind.openai => 'OpenAI',
    AiProviderKind.anthropic => 'Anthropic',
    AiProviderKind.deepseek => 'DeepSeek',
    AiProviderKind.xai => 'Grok',
    AiProviderKind.custom => '自定义',
  };

  /// Default public base URL for the preset. Empty for [custom].
  String get defaultBaseUrl => switch (this) {
    AiProviderKind.openai => 'https://api.openai.com/v1',
    AiProviderKind.anthropic => 'https://api.anthropic.com',
    AiProviderKind.deepseek => 'https://api.deepseek.com/v1',
    AiProviderKind.xai => 'https://api.x.ai/v1',
    AiProviderKind.custom => '',
  };

  /// Suggested model id when the user picks this preset.
  ///
  /// Prefer current cost-efficient chat IDs for reading assist (dict / translate).
  /// Users can still override via settings or 「获取模型」.
  String get defaultModel => switch (this) {
    // OpenAI API: GPT-5.4 mini — strong small model for everyday tasks.
    AiProviderKind.openai => 'gpt-5.4-mini',
    // Anthropic API alias for current Sonnet generation.
    AiProviderKind.anthropic => 'claude-sonnet-5',
    // DeepSeek Chat Completions: V4 Flash (auto-tracks latest Flash revision).
    AiProviderKind.deepseek => 'deepseek-v4-flash',
    // xAI Grok flagship chat / coding model.
    AiProviderKind.xai => 'grok-4.5',
    // Custom: leave empty; fill via 获取模型 or manual entry.
    AiProviderKind.custom => '',
  };

  /// Fixed protocol for presets. [custom] is null — use settings field.
  AiApiProtocol? get fixedProtocol => switch (this) {
    AiProviderKind.openai ||
    AiProviderKind.deepseek ||
    AiProviderKind.xai => AiApiProtocol.openai,
    AiProviderKind.anthropic => AiApiProtocol.anthropic,
    AiProviderKind.custom => null,
  };
}

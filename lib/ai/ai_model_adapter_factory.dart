import 'adapters/genkit_anthropic_model_adapter.dart';
import 'adapters/genkit_openai_model_adapter.dart';
import 'ai_model_adapter.dart';
import 'ai_provider_kind.dart';

class DefaultAiModelAdapterFactory implements AiModelAdapterFactory {
  const DefaultAiModelAdapterFactory();

  @override
  AiModelAdapter? create({
    required AiProviderKind providerKind,
    required String baseUrl,
    required String apiKey,
    required String model,
    bool reasoningEnabled = false,
  }) {
    if (baseUrl.trim().isEmpty || model.trim().isEmpty) return null;
    if (providerKind == AiProviderKind.anthropic) {
      if (apiKey.trim().isEmpty) return null;
      return GenkitAnthropicModelAdapter(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        reasoningEnabled: reasoningEnabled,
      );
    }
    return GenkitOpenAiModelAdapter(
      baseUrl: baseUrl,
      apiKey: apiKey.trim().isEmpty ? 'local-byok' : apiKey,
      model: model,
      providerKind: providerKind,
      reasoningEnabled: reasoningEnabled,
    );
  }
}

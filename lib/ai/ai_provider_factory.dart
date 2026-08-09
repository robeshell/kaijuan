import 'ai_provider.dart';
import 'ai_provider_kind.dart';
import 'ai_settings.dart';
import 'anthropic_provider.dart';
import 'openai_compatible_provider.dart';

/// Default transport composition.
///
/// The provider contract deliberately does not import concrete transports;
/// composition belongs here so concrete protocol implementations depend in a
/// single direction on [AiProvider].
class DefaultAiProviderFactory implements AiProviderFactory {
  const DefaultAiProviderFactory();

  @override
  AiProvider? create({required AiSettings settings, required String apiKey}) {
    final key = apiKey.trim();
    // Local backends (Ollama) need no API key; the OpenAI-compatible provider
    // sends an empty Authorization header, which local endpoints ignore.
    if (key.isEmpty && !settings.providerKind.isLocalBackend) return null;
    final baseUrl = settings.resolvedBaseUrl;
    if (baseUrl.isEmpty || !settings.hasValidEndpoint) return null;
    // Model may be empty when only listing models; complete/stream still need
    // a non-empty model set by the caller beforehand.
    final model = settings.resolvedModel;

    return switch (settings.providerKind) {
      AiProviderKind.anthropic => AnthropicAiProvider(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      ),
      _ => OpenAiCompatibleAiProvider(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      ),
    };
  }
}

import 'ai_model_adapter.dart';
import 'ai_models.dart';

/// Graph calls carry long prompts and emit large JSON; the chat default
/// (45s) is too tight for one extraction pass.
const kGraphCallTimeout = Duration(seconds: 120);

List<AiModelMessage> graphModelMessages(List<AiMessage> messages) => [
  for (final message in messages)
    AiModelMessage(
      role: switch (message.role) {
        AiMessageRole.system => AiModelRole.system,
        AiMessageRole.user => AiModelRole.user,
        AiMessageRole.assistant => AiModelRole.assistant,
      },
      text: message.content,
    ),
];

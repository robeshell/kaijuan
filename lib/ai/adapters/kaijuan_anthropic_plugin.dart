// Copyright 2025 Google LLC
// Modifications Copyright 2026 Kaijuan contributors.
// Licensed under the Apache License, Version 2.0. See
// https://www.apache.org/licenses/LICENSE-2.0
//
// Isolated compatibility patch for genkit_anthropic 0.2.11. The upstream
// plugin reads ReasoningPart but drops it while converting model history back
// to Anthropic. Tool use with extended thinking requires the original signed
// thinking block, so this subclass replaces only the model action and keeps
// the upstream SDK, schemas and response converters.

import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as sdk;
import 'package:genkit/plugin.dart';
import 'package:genkit_anthropic/genkit_anthropic.dart';
// The Preview plugin does not yet expose a hook for message conversion.
// Keeping this implementation import inside the adapter package makes the
// workaround removable with one dependency upgrade.
// ignore: implementation_imports
import 'package:genkit_anthropic/src/plugin_impl.dart';

final class KaijuanAnthropicPlugin extends AnthropicPluginImpl {
  KaijuanAnthropicPlugin({
    required super.apiKey,
    required super.baseUrl,
    super.headers,
  });

  @override
  Action? resolve(String actionType, String name) {
    if (actionType != 'model') return null;
    return _createPatchedModel(name);
  }

  Model _createPatchedModel(String modelName) {
    return Model(
      name: 'anthropic/$modelName',
      customOptions: AnthropicOptions.$schema,
      metadata: {'model': commonModelInfo.toJson()},
      fn: (request, context) async {
        final options = request!.config == null
            ? AnthropicOptions()
            : AnthropicOptions.$schema.parse(request.config!);
        final requestClient = options.apiKey == null
            ? client
            : sdk.AnthropicClient.withApiKey(
                options.apiKey!,
                defaultHeaders: headers,
                baseUrl: baseUrl,
              );
        try {
          final createRequest = _buildRequest(request, modelName, options);
          if (context.streamingRequested) {
            final stream = requestClient.messages.createStream(createRequest);
            final accumulator = sdk.MessageStreamAccumulator();
            await for (final event in stream) {
              accumulator.add(event);
              _handleEvent(event, context.sendChunk);
            }
            final message = accumulator.toMessage();
            return ModelResponse(
              finishReason: mapFinishReason(message.stopReason),
              message: _fromAnthropicMessage(message),
              usage: mapUsage(message.usage),
            );
          }
          final message = await requestClient.messages.create(createRequest);
          return ModelResponse(
            finishReason: mapFinishReason(message.stopReason),
            message: _fromAnthropicMessage(message),
            usage: mapUsage(message.usage),
            raw: message.toJson(),
          );
        } catch (error, stackTrace) {
          if (error is GenkitException) rethrow;
          final status = error is sdk.ApiException
              ? StatusCodes.fromHttpStatus(error.statusCode)
              : null;
          throw GenkitException(
            'Anthropic API error: $error',
            status: status,
            details: error is sdk.ApiException ? error.message : '$error',
            underlyingException: error,
            stackTrace: stackTrace,
          );
        } finally {
          if (options.apiKey != null) requestClient.close();
        }
      },
    );
  }

  sdk.MessageCreateRequest _buildRequest(
    ModelRequest request,
    String modelName,
    AnthropicOptions options,
  ) {
    final systemMessage = request.messages
        .where((message) => message.role == Role.system)
        .firstOrNull;
    final messages = request.messages
        .where((message) => message.role != Role.system)
        .map(_toAnthropicMessage)
        .toList();
    final tools =
        request.tools?.map(toAnthropicTool).toList() ?? <sdk.ToolDefinition>[];
    sdk.ToolChoice? toolChoice;
    if (request.output?.schema != null) {
      final schema = Map<String, dynamic>.from(request.output!.schema!);
      schema.putIfAbsent('type', () => 'object');
      const name = 'return_output';
      tools.add(
        sdk.ToolDefinition.custom(
          sdk.Tool(
            name: name,
            description: 'Return the structured output.',
            inputSchema: sdk.InputSchema.fromJson(schema),
          ),
        ),
      );
      toolChoice = sdk.ToolChoice.tool(name);
    }
    if (request.toolChoice != null) {
      toolChoice = switch (request.toolChoice) {
        'auto' => sdk.ToolChoice.auto(),
        'any' => sdk.ToolChoice.any(),
        'none' => sdk.ToolChoice.none(),
        final name => sdk.ToolChoice.tool(name!),
      };
    }
    final thinking = switch (options.thinking?.type ?? '') {
      'disabled' => sdk.ThinkingConfig.disabled(),
      'adaptive' => sdk.ThinkingConfig.adaptive(
        display: sdk.ThinkingDisplayMode.summarized,
      ),
      'enabled' => sdk.ThinkingConfig.enabled(
        budgetTokens: options.thinking?.budgetTokens ?? 1024,
        display: sdk.ThinkingDisplayMode.summarized,
      ),
      _ => null,
    };
    return sdk.MessageCreateRequest(
      model: modelName,
      messages: messages,
      system: systemMessage == null
          ? null
          : convertSystemMessage(systemMessage),
      maxTokens: options.maxTokens ?? 4096,
      temperature: options.temperature,
      topP: options.topP,
      topK: options.topK,
      stopSequences: options.stopSequences,
      tools: tools.isEmpty ? null : tools,
      toolChoice: toolChoice,
      thinking: thinking,
    );
  }

  static sdk.InputMessage _toAnthropicMessage(Message message) {
    final isUser = message.role == Role.user || message.role == Role.tool;
    final blocks = message.content.expand<sdk.InputContentBlock>((part) {
      if (part.isReasoning) {
        final metadata = part.reasoningPart?.metadata;
        final redactedData = metadata?['redactedData'];
        if (redactedData is String && redactedData.isNotEmpty) {
          return [
            sdk.UnknownInputContentBlock(
              raw: {'type': 'redacted_thinking', 'data': redactedData},
            ),
          ];
        }
        final signature = metadata?['signature'];
        if (signature is! String || signature.isEmpty) {
          throw GenkitException(
            'Anthropic thinking block is missing its signature',
            status: StatusCodes.INVALID_ARGUMENT,
          );
        }
        return [
          sdk.UnknownInputContentBlock(
            raw: {
              'type': 'thinking',
              'thinking': part.reasoning,
              'signature': signature,
            },
          ),
        ];
      }
      if (part.isText) return [sdk.InputContentBlock.text(part.text!)];
      if (part.isToolRequest) {
        final call = part.toolRequest!;
        return [
          sdk.InputContentBlock.toolUse(
            id: call.ref ?? '',
            name: call.name,
            input: call.input is Map
                ? (call.input as Map).cast<String, dynamic>()
                : <String, dynamic>{},
          ),
        ];
      }
      if (part.isToolResponse) {
        final result = part.toolResponse!;
        return [
          sdk.InputContentBlock.toolResult(
            toolUseId: result.ref ?? '',
            content: [sdk.ToolResultContent.text(jsonEncode(result.output))],
          ),
        ];
      }
      return const <sdk.InputContentBlock>[];
    }).toList();
    return isUser
        ? sdk.InputMessage.userBlocks(blocks)
        : sdk.InputMessage.assistantBlocks(blocks);
  }

  static Message _fromAnthropicMessage(sdk.Message message) {
    final content = message.content
        .map<Part>(
          (block) => switch (block) {
            sdk.TextBlock(:final text) => TextPart(text: text),
            sdk.ToolUseBlock(:final id, :final name, :final input) =>
              name == 'return_output'
                  ? TextPart(text: jsonEncode(_extractOutput(input)))
                  : ToolRequestPart(
                      toolRequest: ToolRequest(
                        ref: id,
                        name: name,
                        input: input,
                      ),
                    ),
            sdk.ThinkingBlock(:final thinking, :final signature) =>
              ReasoningPart(
                reasoning: thinking,
                metadata: {'signature': signature},
              ),
            sdk.RedactedThinkingBlock(:final data) => ReasoningPart(
              reasoning: '',
              metadata: {'redactedData': data},
            ),
            _ => TextPart(text: ''),
          },
        )
        .where((part) => part is! TextPart || part.text.isNotEmpty)
        .toList();
    return Message(role: Role.model, content: content);
  }

  static Map<String, dynamic> _extractOutput(Map<String, dynamic> input) {
    if (input.keys.length == 1) {
      final output = input['output'] ?? input[r'$output'];
      if (output is Map) return output.cast<String, dynamic>();
    }
    return input;
  }

  static void _handleEvent(
    sdk.MessageStreamEvent event,
    void Function(ModelResponseChunk chunk) sendChunk,
  ) {
    switch (event) {
      case sdk.ContentBlockDeltaEvent(:final index, :final delta):
        switch (delta) {
          case sdk.TextDelta(:final text):
            sendChunk(
              ModelResponseChunk(
                index: index,
                content: [TextPart(text: text)],
              ),
            );
          case sdk.ThinkingDelta(:final thinking):
            sendChunk(
              ModelResponseChunk(
                index: index,
                content: [ReasoningPart(reasoning: thinking)],
              ),
            );
          default:
        }
      case sdk.ErrorEvent(:final message):
        throw GenkitException(
          'Anthropic stream error: $message',
          status: StatusCodes.INTERNAL,
        );
      default:
    }
  }
}

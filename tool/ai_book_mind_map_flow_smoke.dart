import 'dart:convert';
import 'dart:io';

import 'package:kaijuan/ai/ai_book_mind_map_service.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_chat_service.dart';
import 'package:kaijuan/ai/ai_chat_tools.dart';
import 'package:kaijuan/ai/ai_model_adapter_factory.dart';
import 'package:kaijuan/ai/ai_product_action.dart';
import 'package:kaijuan/ai/ai_provider_kind.dart';
import 'package:kaijuan/ai/ai_run.dart';
import 'package:kaijuan/ai/ai_settings.dart';

/// Headless real-provider smoke for the complete book-mind-map path.
///
/// Credentials are accepted only through the process environment and are
/// never printed or persisted. The smoke verifies both the conversational
/// terminal product-tool decision and the structured mind-map Workflow.
Future<void> main() async {
  final environment = Platform.environment;
  final provider = AiProviderKind.fromStorage(
    environment['AI_SMOKE_PROVIDER']?.trim() ?? 'deepseek',
  );
  final apiKey = environment['AI_SMOKE_API_KEY']?.trim() ?? '';
  final baseUrl = environment['AI_SMOKE_BASE_URL']?.trim() ?? '';
  final model = environment['AI_SMOKE_MODEL']?.trim() ?? '';
  if (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty) {
    throw StateError('AI smoke key, endpoint, and model are required');
  }
  final settings = AiSettings(
    enabled: true,
    providerKind: provider,
    baseUrl: baseUrl,
    model: model,
  );
  final factory = const DefaultAiModelAdapterFactory();
  openAdapter() => factory.create(
    providerKind: provider,
    baseUrl: settings.resolvedBaseUrl,
    apiKey: apiKey,
    model: settings.resolvedModel,
    reasoningEnabled: false,
  );

  final chat = AiChatService(
    isAvailable: () => true,
    openModelAdapter: ({reasoningEnabled}) => openAdapter(),
  );
  final chatEvents = await chat
      .streamRun(
        run: AiRunDescriptor(
          runId: AiRunIds.next(),
          task: AiRunTask.bookChat,
          scope: const AiRunScope(contentHash: 'headless-smoke'),
        ),
        userText: '请为当前章生成思维导图',
        history: const [],
        context: const AiChatContextBundle(chapterTitle: '测试章节'),
        bookTitle: '流程测试书',
        tools: const _SmokeToolHost(),
      )
      .toList();
  final productEvents = chatEvents.whereType<AiRunProductActionRequested>();
  if (productEvents.length != 1 ||
      productEvents.single.request is! AiCreateBookMindMapAction) {
    throw StateError('Chat did not request the native mind-map product action');
  }

  final mindMap =
      await AiBookMindMapService(
        isAvailable: () => true,
        openModelAdapter: openAdapter,
        settings: () => settings,
      ).generate(
        contentHash: 'headless-smoke',
        workKey: null,
        bookTitle: '流程测试书',
        scopeLabel: '测试章节',
        userInstruction: '请为当前章生成思维导图',
        sections: const [
          AiBookSectionSlice(
            index: 1,
            label: '问题与背景',
            text: '城市为缓解交通拥堵，长期只增加道路供给，但新增道路很快吸引更多汽车出行，拥堵再次出现。',
          ),
          AiBookSectionSlice(
            index: 2,
            label: '机制与选择',
            text: '作者认为问题来自诱导需求。有效方案应同时改善公共交通、管理停车成本，并让道路价格反映拥堵代价。',
          ),
          AiBookSectionSlice(
            index: 3,
            label: '边界与结论',
            text: '这些政策需要照顾低收入通勤者，并用透明的收入返还降低不公平。结论是供给扩张必须与需求管理配合。',
          ),
        ],
      );
  if (mindMap.nodes.length < 4 ||
      !mindMap.nodes.any((node) => node.parentId == mindMap.root.nodeId)) {
    throw StateError('Structured mind map is unexpectedly incomplete');
  }
  stdout.writeln(
    jsonEncode({
      'provider': provider.storageValue,
      'model': settings.resolvedModel,
      'chatAction': 'createBookMindMap',
      'nodes': mindMap.nodes.length,
      'root': mindMap.root.title,
      'organizingPrinciple': mindMap.organizingPrinciple,
    }),
  );
}

class _SmokeToolHost implements AiChatToolHost {
  const _SmokeToolHost();

  @override
  Future<String> toolGetToc() async => '§1 测试章节';

  @override
  Future<String> toolGetCurrentChapter({int maxChars = 10000}) async =>
      '测试章节正文';

  @override
  Future<String> toolGetChapter(
    int sectionIndex1Based, {
    int maxChars = 10000,
  }) async => '测试章节正文';

  @override
  Future<String> toolSearchBook(String query, {int maxChars = 12000}) async =>
      '无结果';

  @override
  Future<String> toolSampleBook({int maxChars = 36000}) async => '测试章节正文';
}

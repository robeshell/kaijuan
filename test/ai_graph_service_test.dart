import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider.dart';
import 'package:kaijuan/ai/ai_settings.dart';

void main() {
  AiBookGraphService serviceWith(_GraphProvider provider) {
    return AiBookGraphService(
      isAvailable: () => true,
      openProvider: () => provider,
      settings: () => const AiSettings(model: 'graph-test'),
    );
  }

  AiBookSectionSlice slice(int index, String label, String text) {
    return AiBookSectionSlice(index: index, label: label, text: text);
  }

  group('AiBookGraph serialization', () {
    test('JSON round-trip preserves graph, entities, relations and evidence',
        () {
      final source = AiBookGraph(
        contentHash: 'h1',
        generatedAt: DateTime.utc(2026, 8, 5, 12),
        model: 'graph-test',
        includesUnread: false,
        coveredSections: const [1, 2],
        entities: const [
          AiGraphEntity(
            name: '张三',
            type: AiGraphEntityType.person,
            aliases: ['三哥'],
            description: '主角。',
            evidence: [
              AiGraphEvidence(
                sectionIndex: 1,
                quote: '张三进京',
                progressInSection: 0.5,
                spanResolved: true,
              ),
            ],
            chapterFreq: {1: 1},
            firstSection: 1,
            lastSection: 2,
          ),
        ],
        relations: const [
          AiGraphRelation(
            source: '张三',
            target: '李四',
            type: 'meet',
            description: '在城门相遇。',
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '张三与李四相遇'),
            ],
            weight: 1,
          ),
        ],
      );

      final restored = AiBookGraph.fromJson(source.toJson());

      expect(restored, isNotNull);
      expect(restored!.contentHash, 'h1');
      expect(restored.includesUnread, isFalse);
      expect(restored.coveredSections, [1, 2]);
      final entity = restored.entities.single;
      expect(entity.name, '张三');
      expect(entity.type, AiGraphEntityType.person);
      expect(entity.aliases, ['三哥']);
      expect(entity.chapterFreq, {1: 1});
      expect(entity.evidence.single.spanResolved, isTrue);
      expect(entity.evidence.single.progressInSection, 0.5);
      expect(restored.relations.single.mergeKey, contains('meet'));
    });

    test('older generator version cache is rejected', () {
      final source = AiBookGraph(
        contentHash: 'h1',
        entities: const [],
      );
      final old = {
        ...source.toJson(),
        'version': AiBookGraph.currentVersion - 1,
      };
      expect(AiBookGraph.fromJson(old), isNull);
    });
  });

  group('AiBookGraphService extraction', () {
    test('extracts entities and relations with quote back-fill', () async {
      final body = '张三与李四在城门口相见，互致问候。';
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":["张三爷"],
              "description":"主人公。",
              "evidence":[{"section":1,"quote":"张三与李四在城门口相见"}]}],
             "relations":[{"source":"张三","target":"李四","type":"meet",
              "description":"在城门相见。",
              "evidence":[{"section":1,"quote":"张三与李四在城门口相见"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', body)],
        includesUnread: true,
      );

      final entity = graph.entities.single;
      expect(entity.name, '张三');
      expect(entity.aliases, ['张三爷']);
      expect(entity.evidence.single.spanResolved, isTrue);
      expect(entity.evidence.single.progressInSection, isNotNull);
      expect(entity.firstSection, 1);
      expect(entity.lastSection, 1);
      final relation = graph.relations.single;
      expect(relation.source, '张三');
      expect(relation.target, '李四');
      expect(relation.type, 'meet');
      expect(graph.coveredSections, [1]);
      expect(graph.model, 'graph-test');
    });

    test('unresolvable quote degrades to section-level evidence', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"主角。",
              "evidence":[{"section":1,"quote":"这段引文不在原文中"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '完全不相关的正文内容。')],
        includesUnread: true,
      );

      final evidence = graph.entities.single.evidence.single;
      expect(evidence.spanResolved, isFalse);
      expect(evidence.progressInSection, isNull);
      expect(evidence.sectionIndex, 1);
    });

    test('sequential merge folds aliases into one canonical entity', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"主角。",
              "evidence":[{"section":1,"quote":"张三出场"}]}],
             "relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"三哥","type":"person","aliases":["张三"],
              "description":"",
              "evidence":[{"section":2,"quote":"三哥离开"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一回', '张三出场。'),
          slice(2, '第二回', '三哥离开。'),
        ],
        includesUnread: true,
      );

      expect(graph.entities.length, 1);
      final entity = graph.entities.single;
      expect(entity.name, '张三');
      expect(entity.aliases, containsAll(['三哥']));
      expect(entity.evidence.length, 2);
      expect(entity.chapterFreq, {1: 1, 2: 1});
      expect(entity.firstSection, 1);
      expect(entity.lastSection, 2);
      expect(provider.requests.length, 2);
    });

    test('duplicate evidence is not appended twice', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"主角。",
              "evidence":[{"section":1,"quote":"张三出场"},
                          {"section":1,"quote":"张三出场"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '张三出场。')],
        includesUnread: true,
      );

      expect(graph.entities.single.evidence.length, 1);
    });
  });

  group('incremental and read-range gating', () {
    test('already-covered sections are not re-extracted', () async {
      final provider = _GraphProvider(
        responses: {
          2: '''
            {"entities":[{"name":"李四","type":"person","aliases":[],
              "description":"配角。",
              "evidence":[{"section":2,"quote":"李四出场"}]}],
             "relations":[]}
          ''',
        },
      );
      final existing = AiBookGraph(
        contentHash: 'h1',
        coveredSections: const [1],
        entities: const [
          AiGraphEntity(
            name: '张三',
            type: AiGraphEntityType.person,
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '张三出场'),
            ],
            firstSection: 1,
            lastSection: 1,
          ),
        ],
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一回', '张三出场。'),
          slice(2, '第二回', '李四出场。'),
        ],
        includesUnread: true,
        existing: existing,
      );

      expect(provider.requests.length, 1);
      expect(graph.coveredSections, [1, 2]);
      expect(graph.entities.any((e) => e.name == '张三'), isTrue);
      expect(graph.entities.any((e) => e.name == '李四'), isTrue);
    });

    test('allowUnread off limits extraction to read sections', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"主角。",
              "evidence":[{"section":1,"quote":"张三出场"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一回', '张三出场。'),
          slice(2, '第二回', '李四出场。'),
        ],
        includesUnread: false,
        readThroughSection: 1,
      );

      expect(provider.requests.length, 1);
      expect(graph.coveredSections, [1]);
      expect(graph.entities.any((e) => e.name == '李四'), isFalse);
    });
  });

  group('failure and cancellation', () {
    test('cancel before the run throws a stopped error with partial', () async {
      final token = CancelToken()..cancel();
      final existing = AiBookGraph(contentHash: 'h1');

      await expectLater(
        serviceWith(_GraphProvider()).generate(
          bookTitle: '测试书',
          sections: [slice(1, '第一回', '正文。')],
          includesUnread: true,
          existing: existing,
          cancelToken: token,
        ),
        throwsA(
          isA<AiGraphGenerationException>().having(
            (e) => e.message,
            'message',
            contains('已停止'),
          ),
        ),
      );
    });

    test('invalid JSON output is retried once then fails', () async {
      final provider = _GraphProvider(invalidJson: true);

      await expectLater(
        serviceWith(provider).generate(
          bookTitle: '测试书',
          sections: [slice(1, '第一回', '正文。')],
          includesUnread: true,
        ),
        throwsA(
          isA<AiGraphGenerationException>().having(
            (e) => e.message,
            'message',
            contains('无效'),
          ),
        ),
      );
      expect(provider.requests.length, 2);
    });

    test('entities without evidence are dropped', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"幽灵","type":"person","aliases":[],
              "description":"无证据。","evidence":[]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '正文内容。')],
        includesUnread: true,
      );

      expect(graph.entities, isEmpty);
      expect(graph.coveredSections, [1]);
    });
  });
}

class _GraphProvider implements AiProvider {
  _GraphProvider({this.responses = const {}, this.invalidJson = false});

  /// sectionIndex -> raw JSON body (may be wrapped in ```json fences).
  final Map<int, String> responses;
  final bool invalidJson;
  final List<AiCompletionRequest> requests = [];

  @override
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (invalidJson) {
      return const AiCompletionResult(text: '抱歉，我无法完成这个请求。');
    }
    final prompt = request.messages.last.content;
    final match = RegExp(r'章节编号：(\d+)').firstMatch(prompt);
    final section = int.parse(match!.group(1)!);
    final body = responses[section] ?? '{"entities":[],"relations":[]}';
    return AiCompletionResult(text: '```json\n$body\n```');
  }

  @override
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken}) async =>
      const [];
}

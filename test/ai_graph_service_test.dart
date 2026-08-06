import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider.dart';
import 'package:kaijuan/ai/ai_settings.dart';
import 'dart:io';

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
    test('event type parses both Chinese labels and English wire names',
        () {
      expect(AiGraphEventType.fromWireName('战斗'), AiGraphEventType.combat);
      expect(AiGraphEventType.fromWireName('combat'), AiGraphEventType.combat);
      expect(AiGraphEventType.fromWireName('关系变化'),
          AiGraphEventType.relationship);
      expect(AiGraphEventType.fromWireName('不存在的类型'),
          AiGraphEventType.other);
      expect(AiGraphEventType.fromWireName(null), AiGraphEventType.other);
    });

    test('JSON round-trip preserves graph, entities, relations and evidence',
        () {
      final source = AiBookGraph(
        contentHash: 'h1',
        generatedAt: DateTime.utc(2026, 8, 5, 12),
        model: 'graph-test',
        includesUnread: false,
        coveredSections: const [1, 2],
        sectionTitles: const {2: '第二章'},
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
          AiGraphEntity(
            name: '罗素',
            type: AiGraphEntityType.person,
            scope: AiGraphEntityScope.reference,
            evidence: [
              AiGraphEvidence(sectionIndex: 2, quote: '如罗素所言'),
            ],
            chapterFreq: {2: 1},
            firstSection: 2,
            lastSection: 2,
          ),
          AiGraphEntity(
            name: '城门相争',
            type: AiGraphEntityType.event,
            eventType: AiGraphEventType.combat,
            importance: 3,
            evidence: [
              AiGraphEvidence(sectionIndex: 1, quote: '两军于城门外交战'),
            ],
            chapterFreq: {1: 1},
            firstSection: 1,
            lastSection: 1,
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
      final entity = restored.entities
          .firstWhere((e) => e.name == '张三');
      expect(entity.name, '张三');
      expect(entity.type, AiGraphEntityType.person);
      expect(entity.scope, AiGraphEntityScope.setting);
      expect(entity.aliases, ['三哥']);
      expect(entity.chapterFreq, {1: 1});
      expect(entity.evidence.single.spanResolved, isTrue);
      expect(entity.evidence.single.progressInSection, 0.5);
      final reference = restored.entities
          .firstWhere((e) => e.name == '罗素');
      expect(reference.scope, AiGraphEntityScope.reference);
      final event = restored.entities.firstWhere((e) => e.name == '城门相争');
      expect(event.eventType, AiGraphEventType.combat);
      expect(event.importance, 3);
      expect(restored.sectionTitles, {2: '第二章'});
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

    test('narration plan round-trips inside the graph package', () {
      const plan = AiNarrationPlan(
        features: {
          'eventDriven': 0.8,
          'characterEnsemble': 0.9,
          'organization': 0.6,
          'geography': 0.3,
          'essay': 0.0,
        },
        defaultView: 'family_tree',
        viewOrder: ['family_tree', 'persons', 'events', 'graph'],
        wantMap: true,
      );
      final source = AiBookGraph(
        contentHash: 'h1',
        narration: plan,
      );
      final restored = AiBookGraph.fromJson(source.toJson());
      expect(restored, isNotNull);
      expect(restored!.narration, isNotNull);
      expect(restored.narration!.defaultView, 'family_tree');
      expect(restored.narration!.viewOrder, ['family_tree', 'persons', 'events', 'graph']);
      expect(restored.narration!.wantMap, isTrue);
      expect(restored.narration!.feature('characterEnsemble'), 0.9);
    });

    test('old graph without narration falls back to null', () {
      final source = AiBookGraph(contentHash: 'h1').toJson();
      final restored = AiBookGraph.fromJson(source);
      expect(restored, isNotNull);
      expect(restored!.narration, isNull);
    });

    test('kin kinship label round-trips through the relation JSON', () {
      final relation = AiGraphRelation(
        source: '方老先生',
        target: '方鸿渐',
        type: '亲属',
        kin: '父子',
        description: '方老先生是方鸿渐的父亲。',
        evidence: [
          AiGraphEvidence(sectionIndex: 1, quote: '父子'),
        ],
        weight: 1,
      );
      final restored = AiGraphRelation.fromJson(relation.toJson());
      expect(restored, isNotNull);
      expect(restored!.kin, '父子');
      // Old graphs without the field read as empty.
      final old = Map<String, dynamic>.from(relation.toJson())..remove('kin');
      expect(AiGraphRelation.fromJson(old)!.kin, isEmpty);
    });
    test('invalid narration payload is rejected (falls back to default view)',
        () {
      expect(
        AiNarrationPlan.fromJson({
          'features': {'eventDriven': 0.5}, // missing the other four
          'defaultView': 'persons',
          'viewOrder': ['persons'],
          'wantMap': false,
        }),
        isNull,
      );
      expect(AiNarrationPlan.fromJson(null), isNull);
      // Out-of-range values clamp instead of invalidating the plan.
      final clamped = AiNarrationPlan.fromJson({
        'features': {
          'eventDriven': 1.5,
          'characterEnsemble': -0.2,
          'organization': 0.5,
          'geography': 0.5,
          'essay': 0.5,
        },
        'defaultView': 'persons',
        'viewOrder': ['persons'],
        'wantMap': false,
      });
      expect(clamped, isNotNull);
      expect(clamped!.feature('eventDriven'), 1.0);
      expect(clamped.feature('characterEnsemble'), 0.0);
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
              "evidence":[{"section":1,"quote":"张三与李四在城门口相见"}]},
             {"name":"李四","type":"person","aliases":[],
              "description":"次要人物。",
              "evidence":[{"section":1,"quote":"张三与李四在城门口相见"}]}],
             "relations":[{"source":"张三","target":"李四","type":"同僚",
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

      final entity = graph.entities.firstWhere((e) => e.name == '张三');
      expect(entity.name, '张三');
      expect(entity.aliases, ['张三爷']);
      expect(entity.evidence.single.spanResolved, isTrue);
      expect(entity.evidence.single.progressInSection, isNotNull);
      expect(entity.firstSection, 1);
      expect(entity.lastSection, 1);
      final relation = graph.relations.single;
      expect(relation.source, '张三');
      expect(relation.target, '李四');
      expect(relation.type, '同僚');
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

    test('model scope survives extraction', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","scope":"setting",
              "description":"主角。",
              "evidence":[{"section":1,"quote":"张三进京"}]},
             {"name":"罗素","type":"person","scope":"reference",
              "description":"引用的哲学家。",
              "evidence":[{"section":1,"quote":"如罗素所言"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '张三进京。如罗素所言。')],
        includesUnread: true,
      );

      expect(
        graph.entities
            .firstWhere((e) => e.name == '张三')
            .scope,
        AiGraphEntityScope.setting,
      );
      expect(
        graph.entities.firstWhere((e) => e.name == '罗素').scope,
        AiGraphEntityScope.reference,
      );
    });

    test('citation-quote hard rule downgrades a setting entity', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"罗素","type":"person","scope":"setting",
              "description":"哲学家。",
              "evidence":[{"section":1,"quote":"如罗素所言，思考要独立"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '如罗素所言，思考要独立。')],
        includesUnread: true,
      );

      expect(
        graph.entities.single.scope,
        AiGraphEntityScope.reference,
      );
    });

    test('single-chapter appearance does not demote an essay person',
        () async {
      // Essay collections: every chapter is standalone, so a person who
      // appears in exactly one chapter is still book content, not a
      // citation. The demotion must come from the model or quote patterns.
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","scope":"setting",
              "evidence":[{"section":1,"quote":"张三登场"}]},
             {"name":"过客","type":"person","scope":"setting",
              "evidence":[{"section":1,"quote":"过客匆匆路过"}]}],
             "relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"张三","type":"person","scope":"setting",
              "evidence":[{"section":2,"quote":"张三继续"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一回', '张三登场。过客匆匆路过。'),
          slice(2, '第二回', '张三继续。'),
        ],
        includesUnread: true,
      );

      expect(
        graph.entities.firstWhere((e) => e.name == '张三').scope,
        AiGraphEntityScope.setting,
      );
      expect(
        graph.entities.firstWhere((e) => e.name == '过客').scope,
        AiGraphEntityScope.setting,
      );
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
      final entity = graph.entities.firstWhere((e) => e.name == '张三');
      expect(entity.name, '张三');
      expect(entity.aliases, containsAll(['三哥']));
      expect(entity.evidence.length, 2);
      expect(entity.chapterFreq, {1: 1, 2: 1});
      expect(entity.firstSection, 1);
      expect(entity.lastSection, 2);
      expect(provider.extractionRequests.length, 2);
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

    test('step-0 narration plan lands in the graph; extraction is untouched',
        () async {
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
        sections: [slice(1, '第一回', '张三出场。')],
        includesUnread: true,
      );

      expect(graph.narration, isNotNull);
      expect(graph.narration!.defaultView, 'events');
      expect(graph.narration!.viewOrder.first, 'events');
      expect(graph.entities.single.name, '张三');
      // One plan call + one extraction call.
      expect(provider.requests.length, 2);
      expect(provider.extractionRequests.length, 1);
      // Direction convention is baked into the extraction prompt (system
      // message: fixed rules live there for DeepSeek context-cache hits).
      final prompt = provider.extractionRequests.single.messages
          .map((m) => m.content)
          .join('\n');
      expect(prompt, contains('方向性关系（亲属/师徒/隶属/效力/追随）必须固定方向'));
      expect(prompt, contains('quote 必须逐字来自正文，单条不超过 30 字'));
    });

    test('organization-driven plan feeds back into the extraction prompt',
        () async {
      final provider = _GraphProvider(
        narrationBody: '{'
            '"features":{"eventDriven":0.3,"characterEnsemble":0.4,'
            '"organization":0.9,"geography":0.2,"essay":0.0},'
            '"defaultView":"family_tree","viewOrder":["family_tree","persons"],'
            '"wantMap":false}',
        responses: {
          1: '''
            {"entities":[{"name":"史塔克家族","type":"organization","aliases":[],
              "description":"北境守护家族。",
              "evidence":[{"section":1,"quote":"史塔克家族坐镇临冬城"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '史塔克家族坐镇临冬城。')],
        includesUnread: true,
      );

      expect(graph.narration!.feature('organization'), 0.9);
      final prompt =
          provider.extractionRequests.single.messages.last.content;
      expect(prompt, contains('person|location|event|organization'));
      expect(graph.entities.single.type, AiGraphEntityType.organization);
    });

    test('failed narration call silently degrades and does not block', () async {
      // Force the narration call to fail while keeping extraction valid:
      // reuse _GraphProvider with a narration body that is not valid JSON.
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
      // Force the narration call to fail while keeping extraction valid:
      // reuse _GraphProvider with a narration body that is not valid JSON.
      final failing = _GraphProvider(
        narrationBody: 'not json at all',
        responses: provider.responses,
      );

      final graph = await serviceWith(failing).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '张三出场。')],
        includesUnread: true,
      );

      expect(graph.narration, isNull);
      expect(graph.entities.single.name, '张三');
      expect(graph.coveredSections, [1]);
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

      expect(provider.extractionRequests.length, 1);
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

      expect(provider.extractionRequests.length, 1);
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
      expect(provider.extractionRequests.length, 2);
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

    test('confirmed plan is used and step-0 call is skipped', () async {
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
      const confirmed = AiNarrationPlan(
        features: {
          'eventDriven': 0.9,
          'characterEnsemble': 0.1,
          'organization': 0.0,
          'geography': 0.0,
          'essay': 0.0,
        },
        defaultView: 'events',
        viewOrder: ['events', 'persons', 'locations', 'graph'],
        wantMap: false,
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '张三出场。')],
        includesUnread: true,
        plannedNarration: confirmed,
      );

      // The confirmed plan lands as-is; only the extraction call ran (no
      // step-0 request because the caller already decided the plan).
      expect(graph.narration, same(confirmed));
      expect(provider.requests.length, 1);
      expect(provider.extractionRequests.length, 1);
    });

    test('withDefaultView re-orders the view order', () {
      const plan = AiNarrationPlan(
        features: {
          'eventDriven': 0.5,
          'characterEnsemble': 0.5,
          'organization': 0.5,
          'geography': 0.5,
          'essay': 0.5,
        },
        defaultView: 'persons',
        viewOrder: ['persons', 'events', 'locations', 'graph'],
        wantMap: false,
      );

      final changed = plan.withDefaultView('family_tree');
      expect(changed.defaultView, 'family_tree');
      expect(changed.viewOrder, ['family_tree', 'persons', 'events', 'locations', 'graph']);
      // Unchanged view returns the same instance.
      expect(plan.withDefaultView('persons'), same(plan));
    });
  });

  group('normalizeRelationType', () {
    AiBookGraphService service() => serviceWith(_GraphProvider());

    test('maps English NER tags to the Chinese vocabulary', () {
      final s = service();
      expect(s.normalizeRelationType('trusts'), '信任');
      expect(s.normalizeRelationType('teacher_student'), '师生');
      expect(s.normalizeRelationType('served'), '效力');
      expect(s.normalizeRelationType('replaced'), '更替');
      expect(s.normalizeRelationType('mediated'), '调停');
    });

    test('keeps Chinese vocabulary and collapses unknown to the fallback', () {
      final s = service();
      expect(s.normalizeRelationType('弹劾'), '弹劾');
      expect(s.normalizeRelationType(' TRUSTS '), '信任');
      expect(s.normalizeRelationType('???'), '相关');
      expect(s.normalizeRelationType(''), '相关');
    });

    test('uses per-settings relation words instead of the defaults', () {
      final s = AiBookGraphService(
        isAvailable: () => true,
        openProvider: () => _GraphProvider(),
        settings: () => const AiSettings(
          graphRuleWords: AiGraphRuleWords(
            relationTypes: ['知己'],
            relationTypeAliases: {'pal': '知己'},
          ),
        ),
      );
      expect(s.normalizeRelationType('知己'), '知己');
      expect(s.normalizeRelationType('pal'), '知己');
      expect(s.normalizeRelationType('trusts'), '相关'); // default alias gone
    });
  });

  group('AiGraphStore per-work graphs', () {
    late Directory tempDir;
    late AiGraphStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ai_graph_store_test');
      store = AiGraphStore(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    AiBookGraph graphFor(String work) => AiBookGraph(
      contentHash: 'h1',
      generatedAt: DateTime.utc(2026, 8, 5, 12),
      model: 'graph-test',
      includesUnread: false,
      coveredSections: const [1],
      entities: [
        AiGraphEntity(
          name: work,
          type: AiGraphEntityType.person,
          aliases: const [],
          description: '',
          evidence: [
            AiGraphEvidence(sectionIndex: 1, quote: work),
          ],
        ),
      ],
      relations: const [],
    );

    test('whole-book and per-work graphs live in separate files', () async {
      await store.write(graphFor('整本'), workKey: null);
      await store.write(graphFor('s51'), workKey: 's51');
      await store.write(graphFor('s95'), workKey: 's95');

      expect((await store.read('h1'))?.entities.single.name, '整本');
      expect((await store.read('h1', workKey: 's51'))?.entities.single.name,
          's51');
      final all = await store.readAllFor('h1');
      expect(all.keys.toSet(), {'s51', 's95'});
    });

    test('delete only removes the targeted work', () async {
      await store.write(graphFor('s51'), workKey: 's51');
      await store.write(graphFor('s95'), workKey: 's95');
      await store.delete('h1', workKey: 's51');
      expect(await store.read('h1', workKey: 's51'), isNull);
      expect((await store.readAllFor('h1')).keys.toSet(), {'s95'});
    });
  });
}

class _GraphProvider implements AiProvider {
  _GraphProvider({
    this.responses = const {},
    this.invalidJson = false,
    this.narrationBody = defaultNarrationBody,
  });

  /// sectionIndex -> raw JSON body (may be wrapped in ```json fences).
  final Map<int, String> responses;
  final bool invalidJson;

  /// Step-0 display plan body (default: event-driven, organization low).
  final String narrationBody;

  static const String defaultNarrationBody = '{'
      '"features":{"eventDriven":0.8,"characterEnsemble":0.2,'
      '"organization":0.1,"geography":0.1,"essay":0.0},'
      '"defaultView":"events","viewOrder":["events","persons","locations","graph"],'
      '"wantMap":false}';
  final List<AiCompletionRequest> requests = [];

  /// Requests that hit the per-chapter extraction prompt (any message carries
  /// a 章节编号 line — the retry nudge appends to the original messages);
  /// the step-0 narration call is a separate request type.
  List<AiCompletionRequest> get extractionRequests => [
    for (final r in requests)
      if (r.messages.any((m) => m.content.contains('章节编号：'))) r,
  ];

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
    if (match == null) {
      // Step-0 display plan call: return a valid plan so generation walks
      // the real path (the plan itself is asserted in narration tests).
      return AiCompletionResult(
        text: '```json\n$narrationBody\n```',
      );
    }
    final section = int.parse(match.group(1)!);
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

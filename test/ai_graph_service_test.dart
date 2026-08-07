import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_provider.dart';
import 'package:kaijuan/ai/ai_settings.dart';
import 'dart:convert';
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

    test('mergeLog survives JSON round-trip', () {
      final source = AiBookGraph(
        contentHash: 'h1',
        generatedAt: DateTime.utc(2026, 8, 6, 12),
        model: 'graph-test',
        includesUnread: false,
        coveredSections: const [1, 2],
        sectionTitles: const {2: '第二章'},
        entities: const [],
        relations: const [],
        mergeLog: const [
          {
            'from': '孝定皇太后',
            'to': '慈圣太后',
            'score': 0.5,
            'reason': 'review',
            'section': 2,
          },
        ],
      );

      final restored = AiBookGraph.fromJson(
        jsonDecode(jsonEncode(source.toJson())),
      )!;
      expect(restored.mergeLog, [
        {
          'from': '孝定皇太后',
          'to': '慈圣太后',
          'score': 0.5,
          'reason': 'review',
          'section': 2,
        },
      ]);
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
      expect(restored.narration!.viewOrder, [
        'family_tree',
        'persons',
        'events',
        'graph',
        'locations',
        'org_tree',
      ]);
      expect(restored.narration!.wantMap, isTrue);
      expect(restored.narration!.feature('characterEnsemble'), 0.9);
    });

    test('excluded section slice round-trips and defaults empty', () {
      final source = AiBookGraph(
        contentHash: 'h1',
        excludedGraphSections: const [3, 5, 7],
      );
      final restored = AiBookGraph.fromJson(source.toJson());
      expect(restored, isNotNull);
      expect(restored!.excludedGraphSections, [3, 5, 7]);

      // Old graphs (no field) default to no exclusions.
      final old = Map<String, dynamic>.from(source.toJson())
        ..remove('excludedGraphSections');
      expect(AiBookGraph.fromJson(old)!.excludedGraphSections, isEmpty);
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
    test('incomplete narration payload degrades instead of failing', () {
      // Missing feature dimensions default to 0; unknown defaultView falls
      // back to the strongest feature's view; empty viewOrder is rebuilt.
      final degraded = AiNarrationPlan.fromJson({
        'features': {'eventDriven': 0.5}, // missing the other four
        'defaultView': 'persons',
        'viewOrder': ['persons'],
        'wantMap': false,
      });
      expect(degraded, isNotNull);
      expect(degraded!.feature('eventDriven'), 0.5);
      expect(degraded.feature('essay'), 0.0);
      expect(degraded.defaultView, 'persons');
      expect(degraded.viewOrder.first, 'persons');

      // Unknown defaultView + empty viewOrder → derived from the strongest
      // feature (organization → family_tree), order rebuilt around it.
      final derived = AiNarrationPlan.fromJson({
        'features': {
          'eventDriven': 0.2,
          'characterEnsemble': 0.4,
          'organization': 0.9,
          'geography': 0.1,
          'essay': 0.1,
        },
        'defaultView': 'some_future_view',
        'viewOrder': <dynamic>[],
      });
      expect(derived, isNotNull);
      expect(derived!.defaultView, 'family_tree');
      expect(derived.viewOrder.first, 'family_tree');
      expect(derived.viewOrder.toSet(), containsAll(AiNarrationPlan.knownViews));

      // Only a structurally missing payload is rejected.
      expect(AiNarrationPlan.fromJson(null), isNull);
      expect(AiNarrationPlan.fromJson({'features': 'not-a-map'}), isNull);

      // An essay book never gets lineage/faction views, even when the model
      // guessed one (a collection judged as a whole scores organization).
      final essay = AiNarrationPlan.fromJson({
        'features': {
          'eventDriven': 0.1,
          'characterEnsemble': 0.3,
          'organization': 0.9,
          'geography': 0.2,
          'essay': 1.0,
        },
        'defaultView': 'family_tree',
        'viewOrder': ['family_tree', 'org_tree', 'graph', 'locations'],
      });
      expect(essay, isNotNull);
      expect(essay!.defaultView, 'graph');
      expect(essay.viewOrder, isNot(contains('family_tree')));
      expect(essay.viewOrder, isNot(contains('org_tree')));
      expect(essay.viewOrder.first, 'graph');

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

    test('similar person names merge across sections (慈圣太后/慈圣皇太后)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"慈圣太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣太后"}],
              "scope":"setting"}],
             "relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"慈圣皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":2,"quote":"慈圣皇太后"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],"description":"",
              "evidence":[{"section":2,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣皇太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":2,"quote":"慈圣皇太后是万历皇帝生母"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '慈圣太后。'),
          slice(2, '第二节', '慈圣皇太后是万历皇帝生母。'),
        ],
        includesUnread: true,
      );

      // 慈圣太后/慈圣皇太后 are the same person (皇后→太后升格) → one entity.
      final cisu = graph.entities.where((e) => e.name.contains('慈圣'));
      expect(cisu.length, 1);
      expect(cisu.single.name, '慈圣太后');
      expect(graph.entities.length, 2);
      // Relation endpoints normalized to the canonical names.
      final relation = graph.relations.single;
      expect(relation.source, '慈圣太后');
      expect(relation.target, '万历皇帝');
      // Audit trail records the name-structure merge (score 0.7, stem rule).
      expect(
        graph.mergeLog.any((e) =>
            e['reason'] == 'name' &&
            e['from'] == '慈圣皇太后' &&
            e['to'] == '慈圣太后' &&
            e['score'] == 0.7),
        isTrue,
      );
    });

    test('unrelated person names never merge (正德皇帝 vs 万历皇帝)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"正德皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"正德皇帝"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":2,"quote":"万历皇帝"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '正德皇帝。'), slice(2, '二', '万历皇帝。')],
        includesUnread: true,
      );

      expect(graph.entities.length, 2);
      expect(graph.entities.map((e) => e.name).toSet(),
          {'正德皇帝', '万历皇帝'});
    });

    test('same relation across sections fuses into one edge with all evidence',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"张三与李四同在京城为官"}],
              "scope":"setting"},
             {"name":"李四","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"张三与李四同在京城为官"}],
              "scope":"setting"}],
             "relations":[{"source":"张三","target":"李四","type":"同僚",
              "description":"同在京城。",
              "evidence":[{"section":1,"quote":"张三与李四同在京城为官"}]}]}
          ''',
          2: '''
            {"entities":[],
             "relations":[{"source":"张三","target":"李四","type":"同僚",
              "description":"同在京城。",
              "evidence":[{"section":2,"quote":"张三李四同僚多年"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '张三与李四同在京城为官。'),
          slice(2, '第二节', '张三李四同僚多年。'),
        ],
        includesUnread: true,
      );

      // Knowledge fusion: mergeKey (source|target|type) dedupes the edge and
      // appends evidence; weight reflects the fused evidence count.
      expect(graph.relations.length, 1);
      final relation = graph.relations.single;
      expect(relation.source, '张三');
      expect(relation.target, '李四');
      expect(relation.type, '同僚');
      expect(relation.evidence.length, 2);
      expect(relation.weight, 2);
    });

    test('generic honorific never absorbs a named person (皇帝≠万历皇帝)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"皇帝","type":"person","aliases":[],
              "description":"当朝天子。",
              "evidence":[{"section":1,"quote":"皇帝"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":[],
              "description":"明朝皇帝。",
              "evidence":[{"section":2,"quote":"万历皇帝"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '皇帝。'), slice(2, '二', '万历皇帝。')],
        includesUnread: true,
      );

      // 皇帝 ⊂ 万历皇帝 is a suffix hit but 皇帝 is a role, not a name: the
      // emperor's entity must survive (regression: it used to fold away).
      expect(graph.entities.map((e) => e.name).toSet(),
          {'皇帝', '万历皇帝'});
      expect(graph.entities.length, 2);
    });

    test('generic honorific never absorbs a titled person (太后≠慈圣太后)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"太后","type":"person","aliases":[],
              "description":"太后临朝。",
              "evidence":[{"section":1,"quote":"太后"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"慈圣太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":2,"quote":"慈圣太后"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '太后。'), slice(2, '二', '慈圣太后。')],
        includesUnread: true,
      );

      expect(graph.entities.map((e) => e.name).toSet(),
          {'太后', '慈圣太后'});
      expect(graph.entities.length, 2);
    });

    test('real substring aliases still merge locally (万历 ⊂ 万历皇帝)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"万历","type":"person","aliases":[],
              "description":"明朝皇帝。",
              "evidence":[{"section":1,"quote":"万历"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":[],
              "description":"明朝皇帝。",
              "evidence":[{"section":2,"quote":"万历皇帝"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '万历。'), slice(2, '二', '万历皇帝。')],
        includesUnread: true,
      );

      // 万历 is a real name (not a role): the substring rule still folds it,
      // keeping the first-seen canonical (万历).
      expect(graph.entities.map((e) => e.name).toSet(), {'万历'});
      expect(graph.entities.length, 1);
    });

    test('shared-relation review defaults to different (张居正≠冯保)',
        () async {
      final provider = _GraphProvider(
        reviewVerdicts: '["different"]',
        responses: {
          1: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"},
             {"name":"张居正","type":"person","aliases":[],
              "description":"内阁首辅。",
              "evidence":[{"section":1,"quote":"张居正任首辅"}],
              "scope":"setting"}],
             "relations":[{"source":"张居正","target":"万历皇帝",
              "type":"效力",
              "evidence":[{"section":1,"quote":"张居正辅佐万历"}]}]}
          ''',
          2: '''
            {"entities":[{"name":"冯保","type":"person","aliases":[],
              "description":"司礼监掌印太监。",
              "evidence":[{"section":2,"quote":"冯保掌司礼监"}],
              "scope":"setting"}],
             "relations":[{"source":"冯保","target":"万历皇帝",
              "type":"效力",
              "evidence":[{"section":2,"quote":"冯保辅佐万历"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '张居正任首辅。万历皇帝年幼。'),
          slice(2, '第二节', '冯保掌司礼监。万历皇帝倚重。'),
        ],
        includesUnread: true,
      );

      // Both serve 万历皇帝 (shared ascending relation → review) but are
      // clearly different people: the model says different, no merge.
      expect(graph.entities.map((e) => e.name).toSet(),
          {'万历皇帝', '张居正', '冯保'});
      expect(graph.relations.length, 2);
    });

    test('protagonist mislabelled reference is restored to setting (张居正)',
        () async {
      final quotes = List.generate(6, (i) => '张居正主持新政第${i + 1}条。');
      final body = quotes.join();
      final evidence = [
        for (var i = 0; i < 6; i++)
          '{"section":1,"quote":"张居正主持新政第${i + 1}条"}',
      ].join(',');
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张居正","type":"person","aliases":[],
              "description":"首辅。","evidence":[$evidence],
              "scope":"reference"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', body)],
        includesUnread: true,
      );

      // 6 quote-backed evidence quotes, zero citation templates: the model
      // mislabelled the protagonist — restore to setting (family-tree scope).
      final zjz = graph.entities.singleWhere((e) => e.name == '张居正');
      expect(zjz.scope, AiGraphEntityScope.setting);
    });

    test('flipped kin mirror dedupes to the stronger direction (万历母子)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"慈圣皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣皇太后是万历皇帝生母"},
                          {"section":1,"quote":"皇太后劝万历读书"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣皇太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"慈圣皇太后是万历皇帝生母"},
                          {"section":1,"quote":"皇太后劝万历读书"}]},
             {"source":"万历皇帝","target":"慈圣皇太后",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"万历皇帝叩拜皇太后"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '慈圣皇太后是万历皇帝生母。皇太后劝万历读书。万历皇帝叩拜皇太后。')],
        includesUnread: true,
      );

      // The flipped mirror (万历→慈圣 母子, weaker) is dropped; only the
      // stronger, correct direction survives — the junior is no longer a
      // candidate parent in the family tree.
      expect(graph.relations.length, 1);
      final kin = graph.relations.single;
      expect(kin.source, '慈圣皇太后');
      expect(kin.target, '万历皇帝');
      expect(kin.kin, '母子');
    });

    test('kin-less 亲属 relation is dropped at merge time (恭妃非子)', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"},
             {"name":"恭妃王氏","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"恭妃王氏"}],
              "scope":"setting"}],
             "relations":[{"source":"万历皇帝","target":"恭妃王氏",
              "type":"亲属","description":"","kin":"",
              "evidence":[{"section":1,"quote":"万历皇帝临幸恭妃王氏"}]},
             {"source":"万历皇帝","target":"恭妃王氏",
              "type":"婚配","description":"夫妻。","kin":"夫妻",
              "evidence":[{"section":1,"quote":"万历皇帝与恭妃王氏为夫妻"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '万历皇帝临幸恭妃王氏。万历皇帝与恭妃王氏为夫妻。')],
        includesUnread: true,
      );

      // The kin-less 亲属 edge is an unconfirmed guess — dropped. The real
      // 婚配 edge survives (and is what the list/graph views should show).
      expect(graph.relations.length, 1);
      final relation = graph.relations.single;
      expect(relation.type, '婚配');
      expect(relation.kin, '妃嫔'); // 恭妃王氏 → rank term, not informal 夫妻
    });

    test('hallucinated entity with no verbatim mention is grounded out',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"主角。",
              "evidence":[{"section":1,"quote":"张三登场"}],
              "scope":"setting"},
             {"name":"八爪星人","type":"person","aliases":[],
              "description":"外星来客。",
              "evidence":[{"section":1,"quote":"八爪星人降临"}],
              "scope":"setting"}],
             "relations":[{"source":"张三","target":"八爪星人","type":"敌对",
              "evidence":[{"section":1,"quote":"张三与八爪星人交战"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '张三登场。')],
        includesUnread: true,
      );

      // 八爪星人 never appears in the book body — the model invented it
      // (pre-training leakage); the entity and its edge are grounded out.
      expect(graph.entities.map((e) => e.name), ['张三']);
      expect(graph.relations, isEmpty);
      // A real alias keeps the entity grounded (今上 = 万历皇帝 in body).
      expect(graph.coveredSections, [1]);
    });

    test('aliases keep an entity grounded when the canonical name is absent',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":["今上"],
              "description":"天子。",
              "evidence":[{"section":1,"quote":"今上"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '今上临朝。')],
        includesUnread: true,
      );

      // Canonical 万历皇帝 never appears verbatim, but alias 今上 does — the
      // entity stays (grounding checks name AND aliases).
      expect(graph.entities.map((e) => e.name), ['万历皇帝']);
    });

    test('contextual kinship terms never absorb named people (哥哥≠刘哥哥)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"刘哥哥","type":"person","aliases":[],
              "description":"结义大哥。",
              "evidence":[{"section":1,"quote":"刘哥哥"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"哥哥","type":"person","aliases":[],
              "description":"家中长兄。",
              "evidence":[{"section":2,"quote":"哥哥"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '刘哥哥。'), slice(2, '二', '哥哥。')],
        includesUnread: true,
      );

      // 哥哥 ⊂ 刘哥哥 is a suffix hit, but 哥哥 is a contextual kinship term
      // that refers to different people in different chapters — never a merge
      // key (AI-Reader-V2 dangerous-alias table).
      expect(graph.entities.map((e) => e.name).toSet(),
          {'刘哥哥', '哥哥'});
    });

    test('先生 never absorbs a titled person (先生≠陈先生)', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"陈先生","type":"person","aliases":[],
              "description":"塾师。",
              "evidence":[{"section":1,"quote":"陈先生"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"先生","type":"person","aliases":[],
              "description":"尊称。",
              "evidence":[{"section":2,"quote":"先生"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '陈先生。'), slice(2, '二', '先生。')],
        includesUnread: true,
      );

      expect(graph.entities.map((e) => e.name).toSet(),
          {'陈先生', '先生'});
    });

    test('依据X/按照X narration does not trigger the citation rule',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张居正","type":"person","scope":"setting",
              "description":"首辅。",
              "evidence":[{"section":1,"quote":"依据张居正的奏疏办事"},
                          {"section":1,"quote":"按张居正的意思办"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '依据张居正的奏疏办事。按张居正的意思办。')],
        includesUnread: true,
      );

      // 依据X/按X describe the court acting per 张居正 — narration, not a
      // citation of him; the entity must stay setting (S3 regression).
      expect(graph.entities.single.scope, AiGraphEntityScope.setting);
    });

    test('relation endpoint without an entity is dropped (先生 泛称端点)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"陈先生","type":"person","aliases":[],
              "description":"塾师。",
              "evidence":[{"section":1,"quote":"陈先生"}],
              "scope":"setting"}],
             "relations":[{"source":"先生","target":"陈先生","type":"师生",
              "evidence":[{"section":1,"quote":"先生教陈先生读书"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '先生教陈先生读书。')],
        includesUnread: true,
      );

      // 先生 never appeared as an entity mention → the dangling edge is
      // dropped instead of shipping an unclickable node (S2 regression).
      expect(graph.relations, isEmpty);
      expect(graph.entities.map((e) => e.name), ['陈先生']);
    });

    test('cross-kin reversed mirrors dedupe to the stronger direction',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"慈圣皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣皇太后"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣皇太后","target":"万历皇帝",
              "type":"亲属","kin":"父子",
              "evidence":[{"section":1,"quote":"慈圣皇太后教导万历"},
                          {"section":1,"quote":"皇太后训子"}]},
             {"source":"万历皇帝","target":"慈圣皇太后",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"万历皇帝拜见皇太后"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '慈圣皇太后教导万历。皇太后训子。万历皇帝拜见皇太后。')],
        includesUnread: true,
      );

      // A→B 父子 vs B→A 母子 — different kin, same conflict: only the
      // stronger direction survives (S4 regression).
      expect(graph.relations.length, 1);
      final kin = graph.relations.single;
      expect(kin.source, '慈圣皇太后');
      expect(kin.target, '万历皇帝');
    });

    test('equal-strength mirror keeps the earlier-appearing source', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"慈圣皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣皇太后"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣皇太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"皇太后召见万历"}]},
             {"source":"万历皇帝","target":"慈圣皇太后",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"万历皇帝叩拜皇太后"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '慈圣皇太后召见万历。万历皇帝叩拜皇太后。')],
        includesUnread: true,
      );

      // Both mirrors carry one evidence quote: the tie resolves to the
      // earlier-appearing source (慈圣皇太后 firstSection 1) so the emperor
      // is never drawn as his mother's parent (S5 regression).
      expect(graph.relations.length, 1);
      expect(graph.relations.single.source, '慈圣皇太后');
      expect(graph.relations.single.target, '万历皇帝');
    });

    test('re-run with an excluded section does not ground out its entities',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"甲","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"甲"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"乙","type":"person","aliases":[],
              "description":"序言人物。",
              "evidence":[{"section":2,"quote":"乙"}],
              "scope":"setting"}],"relations":[]}
          ''',
          4: '{"entities":[],"relations":[]}',
        },
      );
      final service = serviceWith(provider);

      final first = await service.generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '一', '甲。'),
          slice(2, '二', '乙。'),
        ],
        includesUnread: true,
      );
      expect(first.entities.map((e) => e.name), contains('乙'));

      // Re-run excluding section 2, adding section 4: 乙's evidence lives in
      // a section that is no longer in the body — grounding must skip it,
      // not treat the exclusion as a hallucination (S1 regression).
      final second = await service.generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '一', '甲。'),
          slice(4, '四', '新内容。'),
        ],
        existing: first,
        includesUnread: true,
      );
      expect(second.entities.map((e) => e.name), contains('乙'));
      expect(second.coveredSections, containsAll([1, 2, 4]));
    });

    test('configured generic terms drive the merge (config library, not code)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"刘爷爷","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"刘爷爷"}],
              "scope":"setting"}],"relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"老爷子","type":"person","aliases":[],
              "description":"尊称。",
              "evidence":[{"section":2,"quote":"老爷子"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );
      // 老爷子 is a book-specific 称谓: configured via AiGraphRuleWords —
      // the pipeline itself has no hardcoded book vocabulary.
      final service = AiBookGraphService(
        isAvailable: () => true,
        openProvider: () => provider,
        settings: () => const AiSettings(
          model: 'graph-test',
          graphRuleWords: AiGraphRuleWords(genericPersonTerms: ['老爷子']),
        ),
      );

      final graph = await service.generate(
        bookTitle: '测试书',
        sections: [slice(1, '一', '刘爷爷。'), slice(2, '二', '老爷子。')],
        includesUnread: true,
      );

      // 老爷子 ⊂ 刘爷爷 is a suffix hit, but the configured term excludes it
      // from merging — book vocabulary lives in settings, not in the pipeline.
      expect(graph.entities.map((e) => e.name).toSet(),
          {'刘爷爷', '老爷子'});
    });

    test('book priors resolve classics aliases before generic rules (行者→孙悟空)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"行者","type":"person","aliases":[],
              "description":"取经人。",
              "evidence":[{"section":1,"quote":"行者"}],
              "scope":"setting"}],
             "relations":[]}
          ''',
          2: '''
            {"entities":[{"name":"孙悟空","type":"person","aliases":[],
              "description":"","evidence":[{"section":2,"quote":"孙悟空"}],
              "scope":"setting"},
             {"name":"唐僧","type":"person","aliases":[],
              "description":"","evidence":[{"section":2,"quote":"唐僧"}],
              "scope":"setting"}],
             "relations":[{"source":"行者","target":"唐僧","type":"师徒",
              "kin":"师徒",
              "evidence":[{"section":2,"quote":"行者拜唐僧为师"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '西游记',
        sections: [slice(1, '一', '行者。'), slice(2, '二', '孙悟空。唐僧。行者拜唐僧为师。')],
        includesUnread: true,
      );

      // 行者 is a prior alias of 孙悟空 (config library, matched by title):
      // the entity canonicalizes immediately, later mentions merge into it,
      // and the relation endpoint follows the prior.
      final names = graph.entities.map((e) => e.name).toSet();
      expect(names, isNot(contains('行者')));
      expect(names, contains('孙悟空'));
      expect(graph.entities.length, 2); // 孙悟空 + 唐僧
      final relation = graph.relations.single;
      expect(relation.source, '孙悟空');
      expect(relation.target, '唐僧');
    });

    test('book priors are inert for unmatched titles', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"行者","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"行者"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '无名书',
        sections: [slice(1, '一', '行者。')],
        includesUnread: true,
      );

      // No priors for this title: 行者 stays its own entity (no forced merge).
      expect(graph.entities.map((e) => e.name), ['行者']);
    });

    test('configured book priors take effect (config library, not code)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"师太","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"师太"}],
              "scope":"setting"}],"relations":[]}
          ''',
        },
      );
      final service = AiBookGraphService(
        isAvailable: () => true,
        openProvider: () => provider,
        settings: () => const AiSettings(
          model: 'graph-test',
          graphRuleWords: AiGraphRuleWords(
            bookNamePriors: {'江湖志': {'师太': '静玄师太'}},
          ),
        ),
      );

      final graph = await service.generate(
        bookTitle: '江湖志',
        sections: [slice(1, '一', '师太。')],
        includesUnread: true,
      );

      expect(graph.entities.single.name, '静玄师太');
    });

    test('marital kin refines to rank terms for imperial consorts',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[
             {"name":"万历皇帝","type":"person","aliases":[],"scope":"setting",
              "evidence":[{"section":1,"quote":"万历皇帝"}],"relations":[]},
             {"name":"王皇后","type":"person","aliases":["孝端皇后"],"scope":"setting",
              "evidence":[{"section":1,"quote":"王皇后"}],"relations":[]},
             {"name":"恭妃王氏","type":"person","aliases":[],"scope":"setting",
              "evidence":[{"section":1,"quote":"恭妃王氏"}],"relations":[]},
             {"name":"郑氏","type":"person","aliases":["郑贵妃"],"scope":"setting",
              "evidence":[{"section":1,"quote":"郑氏"}],"relations":[]},
             {"name":"张三","type":"person","aliases":[],"scope":"setting",
              "evidence":[{"section":1,"quote":"张三"}],"relations":[]},
             {"name":"李四","type":"person","aliases":[],"scope":"setting",
              "evidence":[{"section":1,"quote":"李四"}],"relations":[]}],
             "relations":[
              {"source":"万历皇帝","target":"王皇后","type":"婚配","kin":"夫妻",
               "evidence":[{"section":1,"quote":"万历皇帝与王皇后成婚"}]},
              {"source":"万历皇帝","target":"恭妃王氏","type":"婚配","kin":"夫妻",
               "evidence":[{"section":1,"quote":"万历皇帝与恭妃王氏成婚"}]},
              {"source":"万历皇帝","target":"郑氏","type":"婚配","kin":"夫妻",
               "evidence":[{"section":1,"quote":"万历皇帝与郑氏成婚"}]},
              {"source":"张三","target":"李四","type":"婚配","kin":"夫妻",
               "evidence":[{"section":1,"quote":"张三与李四结为夫妻"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '万历皇帝与王皇后成婚。万历皇帝与恭妃王氏成婚。万历皇帝与郑氏成婚。张三与李四结为夫妻。')],
        includesUnread: true,
      );

      final kinByTarget = {
        for (final r in graph.relations.where((r) => r.type == '婚配'))
          r.target: r.kin,
      };
      expect(kinByTarget['王皇后'], '皇后', reason: '王皇后是正妻');
      expect(kinByTarget['恭妃王氏'], '妃嫔', reason: '恭妃是妃妾');
      expect(kinByTarget['郑氏'], '贵妃', reason: '郑氏即郑贵妃（aliases）');
      expect(kinByTarget['李四'], '夫妻', reason: '平民夫妻保持原词');
    });

    test('relation-evidence co-reference resolves via LLM review (孝定=慈圣)',
        () async {
      final provider = _GraphProvider(
        reviewVerdicts: '["same"]',
        responses: {
          1: '''
            {"entities":[{"name":"慈圣太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣太后是万历皇帝生母"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"慈圣太后是万历皇帝生母"}]}]}
          ''',
          2: '''
            {"entities":[{"name":"孝定皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":2,"quote":"孝定皇太后是万历皇帝生母"}],
              "scope":"setting"}],
             "relations":[{"source":"孝定皇太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":2,"quote":"孝定皇太后是万历皇帝生母"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '慈圣太后是万历皇帝生母。'),
          slice(2, '第二节', '孝定皇太后是万历皇帝生母。'),
        ],
        includesUnread: true,
      );

      // Same person despite unrelated names: the shared 母子 relation triggers
      // the review and the model confirms → one entity, both aliases kept.
      final merged = graph.entities.where((e) =>
          e.name.contains('慈圣') || e.name.contains('孝定'));
      expect(merged.length, 1);
      expect(merged.single.name, '慈圣太后');
      expect(merged.single.aliases, contains('孝定皇太后'));
      expect(graph.entities.length, 2);
      // Relation endpoints rewired to the surviving canonical.
      expect(graph.relations.single.source, '慈圣太后');
      expect(graph.relations.single.target, '万历皇帝');
      // Audit trail records the reviewed merge.
      expect(
        graph.mergeLog.any((e) =>
            e['reason'] == 'review' && e['from'] == '孝定皇太后'),
        isTrue,
      );
    });

    test('shared father never merges siblings (下溯证据不误合)', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"},
             {"name":"朱常洛","type":"person","aliases":[],
              "description":"万历长子。",
              "evidence":[{"section":1,"quote":"朱常洛是万历长子"}],
              "scope":"setting"}],
             "relations":[{"source":"万历皇帝","target":"朱常洛",
              "type":"亲属","kin":"父子",
              "evidence":[{"section":1,"quote":"朱常洛是万历长子"}]}]}
          ''',
          2: '''
            {"entities":[{"name":"朱常洵","type":"person","aliases":[],
              "description":"万历之子。",
              "evidence":[{"section":2,"quote":"朱常洵是万历之子"}],
              "scope":"setting"}],
             "relations":[{"source":"万历皇帝","target":"朱常洵",
              "type":"亲属","kin":"父子",
              "evidence":[{"section":2,"quote":"朱常洵是万历之子"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '朱常洛是万历长子。万历皇帝登基。'),
          slice(2, '第二节', '朱常洵是万历之子。万历皇帝下诏。'),
        ],
        includesUnread: true,
      );

      // Both sons share the father but are different people: no merge, no
      // review call (descending relation evidence is intentionally weak).
      expect(graph.entities.map((e) => e.name).toSet(),
          {'万历皇帝', '朱常洛', '朱常洵'});
      expect(graph.relations.length, 2);
      expect(graph.mergeLog.where((e) => e['reason'] == 'review'), isEmpty);
    });

    test('merge review failure never fails the generation', () async {
      final provider = _GraphProvider(
        throwOnReview: true,
        responses: {
          1: '''
            {"entities":[{"name":"慈圣太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣太后是万历皇帝生母"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"慈圣太后是万历皇帝生母"}]}]}
          ''',
          2: '''
            {"entities":[{"name":"孝定皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":2,"quote":"孝定皇太后是万历皇帝生母"}],
              "scope":"setting"}],
             "relations":[{"source":"孝定皇太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":2,"quote":"孝定皇太后是万历皇帝生母"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '慈圣太后是万历皇帝生母。'),
          slice(2, '第二节', '孝定皇太后是万历皇帝生母。'),
        ],
        includesUnread: true,
      );

      // Review failed silently: both entities stay, graph still complete.
      expect(graph.entities.length, 3);
      expect(graph.coveredSections, [1, 2]);
      expect(graph.mergeLog.where((e) => e['reason'] == 'review'), isEmpty);
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
        sections: [slice(1, '第一回', '张三登场。完全不相关的正文内容。')],
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

    test('根据X narration does not trigger the citation rule (张居正安排)',
        () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张居正","type":"person","scope":"setting",
              "description":"首辅。",
              "evidence":[{"section":1,"quote":"根据张居正的安排，逢三六九早朝"}]}],
             "relations":[]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '根据张居正的安排，逢三六九早朝。')],
        includesUnread: true,
      );

      // 根据X is narration (X arranged something), not a citation of X: the
      // 据X template must not fire here — the entity stays setting.
      expect(
        graph.entities.single.scope,
        AiGraphEntityScope.setting,
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

    test('relations without evidence are dropped (后验校验)', () async {
      final provider = _GraphProvider(
        responses: {
          1: '''
            {"entities":[{"name":"张三","type":"person","aliases":[],
              "description":"主角。",
              "evidence":[{"section":1,"quote":"张三出场"}],
              "scope":"setting"},
             {"name":"李四","type":"person","aliases":[],
              "description":"配角。",
              "evidence":[{"section":1,"quote":"李四出场"}],
              "scope":"setting"}],
             "relations":[{"source":"张三","target":"李四","type":"同僚",
              "description":"无证据的关系。","evidence":[]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [slice(1, '第一回', '张三出场。李四出场。')],
        includesUnread: true,
      );

      // Provenance is mandatory: an edge without quote-backed evidence never
      // enters the graph, even when both endpoints exist.
      expect(graph.entities.length, 2);
      expect(graph.relations, isEmpty);
      expect(graph.coveredSections, [1]);
    });

    test('review batch is consumed once (no starvation, no re-submit)',
        () async {
      // 12 mentions sharing the same ascending relation, spread over 3
      // batches (5/5/2 sections): batch 1 reviews 4 pairs, batch 2 five,
      // batch 3 the remaining two — later batches must never re-submit
      // consumed pairs (the old code re-submitted the first 10 every time
      // and starved the last pair).
      final sections = <int, Map<String, Object?>>{};
      for (var i = 1; i <= 12; i++) {
        sections[i] = {
          '母$i': '{"name":"母$i","type":"person","aliases":[],'
              '"description":"万历之母。","evidence":[{"section":$i,"quote":"母$i"}],'
              '"scope":"setting"}',
          '皇$i': '{"name":"皇太后$i","type":"person","aliases":[],'
              '"description":"万历之母。","evidence":[{"section":$i,"quote":"皇太后$i"}],'
              '"scope":"setting"}',
        };
      }
      // Six sections per 母/皇 half; the 5/5/2 batch boundaries (1-5, 6-10,
      // 11-12) fall between and inside the two halves, exercising both
      // cross-half and within-half pending accumulation.
      final motherSections = [
        for (var i = 1; i <= 6; i++) i,
      ];
      final queenSections = [
        for (var i = 7; i <= 12; i++) i,
      ];
      final responses = <int, String>{};
      // Section 1 also establishes the shared relation object as a real
      // entity (endpoint grounding drops relations to non-entities).
      const emperor = '{"name":"万历皇帝","type":"person","aliases":[],'
          '"description":"天子。","evidence":[{"section":1,"quote":"万历皇帝"}],'
          '"scope":"setting"}';
      for (final i in motherSections) {
        responses[i] =
            '{"entities":[${sections[i]!['母$i']}'
            '${i == 1 ? ',$emperor' : ''}],'
            '"relations":[{"source":"母$i","target":"万历皇帝","type":"亲属",'
            '"kin":"母子","evidence":[{"section":$i,"quote":"母$i是万历之母"}]}]}';
      }
      for (final i in queenSections) {
        responses[i] =
            '{"entities":[${sections[i]!['皇$i']}],'
            '"relations":[{"source":"皇太后$i","target":"万历皇帝","type":"亲属",'
            '"kin":"母子","evidence":[{"section":$i,"quote":"皇太后$i是万历之母"}]}]}';
      }
      final provider = _GraphProvider(
        reviewVerdicts: '["different","different","different","different",'
            '"different","different","different","different","different","different"]',
        responses: responses,
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          for (final i in [...motherSections, ...queenSections])
            slice(i, '第$i节', '母$i。'),
        ],
        includesUnread: true,
      );

      final reviewRequests = provider.requests
          .where((r) => r.messages.any((m) => m.content.contains('人物身份判定引擎')))
          .toList();
      // With consumption: later batches carry only the leftover pairs and
      // never re-submit earlier ones — the last batch has 2 pending pairs
      // (12 total, cap 10). Without consumption (the old bug) the last batch
      // would re-submit the first 10 at full cap.
      expect(reviewRequests.length, greaterThanOrEqualTo(2));
      final lastPairCount =
          '称谓A'.allMatches(reviewRequests.last.messages.last.content).length;
      expect(lastPairCount, lessThan(10));
      // And each review call submitted a different set of pairs.
      final pairSets = [
        for (final r in reviewRequests)
          '称谓A「([^」]+)」'
              .allMatches(r.messages.last.content)
              .map((m) => m.group(1)!)
              .toSet(),
      ];
      for (var i = 1; i < pairSets.length; i++) {
        expect(
          pairSets[i].intersection(pairSets[i - 1]),
          isEmpty,
          reason: '复核批次不得重复提交已消费的对',
        );
      }
      expect(graph.coveredSections.length, 12);
    });

    test('post-review relations keep fusing instead of duplicating', () async {
      // Section 3 re-mentions the already-fused 慈圣太后→万历皇帝 edge after
      // the 孝定=慈圣 review merged section 2's edge: relationIndex must be
      // rebuilt, so the third chunk fuses into the same relation.
      final provider = _GraphProvider(
        reviewVerdicts: '["same"]',
        responses: {
          1: '''
            {"entities":[{"name":"慈圣太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":1,"quote":"慈圣太后是万历皇帝生母"}],
              "scope":"setting"},
             {"name":"万历皇帝","type":"person","aliases":[],
              "description":"","evidence":[{"section":1,"quote":"万历皇帝"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":1,"quote":"慈圣太后是万历皇帝生母"}]}]}
          ''',
          2: '''
            {"entities":[{"name":"孝定皇太后","type":"person","aliases":[],
              "description":"万历生母。",
              "evidence":[{"section":2,"quote":"孝定皇太后是万历皇帝生母"}],
              "scope":"setting"}],
             "relations":[{"source":"孝定皇太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":2,"quote":"孝定皇太后是万历皇帝生母"}]}]}
          ''',
          3: '''
            {"entities":[{"name":"慈圣太后","type":"person","aliases":[],
              "description":"","evidence":[{"section":3,"quote":"慈圣太后"}],
              "scope":"setting"}],
             "relations":[{"source":"慈圣太后","target":"万历皇帝",
              "type":"亲属","kin":"母子",
              "evidence":[{"section":3,"quote":"慈圣太后与万历母子情深"}]}]}
          ''',
        },
      );

      final graph = await serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: [
          slice(1, '第一节', '慈圣太后是万历皇帝生母。'),
          slice(2, '第二节', '孝定皇太后是万历皇帝生母。'),
          slice(3, '第三节', '慈圣太后与万历母子情深。'),
        ],
        includesUnread: true,
      );

      expect(graph.entities.where((e) => e.name.contains('慈圣')), hasLength(1));
      expect(graph.relations.length, 1);
      expect(graph.relations.single.evidence.length, 3);
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
    this.reviewVerdicts = '[]',
    this.throwOnReview = false,
  });

  /// sectionIndex -> raw JSON body (may be wrapped in ```json fences).
  final Map<int, String> responses;
  final bool invalidJson;

  /// Step-0 display plan body (default: event-driven, organization low).
  final String narrationBody;

  /// JSON array returned by the merge-review call (the 人物身份判定引擎 prompt).
  final String reviewVerdicts;
  final bool throwOnReview;

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
    if (request.messages.any((m) => m.content.contains('人物身份判定引擎'))) {
      if (throwOnReview) throw Exception('review failed');
      return AiCompletionResult(text: reviewVerdicts);
    }
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_settings.dart';

/// Synthetic-book regression baseline (docs/specs/ai-graph.md §5).
///
/// Deliberately NOT bound to any real book: 南国纪事 is a fictional text
/// whose model output plants every known failure mode of the extraction +
/// merge pipeline, so the assertions exercise general quality guarantees
/// instead of one book's quirks. If a future change breaks any of these, the
/// failure is a regression in the pipeline, not a mismatch with a real title.
///
/// Modes covered:
///  - generic-honorific absorption (老太爷 must not swallow 沈老爷子)
///  - flipped kin mirrors (沈小文→沈夫人 母子 vs 沈夫人→沈小文 母子)
///  - kin-less 亲属 edges (沈文→沈夫人 亲属 kin=空 → dropped, 婚配 kept)
///  - scope mislabelling (protagonist 沈武 → restored to setting; real
///    citation 庄周 stays reference)
///  - cross-alias co-reference (沈文 = 沈先生 = 子安, merged, audited)
///  - sibling non-merge (沈文 ≠ 沈武, shared father alone is not identity)

AiBookSectionSlice slice(int index, String label, String text) {
  return AiBookSectionSlice(index: index, label: label, text: text);
}

class _GraphProvider implements AiModelAdapter, AiStructuredOutputAdapter {
  _GraphProvider(this.responses);

  final Map<int, String> responses;
  final List<AiModelJsonRequest> requests = [];

  static const String defaultNarrationBody =
      '{'
      '"features":{"eventDriven":0.8,"characterEnsemble":0.2,'
      '"organization":0.1,"geography":0.1,"essay":0.0},'
      '"defaultView":"events","viewOrder":["events","persons","locations","graph"],'
      '"wantMap":false}';

  @override
  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    final prompt = request.messages.last.text;
    if (request.messages.any((m) => m.text.contains('人物身份判定引擎'))) {
      return const AiModelJsonResult(value: {'verdicts': []});
    }
    if (request.messages.any((m) => m.text.contains('亲属关系方向核验器'))) {
      return const AiModelJsonResult(value: {'relations': []});
    }
    if (request.messages.any((m) => m.text.contains('知识图谱漏项复核器'))) {
      return const AiModelJsonResult(value: {'entities': [], 'relations': []});
    }
    if (request.messages.any((m) => m.text.contains('书籍编辑'))) {
      return const AiModelJsonResult(value: {'entities': []});
    }
    final match = RegExp(r'章节编号：(\d+)').firstMatch(prompt);
    if (match == null) {
      return AiModelJsonResult(
        value: Map<String, dynamic>.from(
          jsonDecode(defaultNarrationBody) as Map,
        ),
      );
    }
    final section = int.parse(match.group(1)!);
    final body = responses[section] ?? '{"entities":[],"relations":[]}';
    return AiModelJsonResult(
      value: Map<String, dynamic>.from(jsonDecode(body) as Map),
    );
  }

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) {
    throw UnimplementedError();
  }

  @override
  String get runtimeName => 'synthetic-graph-test';

  @override
  Future<void> close() async {}
}

void main() {
  // 南国纪事 — a fictional clan saga, six sections.
  final sections = [
    slice(
      1,
      '立家',
      '沈老爷子膝下二子，长子沈文，次子沈武。'
          '沈文字子安，乡里皆称沈先生。沈老爷子将家业托付沈文。',
    ),
    slice(
      2,
      '分家',
      '老太爷去世后，家业由沈文主持。'
          '沈武性情豪迈，与沈文常起争执。沈文沈武终是兄弟阋墙。',
    ),
    slice(
      3,
      '添丁',
      '沈文娶沈夫人为妻，次年得子沈小文。'
          '沈夫人教子甚严，常责沈小文读书。沈小文得母沈夫人教导。',
    ),
    slice(
      4,
      '延师',
      '沈小文拜陈先生为师。沈文与沈武兄弟失和，家业之争愈烈。'
          '陈先生教沈小文经史。',
    ),
    slice(
      5,
      '外放',
      '如庄周所言，小知不及大知。沈武被外放南疆，'
          '督粮饷、练乡勇、修水利、抚流民、整户籍，五年未归。',
    ),
    slice(
      6,
      '承业',
      '沈小文成年，承家业。沈夫人与沈文相守一生。'
          '沈小文治家有方，乡里称善。沈小文常追念沈老爷教诲。',
    ),
  ];

  // Planted model output: each known failure mode appears exactly once.
  final responses = <int, String>{
    1: '''
      {"entities":[
        {"name":"沈老爷子","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":1,"quote":"沈老爷子膝下二子"}]},
        {"name":"沈文","type":"person","aliases":["沈先生","子安"],"scope":"setting",
         "evidence":[{"section":1,"quote":"沈文字子安，乡里皆称沈先生"}]},
        {"name":"沈武","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":1,"quote":"次子沈武"}]}],
       "relations":[
        {"source":"沈老爷子","target":"沈文","type":"亲属","kin":"父子",
         "evidence":[{"section":1,"quote":"沈老爷子膝下二子，长子沈文"}]},
        {"source":"沈老爷子","target":"沈武","type":"亲属","kin":"父子",
         "evidence":[{"section":1,"quote":"次子沈武"}]}]}
    ''',
    2: '''
      {"entities":[
        {"name":"老太爷","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":2,"quote":"老太爷去世后"}]},
        {"name":"沈武","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":2,"quote":"沈武性情豪迈"}]}],
       "relations":[
        {"source":"沈文","target":"沈武","type":"亲属","kin":"兄弟",
         "evidence":[{"section":2,"quote":"沈文沈武终是兄弟阋墙"}]}]}
    ''',
    3: '''
      {"entities":[
        {"name":"沈夫人","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":3,"quote":"沈文娶沈夫人为妻"}]},
        {"name":"沈小文","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":3,"quote":"次年得子沈小文"}]}],
       "relations":[
        {"source":"沈文","target":"沈夫人","type":"亲属","kin":"",
         "evidence":[{"section":3,"quote":"沈文娶沈夫人为妻"}]},
        {"source":"沈文","target":"沈夫人","type":"婚配","kin":"夫妻",
         "evidence":[{"section":3,"quote":"沈文娶沈夫人为妻"}]},
        {"source":"沈夫人","target":"沈小文","type":"亲属","kin":"母子",
         "evidence":[{"section":3,"quote":"沈夫人教子甚严"}]},
        {"source":"沈小文","target":"沈夫人","type":"亲属","kin":"母子",
         "evidence":[{"section":3,"quote":"沈小文得母沈夫人教导"}]}]}
    ''',
    4: '''
      {"entities":[
        {"name":"陈先生","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":4,"quote":"沈小文拜陈先生为师"}]}],
       "relations":[
        {"source":"陈先生","target":"沈小文","type":"师生","kin":"师生",
         "evidence":[{"section":4,"quote":"沈小文拜陈先生为师"}]},
        {"source":"沈文","target":"沈武","type":"敌对","kin":"",
         "evidence":[{"section":4,"quote":"沈文与沈武兄弟失和"}]}]}
    ''',
    5: '''
      {"entities":[
        {"name":"沈武","type":"person","aliases":[],"scope":"reference",
         "evidence":[{"section":5,"quote":"沈武被外放南疆"},
                     {"section":5,"quote":"督粮饷"},
                     {"section":5,"quote":"练乡勇"},
                     {"section":5,"quote":"修水利"},
                     {"section":5,"quote":"抚流民"}]},
        {"name":"庄周","type":"person","aliases":[],"scope":"reference",
         "evidence":[{"section":5,"quote":"如庄周所言"}]}],
       "relations":[]}
    ''',
    6: '''
      {"entities":[
        {"name":"沈小文","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":6,"quote":"沈小文成年"}]},
        {"name":"沈文","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":6,"quote":"沈夫人与沈文相守一生"}]},
        {"name":"沈老爷","type":"person","aliases":[],"scope":"setting",
         "evidence":[{"section":6,"quote":"沈小文常追念沈老爷教诲"}]}],
       "relations":[
        {"source":"沈文","target":"沈小文","type":"亲属","kin":"父子",
         "evidence":[{"section":6,"quote":"沈小文成年，承家业"}]},
        {"source":"沈夫人","target":"沈文","type":"婚配","kin":"夫妻",
         "evidence":[{"section":6,"quote":"沈夫人与沈文相守一生"}]}]}
    ''',
  };

  group('synthetic book 南国纪事 pipeline', () {
    test('end-to-end generation keeps the clan graph correct', () async {
      final provider = _GraphProvider(responses);
      final service = AiBookGraphService(
        isAvailable: () => true,
        openModelAdapter: () => provider,
        settings: () => const AiSettings(model: 'synth-book'),
        packTargetChars: 0,
      );

      final graph = await service.generate(
        bookTitle: '南国纪事',
        sections: sections,
        includesUnread: true,
      );

      final names = graph.entities
          .map((e) => e.name)
          .toSet(); // Core cast exists and is distinct.
      for (final n in ['沈老爷子', '沈文', '沈武', '沈夫人', '沈小文', '陈先生', '庄周']) {
        expect(names, contains(n), reason: '$n 必须在图谱中');
      }
      // Sibling non-merge: shared father alone is not identity.
      expect(names, containsAll(['沈文', '沈武']));
      // Generic honorific never absorbed the patriarch: 沈老爷子 survived
      // the 老太爷 mention (which may live on as its own generic entity).
      expect(names, contains('沈老爷子'));

      // Cross-alias co-reference: 沈先生/子安 folded into 沈文 (model-given
      // aliases) and 沈老爷 merged into 沈老爷子 by the substring rule — the
      // substring merge must be in the audit log.
      final shenWen = graph.entities.firstWhere((e) => e.name == '沈文');
      expect(shenWen.aliases, containsAll(['沈先生', '子安']));
      expect(names, isNot(contains('沈老爷')), reason: '沈老爷 必须合并进 沈老爷子');
      expect(
        graph.mergeLog.any(
          (m) =>
              m['reason'] == 'name' && m['from'] == '沈老爷' && m['to'] == '沈老爷子',
        ),
        isTrue,
        reason: '名称合并必须进入审计日志',
      );

      // Scope: protagonist 沈武 restored to setting; real citation stays.
      final shenWu = graph.entities.firstWhere((e) => e.name == '沈武');
      expect(
        shenWu.scope,
        AiGraphEntityScope.setting,
        reason: '沈武（主角）被误标 reference 必须恢复',
      );
      final zhuangZhou = graph.entities.firstWhere((e) => e.name == '庄周');
      expect(
        zhuangZhou.scope,
        AiGraphEntityScope.reference,
        reason: '庄周（引用）必须保持 reference',
      );

      // Relations: exact expected edge set.
      final edges = {
        for (final r in graph.relations)
          '${r.source}|${r.kin.isEmpty ? r.type : r.kin}|${r.target}',
      };
      expect(edges, contains('沈老爷子|父子|沈文'));
      expect(edges, contains('沈老爷子|父子|沈武'));
      expect(edges, contains('沈文|父子|沈小文'));
      expect(edges, contains('沈夫人|母子|沈小文'));
      expect(edges, contains('陈先生|师生|沈小文'));
      expect(edges, contains('沈文|兄弟|沈武'));
      expect(edges, contains('沈文|夫妻|沈夫人'));
      // Flipped mirror dropped: only the stronger 母子 direction survives.
      expect(edges, isNot(contains('沈小文|母子|沈夫人')), reason: '反向母子边必须被消解');
      // Kin-less 亲属 edge dropped at merge time.
      expect(
        graph.relations.where((r) => r.type == '亲属' && r.kin.isEmpty),
        isEmpty,
        reason: 'kin 空的亲属边必须被丢弃',
      );
      // No duplicate mirror 夫妻 edges (婚配 reverse pairs are not the tree's
      // concern, but a mirror pair with equal strength must not double-count).
      final marriagePairs = graph.relations
          .where((r) => r.type == '婚配')
          .map((r) => ([r.source, r.target]..sort()).join('~'))
          .toSet();
      expect(marriagePairs, hasLength(1), reason: '婚配边不应出现镜像重复');

      // Quality gate: the fully-fixed pipeline reports a clean bill.
      final quality = service.assessGraphQuality(graph);
      expect(
        quality.hasIssues,
        isFalse,
        reason: '门禁应无问题：${quality.issues.join('; ')}',
      );
    });

    test(
      'quality gate flags flipped mirrors, kin-less edges, mislabelled refs',
      () {
        final service = AiBookGraphService(
          isAvailable: () => true,
          openModelAdapter: () => throw UnimplementedError(),
          settings: () => const AiSettings(model: 'synth-book'),
        );
        final dirty = AiBookGraph(
          contentHash: 'dirty',
          generatedAt: DateTime.utc(2026, 8, 7),
          model: 'synth-book',
          includesUnread: false,
          coveredSections: const [1],
          sectionTitles: const {1: '一'},
          entities: [
            AiGraphEntity(
              name: '沈武',
              type: AiGraphEntityType.person,
              scope: AiGraphEntityScope.reference,
              evidence: [
                for (var i = 0; i < 6; i++)
                  AiGraphEvidence(sectionIndex: 1, quote: '沈武事迹$i'),
              ],
              chapterFreq: const {1: 6},
              firstSection: 1,
              lastSection: 1,
            ),
            AiGraphEntity(
              name: '万历皇帝',
              type: AiGraphEntityType.person,
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: '万历')],
              chapterFreq: const {1: 1},
              firstSection: 1,
              lastSection: 1,
            ),
            AiGraphEntity(
              name: '慈圣皇太后',
              type: AiGraphEntityType.person,
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: '慈圣')],
              chapterFreq: const {1: 1},
              firstSection: 1,
              lastSection: 1,
            ),
            AiGraphEntity(
              name: '恭妃王氏',
              type: AiGraphEntityType.person,
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: '恭妃')],
              chapterFreq: const {1: 1},
              firstSection: 1,
              lastSection: 1,
            ),
          ],
          relations: [
            AiGraphRelation(
              source: '万历皇帝',
              target: '慈圣皇太后',
              type: '亲属',
              kin: '母子',
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: 'q1')],
              weight: 1,
            ),
            AiGraphRelation(
              source: '慈圣皇太后',
              target: '万历皇帝',
              type: '亲属',
              kin: '母子',
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: 'q2')],
              weight: 1,
            ),
            AiGraphRelation(
              source: '万历皇帝',
              target: '恭妃王氏',
              type: '亲属',
              kin: '',
              evidence: [AiGraphEvidence(sectionIndex: 1, quote: 'q3')],
              weight: 1,
            ),
          ],
        );

        final report = service.assessGraphQuality(dirty);
        expect(report.reversedKinPairs, 1, reason: '方向冲突的母子镜像必须被标记');
        expect(report.kinlessKinEdges, 1);
        expect(
          report.mislabelledReferences,
          1,
          reason: '高频 reference 人物（无引用句式）必须被标记',
        );
        expect(report.hasIssues, isTrue);
        expect(report.issues.join('; '), contains('沈武'));
      },
    );

    test(
      'generation is deterministic and idempotent on covered sections',
      () async {
        final provider = _GraphProvider(responses);
        final service = AiBookGraphService(
          isAvailable: () => true,
          openModelAdapter: () => provider,
          settings: () => const AiSettings(model: 'synth-book'),
          packTargetChars: 0,
        );

        final first = await service.generate(
          bookTitle: '南国纪事',
          sections: sections,
          includesUnread: true,
        );
        // Incremental run with all sections covered: nothing re-extracts, the
        // graph is returned unchanged (no double-merge, no drift).
        final again = await service.generate(
          bookTitle: '南国纪事',
          sections: sections,
          includesUnread: true,
        );
        expect(again.entities.length, first.entities.length);
        expect(again.relations.length, first.relations.length);
        expect(again.coveredSections, first.coveredSections);
      },
    );
  });
}

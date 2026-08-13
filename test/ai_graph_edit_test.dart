import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_evidence.dart';
import 'package:kaijuan/ai/ai_graph_service.dart';
import 'package:kaijuan/ai/ai_models.dart';

void main() {
  AiGraphEntity person(
    String name, {
    String? identityHint,
    List<String> aliases = const [],
    String description = '',
    int descriptionSection = 0,
    int firstSection = 1,
    int lastSection = 1,
  }) {
    return AiGraphEntity(
      entityId: graphEntityIdFor(
        type: AiGraphEntityType.person,
        name: name,
        identityHint: identityHint ?? '',
      ),
      name: name,
      type: AiGraphEntityType.person,
      identityHint: identityHint ?? '',
      aliases: aliases,
      description: description,
      descriptionSection: descriptionSection,
      evidence: [
        AiGraphEvidence(
          sectionIndex: firstSection,
          quote: '$name 走了进来。',
          progressInSection: 0.1,
          spanResolved: true,
        ),
      ],
      firstSection: firstSection,
      lastSection: lastSection,
    );
  }

  AiGraphEntity location(String name) {
    return AiGraphEntity(
      entityId: graphEntityIdFor(
        type: AiGraphEntityType.location,
        name: name,
        identityHint: '',
      ),
      name: name,
      type: AiGraphEntityType.location,
      evidence: const [
        AiGraphEvidence(sectionIndex: 1, quote: '他们到了这里。', spanResolved: true),
      ],
      firstSection: 1,
      lastSection: 1,
    );
  }

  group('AiBookGraph.mergeEntities', () {
    test('absorbs aliases, evidence and rewires relations', () {
      final keep = person('张三丰', description: '武当掌门');
      final absorb = person(
        '张三',
        aliases: const ['三爷'],
        description: '后来才知道是同一个人',
        descriptionSection: 4,
        firstSection: 2,
        lastSection: 4,
      );
      final other = person('宋远桥');
      final graph = AiBookGraph(
        contentHash: 'h',
        entities: [keep, absorb, other],
        relations: [
          AiGraphRelation(
            sourceId: absorb.id,
            targetId: other.id,
            source: absorb.name,
            target: other.name,
            type: 'father_of',
            evidence: const [
              AiGraphEvidence(
                sectionIndex: 2,
                quote: '他叫宋远桥过来。',
                spanResolved: true,
              ),
            ],
          ),
          AiGraphRelation(
            sourceId: absorb.id,
            targetId: keep.id,
            source: absorb.name,
            target: keep.name,
            type: 'same_as',
            evidence: const [
              AiGraphEvidence(
                sectionIndex: 3,
                quote: '张三就是张三丰。',
                spanResolved: true,
              ),
            ],
          ),
        ],
      );

      final merged = graph.mergeEntities(keepId: keep.id, absorbId: absorb.id)!;
      expect(merged.entities.map((e) => e.id), [keep.id, other.id]);
      final kept = merged.entityById(keep.id)!;
      expect(kept.name, '张三丰');
      expect(kept.aliases, containsAll(['张三', '三爷']));
      expect(kept.description, '武当掌门');
      expect(kept.evidence.length, 2);
      expect(kept.firstSection, 1);
      expect(kept.lastSection, 4);

      expect(merged.relations, hasLength(1));
      final relation = merged.relations.single;
      expect(relation.sourceId, keep.id);
      expect(relation.targetId, other.id);
      expect(relation.source, '张三丰');
      expect(relation.evidence, hasLength(1));

      expect(merged.mergeLog.last['reason'], 'manual');
      expect(merged.mergeLog.last['from'], '张三');
      expect(merged.mergeLog.last['to'], '张三丰');
    });

    test('rejects mixed types and missing ids', () {
      final zhang = person('张三');
      final wudang = location('武当山');
      final graph = AiBookGraph(contentHash: 'h', entities: [zhang, wudang]);
      expect(
        graph.mergeEntities(keepId: zhang.id, absorbId: wudang.id),
        isNull,
      );
      expect(graph.mergeEntities(keepId: zhang.id, absorbId: zhang.id), isNull);
      expect(
        graph.mergeEntities(keepId: zhang.id, absorbId: 'missing'),
        isNull,
      );
    });

    test('drops the absorbed id from hiddenEntityIds without hiding keep', () {
      final keep = person('张三丰');
      final absorb = person('张三');
      final graph = AiBookGraph(
        contentHash: 'h',
        entities: [keep, absorb],
        hiddenEntityIds: [absorb.id],
      );
      final merged = graph.mergeEntities(keepId: keep.id, absorbId: absorb.id)!;
      expect(merged.hiddenEntityIds, isEmpty);
      expect(merged.entityById(keep.id), isNotNull);
    });
  });

  group('AiBookGraph hide / unhide', () {
    test('hide then unhide restores the same id list', () {
      final entity = person('张三');
      final graph = AiBookGraph(contentHash: 'h', entities: [entity]);
      final hidden = graph.hideEntity(entity.id);
      expect(hidden.hiddenEntityIds, [entity.id]);
      expect(hidden.hiddenEntities.single.name, '张三');
      expect(hidden.hideEntity(entity.id), same(hidden));
      expect(hidden.unhideEntity(entity.id).hiddenEntityIds, isEmpty);
    });
  });

  group('extract cost controls', () {
    test('a normal chapter is one shot; only huge spine units split', () {
      expect(AiBookGraphService.chunkText('甲' * 7000), hasLength(1));
      expect(AiBookGraphService.chunkText('甲' * 30000), hasLength(1));
      final split = AiBookGraphService.chunkText('甲' * 50000);
      expect(split, hasLength(greaterThan(1)));
      expect(split.every((chunk) => chunk.length <= 8000 + 160), isTrue);
    });

    test('short consecutive chapters pack into one extract unit', () {
      final chapters = [
        for (var i = 1; i <= 8; i++)
          AiBookSectionSlice(index: i, label: '第$i章', text: '字' * 2000),
      ];
      final packs = AiBookGraphService.packSections(chapters);
      expect(packs.length, lessThan(chapters.length));
      expect(
        packs.fold<int>(0, (sum, pack) => sum + pack.length),
        chapters.length,
      );
      expect(AiBookGraphService.packLabel(packs.first), contains('–'));
    });

    test('a long chapter stays its own pack', () {
      final sections = [
        AiBookSectionSlice(index: 1, label: '长章', text: '甲' * 20000),
        AiBookSectionSlice(index: 2, label: '短章', text: '乙' * 3000),
      ];
      final packs = AiBookGraphService.packSections(sections);
      expect(packs, hasLength(2));
      expect(packs.first.single.label, '长章');
      expect(packs.last.single.label, '短章');
    });

    test('does not pack across a skipped chapter gap', () {
      final sections = [
        AiBookSectionSlice(index: 1, label: '第一章', text: '甲' * 1000),
        AiBookSectionSlice(index: 3, label: '第三章', text: '乙' * 1000),
      ];
      final packs = AiBookGraphService.packSections(sections);
      expect(packs, hasLength(2));
    });

    test('tiny tails attach instead of paying a solo call', () {
      final sections = [
        AiBookSectionSlice(index: 1, label: '第一章', text: '甲' * 15500),
        const AiBookSectionSlice(index: 2, label: '尾巴', text: '完'),
      ];
      final packs = AiBookGraphService.packSections(sections);
      expect(packs, hasLength(1));
      expect(packs.single.map((section) => section.label), ['第一章', '尾巴']);
    });

    test('packTarget 0 keeps one section per call', () {
      final sections = [
        AiBookSectionSlice(index: 1, label: '一', text: '甲' * 1000),
        AiBookSectionSlice(index: 2, label: '二', text: '乙' * 1000),
      ];
      expect(
        AiBookGraphService.packSections(sections, targetChars: 0),
        hasLength(2),
      );
    });

    test(
      'model-call budget follows body length, not a flat per-section fee',
      () {
        final short = [
          const AiBookSectionSlice(index: 1, label: '短', text: '短正文'),
        ];
        final long = [
          for (var i = 1; i <= 12; i++)
            AiBookSectionSlice(index: i, label: '第$i章', text: '章' * 50000),
        ];
        expect(AiBookGraphService.modelCallBudgetFor(short), 160);
        expect(
          AiBookGraphService.modelCallBudgetFor(long),
          greaterThan(AiBookGraphService.modelCallBudgetFor(short)),
        );
      },
    );

    test('JSON parse errors are not treated as a provider outage', () {
      expect(
        AiBookGraphService.isProviderOutage(
          AiModelStructuredOutputFormatException(),
        ),
        isFalse,
      );
      expect(
        AiBookGraphService.isProviderOutage(
          const AiGraphGenerationException('图谱抽取格式无效，请重试'),
        ),
        isFalse,
      );
      expect(
        AiBookGraphService.isProviderOutage(AiProviderException('连接超时')),
        isTrue,
      );
    });

    test('quote location ignores punctuation drift', () {
      expect(
        AiGraphEvidenceGrounder.locateQuote('他说：“张居正已死。”', '他说，张居正已死'),
        isNotNull,
      );
    });

    test('quote location prefers the hit near the entity name', () {
      const text = '开场一句无关的「走了进来」。后文才写张三走了进来。';
      final first = AiGraphEvidenceGrounder.locateQuote(text, '走了进来');
      final nearName = AiGraphEvidenceGrounder.locateQuote(
        text,
        '走了进来',
        anchors: const ['张三'],
      );
      expect(first, isNotNull);
      expect(nearName, isNotNull);
      expect(nearName!, greaterThan(first!));
    });

    test('short quotes that omit the entity name stay unresolved', () {
      expect(
        AiGraphEvidenceGrounder.locateQuote(
          '他说了许多。后文才出现张三。',
          '他说',
          anchors: const ['张三'],
        ),
        isNull,
      );
      expect(
        AiGraphEvidenceGrounder.locateQuote(
          '张三走了进来。',
          '张三',
          anchors: const ['张三'],
        ),
        isNotNull,
      );
    });

    test('glean types stay off when persons exist and narration is quiet', () {
      const person = AiGraphEntity(
        name: '张三',
        type: AiGraphEntityType.person,
        evidence: [AiGraphEvidence(sectionIndex: 1, quote: '张三')],
      );
      expect(
        AiBookGraphService.missingTypesToGlean(entities: [person]),
        isEmpty,
      );
      expect(
        AiBookGraphService.missingTypesToGlean(
          entities: [person],
          narration: const AiNarrationPlan(
            features: {
              'eventDriven': 0.8,
              'characterEnsemble': 0.2,
              'organization': 0.1,
              'geography': 0.1,
              'essay': 0.0,
            },
            defaultView: 'events',
            viewOrder: ['events', 'persons'],
          ),
        ),
        isEmpty,
      );
    });

    test('glean recovers emphasized organization or geography gaps', () {
      const person = AiGraphEntity(
        name: '张三',
        type: AiGraphEntityType.person,
        evidence: [AiGraphEvidence(sectionIndex: 1, quote: '张三')],
      );
      expect(
        AiBookGraphService.missingTypesToGlean(
          entities: [person],
          narration: const AiNarrationPlan(
            features: {'organization': 0.9, 'geography': 0.2},
            defaultView: 'organizations',
            viewOrder: ['organizations', 'persons'],
          ),
        ),
        [AiGraphEntityType.organization],
      );
      expect(
        AiBookGraphService.missingTypesToGlean(
          entities: [person],
          narration: const AiNarrationPlan(
            features: {'organization': 0.2, 'geography': 0.8},
            defaultView: 'locations',
            viewOrder: ['locations', 'persons'],
          ),
        ),
        [AiGraphEntityType.location],
      );
    });
  });

  group('AiGraphProgress labels', () {
    test('names the current chapter and resume / retry verbs', () {
      expect(AiGraphProgress.analyzingSection(title: '第五章'), '正在分析 · 第五章');
      expect(
        AiGraphProgress.analyzingSection(title: '第五章', resume: true),
        '接着分析 · 第五章',
      );
      expect(
        AiGraphProgress.analyzingSection(title: '  第三章  ', retry: true),
        '正在重试 · 第三章',
      );
      expect(AiGraphProgress.analyzingSection(title: ''), '正在分析');
      expect(
        AiGraphProgress.analyzingSection(title: '第五章', chunk: 3, chunks: 12),
        '正在分析 · 第五章（3/12）',
      );
      expect(
        AiGraphProgress.analyzingSection(title: '第三章', waitedSeconds: 15),
        '正在分析 · 第三章 · 已 15 秒',
      );
      expect(AiGraphProgress.startingExtraction(resume: false), '正在抽取实体与关系');
      expect(
        AiGraphProgress.startingExtraction(resume: true, title: '第四章'),
        '接着从「第四章」继续',
      );
      expect(AiGraphProgress.startingExtraction(resume: true), '接着分析未完成的章节');
    });
  });
}

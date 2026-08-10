import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_settings.dart';
import 'package:kaijuan/ai/book_mind_map_workflow.dart';

void main() {
  const sections = [
    AiBookSectionSlice(
      index: 1,
      sourceSectionIndex: 1,
      label: '第一章',
      text: '第一章证据说明问题。第一章继续展开论据。',
    ),
    AiBookSectionSlice(
      index: 2,
      sourceSectionIndex: 2,
      label: '第二章',
      text: '第二章证据回应问题。第二章给出结论。',
    ),
  ];

  Map<String, dynamic> batch() => {
    'batchId': 'm001',
    'coveredSections': [1, 2],
    'branches': [
      {
        'title': '问题提出',
        'summary': '第一章提出就业取舍的核心问题，并从政策背景展开具体论据。',
        'evidence': [
          {'sectionId': 1, 'quote': '第一章证据'},
        ],
      },
      {
        'title': '回应结论',
        'summary': '第二章结合现实后果回应取舍问题，并给出全书的明确结论。',
        'evidence': [
          {'sectionId': 2, 'quote': '第二章证据'},
        ],
      },
      {
        'title': '影响延伸',
        'summary': '两章共同说明政策取舍会同时改变就业稳定、长期发展与个人机会。',
        'evidence': [
          {'sectionId': 2, 'quote': '给出结论'},
        ],
      },
    ],
  };

  Map<String, dynamic> finalTree() => {
    'contentKind': 'argumentative',
    'coveredSections': [1, 2],
    'nodes': [
      {
        'tempId': 'root',
        'parentTempId': null,
        'order': 0,
        'title': '全书',
        'summary': '全书先提出就业取舍问题，再用两章论证政策选择及其最终代价。',
        'evidence': [],
      },
      {
        'tempId': 'question',
        'parentTempId': 'root',
        'order': 0,
        'title': '问题提出',
        'summary': '第一章提出就业与发展如何取舍的核心问题，并交代争议背景。',
        'evidence': [
          {'sectionId': 1, 'quote': '第一章证据'},
        ],
      },
      {
        'tempId': 'argument',
        'parentTempId': 'question',
        'order': 0,
        'title': '论据展开',
        'summary': '作者从政策目标与现实约束两方面展开论据，解释取舍为何困难。',
        'evidence': [
          {'sectionId': 1, 'quote': '展开论据'},
        ],
      },
      {
        'tempId': 'reply',
        'parentTempId': 'root',
        'order': 1,
        'title': '回应结论',
        'summary': '第二章回应前述问题，并把政策选择带来的影响归纳为明确结论。',
        'evidence': [
          {'sectionId': 2, 'quote': '第二章证据'},
        ],
      },
      {
        'tempId': 'reply-detail',
        'parentTempId': 'reply',
        'order': 0,
        'title': '回应过程',
        'summary': '章节通过事实与因果分析逐步回应核心问题，说明不同选择的后果。',
        'evidence': [
          {'sectionId': 2, 'quote': '回应问题'},
        ],
      },
      {
        'tempId': 'conclusion',
        'parentTempId': 'reply',
        'order': 1,
        'title': '最终结论',
        'summary': '作者最终指出短期保就业会伴随长期发展代价，需要重新权衡政策目标。',
        'evidence': [
          {'sectionId': 2, 'quote': '给出结论'},
        ],
      },
    ],
  };

  Map<String, dynamic> longChapterTree() => {
    'contentKind': 'argumentative',
    'coveredSections': [6],
    'nodes': [
      {
        'tempId': 'root',
        'parentTempId': null,
        'order': 0,
        'title': '章节论证',
        'summary': '本章从背景判断、政策推进和结果代价三个阶段完整说明核心主张。',
        'evidence': [],
      },
      for (final branch in [
        ('background', '背景判断', '开篇标记'),
        ('process', '政策过程', '第一处遗漏标记'),
        ('cost', '结果代价', '第二处遗漏标记'),
      ].indexed) ...[
        {
          'tempId': branch.$2.$1,
          'parentTempId': 'root',
          'order': branch.$1,
          'title': branch.$2.$2,
          'summary': '${branch.$2.$2}围绕章节主张补充具体原因、事实与阶段性结论。',
          'evidence': [
            {'sectionId': 6, 'quote': branch.$2.$3},
          ],
        },
        for (var detail = 0; detail < 2; detail++)
          {
            'tempId': '${branch.$2.$1}-$detail',
            'parentTempId': branch.$2.$1,
            'order': detail,
            'title': '${branch.$2.$2}${detail + 1}',
            'summary': '${branch.$2.$2}第 ${detail + 1} 层进一步说明关键事实如何影响政策判断与结果。',
            'evidence': [
              {'sectionId': 6, 'quote': branch.$2.$3},
            ],
          },
      ],
    ],
  };

  Map<String, dynamic> minimalLongChapterTree() => {
    'contentKind': 'argumentative',
    'coveredSections': [6],
    'nodes': [
      {
        'tempId': 'root',
        'parentTempId': null,
        'order': 0,
        'title': '章节论证',
        'summary': '本章围绕政策背景与执行过程，说明不同选择如何改变最终代价。',
        'evidence': [],
      },
      for (final node in [
        ('a', '背景判断', 'root', 0),
        ('a1', '背景细节', 'a', 0),
        ('b', '政策过程', 'root', 1),
        ('b1', '过程细节', 'b', 0),
        ('b2', '结果代价', 'b', 1),
      ])
        {
          'tempId': node.$1,
          'parentTempId': node.$3,
          'order': node.$4,
          'title': node.$2,
          'summary': '${node.$2}提炼正文中实际存在的原因、过程或结果，并说明它与核心主张的关系。',
          'evidence': [
            {'sectionId': 6, 'quote': '开篇标记'},
          ],
        },
    ],
  };

  List<AiBookSectionSlice> largeSections() => [
    AiBookSectionSlice(
      index: 1,
      sourceSectionIndex: 1,
      label: '第一章',
      text: List.filled(1200, '第一章证据说明问题。第一章继续展开论据。').join(),
    ),
    AiBookSectionSlice(
      index: 2,
      sourceSectionIndex: 2,
      label: '第二章',
      text: List.filled(1200, '第二章证据回应问题。第二章给出结论。').join(),
    ),
  ];

  List<AiBookSectionSlice> twoBatchSections() => [
    for (var index = 1; index <= 14; index++)
      AiBookSectionSlice(
        index: index,
        sourceSectionIndex: index,
        label: '第 $index 章',
        text: List.filled(450, '第 $index 章正文包含观点、事实、例子与结论。').join(),
      ),
  ];

  Map<String, dynamic> batchFor(String id, List<int> coveredSections) => {
    'batchId': id,
    'coveredSections': coveredSections,
    'branches': [
      {
        'title': '$id 主题',
        'summary': '$id 从对应章节提炼具体观点、事实、例子与结论。',
        'evidence': [],
      },
    ],
  };

  Map<String, dynamic> twoBatchFinalTree() => {
    'contentKind': 'mixed',
    'coveredSections': [for (var index = 1; index <= 14; index++) index],
    'nodes': [
      {
        'tempId': 'root',
        'parentTempId': null,
        'order': 0,
        'title': '全书主题',
        'summary': '全书综合十四章中的具体观点、事实、例子与结论形成完整主题结构。',
        'evidence': [],
      },
    ],
  };

  Map<String, dynamic> largeFinalTree() {
    final tree = finalTree();
    final nodes = tree['nodes']! as List<Map<String, Object?>>;
    nodes.addAll([
      for (var index = 1; index <= 3; index++)
        {
          'tempId': 'argument-$index',
          'parentTempId': 'question',
          'order': index,
          'title': '背景事实$index',
          'summary': '第一章的第 $index 组事实继续解释政策问题形成的现实约束与具体影响。',
          'evidence': [
            {'sectionId': 1, 'quote': '第一章证据'},
          ],
        },
      for (var index = 2; index <= 4; index++)
        {
          'tempId': 'reply-$index',
          'parentTempId': 'reply',
          'order': index,
          'title': '结论影响$index',
          'summary': '第二章的第 $index 组结论说明政策取舍如何影响就业、发展与个人机会。',
          'evidence': [
            {'sectionId': 2, 'quote': '第二章证据'},
          ],
        },
      {
        'tempId': 'impact',
        'parentTempId': 'root',
        'order': 2,
        'title': '综合影响',
        'summary': '两章共同说明政策取舍会同时改变就业稳定、长期发展与个人机会。',
        'evidence': [
          {'sectionId': 2, 'quote': '给出结论'},
        ],
      },
      {
        'tempId': 'impact-detail',
        'parentTempId': 'impact',
        'order': 0,
        'title': '机会变化',
        'summary': '就业政策的短期保护会进一步改变年轻人的进入机会和长期职业路径。',
        'evidence': [
          {'sectionId': 2, 'quote': '第二章证据'},
        ],
      },
    ]);
    return tree;
  }

  BookMindMapWorkflow workflow(_FakeMindMapAdapter adapter) {
    return BookMindMapWorkflow(
      isAvailable: () => true,
      openModelAdapter: () => adapter,
      settings: () => const AiSettings(model: 'mind-map-test'),
    );
  }

  test(
    'generates structured tree, canonical ids and grounded evidence',
    () async {
      final adapter = _FakeMindMapAdapter([finalTree()]);
      final checkpoints = <AiMindMapCheckpoint>[];
      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
        onCheckpoint: (value) async => checkpoints.add(value),
      );
      expect(adapter.closed, isTrue);
      expect(result.nodes.map((node) => node.nodeId), [
        'mm001',
        'mm002',
        'mm003',
        'mm004',
        'mm005',
        'mm006',
      ]);
      expect(result.nodes[1].evidence.single.spanResolved, isTrue);
      expect(checkpoints, isEmpty);
      expect(adapter.calls, 1);
    },
  );

  test('keeps a single chapter intact within the batch budget', () async {
    final body =
        '开篇标记'
        '${List.filled(2400, '甲').join()}'
        '第一处遗漏标记'
        '${List.filled(2400, '乙').join()}'
        '中段标记'
        '${List.filled(2400, '丙').join()}'
        '第二处遗漏标记'
        '${List.filled(2400, '丁').join()}'
        '尾部标记';
    final adapter = _FakeMindMapAdapter([longChapterTree()]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '长章节测试',
      sections: [
        AiBookSectionSlice(
          index: 6,
          sourceSectionIndex: 6,
          label: '第一章',
          text: body,
        ),
      ],
    );

    final batchInput = adapter.requests.first.messages.last.text;
    expect(batchInput, contains('第一处遗漏标记'));
    expect(batchInput, contains('第二处遗漏标记'));
    expect(adapter.requests.first.messages.first.text, contains('不能只读取章节标题'));
    expect(result.nodes, hasLength(10));
    final evidence = result.nodes
        .expand((node) => node.evidence)
        .toList(growable: false);
    expect(evidence.map((item) => item.sectionIndex).toSet(), {6});
    expect(
      evidence.map((item) => item.progressInSection).toSet(),
      hasLength(3),
    );
    expect(adapter.calls, 1);
  });

  test('accepts a compact substantive tree without density quotas', () async {
    final body = '开篇标记第一处遗漏标记第二处遗漏标记${List.filled(4000, '正文').join()}';
    final adapter = _FakeMindMapAdapter([minimalLongChapterTree()]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '长章节测试',
      sections: [
        AiBookSectionSlice(
          index: 6,
          sourceSectionIndex: 6,
          label: '第一章',
          text: body,
        ),
      ],
    );

    expect(result.nodes, hasLength(6));
    expect(adapter.calls, 1);
    expect(
      adapter.requests.single.messages.first.text,
      contains('有多少有效主题就生成多少节点'),
    );
  });

  test('accepts more than twelve direct branches', () async {
    final tree = {
      'contentKind': 'reference',
      'coveredSections': [1, 2],
      'nodes': [
        {
          'tempId': 'root',
          'parentTempId': null,
          'order': 0,
          'title': '全书主题',
          'summary': '全书系统整理了多个并列主题，每个主题都有独立的正文内容。',
          'evidence': [],
        },
        for (var index = 0; index < 13; index++)
          {
            'tempId': 'branch-$index',
            'parentTempId': 'root',
            'order': index,
            'title': '主题 ${index + 1}',
            'summary': '该主题根据正文归纳一组独立观点与具体结论。',
            'evidence': [
              {
                'sectionId': index.isEven ? 1 : 2,
                'quote': index.isEven ? '第一章证据' : '第二章证据',
              },
            ],
          },
      ],
    };
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '多分支测试',
      sections: sections,
    );

    expect(result.nodes, hasLength(14));
    expect(
      result.nodes.where((node) => node.parentId == 'mm001'),
      hasLength(13),
    );
    expect(adapter.calls, 1);
  });

  test(
    'retries malformed structured JSON without accepting partial nodes',
    () async {
      final body =
          '开篇标记第一处遗漏标记第二处遗漏标记'
          '${List.filled(300, '正文论证与事实说明。').join()}';
      final adapter = _FakeMindMapAdapter([
        AiModelStructuredOutputFormatException(),
        longChapterTree(),
      ]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '结构化输出测试',
        sections: [
          AiBookSectionSlice(
            index: 6,
            sourceSectionIndex: 6,
            label: '第一章',
            text: body,
          ),
        ],
      );

      expect(adapter.calls, 2);
      expect(result.nodes, hasLength(10));
      expect(
        adapter.requests.last.messages.first.text,
        contains('JSON 语法无效或不完整'),
      );
    },
  );

  test(
    'rejects a title-only placeholder summary and retries with reason',
    () async {
      final invalid = finalTree();
      final rows = invalid['nodes']! as List<Map<String, Object?>>;
      rows.first['summary'] = '全书结构';
      final adapter = _FakeMindMapAdapter([invalid, finalTree()]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      );

      expect(result.nodes, hasLength(6));
      expect(adapter.calls, 2);
      expect(
        adapter.requests.last.messages.first.text,
        contains('根节点 summary 必须概括正文中心结论'),
      );
    },
  );

  test(
    'matching checkpoint resumes without repeating completed batch',
    () async {
      final fingerprint = aiMindMapScopeFingerprint(
        contentHash: 'a' * 64,
        workKey: null,
        sectionIndices: const [1, 2],
      );
      final adapter = _FakeMindMapAdapter([largeFinalTree()]);
      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: largeSections(),
        checkpoint: AiMindMapCheckpoint(
          contentHash: 'a' * 64,
          workKey: null,
          scopeFingerprint: fingerprint,
          completedBatches: [batch()],
        ),
      );
      expect(adapter.calls, 1);
      expect(result.nodes, hasLength(14));
    },
  );

  test('large ranges checkpoint batches before the final reduction', () async {
    final adapter = _FakeMindMapAdapter([batch(), largeFinalTree()]);
    final checkpoints = <AiMindMapCheckpoint>[];

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '大范围测试',
      sections: largeSections(),
      onCheckpoint: (value) async => checkpoints.add(value),
    );

    expect(result.nodes, hasLength(14));
    expect(adapter.calls, 2);
    expect(checkpoints.single.completedBatches.single['batchId'], 'm001');
  });

  test(
    'whole-book input uses larger batches to reduce model round trips',
    () async {
      final wholeBookSections = [
        for (var index = 1; index <= 8; index++)
          AiBookSectionSlice(
            index: index,
            sourceSectionIndex: index,
            label: '第 $index 章',
            text: List.filled(400, '每节正文内容用于跨章综合。').join(),
          ),
      ];
      final covered = [for (var index = 1; index <= 8; index++) index];
      final adapter = _FakeMindMapAdapter([
        {
          'batchId': 'm001',
          'coveredSections': covered,
          'branches': [
            {
              'title': '跨章主题',
              'summary': '八个章节共同展开了一组相互关联的观点与结论。',
              'evidence': [],
            },
          ],
        },
        {
          'contentKind': 'mixed',
          'coveredSections': covered,
          'nodes': [
            {
              'tempId': 'root',
              'parentTempId': null,
              'order': 0,
              'title': '全书主题',
              'summary': '全书通过八个章节整体说明了主题的展开过程与最终结论。',
              'evidence': [],
            },
          ],
        },
      ]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '整书批次测试',
        sections: wholeBookSections,
      );

      expect(result.scopeSectionIndices, covered);
      expect(result.nodes, hasLength(1));
      expect(adapter.calls, 2);
    },
  );

  test('independent whole-book batches run with bounded concurrency', () async {
    final adapter = _FakeMindMapAdapter([
      batchFor('m001', [for (var index = 1; index <= 8; index++) index]),
      batchFor('m002', [for (var index = 9; index <= 14; index++) index]),
      twoBatchFinalTree(),
    ], delay: const Duration(milliseconds: 10));

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '并发批次测试',
      sections: twoBatchSections(),
    );

    expect(result.scopeSectionIndices, [
      for (var index = 1; index <= 14; index++) index,
    ]);
    expect(adapter.calls, 3);
    expect(adapter.maxInFlight, 2);
  });

  test('checkpoints a successful peer when a concurrent batch fails', () async {
    final checkpoints = <AiMindMapCheckpoint>[];
    final adapter = _FakeMindMapAdapter([
      AiProviderException('第一批失败'),
      batchFor('m002', [for (var index = 9; index <= 14; index++) index]),
    ], delay: const Duration(milliseconds: 10));

    await expectLater(
      workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '并发失败测试',
        sections: twoBatchSections(),
        onCheckpoint: (value) async => checkpoints.add(value),
      ),
      throwsA(isA<AiProviderException>()),
    );

    expect(adapter.calls, 2);
    expect(adapter.maxInFlight, 2);
    expect(checkpoints, hasLength(1));
    expect(checkpoints.single.completedBatches.single['batchId'], 'm002');
  });

  test(
    'resume skips a non-leading batch completed by a failed window',
    () async {
      final scope = twoBatchSections();
      final checkpoint = AiMindMapCheckpoint(
        contentHash: 'a' * 64,
        workKey: null,
        scopeFingerprint: aiMindMapScopeFingerprint(
          contentHash: 'a' * 64,
          workKey: null,
          sectionIndices: scope.map((section) => section.index),
        ),
        completedBatches: [
          batchFor('m002', [for (var index = 9; index <= 14; index++) index]),
        ],
      );
      final adapter = _FakeMindMapAdapter([
        batchFor('m001', [for (var index = 1; index <= 8; index++) index]),
        twoBatchFinalTree(),
      ]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '并发恢复测试',
        sections: scope,
        checkpoint: checkpoint,
      );

      expect(result.nodes, hasLength(1));
      expect(adapter.calls, 2);
      expect(adapter.requests.first.messages.last.text, contains('批次 m001'));
    },
  );

  test('final output must cover every frozen section', () async {
    final incomplete = finalTree()..['coveredSections'] = [1];
    final adapter = _FakeMindMapAdapter([incomplete, finalTree()]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '覆盖测试',
      sections: sections,
    );

    expect(result.nodes, hasLength(6));
    expect(
      adapter.requests.last.messages.first.text,
      contains('coveredSections 必须精确覆盖冻结范围'),
    );
  });

  test('invalid batch retries with a concrete validation reason', () async {
    final incomplete = batch()..['coveredSections'] = [1];
    final adapter = _FakeMindMapAdapter([
      incomplete,
      batch(),
      largeFinalTree(),
    ]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '批次修复测试',
      sections: largeSections(),
    );

    expect(result.nodes, hasLength(14));
    expect(
      adapter.requests[1].messages.first.text,
      contains('coveredSections 必须完整且只包含当前批次'),
    );
  });

  test('cancelled run closes adapter before any model request', () async {
    final cancel = CancelToken()..cancel();
    final adapter = _FakeMindMapAdapter([finalTree()]);
    await expectLater(
      workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
        cancelToken: cancel,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(adapter.calls, 0);
    expect(adapter.closed, isTrue);
  });

  test(
    'invalid parent reference fails instead of saving a partial tree',
    () async {
      final invalid = finalTree();
      final rows = invalid['nodes']! as List<Map<String, Object?>>;
      rows[1]['parentTempId'] = 'missing';
      final adapter = _FakeMindMapAdapter([invalid, invalid, invalid]);
      await expectLater(
        workflow(adapter).generate(
          contentHash: 'a' * 64,
          workKey: null,
          bookTitle: '测试书',
          sections: sections,
        ),
        throwsA(isA<AiProviderException>()),
      );
      expect(adapter.closed, isTrue);
    },
  );

  test(
    'direct generation retries with the deterministic validation reason',
    () async {
      final invalid = finalTree();
      final rows = invalid['nodes']! as List<Map<String, Object?>>;
      rows[1]['parentTempId'] = 'missing';
      final adapter = _FakeMindMapAdapter([invalid, finalTree()]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      );

      expect(result.nodes, hasLength(6));
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.messages.first.text,
        contains('parentTempId 引用了不存在的节点'),
      );
    },
  );

  test('drops model-added root evidence deterministically', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows.first['evidence'] = [
      {'sectionId': 1, 'quote': '第一章证据'},
    ];
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );

    expect(result.nodes.first.evidence, isEmpty);
    expect(adapter.calls, 1);
  });

  test('abstract group inherits evidence from grounded descendant', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[1]['evidence'] = <Object?>[];
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );

    expect(result.nodes[1].title, '问题提出');
    expect(result.nodes[1].evidence.single.quote, '展开论据');
    expect(result.nodes[1].evidence.single.spanResolved, isTrue);
  });

  test('leaf without evidence remains a valid summary node', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]['evidence'] = <Object?>[];
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );

    expect(result.nodes[2].evidence, isEmpty);
  });

  test('ungrounded leaf does not reject an otherwise valid tree', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]
      ..['title'] = '陌生主题'
      ..['summary'] = '这段内容与所有批次主题完全没有共同信息。'
      ..['evidence'] = <Object?>[];
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );
    expect(result.nodes[2].title, '陌生主题');
    expect(result.nodes[2].evidence, isEmpty);
  });

  test(
    'drops an unresolved evidence quote without rejecting the tree',
    () async {
      final tree = finalTree();
      final rows = tree['nodes']! as List<Map<String, Object?>>;
      rows[2]['evidence'] = [
        {'sectionId': 1, 'quote': '模型改写后无法直接定位的句子'},
      ];
      final adapter = _FakeMindMapAdapter([tree]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      );

      expect(result.nodes[2].evidence, isEmpty);
    },
  );

  test('does not fabricate an evidence quote from node semantics', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]['evidence'] = [
      {'sectionId': 1, 'quote': '模型漏掉了原始引文'},
    ];
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );

    expect(result.nodes[2].evidence, isEmpty);
  });

  test('cross-section evidence mismatch leaves the node ungrounded', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]['evidence'] = [
      {'sectionId': 1, 'quote': '模型改写后无法直接定位的句子'},
    ];
    final adapter = _FakeMindMapAdapter([tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );
    expect(result.nodes[2].evidence, isEmpty);
  });
}

class _FakeMindMapAdapter implements AiModelAdapter, AiStructuredOutputAdapter {
  _FakeMindMapAdapter(this.outputs, {this.delay = Duration.zero});

  final List<Object> outputs;
  final Duration delay;
  final List<AiModelJsonRequest> requests = [];
  var calls = 0;
  var inFlight = 0;
  var maxInFlight = 0;
  var closed = false;

  @override
  String get runtimeName => 'fake-mind-map';

  @override
  Future<AiModelJsonResult> completeJson(
    AiModelJsonRequest request, {
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    requests.add(request);
    final output = outputs[calls++];
    inFlight += 1;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      cancelToken?.throwIfCancelled();
      if (output is Exception) throw output;
      return AiModelJsonResult(value: Map<String, dynamic>.from(output as Map));
    } finally {
      inFlight -= 1;
    }
  }

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) => const Stream.empty();

  @override
  Future<void> close() async => closed = true;
}

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
    ],
  };

  Map<String, dynamic> finalTree() => {
    'contentKind': 'argumentative',
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
    'nodes': [
      {
        'tempId': 'root',
        'parentTempId': null,
        'order': 0,
        'title': '章节论证',
        'summary': '章节论证结构。',
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
          'summary': '${node.$2}的具体内容。',
          'evidence': [
            {'sectionId': 6, 'quote': '开篇标记'},
          ],
        },
    ],
  };

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
      final adapter = _FakeMindMapAdapter([batch(), finalTree()]);
      final checkpoints = <AiMindMapCheckpoint>[];
      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
        onCheckpoint: (value) async => checkpoints.add(value),
      );
      expect(adapter.calls, 2);
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
      expect(checkpoints.single.completedBatches.single['batchId'], 'm001');
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

  test('rejects a schema-minimum tree for a long chapter', () async {
    final body = '开篇标记第一处遗漏标记第二处遗漏标记${List.filled(4000, '正文').join()}';
    final adapter = _FakeMindMapAdapter([
      minimalLongChapterTree(),
      longChapterTree(),
    ]);

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

    expect(result.nodes, hasLength(10));
    expect(adapter.requests.last.messages.first.text, contains('至少需要 10 个节点'));
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
      final adapter = _FakeMindMapAdapter([batch(), invalid, finalTree()]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      );

      expect(result.nodes, hasLength(6));
      expect(adapter.calls, 3);
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
      final adapter = _FakeMindMapAdapter([finalTree()]);
      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
        checkpoint: AiMindMapCheckpoint(
          contentHash: 'a' * 64,
          workKey: null,
          scopeFingerprint: fingerprint,
          completedBatches: [batch()],
        ),
      );
      expect(adapter.calls, 1);
      expect(result.nodes, hasLength(6));
    },
  );

  test('cancelled run closes adapter before any model request', () async {
    final cancel = CancelToken()..cancel();
    final adapter = _FakeMindMapAdapter([batch(), finalTree()]);
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
      final adapter = _FakeMindMapAdapter([batch(), invalid, invalid]);
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
    'final reduce retries with the deterministic validation reason',
    () async {
      final invalid = finalTree();
      final rows = invalid['nodes']! as List<Map<String, Object?>>;
      rows[1]['parentTempId'] = 'missing';
      final adapter = _FakeMindMapAdapter([batch(), invalid, finalTree()]);

      final result = await workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      );

      expect(result.nodes, hasLength(6));
      expect(adapter.requests, hasLength(3));
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
    final adapter = _FakeMindMapAdapter([batch(), tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );

    expect(result.nodes.first.evidence, isEmpty);
    expect(adapter.calls, 2);
  });

  test('abstract group inherits evidence from grounded descendant', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[1]['evidence'] = <Object?>[];
    final adapter = _FakeMindMapAdapter([batch(), tree]);

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
    final adapter = _FakeMindMapAdapter([batch(), tree]);

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
    final adapter = _FakeMindMapAdapter([batch(), tree]);

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
      final adapter = _FakeMindMapAdapter([batch(), tree]);

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
    final summary = batch();
    final branches = summary['branches']! as List;
    branches.add(<String, Object>{
      'title': '论据展开',
      'summary': '第一章围绕核心问题继续展开论据。',
      'evidence': [
        {'sectionId': 1, 'quote': '展开论据'},
      ],
    });
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]['evidence'] = [
      {'sectionId': 1, 'quote': '模型漏掉了原始引文'},
    ];
    final adapter = _FakeMindMapAdapter([summary, tree]);

    final result = await workflow(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      sections: sections,
    );

    expect(result.nodes[2].evidence, isEmpty);
  });

  test('cross-section evidence mismatch leaves the node ungrounded', () async {
    final summary = batch();
    final branches = summary['branches']! as List<Map<String, Object?>>;
    branches[0]['evidence'] = [
      {'sectionId': 2, 'quote': '第二章证据'},
    ];
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]['evidence'] = [
      {'sectionId': 1, 'quote': '模型改写后无法直接定位的句子'},
    ];
    final adapter = _FakeMindMapAdapter([summary, tree]);

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
  _FakeMindMapAdapter(this.outputs);

  final List<Object> outputs;
  final List<AiModelJsonRequest> requests = [];
  var calls = 0;
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
    if (output is Exception) throw output;
    return AiModelJsonResult(value: Map<String, dynamic>.from(output as Map));
  }

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) => const Stream.empty();

  @override
  Future<void> close() async => closed = true;
}

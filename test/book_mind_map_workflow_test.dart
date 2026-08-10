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
        'summary': '第一章提出核心问题并展开论据。',
        'evidence': [
          {'sectionId': 1, 'quote': '第一章证据'},
        ],
      },
      {
        'title': '回应结论',
        'summary': '第二章回应问题并给出结论。',
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
        'summary': '全书结构',
        'evidence': [],
      },
      {
        'tempId': 'question',
        'parentTempId': 'root',
        'order': 0,
        'title': '问题提出',
        'summary': '提出核心问题。',
        'evidence': [
          {'sectionId': 1, 'quote': '第一章证据'},
        ],
      },
      {
        'tempId': 'argument',
        'parentTempId': 'question',
        'order': 0,
        'title': '论据展开',
        'summary': '围绕问题展开论据。',
        'evidence': [
          {'sectionId': 1, 'quote': '展开论据'},
        ],
      },
      {
        'tempId': 'reply',
        'parentTempId': 'root',
        'order': 1,
        'title': '回应结论',
        'summary': '回应问题并形成结论。',
        'evidence': [
          {'sectionId': 2, 'quote': '第二章证据'},
        ],
      },
      {
        'tempId': 'reply-detail',
        'parentTempId': 'reply',
        'order': 0,
        'title': '回应过程',
        'summary': '逐步回应核心问题。',
        'evidence': [
          {'sectionId': 2, 'quote': '回应问题'},
        ],
      },
      {
        'tempId': 'conclusion',
        'parentTempId': 'reply',
        'order': 1,
        'title': '最终结论',
        'summary': '给出全书结论。',
        'evidence': [
          {'sectionId': 2, 'quote': '给出结论'},
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

  test('leaf with omitted evidence matches a verified batch theme', () async {
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

    expect(result.nodes[2].evidence.single.quote, '第一章证据');
    expect(result.nodes[2].evidence.single.spanResolved, isTrue);
  });

  test('unmatched ungrounded leaf still rejects the final tree', () async {
    final tree = finalTree();
    final rows = tree['nodes']! as List<Map<String, Object?>>;
    rows[2]
      ..['title'] = '陌生主题'
      ..['summary'] = '这段内容与所有批次主题完全没有共同信息。'
      ..['evidence'] = <Object?>[];
    final adapter = _FakeMindMapAdapter([batch(), tree, tree]);

    await expectLater(
      workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(
      adapter.requests.last.messages.first.text,
      contains('非根叶节点必须至少有一条可定位 evidence 引文'),
    );
  });

  test(
    'repairs rewritten quote from verified evidence in same section',
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

      expect(result.nodes[2].evidence.single.quote, '第一章证据');
      expect(result.nodes[2].evidence.single.spanResolved, isTrue);
    },
  );

  test(
    'uses node semantics to disambiguate evidence within one section',
    () async {
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

      expect(result.nodes[2].evidence.single.quote, '展开论据');
      expect(result.nodes[2].evidence.single.spanResolved, isTrue);
    },
  );

  test('does not repair rewritten quote with cross-section evidence', () async {
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
    final adapter = _FakeMindMapAdapter([summary, tree, tree]);

    await expectLater(
      workflow(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        sections: sections,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(adapter.calls, 3);
  });
}

class _FakeMindMapAdapter implements AiModelAdapter, AiStructuredOutputAdapter {
  _FakeMindMapAdapter(this.outputs);

  final List<Map<String, dynamic>> outputs;
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
    return AiModelJsonResult(value: outputs[calls++]);
  }

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) => const Stream.empty();

  @override
  Future<void> close() async => closed = true;
}

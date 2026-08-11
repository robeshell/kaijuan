import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_service.dart';
import 'package:kaijuan/ai/ai_cancel.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_model_adapter.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_settings.dart';

void main() {
  const sections = [
    AiBookSectionSlice(
      index: 1,
      sourceSectionIndex: 1,
      label: '第一章',
      text: '第一章提出就业取舍，并说明短期保护的代价。',
    ),
    AiBookSectionSlice(
      index: 2,
      sourceSectionIndex: 2,
      label: '第二章',
      text: '第二章分析长期发展，最后给出结论。',
    ),
  ];

  Map<String, dynamic> tree() => {
    'contentKind': 'argumentative',
    'nodes': [
      {
        'tempId': 'root',
        'parentTempId': null,
        'order': 0,
        'title': '就业与发展',
        'summary': '全书分析短期就业保护与长期发展之间的取舍。',
        'evidence': <Object?>[],
      },
      {
        'tempId': 'cost',
        'parentTempId': 'root',
        'order': 0,
        'title': '短期代价',
        'summary': '短期保护能够稳定就业，但会积累后续调整成本。',
        'evidence': [
          {'sectionId': 1, 'quote': '短期保护的代价'},
        ],
      },
      {
        'tempId': 'future',
        'parentTempId': 'root',
        'order': 1,
        'title': '长期发展',
        'summary': '长期发展要求重新权衡政策目标并形成明确结论。',
        'evidence': [
          {'sectionId': 2, 'quote': '长期发展'},
        ],
      },
    ],
  };

  AiBookMindMapService service(_FakeAdapter adapter) => AiBookMindMapService(
    isAvailable: () => true,
    openModelAdapter: () => adapter,
    settings: () => const AiSettings(model: 'mind-map-test'),
  );

  test('sends the complete selected text in one structured call', () async {
    final adapter = _FakeAdapter(tree());
    final result = await service(adapter).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      scopeLabel: '全书',
      userInstruction: '生成一份详细的全书思维导图',
      sections: sections,
    );

    expect(adapter.calls, 1);
    expect(adapter.closed, isTrue);
    final prompt = adapter.request.messages.last.text;
    expect(prompt, contains(sections[0].text));
    expect(prompt, contains(sections[1].text));
    expect(prompt, contains('生成一份详细的全书思维导图'));
    expect(result.nodes.map((node) => node.nodeId), [
      'mm001',
      'mm002',
      'mm003',
    ]);
    expect(result.nodes[1].evidence.single.spanResolved, isTrue);
  });

  test('keeps valid tree when optional evidence cannot be located', () async {
    final value = tree();
    final nodes = value['nodes']! as List<Map<String, Object?>>;
    nodes[1]['evidence'] = [
      {'sectionId': 1, 'quote': '正文中不存在的改写'},
    ];
    final result = await service(_FakeAdapter(value)).generate(
      contentHash: 'a' * 64,
      workKey: null,
      bookTitle: '测试书',
      scopeLabel: '全书',
      userInstruction: '生成思维导图',
      sections: sections,
    );
    expect(result.nodes[1].evidence, isEmpty);
  });

  test(
    'normalizes a valid multi-root forest without another model call',
    () async {
      final value = tree();
      final nodes = (value['nodes']! as List)
          .map((node) => Map<String, dynamic>.from(node as Map))
          .toList();
      value['nodes'] = nodes;
      nodes.removeAt(0);
      nodes[0]['parentTempId'] = null;
      nodes[1]['parentTempId'] = '';
      final adapter = _FakeAdapter(value);

      final result = await service(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        scopeLabel: '全书',
        userInstruction: '生成思维导图',
        sections: sections,
      );

      expect(adapter.calls, 1);
      expect(result.nodes, hasLength(3));
      expect(result.nodes.first.title, '测试书');
      expect(result.nodes.first.parentId, isNull);
      expect(result.nodes.skip(1).map((node) => node.parentId), [
        'mm001',
        'mm001',
      ]);
      expect(result.nodes.skip(1).map((node) => node.level), [1, 1]);
      expect(result.nodes.first.summary, contains('短期保护能够稳定就业'));
    },
  );

  test(
    'scales coverage guidance and output budget with the selected corpus',
    () async {
      final longSections = [
        for (var index = 0; index < 12; index++)
          AiBookSectionSlice(
            index: index + 1,
            sourceSectionIndex: index + 1,
            label: '第 ${index + 1} 章',
            text: List.filled(240, '第${index + 1}章包含政策背景、事实案例与影响分析。').join(),
          ),
      ];
      final adapter = _FakeAdapter(tree());

      await service(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '长书测试',
        scopeLabel: '全书',
        userInstruction: '生成一份详细完整的全书思维导图',
        sections: longSections,
      );

      final prompt = adapter.request.messages.last.text;
      expect(prompt, contains('有效章节：12'));
      expect(prompt, contains('可参考约'));
      expect(prompt, contains('不是最低数量'));
      expect(prompt, isNot(contains('至少生成')));
      expect(adapter.request.maxTokens, greaterThan(12000));
    },
  );

  test('rejects invalid parent references without retrying', () async {
    final value = tree();
    final nodes = value['nodes']! as List<Map<String, Object?>>;
    nodes[1]['parentTempId'] = 'missing';
    final adapter = _FakeAdapter(value);
    await expectLater(
      service(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        scopeLabel: '全书',
        userInstruction: '生成思维导图',
        sections: sections,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(adapter.calls, 1);
  });

  test('honors cancellation before the model call', () async {
    final adapter = _FakeAdapter(tree());
    final cancel = CancelToken()..cancel();
    await expectLater(
      service(adapter).generate(
        contentHash: 'a' * 64,
        workKey: null,
        bookTitle: '测试书',
        scopeLabel: '全书',
        userInstruction: '生成思维导图',
        sections: sections,
        cancelToken: cancel,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(adapter.calls, 0);
  });
}

class _FakeAdapter implements AiModelAdapter, AiStructuredOutputAdapter {
  _FakeAdapter(this.output);

  final Map<String, dynamic> output;
  late AiModelJsonRequest request;
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
    this.request = request;
    calls++;
    return AiModelJsonResult(value: output);
  }

  @override
  Stream<AiModelTurnEvent> streamTurn(
    AiModelTurnRequest request, {
    CancelToken? cancelToken,
  }) => const Stream.empty();

  @override
  Future<void> close() async => closed = true;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_outline.dart';
import 'package:kaijuan/ai/ai_provider.dart';
import 'package:kaijuan/ai/ai_settings.dart';

void main() {
  AiBookOutlineService serviceWith(_OutlineProvider provider) {
    return AiBookOutlineService(
      isAvailable: () => true,
      openProvider: () => provider,
      settings: () => const AiSettings(model: 'outline-test'),
    );
  }

  test('outline JSON round-trip preserves tagline and themes', () {
    final source = AiBookOutline(
      createdAt: DateTime.utc(2026, 8, 5, 12),
      model: 'outline-test',
      overview: '一部关于沉默与话语的杂文集。',
      units: const [
        AiOutlineUnit(title: '沉默的辩证法', blurb: '沉默作为文化选择。'),
        AiOutlineUnit(title: '知识分子的处境', blurb: '插队与思想灌输。'),
      ],
    );

    final restored = AiBookOutline.fromJson(source.toJson());

    expect(restored, isNotNull);
    expect(restored!.overview, '一部关于沉默与话语的杂文集。');
    expect(restored.units, hasLength(2));
    expect(restored.units.first.title, '沉默的辩证法');
    expect(restored.units.first.blurb, '沉默作为文化选择。');
  });

  test('outline cache ignores a result from an older generator version', () {
    final source = AiBookOutline(
      createdAt: DateTime.utc(2026, 8, 5, 12),
      model: 'outline-test',
      overview: '旧大纲。',
      units: const [AiOutlineUnit(title: '旧', blurb: '旧主题。')],
    );
    final oldJson = {
      ...source.toJson(),
      'version': AiBookOutline.currentVersion - 1,
    };

    expect(AiBookOutline.fromJson(oldJson), isNull);
  });

  test('generate makes one provider call and parses themes', () async {
    final provider = _OutlineProvider();
    final progress = <AiOutlineProgress>[];
    final sections = [
      for (var index = 1; index <= 5; index++)
        AiBookSectionSlice(
          index: index,
          label: '第 $index 节',
          text: '正文$index ' * 1100,
        ),
    ];

    final outline = await serviceWith(provider).generate(
      bookTitle: '测试书',
      sections: sections,
      onProgress: progress.add,
    );

    expect(provider.requests, hasLength(1));
    expect(outline.model, 'outline-test');
    expect(outline.overview, isNotEmpty);
    expect(outline.units, isNotEmpty);
    expect(progress.last.finalizing, isTrue);
  });

  test('generate throws on invalid provider output', () async {
    final provider = _OutlineProvider(invalidOutput: true);

    await expectLater(
      serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: const [
          AiBookSectionSlice(index: 1, label: '一', text: '正文一'),
        ],
      ),
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          '大纲提炼失败，请重试',
        ),
      ),
    );
  });

  test('generate throws when no usable body', () async {
    final provider = _OutlineProvider();

    await expectLater(
      serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: const [
          AiBookSectionSlice(index: 1, label: '目录', text: '   '),
        ],
      ),
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          '没有可用于生成大纲的正文',
        ),
      ),
    );
    expect(provider.requests, isEmpty);
  });

  test('generate survives 54+ sections (pack budget must not clamp-crash)',
      () async {
    final provider = _OutlineProvider();
    final outline = await serviceWith(provider).generate(
      bookTitle: '大部头',
      sections: [
        for (var i = 1; i <= 60; i++)
          AiBookSectionSlice(
            index: i,
            label: '第 $i 章',
            text: '第 $i 章正文',
            sourceSectionIndex: i,
            isNavigationUnit: true,
          ),
      ],
    );
    // 1500×60 = 90000 > 80000 cap：旧 clamp 在这里抛 ArgumentError。
    expect(outline.units, isNotEmpty);
    expect(provider.requests, hasLength(1));
  });

  test('generate honors cancellation before the call', () async {
    final provider = _OutlineProvider();
    final cancel = CancelToken()..cancel();

    await expectLater(
      serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: const [
          AiBookSectionSlice(index: 1, label: '一', text: '正文一'),
        ],
        cancelToken: cancel,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(provider.requests, isEmpty);
  });

}

class _OutlineProvider implements AiProvider {
  _OutlineProvider({this.invalidOutput = false});

  final bool invalidOutput;
  final List<AiCompletionRequest> requests = [];

  @override
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (invalidOutput) {
      return const AiCompletionResult(text: 'not json');
    }
    return const AiCompletionResult(
      text:
          '{"overview":"一本关于测试的书。",'
          '"units":['
          '{"title":"单元一","blurb":"单元一的一段话说明。"},'
          '{"title":"单元二","blurb":"单元二的一段话说明。"}'
          ']}',
    );
  }

  @override
  Future<List<AiModelInfo>> listModels({CancelToken? cancelToken}) async =>
      const [];

  @override
  Stream<AiStreamChunk> stream(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {}
}

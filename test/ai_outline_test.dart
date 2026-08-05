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

  test('outline JSON round-trip preserves cache metadata', () {
    final source = AiBookOutline(
      createdAt: DateTime.utc(2026, 8, 5, 12),
      model: 'outline-test',
      includesUnread: true,
      overview: '全书围绕一次迁都与归京展开。',
      themes: const ['权力', '抉择'],
      chapters: const [
        AiBookOutlineChapter(
          sectionIndex: 7,
          title: '开端',
          summary: '事件发生后，主角被迫离开南京。',
          keyPoints: ['爆炸', '出逃'],
          sourceSectionIndex: 1,
        ),
      ],
    );

    final restored = AiBookOutline.fromJson(source.toJson());

    expect(restored, isNotNull);
    expect(restored!.includesUnread, isTrue);
    expect(restored.model, 'outline-test');
    expect(restored.chapters.single.keyPoints, ['爆炸', '出逃']);
    expect(restored.chapters.single.sourceSectionIndex, 1);
  });

  test('outline JSON preserves unloaded and loaded child branches', () {
    final source = AiBookOutline(
      createdAt: DateTime.utc(2026, 8, 5, 12),
      model: 'outline-test',
      includesUnread: true,
      overview: '全书概览。',
      chapters: const [
        AiBookOutlineChapter(
          sectionIndex: 1,
          title: '第一部',
          summary: '第一部摘要。',
          sourceSectionIndex: 2,
          endSectionIndexExclusive: 10,
          nodeId: 'top-1',
          children: [
            AiBookOutlineChapter(
              sectionIndex: 1,
              title: '第一章',
              summary: '第一章摘要。',
              sourceSectionIndex: 2,
              source: AiOutlineNodeSource.heading,
              nodeId: 'top-1/1',
              children: [],
            ),
          ],
        ),
        AiBookOutlineChapter(
          sectionIndex: 2,
          title: '第二部',
          summary: '第二部摘要。',
          nodeId: 'top-2',
        ),
      ],
    );

    final restored = AiBookOutline.fromJson(source.toJson());

    expect(restored, isNotNull);
    expect(restored!.chapters[0].endSectionIndexExclusive, 10);
    expect(
      restored.chapters[0].children!.single.source,
      AiOutlineNodeSource.heading,
    );
    expect(restored.chapters[0].children!.single.children, isEmpty);
    expect(restored.chapters[1].children, isNull);
  });

  test('outline cache ignores a result from an older generator version', () {
    final source = AiBookOutline(
      createdAt: DateTime.utc(2026, 8, 5, 12),
      model: 'outline-test',
      includesUnread: true,
      overview: '旧大纲。',
      chapters: const [
        AiBookOutlineChapter(sectionIndex: 1, title: '旧章节', summary: '旧摘要。'),
      ],
    );
    final oldJson = {
      ...source.toJson(),
      'version': AiBookOutline.currentVersion - 1,
    };

    expect(AiBookOutline.fromJson(oldJson), isNull);
  });

  test(
    'generates every section in bounded batches and reports progress',
    () async {
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
        includesUnread: false,
        onProgress: progress.add,
      );

      expect(provider.requests, hasLength(4));
      expect(outline.model, 'outline-test');
      expect(outline.includesUnread, isFalse);
      expect(outline.chapters.map((chapter) => chapter.sectionIndex), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(progress.last.finalizing, isTrue);
      expect(progress.last.label, '正在整理全书脉络');
    },
  );

  test('rejects a batch that omits one provided section', () async {
    final provider = _OutlineProvider(omitLastSection: true);

    await expectLater(
      serviceWith(provider).generate(
        bookTitle: '测试书',
        sections: const [
          AiBookSectionSlice(index: 1, label: '一', text: '正文一'),
          AiBookSectionSlice(index: 2, label: '二', text: '正文二'),
        ],
        includesUnread: true,
      ),
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          '章节大纲不完整，请重试',
        ),
      ),
    );
  });

  test('limits a summary batch to four short sections', () async {
    final provider = _OutlineProvider();

    final outline = await serviceWith(provider).generate(
      bookTitle: '短章合集',
      includesUnread: true,
      sections: [
        for (var index = 1; index <= 9; index++)
          AiBookSectionSlice(index: index, label: '第 $index 节', text: '短正文'),
      ],
    );

    // Structure plan + 3 bounded summary batches + final overview.
    expect(provider.requests, hasLength(5));
    expect(outline.chapters, hasLength(9));
  });

  test('uses model structure groups as outline units', () async {
    final provider = _OutlineProvider(
      structurePlan:
          '{"groups":['
          '{"title":"第一部","sectionIndexes":[1,2]},'
          '{"title":"第二部","sectionIndexes":[3,4,5]}'
          '],"ignoredSectionIndexes":[]}',
    );

    final outline = await serviceWith(provider).generate(
      bookTitle: '合集',
      sections: const [
        AiBookSectionSlice(index: 1, label: '甲之一', text: '第一部开端'),
        AiBookSectionSlice(index: 2, label: '甲之二', text: '第一部发展'),
        AiBookSectionSlice(index: 3, label: '乙之一', text: '第二部开端'),
        AiBookSectionSlice(index: 4, label: '乙之二', text: '第二部发展'),
        AiBookSectionSlice(index: 5, label: '乙之三', text: '第二部结尾'),
      ],
      includesUnread: true,
    );

    expect(outline.chapters.map((chapter) => chapter.sectionIndex), [1, 3]);
    expect(outline.chapters.map((chapter) => chapter.title), ['第一部', '第二部']);
    expect(provider.requests.first.messages.last.content, contains('结构清单：'));
  });

  test(
    'summarizes a small set of navigation units without a structure plan',
    () async {
      final provider = _OutlineProvider();

      final outline = await serviceWith(provider).generate(
        bookTitle: '合集',
        includesUnread: true,
        sections: const [
          AiBookSectionSlice(
            index: 1,
            label: '第一部',
            text: '第一部正文',
            isNavigationUnit: true,
          ),
          AiBookSectionSlice(
            index: 2,
            label: '第二部',
            text: '第二部正文',
            isNavigationUnit: true,
          ),
        ],
      );

      expect(outline.chapters.map((chapter) => chapter.sectionIndex), [1, 2]);
      expect(provider.requests, hasLength(2));
      expect(
        provider.requests.any(
          (request) => request.messages.last.content.contains('结构清单：'),
        ),
        isFalse,
      );
    },
  );

  test('keeps original spine locations for logically split units', () async {
    final outline = await serviceWith(_OutlineProvider()).generate(
      bookTitle: '合集',
      sections: const [
        AiBookSectionSlice(
          index: 1,
          sourceSectionIndex: 1,
          label: '第一部',
          text: '第一部正文',
        ),
        AiBookSectionSlice(
          index: 2,
          sourceSectionIndex: 1,
          label: '第二部',
          text: '第二部正文',
        ),
      ],
      includesUnread: true,
    );

    expect(outline.chapters.map((chapter) => chapter.sourceSectionIndex), [
      1,
      1,
    ]);
  });

  test(
    'generates bounded, reader-derived child outlines without overview',
    () async {
      final provider = _OutlineProvider();

      final children = await serviceWith(provider).generateChildren(
        bookTitle: '合集',
        parentNodeId: 'top-1',
        candidates: [
          for (var index = 1; index <= 5; index++)
            AiBookOutlineCandidate(
              label: '第 $index 章',
              startSectionIndex: index * 10,
              endSectionIndexExclusive: index * 10 + 1,
              text: '第 $index 章正文',
              source: AiOutlineNodeSource.toc,
            ),
        ],
      );

      expect(provider.requests, hasLength(2));
      expect(children.map((chapter) => chapter.nodeId), [
        'top-1/1',
        'top-1/2',
        'top-1/3',
        'top-1/4',
        'top-1/5',
      ]);
      expect(children.map((chapter) => chapter.sourceSectionIndex), [
        10,
        20,
        30,
        40,
        50,
      ]);
    },
  );

  test(
    'groups a long child list before requesting per-entry summaries',
    () async {
      final provider = _OutlineProvider();

      final children = await serviceWith(provider).generateChildren(
        bookTitle: '长文集',
        parentNodeId: 'top-1',
        candidates: [
          for (var index = 1; index <= 17; index++)
            AiBookOutlineCandidate(
              label: '第 $index 篇',
              startSectionIndex: index * 10,
              endSectionIndexExclusive: index * 10 + 1,
              text: '第 $index 篇正文',
              source: AiOutlineNodeSource.toc,
            ),
        ],
      );

      expect(provider.requests, hasLength(1));
      expect(children, hasLength(3));
      expect(children.map((chapter) => chapter.nodeId), [
        'top-1/group-1',
        'top-1/group-2',
        'top-1/group-3',
      ]);
      expect(
        children.every(
          (chapter) => chapter.source == AiOutlineNodeSource.semantic,
        ),
        isTrue,
      );
      expect(children.map((chapter) => chapter.sourceSectionIndex), [
        10,
        90,
        170,
      ]);
    },
  );

  test('invalid structure plan falls back without dropping sections', () async {
    final provider = _OutlineProvider(
      structurePlan:
          '{"groups":[{"title":"错误分组","sectionIndexes":[1]}],'
          '"ignoredSectionIndexes":[2,3]}',
    );

    final outline = await serviceWith(provider).generate(
      bookTitle: '测试书',
      sections: const [
        AiBookSectionSlice(index: 1, label: '一', text: '正文一'),
        AiBookSectionSlice(index: 2, label: '二', text: '正文二'),
        AiBookSectionSlice(index: 3, label: '三', text: '正文三'),
      ],
      includesUnread: false,
    );

    expect(outline.chapters.map((chapter) => chapter.sectionIndex), [1, 2, 3]);
  });

  test(
    'does not call the provider after cancellation before structure planning',
    () async {
      final provider = _OutlineProvider();
      final cancel = CancelToken()..cancel();

      await expectLater(
        serviceWith(provider).generate(
          bookTitle: '测试书',
          sections: const [
            AiBookSectionSlice(index: 1, label: '一', text: '正文一'),
          ],
          includesUnread: false,
          cancelToken: cancel,
        ),
        throwsA(isA<AiProviderException>()),
      );
      expect(provider.requests, isEmpty);
    },
  );
}

class _OutlineProvider implements AiProvider {
  _OutlineProvider({this.omitLastSection = false, this.structurePlan});

  final bool omitLastSection;
  final String? structurePlan;
  final List<AiCompletionRequest> requests = [];

  @override
  Future<AiCompletionResult> complete(
    AiCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    final prompt = request.messages.last.content;
    if (prompt.contains('结构清单：')) {
      if (structurePlan != null) {
        return AiCompletionResult(text: structurePlan!);
      }
      final rows = RegExp(r'\[§(\d+) ')
          .allMatches(prompt)
          .map((match) {
            final index = match.group(1)!;
            return '{"title":"第$index 节","sectionIndexes":[$index]}';
          })
          .join(',');
      return AiCompletionResult(
        text: '{"groups":[$rows],"ignoredSectionIndexes":[]}',
      );
    }
    if (prompt.contains('子级分组清单：')) {
      final indexes = RegExp(
        r'\[§(\d+) ',
      ).allMatches(prompt).map((match) => int.parse(match.group(1)!)).toList();
      final rows = <String>[];
      for (var start = 0; start < indexes.length; start += 8) {
        final group = indexes.skip(start).take(8).toList();
        rows.add(
          '{"title":"第${group.first}至${group.last}篇",'
          '"sectionIndexes":[${group.join(',')}],'
          '"summary":"这一组收录相邻篇章的核心内容。",'
          '"keyPoints":["篇章脉络"]}',
        );
      }
      return AiCompletionResult(text: '{"groups":[${rows.join(',')}]}');
    }
    if (prompt.contains('章节摘要：')) {
      return const AiCompletionResult(
        text: '{"overview":"全书由多段危机串联而成。","themes":["选择"]}',
      );
    }
    final matches = RegExp(r'\[§(\d+) ([^\]]+)\]').allMatches(prompt).toList();
    final rows = matches
        .take(omitLastSection ? matches.length - 1 : matches.length)
        .map(
          (match) =>
              '{"sectionIndex":${match.group(1)},"title":"${match.group(2)}","summary":"本节的关键事件和转折。","keyPoints":["要点"]}',
        )
        .join(',');
    return AiCompletionResult(text: '[$rows]');
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

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_structure_supplements.dart';
import 'package:kaijuan/domain/book_structure.dart';

void main() {
  BookStructureSection section(
    int index, {
    List<BookStructureHeading>? headings,
  }) => BookStructureSection(
    sectionIndex: index,
    href: 'text/$index.xhtml',
    documentTitle: '第 ${index + 1} 节',
    bodyCharCount: 1200,
    headings: headings ?? const [],
  );

  BookStructureNavigationNode node({
    required String id,
    required String title,
    required int order,
    required int sectionIndex,
    String? parentId,
    int depth = 0,
    int children = 0,
  }) => BookStructureNavigationNode(
    nodeId: id,
    parentId: parentId,
    title: title,
    depth: depth,
    order: order,
    href: 'text/$sectionIndex.xhtml',
    sectionIndex: sectionIndex,
    directChildCount: children,
  );

  AiBookStructureManifest classify(
    BookStructureIndex index, {
    String? fallbackPublicationTitle,
  }) => AiBookStructureResolver.resolveIndex(
    index: index,
    isSupplementTitle: matchesAiStructureSupplementTitle,
    fallbackPublicationTitle: fallbackPublicationTitle,
  );

  test('bridge JSON preserves every section, heading and locator', () {
    final index = BookStructureIndex.tryParse('''
{
  "indexVersion": 1,
  "publicationTitle": "示例书",
  "sections": [
    {
      "sectionIndex": 0,
      "href": "Text/ch1.xhtml",
      "documentTitle": "第一章",
      "bodyCharCount": 4200,
      "headings": [
        {"title": "第一章", "level": 1, "order": 0, "fragment": "ch1", "cfi": "epubcfi(/6/2!/4/2)"}
      ]
    }
  ],
  "navigation": [
    {"nodeId": "nav-1", "parentId": null, "title": "第一章", "depth": 0, "order": 0, "href": "Text/ch1.xhtml#ch1", "fragment": "ch1", "sectionIndex": 0, "directChildCount": 0}
  ]
}
''');

    expect(index, isNotNull);
    expect(index!.sections, hasLength(1));
    expect(index.publicationTitle, '示例书');
    expect(index.headingCount, 1);
    expect(index.bodyCharCount, 4200);
    expect(index.sections.single.headings.single.cfi, 'epubcfi(/6/2!/4/2)');
    expect(index.navigationRoots.single.fragment, 'ch1');
  });

  test('chapter and dash-subtitle navigation remains a single work', () {
    final navigation = <BookStructureNavigationNode>[];
    for (var chapter = 0; chapter < 11; chapter++) {
      navigation
        ..add(
          node(
            id: 'chapter-$chapter',
            title: '第${chapter + 1}章 主题',
            order: navigation.length,
            sectionIndex: chapter,
          ),
        )
        ..add(
          node(
            id: 'subtitle-$chapter',
            title: '——回顾第${chapter + 1}章的背景与影响',
            order: navigation.length,
            sectionIndex: chapter,
          ),
        );
    }
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '哈利波特全集',
        sections: [for (var index = 0; index < 11; index++) section(index)],
        navigation: navigation,
      ),
    );

    expect(manifest.kind, AiBookStructureKind.singleWork);
    expect(manifest.works, isEmpty);
  });

  test('top-level books with their own chapter trees form an omnibus', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '哈利波特全集',
        sections: [for (var index = 0; index < 8; index++) section(index)],
        navigation: [
          node(
            id: 'work-a',
            title: '魔法石',
            order: 0,
            sectionIndex: 0,
            children: 2,
          ),
          node(
            id: 'a-1',
            parentId: 'work-a',
            depth: 1,
            title: '第一章',
            order: 1,
            sectionIndex: 1,
          ),
          node(
            id: 'a-2',
            parentId: 'work-a',
            depth: 1,
            title: '第二章',
            order: 2,
            sectionIndex: 2,
          ),
          node(
            id: 'work-b',
            title: '密室',
            order: 3,
            sectionIndex: 4,
            children: 2,
          ),
          node(
            id: 'b-1',
            parentId: 'work-b',
            depth: 1,
            title: '第一章',
            order: 4,
            sectionIndex: 5,
          ),
          node(
            id: 'b-2',
            parentId: 'work-b',
            depth: 1,
            title: '第二章',
            order: 5,
            sectionIndex: 6,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['魔法石', '密室']);
    expect(manifest.works.first.startSection, 1);
    expect(manifest.works.last.startSection, 5);
  });

  test('volume roots are one segmented work', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        sections: [section(0), section(3)],
        navigation: [
          node(id: 'v1', title: '第一卷', order: 0, sectionIndex: 0),
          node(id: 'v2', title: '第二卷', order: 1, sectionIndex: 3),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.segmentedSingleWork);
    expect(manifest.works, hasLength(2));
  });

  test('financial Chinese numerals are recognized as volume roots', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        sections: [section(0), section(3)],
        navigation: [
          node(id: 'v1', title: '第壹部 起点', order: 0, sectionIndex: 0),
          node(id: 'v2', title: '第贰部 转折', order: 1, sectionIndex: 3),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.segmentedSingleWork);
  });

  test(
    'independent trees sharing one spine stay uncertain without fake ranges',
    () {
      final manifest = classify(
        BookStructureIndex(
          indexVersion: 1,
          publicationTitle: '鲁迅作品全集',
          sections: [section(0)],
          navigation: [
            node(
              id: 'work-a',
              title: '呐喊',
              order: 0,
              sectionIndex: 0,
              children: 2,
            ),
            node(
              id: 'work-b',
              title: '彷徨',
              order: 1,
              sectionIndex: 0,
              children: 2,
            ),
          ],
        ),
      );

      expect(manifest.kind, AiBookStructureKind.uncertain);
      expect(manifest.works, isEmpty);
    },
  );

  test('ordinary chapter subtrees do not imply an omnibus', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: 'AI Agent 深度指南',
        sections: [section(0), section(1), section(2)],
        navigation: [
          node(
            id: 'intro',
            title: '上下文工程',
            order: 0,
            sectionIndex: 0,
            children: 5,
          ),
          node(
            id: 'tools',
            title: '工具',
            order: 1,
            sectionIndex: 1,
            children: 7,
          ),
          node(
            id: 'evals',
            title: '评估',
            order: 2,
            sectionIndex: 2,
            children: 4,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.singleWork);
  });

  test('split upper middle lower installments merge into one work', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '系列卷1-2合集',
        sections: [for (var index = 0; index < 6; index++) section(index)],
        navigation: [
          node(
            id: 'a-up',
            title: '权力游戏（上）',
            order: 0,
            sectionIndex: 0,
            children: 3,
          ),
          node(
            id: 'a-down',
            title: '权力游戏（下）',
            order: 1,
            sectionIndex: 2,
            children: 3,
          ),
          node(
            id: 'b-up',
            title: '列王纷争（上）',
            order: 2,
            sectionIndex: 4,
            children: 3,
          ),
          node(
            id: 'b-down',
            title: '列王纷争（下）',
            order: 3,
            sectionIndex: 5,
            children: 3,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['权力游戏', '列王纷争']);
  });

  test('hierarchical omnibus keeps work trees and drops leaf front matter', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '代表作品集套装共2册',
        sections: [for (var index = 0; index < 8; index++) section(index)],
        navigation: [
          node(
            id: 'publisher',
            title: 'Digital Lab简介',
            order: 0,
            sectionIndex: 0,
          ),
          node(
            id: 'work-a',
            title: '作品甲',
            order: 1,
            sectionIndex: 1,
            children: 3,
          ),
          node(
            id: 'work-b',
            title: '作品乙',
            order: 2,
            sectionIndex: 4,
            children: 3,
          ),
          node(id: 'afterword', title: '后记', order: 3, sectionIndex: 7),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['作品甲', '作品乙']);
    expect(manifest.works.last.endSectionExclusive, 8);
  });

  test(
    'segmented work exposes only volume nodes and stops before back matter',
    () {
      final manifest = classify(
        BookStructureIndex(
          indexVersion: 1,
          publicationTitle: '分部历史',
          sections: [for (var index = 0; index < 7; index++) section(index)],
          navigation: [
            node(
              id: 'recommendation',
              title: '名人推荐',
              order: 0,
              sectionIndex: 0,
            ),
            node(id: 'intro', title: '引子', order: 1, sectionIndex: 1),
            node(id: 'volume-a', title: '第壹部 起点', order: 2, sectionIndex: 2),
            node(id: 'volume-b', title: '第贰部 转折', order: 3, sectionIndex: 4),
            node(id: 'afterword', title: '后记', order: 4, sectionIndex: 6),
          ],
        ),
      );

      expect(manifest.kind, AiBookStructureKind.segmentedSingleWork);
      expect(manifest.works.map((work) => work.title), ['第壹部 起点', '第贰部 转折']);
      expect(manifest.works.last.endSectionExclusive, 7);
    },
  );

  test('declared omnibus count mismatch fails closed without fake choices', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '代表作品集套装共3册',
        sections: [section(0), section(2)],
        navigation: [
          node(
            id: 'work-a',
            title: '作品甲',
            order: 0,
            sectionIndex: 0,
            children: 2,
          ),
          node(
            id: 'work-b',
            title: '作品乙',
            order: 1,
            sectionIndex: 2,
            children: 2,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.uncertain);
    expect(manifest.works, isEmpty);
  });

  test('publication collection container is not exposed as a work', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '推理作品集共2册',
        sections: [for (var index = 0; index < 6; index++) section(index)],
        navigation: [
          node(
            id: 'container',
            title: '推理作品集',
            order: 0,
            sectionIndex: 0,
            children: 2,
          ),
          node(
            id: 'work-a',
            title: '作品甲',
            order: 1,
            sectionIndex: 1,
            children: 2,
          ),
          node(
            id: 'work-b',
            title: '作品乙',
            order: 2,
            sectionIndex: 4,
            children: 2,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['作品甲', '作品乙']);
  });

  test('declared count closes after dropping a generic collection header', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '珍藏共2册',
        sections: [for (var index = 0; index < 6; index++) section(index)],
        navigation: [
          node(
            id: 'container',
            title: '作者作品集',
            order: 0,
            sectionIndex: 0,
            children: 2,
          ),
          node(
            id: 'work-a',
            title: '作品甲',
            order: 1,
            sectionIndex: 1,
            children: 2,
          ),
          node(
            id: 'work-b',
            title: '作品乙',
            order: 2,
            sectionIndex: 4,
            children: 2,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['作品甲', '作品乙']);
  });

  test('generic reader notes and chronology are excluded from an omnibus', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '侦探作品套装共2册',
        sections: [for (var index = 0; index < 8; index++) section(index)],
        navigation: [
          node(id: 'chronology', title: '侦探作品年表', order: 0, sectionIndex: 0),
          node(id: 'reader', title: '致中国读者', order: 1, sectionIndex: 1),
          node(
            id: 'work-a',
            title: '作品甲',
            order: 2,
            sectionIndex: 2,
            children: 2,
          ),
          node(
            id: 'work-b',
            title: '作品乙',
            order: 3,
            sectionIndex: 5,
            children: 2,
          ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['作品甲', '作品乙']);
  });

  test('flat title-directory boundaries recover a declared omnibus', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '科幻经典共2册',
        sections: [for (var index = 0; index < 8; index++) section(index)],
        navigation: [
          node(id: 'set', title: '科幻经典套装共2册', order: 0, sectionIndex: 0),
          node(id: 'set-toc', title: '目录', order: 1, sectionIndex: 0),
          node(id: 'work-a', title: '作品甲', order: 2, sectionIndex: 1),
          node(id: 'toc-a', title: '目录', order: 3, sectionIndex: 1),
          node(id: 'a-1', title: '第一章', order: 4, sectionIndex: 2),
          node(id: 'a-2', title: '第二章', order: 5, sectionIndex: 3),
          node(id: 'work-b', title: '作品乙', order: 6, sectionIndex: 4),
          node(id: 'toc-b', title: '总目录', order: 7, sectionIndex: 4),
          node(id: 'b-1', title: '第一章', order: 8, sectionIndex: 5),
          node(id: 'b-2', title: '第二章', order: 9, sectionIndex: 6),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['作品甲', '作品乙']);
  });

  test('declared numbered set expands intermediate season groups', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '长篇系列',
        sections: [for (var index = 0; index < 10; index++) section(index)],
        navigation: [
          node(
            id: 'season-a',
            title: '第一季',
            order: 0,
            sectionIndex: 0,
            children: 2,
          ),
          node(
            id: 'work-a',
            parentId: 'season-a',
            depth: 1,
            title: '作品甲',
            order: 1,
            sectionIndex: 1,
            children: 2,
          ),
          node(
            id: 'work-b',
            parentId: 'season-a',
            depth: 1,
            title: '作品乙',
            order: 2,
            sectionIndex: 3,
            children: 2,
          ),
          node(
            id: 'season-b',
            title: '第二季',
            order: 3,
            sectionIndex: 5,
            children: 2,
          ),
          node(
            id: 'work-c',
            parentId: 'season-b',
            depth: 1,
            title: '作品丙',
            order: 4,
            sectionIndex: 5,
            children: 2,
          ),
          node(
            id: 'work-d',
            parentId: 'season-b',
            depth: 1,
            title: '作品丁',
            order: 5,
            sectionIndex: 7,
            children: 2,
          ),
          node(id: 'special', title: '特别篇', order: 6, sectionIndex: 9),
        ],
      ),
      fallbackPublicationTitle: '长篇系列1-4全集',
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), [
      '作品甲',
      '作品乙',
      '作品丙',
      '作品丁',
    ]);
  });

  test('declared collection with unrecovered chapter tree stays uncertain', () {
    final manifest = classify(
      BookStructureIndex(
        indexVersion: 1,
        publicationTitle: '作品合集共3册',
        sections: [for (var index = 0; index < 5; index++) section(index)],
        navigation: [
          for (var index = 0; index < 5; index++)
            node(
              id: 'chapter-$index',
              title: '第${index + 1}章',
              order: index,
              sectionIndex: index,
            ),
        ],
      ),
    );

    expect(manifest.kind, AiBookStructureKind.uncertain);
    expect(manifest.works, isEmpty);
  });
}

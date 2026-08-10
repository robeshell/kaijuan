import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_corpus.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_book_structure_session.dart';
import 'package:kaijuan/domain/book_structure.dart';

void main() {
  test('one cached structure drives work lookup for all AI features', () async {
    var loads = 0;
    final corpus = AiBookCorpusCache(
      loadBookBody:
          (maxChars, {required toc, startSection, endSectionExclusive}) async {
            loads++;
            if (toc) {
              return '''
[§1@3~+17 魔法石]
第一部正文样本
[§2@25~+18 密室]
第二部正文样本
''';
            }
            return '[§1@3 第一章]\n正文';
          },
      loadChapter: () async => '',
    );
    final session = AiBookStructureSession(
      corpus: corpus,
      isSupplementTitle: (_) => false,
    );

    final first = await session.resolve(maxChars: 100000);
    final second = await session.resolve(maxChars: 100000);

    expect(first, hasLength(2));
    expect(identical(first, second), isTrue);
    expect(session.manifest?.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(session.hasCollectionWorks, isTrue);
    expect(session.hasAmbiguousInternalWorks, isFalse);
    expect(session.workAtSection(30)?.title, '密室');
    expect(loads, 2);
  });

  test('typed structure index is preferred over legacy正文 extraction', () async {
    var corpusLoads = 0;
    var indexLoads = 0;
    final corpus = AiBookCorpusCache(
      loadBookBody:
          (maxChars, {required toc, startSection, endSectionExclusive}) async {
            corpusLoads++;
            return '[§1@1 第一章]\n旧正文路径';
          },
      loadChapter: () async => '旧章节',
    );
    final session = AiBookStructureSession(
      corpus: corpus,
      isSupplementTitle: (_) => false,
      loadIndex: () async {
        indexLoads++;
        return const BookStructureIndex(
          indexVersion: 1,
          sections: [
            BookStructureSection(
              sectionIndex: 0,
              href: 'chapter.xhtml',
              documentTitle: '第一章',
              bodyCharCount: 1000,
              headings: [],
            ),
          ],
          navigation: [
            BookStructureNavigationNode(
              nodeId: 'chapter',
              title: '第一章',
              depth: 0,
              order: 0,
              href: 'chapter.xhtml',
              sectionIndex: 0,
              directChildCount: 0,
            ),
          ],
        );
      },
    );

    await session.resolve(maxChars: 100000);
    await session.resolve(maxChars: 100000);

    expect(session.index, isNotNull);
    expect(session.manifest?.kind, AiBookStructureKind.singleWork);
    expect(indexLoads, 1);
    expect(corpusLoads, 0);
  });
}

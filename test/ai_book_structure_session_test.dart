import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_corpus.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_book_structure_session.dart';

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
}

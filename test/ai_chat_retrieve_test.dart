import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';

void main() {
  const sampleBook = '''
[§1 汉代]
汉代讲三公九卿与察举。

[§2 唐代]
唐代讲三省六部与科举。石神终于开始做规划，细节写得很密。

[§3 宋代]
宋代讲相权削弱。

[§4 明代]
明代废宰相。

[§5 清代]
清代军机处。
''';

  test('splitSections parses spine markers', () {
    final sections = AiChatRetrieve.splitSections(sampleBook);
    expect(sections.length, 5);
    expect(sections[1].text, contains('三省六部'));
  });

  test('splitSections preserves an original spine index for logical units', () {
    const logicalBook = '[§12@1 第一部]\n正文';

    final section = AiChatRetrieve.splitSections(logicalBook).single;

    expect(section.index, 12);
    expect(section.sourceSectionIndex, 1);
    expect(section.originSectionIndex, 1);
    expect(section.label, '第一部');
  });

  test('splitSections preserves an authoritative navigation unit marker', () {
    const logicalBook = '[§12@1~ 第一部]\n正文';

    final section = AiChatRetrieve.splitSections(logicalBook).single;

    expect(section.isNavigationUnit, isTrue);
    expect(section.label, '第一部');
  });

  test('whole-book query samples every lecture', () {
    expect(
      AiChatRetrieve.isWholeBookQuery('请根据提供的各部分正文，概括**整本书**的主线与主题'),
      isTrue,
    );
    final packed = AiChatRetrieve.pack(
      userText: '根据这本书的正文，概括主线与主题',
      selection: '',
      bookBody: sampleBook,
      maxRelatedChars: 2000,
    );
    expect(packed.mode, AiChatPackMode.wholeBook);
    final indexes = packed.relatedSections.map((s) => s.index).toSet();
    expect(indexes, containsAll([1, 2, 3, 4, 5]));
    expect(packed.sectionOutline.length, 5);
  });

  test('focused pack boosts selection section', () {
    final packed = AiChatRetrieve.pack(
      userText: '为什么石神不在一开始就做好规划，而是现在才来做？',
      selection: '石神终于开始做规划，细节写得很密。',
      bookBody: sampleBook,
      maxSections: 4,
    );
    expect(packed.mode, AiChatPackMode.focused);
    final indexes = packed.relatedSections.map((s) => s.index).toList();
    expect(indexes, contains(2));
  });

  test('pack falls back when no tokens match', () {
    final packed = AiChatRetrieve.pack(
      userText: '??????',
      selection: '',
      bookBody: sampleBook,
      maxSections: 2,
      maxRelatedChars: 200,
    );
    expect(packed.mode, AiChatPackMode.focused);
    expect(packed.relatedSections, isNotEmpty);
    expect(packed.relatedSections.first.index, 1);
  });
}

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

  test('splitSections preserves navigation child count', () {
    const logicalBook = '[§12@4~+17 魔法石]\n正文';

    final section = AiChatRetrieve.splitSections(logicalBook).single;

    expect(section.isNavigationUnit, isTrue);
    expect(section.navigationChildCount, 17);
    expect(section.sourceSectionIndex, 4);
    expect(section.label, '魔法石');
  });

  test('splitSections parses heading level and keeps empty containers', () {
    // Book-level container (level 1, empty body) + piece (level 2): the
    // chooser rebuilds the work → book → piece tree from this.
    const logicalBook = '''
[§1@4#1 呐喊]

[§2@4#2 狂人日记]
某君昆仲。

[§3@4#2 孔乙己]
鲁镇的酒店的格局。
''';

    final sections = AiChatRetrieve.splitSections(logicalBook);

    expect(sections, hasLength(3));
    expect(sections[0].level, 1);
    expect(sections[0].text, isEmpty);
    expect(sections[0].label, '呐喊');
    expect(sections[1].level, 2);
    expect(sections[1].label, '狂人日记');
    expect(sections[1].originSectionIndex, 4);
    expect(sections[2].level, 2);
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

  test('long whole-book sampling spans the first and last sections', () {
    final body = StringBuffer();
    for (var i = 1; i <= 120; i++) {
      body.writeln('[§$i 第$i章]\n${'正文$i。' * 200}');
    }
    final packed = AiChatRetrieve.pack(
      userText: '概括整本书的主线与主题',
      selection: '',
      bookBody: body.toString(),
      maxSections: 16,
      maxRelatedChars: 18000,
    );

    final indexes = packed.relatedSections.map((s) => s.index).toList();
    expect(indexes, hasLength(16));
    expect(indexes.first, 1);
    expect(indexes.last, 120);
    expect(indexes.where((index) => index > 60), isNotEmpty);
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

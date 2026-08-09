import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';

void main() {
  AiBookStructureManifest resolve(String navigation, String spine) =>
      AiBookStructureResolver.resolve(
        navigationSections: AiChatRetrieve.splitSections(navigation),
        spineSections: AiChatRetrieve.splitSections(spine),
        isSupplementTitle: (title) =>
            title.contains('封面') || title.startsWith('作者小传'),
      );

  test('ordinary chapter-per-spine novel stays one work', () {
    final manifest = resolve(
      '''
[§1@2~ 第一章 初见]
第一章正文
[§2@3~ 第二章 远行]
第二章正文
[§3@4~ 第三章 归来]
第三章正文
''',
      '''
[§1@2 第一章 初见]
第一章正文
[§2@3 第二章 远行]
第二章正文
[§3@4 第三章 归来]
第三章正文
''',
    );

    expect(manifest.kind, AiBookStructureKind.singleWork);
    expect(manifest.scopedWorks, isEmpty);
  });

  test('parts with child chapters are one segmented work', () {
    final manifest = resolve(
      '''
[§1@2~+8 第一部]
第一部正文
[§2@10~+7 第二部]
第二部正文
[§3@20~+5 第三部]
第三部正文
''',
      '''
[§1@2 第一章]
正文
[§2@10 第九章]
正文
[§3@20 第十六章]
正文
''',
    );

    expect(manifest.kind, AiBookStructureKind.segmentedSingleWork);
    expect(manifest.works.map((work) => work.title), ['第一部', '第二部', '第三部']);
    expect(manifest.scopedWorks, isEmpty);
  });

  test('hierarchical omnibus uses TOC anchors, not chapter spine density', () {
    final manifest = resolve(
      '''
[§1@3~+17 魔法石]
第一部正文样本
[§2@25~+18 密室]
第二部正文样本
[§3@51~+22 阿兹卡班的囚徒]
第三部正文样本
''',
      '''
[§1@3 第一章]
正文
[§2@4 第二章]
正文
[§3@5 第三章]
正文
''',
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.scopedWorks, hasLength(3));
    expect(manifest.scopedWorks[0].startSection, 3);
    expect(manifest.scopedWorks[0].endSectionExclusive, 25);
    expect(manifest.workAtSpine(30)?.title, '密室');
  });

  test('later omnibus works survive a truncated spine fact sample', () {
    final navigation = StringBuffer();
    for (var i = 0; i < 7; i++) {
      navigation.writeln(
        '[§${i + 1}@${i * 30 + 2}~+20 作品${i + 1}]\n作品${i + 1}样本',
      );
    }
    final manifest = resolve(
      navigation.toString(),
      '[§1@2 第一章]\n只有书首 spine 被采到',
    );

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.scopedWorks, hasLength(7));
    expect(manifest.scopedWorks.last.startSection, 182);
  });

  test('flat evocative chapter navigation defaults to one work', () {
    final manifest = resolve(
      '''
[§1@2~ 风起]
正文
[§2@3~ 云涌]
正文
[§3@4~ 潮落]
正文
''',
      '''
[§1@2 风起]
正文
[§2@3 云涌]
正文
[§3@4 潮落]
正文
''',
    );

    expect(manifest.kind, AiBookStructureKind.singleWork);
    expect(manifest.works, isEmpty);
    expect(manifest.scopedWorks, isEmpty);
    expect(manifest.requiresUserScopeConfirmation, isFalse);
    expect(manifest.requiresLogicalWorkLocator, isFalse);
  });

  test('multiple logical works in one spine fail closed', () {
    final manifest = resolve('[§1@4~ 合订正文]\n正文', '''
[§1@4#1 呐喊]
[§2@4#2 狂人日记]
正文一
[§3@4#1 彷徨]
[§4@4#2 祝福]
正文二
''');

    expect(manifest.kind, AiBookStructureKind.uncertain);
    expect(manifest.works.map((work) => work.title), ['呐喊', '彷徨']);
    expect(manifest.works.every((work) => work.needsLogicalLocator), isTrue);
    expect(manifest.requiresLogicalWorkLocator, isTrue);
    expect(manifest.scopedWorks, isEmpty);
  });

  test('duplicate navigation starts fail closed even without parsed works', () {
    final manifest = resolve('''
[§1@4~ 作品甲]
正文甲
[§2@4~ 作品乙]
正文乙
''', '[§1@4 合订正文]\n正文');

    expect(manifest.kind, AiBookStructureKind.uncertain);
    expect(manifest.works, isEmpty);
    expect(manifest.requiresLogicalWorkLocator, isTrue);
    expect(manifest.scopedWorks, isEmpty);
  });

  test('supplement navigation is excluded before classification', () {
    final manifest = resolve('''
[§1@1~ 系列封面]
图片说明
[§2@2~ 作者小传：罗琳]
作者生平
[§3@3~+10 魔法石]
正文一
[§4@20~+12 密室]
正文二
''', '[§1@3 第一章]\n正文');

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.map((work) => work.title), ['魔法石', '密室']);
  });

  test('a trailing supplement bounds the final work without becoming one', () {
    final manifest = resolve('''
[§1@3~+10 魔法石]
正文一
[§2@20~+12 密室]
正文二
[§3@42~ 作者小传：罗琳]
作者生平
''', '[§1@3 第一章]\n正文');

    expect(manifest.kind, AiBookStructureKind.multiWorkOmnibus);
    expect(manifest.works.last.title, '密室');
    expect(manifest.works.last.endSectionExclusive, 42);
    expect(manifest.workAtSpine(41)?.title, '密室');
    expect(manifest.workAtSpine(42), isNull);
  });
}

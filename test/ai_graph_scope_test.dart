import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph_scope.dart';

void main() {
  group('AiGraphScopePlanner', () {
    test('keeps supplements visible and only changes their recommendation', () {
      final plan = AiGraphScopePlanner.build(
        sections: const [
          AiBookSectionSlice(index: 1, label: '前言', text: '作者的话'),
          AiBookSectionSlice(index: 2, label: '第一章', text: '正文'),
          AiBookSectionSlice(index: 3, label: '目录', text: ''),
        ],
        isSuggestedSupplement: (title) => title == '前言' || title == '目录',
      );

      expect(plan.choices, hasLength(3));
      expect(plan.choices[0].role, AiGraphSectionRole.suggestedSupplement);
      expect(plan.choices[0].canSelect, isTrue);
      expect(plan.choices[1].selectedByDefault, isTrue);
      expect(plan.choices[2].role, AiGraphSectionRole.unavailable);
      expect(plan.recommendedExcluded, {1, 3});
    });

    test('applies a recognized work range without filtering its contents', () {
      const work = AiBookWork(
        id: 's4',
        title: '第二部作品',
        startSection: 4,
        endSectionExclusive: 6,
      );
      final plan = AiGraphScopePlanner.build(
        work: work,
        sections: const [
          AiBookSectionSlice(
            index: 1,
            sourceSectionIndex: 3,
            label: '第一部',
            text: '一',
          ),
          AiBookSectionSlice(
            index: 2,
            sourceSectionIndex: 4,
            label: '第二部前言',
            text: '二',
          ),
          AiBookSectionSlice(
            index: 3,
            sourceSectionIndex: 5,
            label: '第二部正文',
            text: '三',
          ),
          AiBookSectionSlice(
            index: 4,
            sourceSectionIndex: 6,
            label: '第三部',
            text: '四',
          ),
        ],
        isSuggestedSupplement: (title) => title.endsWith('前言'),
      );

      expect(plan.choices.map((choice) => choice.section.label), [
        '第二部前言',
        '第二部正文',
      ]);
      expect(plan.recommendedExcluded, {2});
    });
  });
}

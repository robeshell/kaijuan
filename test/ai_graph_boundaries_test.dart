import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph_evidence.dart';
import 'package:kaijuan/ai/ai_graph_response.dart';

void main() {
  test('structured response accepts only a complete JSON object', () {
    expect(AiGraphResponse.decodeObject('```json\n{"entities": []}\n```'), {
      'entities': <dynamic>[],
    });
    expect(AiGraphResponse.decodeObject('prefix {"entities": []}'), isNull);
    expect(AiGraphResponse.decodeObject('```json\n{"entities": []}'), isNull);
  });

  test(
    'evidence uses caller section and grounds whitespace-normalized quote',
    () {
      final evidence = AiGraphEvidenceGrounder.fromRaw(
        const [
          {'section': 999, 'quote': '哈利 进入礼堂'},
          {'section': 1000, 'quote': '哈利 进入礼堂'},
        ],
        sectionIndex: 7,
        sectionText: '清晨，哈利\n进入礼堂参加分院仪式。',
      );

      expect(evidence, hasLength(1));
      expect(evidence.single.sectionIndex, 7);
      expect(evidence.single.spanResolved, isTrue);
      expect(evidence.single.progressInSection, isNotNull);
    },
  );
}

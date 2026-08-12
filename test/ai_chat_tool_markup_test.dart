import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_chat_tool_markup.dart';

void main() {
  group('AiChatToolMarkup', () {
    const leaked = '''
我取到了足够的原文证据。让我读取汤川向草薙点破「尸体身份」真相的核心章节。

<|DSML|tool_calls>
<|DSML|invoke name="get_chapter">
<|DSML|parameter name="maxChars" string="false">6000</|DSML|parameter>
<|DSML|parameter name="sectionIndex" string="false">22</|DSML|parameter>
</|DSML|invoke>
</|DSML|tool_calls>
''';

    test('detects DSML tool-call envelopes', () {
      expect(AiChatToolMarkup.looksLikeLeakedToolCall(leaked), isTrue);
      expect(
        AiChatToolMarkup.looksLikeLeakedToolCall('本章主要讲分院仪式与邓布利多致辞。'),
        isFalse,
      );
    });

    test('strips DSML while keeping reader prose', () {
      final cleaned = AiChatToolMarkup.stripLeakedToolCall(leaked);
      expect(cleaned, contains('原文证据'));
      expect(cleaned, isNot(contains('DSML')));
      expect(cleaned, isNot(contains('get_chapter')));
    });

    test('parses DSML invoke into native tool calls', () {
      final calls = AiChatToolMarkup.tryParseLeakedCalls(leaked);
      expect(calls, hasLength(1));
      expect(calls.single.name, 'get_chapter');
      expect(calls.single.arguments['sectionIndex'], 22);
      expect(calls.single.arguments['maxChars'], 6000);
    });
  });
}

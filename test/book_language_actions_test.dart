import 'package:flutter_test/flutter_test.dart';

import 'package:kaijuan/readers/book/book_language_actions.dart';

void main() {
  test(
    'language requests keep the operation and text for future providers',
    () {
      const request = BookLanguageRequest(
        operation: BookLanguageOperation.fullBookTranslation,
        text: 'A whole book',
      itemId: 'book-7',
        cfi: 'epubcfi(/6/2)',
        sourceLanguage: 'en',
        targetLanguage: 'zh-Hans',
      );

      expect(request.operation, BookLanguageOperation.fullBookTranslation);
      expect(request.text, 'A whole book');
    expect(request.itemId, 'book-7');
      expect(request.cfi, 'epubcfi(/6/2)');
      expect(request.sourceLanguage, 'en');
      expect(request.targetLanguage, 'zh-Hans');
    },
  );

  test(
    'empty platform request is handled without invoking native code',
    () async {
      const provider = PlatformBookLanguageProvider();
      final result = await provider.execute(
        const BookLanguageRequest(
          operation: BookLanguageOperation.dictionary,
          text: '  ',
        ),
      );

      expect(result.status, BookLanguageActionStatus.unavailable);
      expect(result.message, '没有可查询的文字');
    },
  );

  test('legacy AI provider hook stays unsupported', () async {
    const provider = AiBookLanguageProvider();
    final result = await provider.execute(
      const BookLanguageRequest(
        operation: BookLanguageOperation.selectionTranslation,
        text: 'hello',
      ),
    );

    expect(result.status, BookLanguageActionStatus.unsupported);
    expect(result.message, contains('启用 AI'));
  });
}

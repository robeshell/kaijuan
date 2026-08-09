import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_corpus.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';

void main() {
  test('navigation and spine corpora keep independent caches', () async {
    final calls = <String>[];
    final corpus = AiBookCorpusCache(
      loadBookBody:
          (maxChars, {required toc, startSection, endSectionExclusive}) async {
            calls.add('$toc:$maxChars:$startSection:$endSectionExclusive');
            return toc ? 'navigation body' : 'spine body';
          },
      loadChapter: () async => 'chapter fallback',
    );

    expect(await corpus.loadNavigation(4000), 'navigation body');
    expect(await corpus.loadNavigation(3000), 'navigation body');
    expect(await corpus.loadSpine(4000), 'spine body');
    expect(calls, ['true:4000:null:null', 'false:4000:null:null']);

    corpus.clear();
    expect(await corpus.loadNavigation(3000), 'navigation body');
    expect(calls, hasLength(3));
  });

  test('chat corpus loader applies the work range before caching', () async {
    final calls = <String>[];
    final corpus = AiBookCorpusCache(
      loadBookBody:
          (maxChars, {required toc, startSection, endSectionExclusive}) async {
            calls.add('$startSection:$endSectionExclusive');
            return 'work body';
          },
      loadChapter: () async => 'fallback',
    );
    const work = AiBookWork(
      id: 's3',
      title: '作品二',
      startSection: 3,
      endSectionExclusive: 6,
    );

    expect(await corpus.loadChat(5000, work), 'work body');
    expect(await corpus.loadChat(4000, work), 'work body');
    expect(calls, ['3:6']);
  });

  test('concurrent spine reads share one reader extraction', () async {
    final gate = Completer<String>();
    var calls = 0;
    final corpus = AiBookCorpusCache(
      loadBookBody:
          (maxChars, {required toc, startSection, endSectionExclusive}) {
            calls++;
            return gate.future;
          },
      loadChapter: () async => 'fallback',
    );

    final first = corpus.loadSpine(5000);
    final second = corpus.loadSpine(4000);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    gate.complete('shared body');
    expect(await first, 'shared body');
    expect(await second, 'shared body');
    expect(calls, 1);
  });

  test(
    'clear prevents an old in-flight read from repopulating the cache',
    () async {
      final firstGate = Completer<String>();
      var calls = 0;
      final corpus = AiBookCorpusCache(
        loadBookBody:
            (maxChars, {required toc, startSection, endSectionExclusive}) {
              calls++;
              return calls == 1 ? firstGate.future : Future.value('fresh body');
            },
        loadChapter: () async => 'fallback',
      );

      final stale = corpus.loadSpine(5000);
      await Future<void>.delayed(Duration.zero);
      corpus.clear();
      firstGate.complete('stale body');
      expect(await stale, 'stale body');

      expect(await corpus.loadSpine(5000), 'fresh body');
      expect(calls, 2);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_corpus.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/presentation/controllers/book_ai_reader_gateway.dart';
import 'package:kaijuan/presentation/controllers/book_ai_workspace_controller.dart';

void main() {
  const work = AiBookWork(
    id: 'work-1',
    title: '第二部',
    startSection: 2,
    endSectionExclusive: 4,
  );

  late BookAiWorkspaceController workspace;
  late BookAiReaderGateway gateway;

  setUp(() {
    workspace = BookAiWorkspaceController(saveChatSession: (_) async {});
    gateway = BookAiReaderGateway(
      workspace,
      AiBookCorpusCache(
        loadBookBody:
            (_, {required toc, startSection, endSectionExclusive}) async => '',
        loadChapter: () async => '',
      ),
    );
  });

  tearDown(() => workspace.dispose());

  test('freezes reader selection, chapter and work-scoped TOC', () async {
    final context = await gateway.loadContext(
      chapterSectionIndex: 3,
      chapterTitle: '第三章',
      tocTitles: const ['序', '第二章', '第三章', '附录'],
      workScope: work,
      currentSelection: '当前选区',
      loadSelectedText: () async => '不应覆盖已有选区',
      loadChapterText: () async => '本章正文',
    );

    expect(context.chapterSectionIndex, 3);
    expect(context.chapterTitle, '第三章');
    expect(context.chapterText, '本章正文');
    expect(context.selectionText, '当前选区');
    expect(context.tocOutline, ['第二章', '第三章']);
    expect(context.scopeLabel, '第二部');
  });

  test('context failure preserves stable chapter identity', () async {
    final context = await gateway.loadContext(
      chapterSectionIndex: 2,
      chapterTitle: '第二章',
      tocTitles: const ['第一章', '第二章'],
      workScope: null,
      loadChapterText: () async => throw StateError('renderer unavailable'),
    );

    expect(context.chapterSectionIndex, 2);
    expect(context.chapterTitle, '第二章');
    expect(context.chapterText, isEmpty);
  });

  test(
    'unbound runtime and search fail through stable capability boundary',
    () async {
      expect(
        gateway.streamChat(
          contentHash: 'hash',
          bookTitle: '书名',
          bookAuthor: null,
          userText: '解释本章',
          history: const [],
          context: const AiChatContextBundle(),
          workScope: null,
        ),
        isNull,
      );
      await expectLater(
        gateway.searchWeb(query: '资料', bookTitle: '书名', bookAuthor: null),
        throwsA(isA<AiProviderException>()),
      );
    },
  );
}

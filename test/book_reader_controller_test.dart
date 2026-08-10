import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_chat_store.dart';
import 'package:kaijuan/ai/ai_chat_retrieve.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_scope.dart';
import 'package:kaijuan/ai/ai_graph_store.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_outline.dart';
import 'package:kaijuan/app/book_reading_preferences.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/book_reader_controller.dart';
import 'package:kaijuan/readers/book/book_models.dart';
import 'package:kaijuan/readers/book/book_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaika_book_ctrl_');
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ReadingItem> insertBook({
    required String id,
    String title = 'Test Book',
  }) async {
    final now = DateTime.utc(2026, 1, 1);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: id,
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: title,
        filePath: '/tmp/$id.epub',
        contentHash: 'hash-$id',
        pageCount: const Value(3),
        addedAt: now,
        updatedAt: now,
      ),
    );
    return database.readingItemById(id).then((r) => r!);
  }

  const sectionMap = BookSectionMap(
    startIndices: [0, 10, 25],
    totalParagraphs: 40,
  );
  const tocTitles = ['Chapter 1', 'Chapter 2', 'Chapter 3'];

  group('defaults', () {
    test('without prefs', () async {
      final item = await insertBook(id: 'defaults');
      final controller = BookReaderController(database: database, item: item);

      expect(controller.fontSize, 18.0);
      expect(controller.lineHeight, 1.7);
      expect(controller.readingTheme, BookReadingTheme.paper);
      expect(controller.margin, 24.0);
      expect(controller.readingMode, BookReadingMode.page);
      expect(controller.isReady, isFalse);
      expect(controller.chromeVisible, isFalse);

      controller.dispose();
    });

    test('with prefs', () async {
      final prefs = await BookReadingPreferences.load(
        supportDirectory: tempDir,
      );
      await prefs.setFontSize(22);
      await prefs.setLineHeight(1.8);
      await prefs.setReadingTheme(BookReadingTheme.sepia);
      await prefs.setMargin(32);
      await prefs.setReadingMode(BookReadingMode.page);

      final item = await insertBook(id: 'with-prefs');
      final controller = BookReaderController(
        database: database,
        item: item,
        readingPreferences: prefs,
      );

      expect(controller.fontSize, 22.0);
      expect(controller.lineHeight, 1.8);
      expect(controller.readingTheme, BookReadingTheme.sepia);
      expect(controller.margin, 32.0);
      expect(controller.readingMode, BookReadingMode.page);

      controller.dispose();
    });
  });

  test('saved full graph stays visible across device-local progress', () async {
    final item = await insertBook(id: 'cross-device-graph');
    final controller = BookReaderController(database: database, item: item);
    await controller.attachEngine(sectionMap, tocTitles);
    final store = AiGraphStore(tempDir);
    controller.attachAiGraphStore(store);
    await store.write(
      AiBookGraph(
        contentHash: item.contentHash,
        generatedAt: DateTime.utc(2026, 8, 9),
        model: 'test',
        includesUnread: true,
        coveredSections: const [5],
        sectionTitles: const {5: '第五章'},
        entities: const [
          AiGraphEntity(
            name: '移动端不应隐藏的人物',
            type: AiGraphEntityType.person,
            evidence: [
              AiGraphEvidence(
                sectionIndex: 5,
                quote: '移动端不应隐藏的人物出场。',
                spanResolved: true,
              ),
            ],
            chapterFreq: {5: 1},
            firstSection: 5,
            lastSection: 5,
          ),
        ],
        relations: const [],
      ),
    );

    // This device is still at section 1 and may have the local unread switch
    // off. The saved graph's generation scope remains the source of truth.
    await controller.loadBookGraph();
    expect(controller.sectionIndex, 0);
    expect(controller.visibleBookGraph?.entities, hasLength(1));
    expect(controller.visibleBookGraph?.entities.single.name, '移动端不应隐藏的人物');
    controller.dispose();
  });

  test('empty covered graph cannot suppress a fresh extraction run', () {
    const emptyCovered = AiBookGraph(
      contentHash: 'empty-covered',
      coveredSections: [1, 2, 3],
    );
    const grounded = AiBookGraph(
      contentHash: 'grounded',
      coveredSections: [1],
      entities: [
        AiGraphEntity(
          name: '有效实体',
          type: AiGraphEntityType.concept,
          evidence: [
            AiGraphEvidence(sectionIndex: 1, quote: '有效实体', spanResolved: true),
          ],
          chapterFreq: {1: 1},
          firstSection: 1,
          lastSection: 1,
        ),
      ],
    );

    expect(
      BookReaderController.graphCanResumeIncrementally(emptyCovered),
      isFalse,
    );
    expect(BookReaderController.graphCanResumeIncrementally(grounded), isTrue);
  });

  test('confirmed graph range is not clipped by renderer progress', () {
    expect(
      BookReaderController.graphReadThroughForGeneration(
        userConfirmedScope: true,
        resettingEmptySnapshot: false,
        existingIncludesUnread: false,
        allowUnread: false,
        readThrough: 1,
      ),
      isNull,
    );
    expect(
      BookReaderController.graphReadThroughForGeneration(
        userConfirmedScope: false,
        resettingEmptySnapshot: false,
        existingIncludesUnread: false,
        allowUnread: false,
        readThrough: 7,
      ),
      7,
    );
  });

  test('attachEngine makes controller ready and exposes metadata', () async {
    final item = await insertBook(id: 'attach');
    final controller = BookReaderController(database: database, item: item);

    final attaching = controller.attachEngine(sectionMap, tocTitles);
    expect(controller.isReady, isFalse);
    await attaching;

    expect(controller.isReady, isTrue);
    expect(controller.sectionCount, 3);
    expect(controller.tocTitles, tocTitles);
    expect(controller.sectionLabel, '1 / 3');

    controller.dispose();
  });

  test('saveChatSession keeps freshly generated work outlines', () async {
    final item = await insertBook(id: 'chat-session');
    final controller = BookReaderController(database: database, item: item);
    await controller.attachEngine(sectionMap, tocTitles);
    final store = JsonAiChatHistoryStore(tempDir);
    controller.attachChatHistoryStore(store);

    final outline = AiBookOutline(
      createdAt: DateTime.utc(2026, 1, 1),
      model: 'test',
      overview: '概述',
      units: const [AiOutlineUnit(title: '主题', blurb: '一句话说明。')],
    );
    final fresh = AiChatSession(
      contentHash: item.contentHash,
      itemId: item.id,
      workOutlines: {'s1': outline},
    );
    await store.write(fresh);

    // A stale sheet snapshot (no work outlines, e.g. before generation)
    // must not wipe the freshly generated outline on save.
    final snapshot = AiChatSession(
      contentHash: item.contentHash,
      itemId: item.id,
    );
    await controller.saveChatSession(snapshot);

    final reloaded = await controller.loadChatSession();
    expect(reloaded.workOutlines['s1']?.overview, '概述');
    expect(reloaded.outline, isNull);

    controller.dispose();
  });

  test(
    'saveChatSession stale snapshot never rolls back disk outlines',
    () async {
      final item = await insertBook(id: 'chat-session-v2');
      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);
      final store = JsonAiChatHistoryStore(tempDir);
      controller.attachChatHistoryStore(store);

      final v1 = AiBookOutline(
        createdAt: DateTime.utc(2026, 1, 1),
        model: 'test',
        overview: '旧版',
        units: const [AiOutlineUnit(title: '旧', blurb: '旧主题。')],
      );
      final v2 = AiBookOutline(
        createdAt: DateTime.utc(2026, 1, 2),
        model: 'test',
        overview: '新版',
        units: const [AiOutlineUnit(title: '新', blurb: '新主题。')],
      );
      // Disk already holds V2 (fresh generation); the sheet snapshot is stale
      // V1 plus a new chat message — saving it must keep V2.
      await store.write(
        AiChatSession(
          contentHash: item.contentHash,
          itemId: item.id,
          workOutlines: {'s1': v2},
        ),
      );
      final stale = AiChatSession(
        contentHash: item.contentHash,
        itemId: item.id,
        workOutlines: {'s1': v1},
        messages: [
          AiChatMessage(
            role: AiMessageRole.user,
            content: 'hi',
            createdAt: DateTime.utc(2026, 1, 3),
          ),
        ],
      );
      await controller.saveChatSession(stale);

      final reloaded = await controller.loadChatSession();
      expect(reloaded.workOutlines['s1']?.overview, '新版');
      expect(reloaded.messages.length, 1);

      controller.dispose();
    },
  );

  test('saveChatSession does not resurrect a deleted outline', () async {
    final item = await insertBook(id: 'chat-session-deleted');
    final controller = BookReaderController(database: database, item: item);
    await controller.attachEngine(sectionMap, tocTitles);
    final store = JsonAiChatHistoryStore(tempDir);
    controller.attachChatHistoryStore(store);

    final deletedSnapshot = AiChatSession(
      contentHash: item.contentHash,
      itemId: item.id,
    );
    await store.write(deletedSnapshot);
    final staleOutline = AiBookOutline(
      createdAt: DateTime.utc(2026, 1, 1),
      model: 'test',
      overview: '已经删除',
      units: const [AiOutlineUnit(title: '旧', blurb: '旧主题。')],
    );
    await controller.saveChatSession(
      AiChatSession(
        contentHash: item.contentHash,
        itemId: item.id,
        outline: staleOutline,
        workOutlines: {'s1': staleOutline},
        messages: [
          AiChatMessage(
            role: AiMessageRole.user,
            content: '保留这条聊天',
            createdAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      ),
    );

    final reloaded = await controller.loadChatSession();
    expect(reloaded.outline, isNull);
    expect(reloaded.workOutlines, isEmpty);
    expect(reloaded.messages.single.content, '保留这条聊天');

    controller.dispose();
  });

  test('desktop capability rejects scroll mode', () async {
    final item = await insertBook(id: 'page-only');
    final controller = BookReaderController(
      database: database,
      item: item,
      scrollModeEnabled: false,
    );

    await controller.setReadingMode(BookReadingMode.scroll);

    expect(controller.readingMode, BookReadingMode.page);
    expect(controller.scrollModeEnabled, isFalse);
    controller.dispose();
  });

  test('font size and line height clamp', () async {
    final item = await insertBook(id: 'clamp');
    final controller = BookReaderController(database: database, item: item);

    await controller.setFontSize(5);
    expect(controller.fontSize, 14.0);

    await controller.setFontSize(50);
    expect(controller.fontSize, 28.0);

    await controller.setLineHeight(0.5);
    expect(controller.lineHeight, 1.2);

    await controller.setLineHeight(5);
    expect(controller.lineHeight, 2.2);

    controller.dispose();
  });

  test('pureBlack theme is preserved', () async {
    final item = await insertBook(id: 'pure-black');
    final controller = BookReaderController(database: database, item: item);

    await controller.setReadingTheme(BookReadingTheme.pureBlack);
    expect(controller.readingTheme, BookReadingTheme.pureBlack);

    controller.dispose();
  });

  group('progress', () {
    test('restores BookLocator from DB', () async {
      final item = await insertBook(id: 'restore');
      await database.upsertProgress(
        itemId: item.id,
        locatorJson: const BookLocator(
          sectionIndex: 1,
          progressInSection: 0.5,
        ).encode(),
        progressFraction: 0.5,
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);

      // Restore is async; wait for it.
      await pumpEventQueue();

      expect(controller.sectionIndex, 1);
      expect(controller.progressInSection, closeTo(0.5, 1e-9));
      final jump = controller.pendingJump;
      expect(jump, isNotNull);
      expect(jump!.sectionIndex, 1);
      expect(jump.progressInSection, closeTo(0.5, 1e-9));
      controller.clearPendingJump();
      expect(controller.pendingJump, isNull);

      controller.dispose();
    });

    test('migrates legacy katbook paragraph JSON', () async {
      final legacyItem = await insertBook(id: 'legacy');
      await database.upsertProgress(
        itemId: legacyItem.id,
        locatorJson: '{"paragraphIndex": 12, "totalParagraphs": 40}',
        progressFraction: 0.3,
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final legacyController = BookReaderController(
        database: database,
        item: legacyItem,
      );
      await legacyController.attachEngine(sectionMap, tocTitles);
      await pumpEventQueue();

      expect(legacyController.sectionIndex, 1);
      expect(legacyController.progressInSection, closeTo(2 / 15, 1e-9));

      legacyController.dispose();
    });

    test('rendition CFI location persists', () async {
      final item = await insertBook(id: 'persist');
      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);
      await pumpEventQueue();

      controller.reportRenditionLocation(
        sectionIndex: 1,
        progress: 0.49,
        cfi: 'epubcfi(/6/4!/4/2)',
      );
      expect(controller.sectionIndex, 1);
      expect(controller.currentLocator.cfi, 'epubcfi(/6/4!/4/2)');

      // Wait for the 500 ms debounce.
      await Future.delayed(const Duration(milliseconds: 600));

      final progress = await database.progressFor(item.id);
      expect(progress, isNotNull);
      final locator = BookLocator.tryDecode(progress!.locatorJson);
      expect(locator, isNotNull);
      expect(locator!.sectionIndex, 1);
      expect(locator.cfi, 'epubcfi(/6/4!/4/2)');

      controller.dispose();
    });
  });

  group('navigation', () {
    test('goToSection and prev/next clamp at bounds', () async {
      final item = await insertBook(id: 'nav');
      final controller = BookReaderController(database: database, item: item);
      await controller.attachEngine(sectionMap, tocTitles);

      controller.goToSection(2);
      expect(controller.sectionIndex, 2);
      expect(controller.progressInSection, 0.0);
      expect(controller.pendingJump, isNotNull);
      controller.clearPendingJump();
      expect(controller.pendingJump, isNull);

      controller.goNextSection();
      expect(controller.sectionIndex, 2); // clamped

      controller.goPreviousSection();
      expect(controller.sectionIndex, 1);

      controller.goToSection(-1);
      expect(controller.sectionIndex, 0);

      controller.dispose();
    });

    test(
      'setReadingMode keeps a semantic locator for Foliate reflow',
      () async {
        final item = await insertBook(id: 'scroll-handoff');
        final controller = BookReaderController(database: database, item: item);
        await controller.attachEngine(sectionMap, tocTitles);
        controller.goToSection(2, progressInSection: 0.42);

        await controller.setReadingMode(BookReadingMode.scroll);

        expect(controller.readingMode, BookReadingMode.scroll);
        expect(controller.pendingJump?.sectionIndex, 2);
        expect(controller.pendingJump?.progressInSection, closeTo(0.42, 0.001));

        controller.dispose();
      },
    );

    test('page actions delegate only to the active rendition', () async {
      final item = await insertBook(id: 'rendition-navigation');
      final controller = BookReaderController(database: database, item: item);
      var nextCount = 0;
      var previousCount = 0;

      expect(controller.hasPageMode, isFalse);
      controller.attachExternalPageNavigation(
        nextPage: () => nextCount++,
        previousPage: () => previousCount++,
      );
      expect(controller.hasPageMode, isTrue);

      controller.goNextPage();
      controller.goPreviousPage();
      expect(nextCount, 1);
      expect(previousCount, 1);

      controller.detachExternalPageNavigation();
      expect(controller.hasPageMode, isFalse);
      controller.dispose();
    });
  });

  test('bookmarks sort by locator, toggle, and jump', () async {
    final item = await insertBook(id: 'bookmark-controller');
    final controller = BookReaderController(database: database, item: item);
    await controller.attachEngine(sectionMap, tocTitles);
    await pumpEventQueue();

    await database.addBookmark(
      itemId: item.id,
      locatorJson: const BookLocator(
        sectionIndex: 2,
        progressInSection: 0.5,
      ).encode(),
    );
    await database.addBookmark(
      itemId: item.id,
      locatorJson: const BookLocator(
        sectionIndex: 0,
        progressInSection: 0.25,
      ).encode(),
    );
    await pumpEventQueue();

    expect(controller.bookmarks, hasLength(2));
    expect(
      controller.bookmarkLabel(controller.bookmarks.first),
      'Chapter 1 · 25%',
    );

    controller.goToBookmark(controller.bookmarks.first);
    expect(controller.sectionIndex, 0);
    expect(controller.progressInSection, closeTo(0.25, 1e-9));
    expect(controller.isCurrentPositionBookmarked, isTrue);

    await controller.toggleBookmark();
    await pumpEventQueue();
    expect(controller.bookmarks, hasLength(1));
    expect(controller.isCurrentPositionBookmarked, isFalse);

    await controller.toggleBookmark();
    await pumpEventQueue();
    expect(controller.bookmarks, hasLength(2));
    expect(controller.isCurrentPositionBookmarked, isTrue);

    controller.dispose();
  });

  test('preferences are persisted through controller setters', () async {
    final prefs = await BookReadingPreferences.load(supportDirectory: tempDir);
    final item = await insertBook(id: 'prefs-persist');
    final controller = BookReaderController(
      database: database,
      item: item,
      readingPreferences: prefs,
    );

    await controller.setFontSize(20);
    await controller.setLineHeight(1.8);
    await controller.setReadingTheme(BookReadingTheme.dark);
    await controller.setMargin(40);
    await controller.setReadingMode(BookReadingMode.page);
    await controller.setPageTurnEffect(BookPageTurnEffect.none);

    final reloaded = await BookReadingPreferences.load(
      supportDirectory: tempDir,
    );
    expect(reloaded.fontSize, 20.0);
    expect(reloaded.lineHeight, 1.8);
    expect(reloaded.readingTheme, BookReadingTheme.dark);
    expect(reloaded.margin, 40.0);
    expect(reloaded.readingMode, BookReadingMode.page);
    expect(reloaded.pageTurnEffect, BookPageTurnEffect.none);

    controller.dispose();
  });

  group('graph section chooser', () {
    test(
      'current mind-map chapter freezes renderer text and locator',
      () async {
        final item = await insertBook(id: 'mind-map-current-chapter');
        final controller = BookReaderController(database: database, item: item);
        addTearDown(controller.dispose);
        await controller.attachEngine(sectionMap, tocTitles);
        controller.goToSection(1);
        final chapter = Completer<String>();
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getChapterText: () => chapter.future,
        );

        final frozen = controller.captureCurrentBookMindMapChapter();
        controller.goToSection(2);
        chapter.complete('第二章正文');

        final section = await frozen;
        expect(section, isNotNull);
        expect(section!.originSectionIndex, 2);
        expect(section.label, 'Chapter 2');
        expect(section.text, '第二章正文');
        expect(controller.sectionIndex, 2);
      },
    );

    test(
      'chat scope narrows the body to the reading work, indices round-trip',
      () {
        const body = '''
[§1@1 目录]
目录列表
[§2@4 狂人日记]
某君昆仲。
[§3@4 孔乙己]
鲁镇的酒店的格局。
[§4@9 故乡]
我冒了严寒。
''';
        const work = AiGraphWorkCandidate(
          id: 's4',
          title: '鲁迅小说精品',
          startSection: 4,
          endSectionExclusive: 8,
        );

        final scoped = scopeChatBodyToWork(body, work);
        final sections = AiChatRetrieve.splitSections(scoped);
        expect(sections.map((s) => s.label), ['狂人日记', '孔乙己']);
        expect(sections.map((s) => s.index), [2, 3]);
        expect(sections.map((s) => s.originSectionIndex), [4, 4]);

        // A null work (plain book) is untouched too.
        expect(scopeChatBodyToWork(body, null), body);
      },
    );

    test(
      'chat scope falls back to the whole body when work cannot resolve',
      () {
        const body = '[§1@1 甲]\n甲正文\n[§2@2 乙]\n乙正文';
        const missing = AiGraphWorkCandidate(
          id: 's9',
          title: '不存在的作品',
          startSection: 9,
          endSectionExclusive: 10,
        );

        expect(scopeChatBodyToWork(body, missing), body);
      },
    );

    test(
      'chat scope does not collapse when one chapter matches work title',
      () {
        const body = '''
[§40@70 Ⅰ 哈利·波特与魔法石]
作品扉页。
[§41@71 第一章 大难不死的男孩]
第一章正文。
''';
        const work = AiGraphWorkCandidate(
          id: 's70',
          title: 'Ⅰ 哈利·波特与魔法石',
          startSection: 70,
          endSectionExclusive: 90,
        );

        final sections = AiChatRetrieve.splitSections(
          scopeChatBodyToWork(body, work),
        );
        expect(sections.map((section) => section.index), [40, 41]);
      },
    );

    test(
      'all chat tools share one ranged corpus, index space, and frozen chapter',
      () async {
        final item = await insertBook(id: 'chat-tools-ranged-omnibus');
        final controller = BookReaderController(database: database, item: item);
        final loads =
            <({bool toc, int? startSection, int? endSectionExclusive})>[];
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getChapterText: () async => '翻页后另一部作品的正文',
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async {
                loads.add((
                  toc: toc,
                  startSection: startSection,
                  endSectionExclusive: endSectionExclusive,
                ));
                // Include out-of-range rows to prove every tool still applies the
                // frozen work boundary even if an engine ignores range options.
                return '''
[§7@20 其他作品]
不应泄漏的伏地魔正文。
[§41@70 第七章 分院帽]
哈利参加了分院仪式。
[§42@71 第八章 魔药课老师]
斯内普在魔药课上向哈利提问牛黄。
[§90@100 下一部作品]
不应泄漏的蛇怪正文。
''';
              },
        );
        const work = AiGraphWorkCandidate(
          id: 's70',
          title: 'Ⅰ 哈利·波特与魔法石',
          startSection: 70,
          endSectionExclusive: 90,
        );
        final host = createBookChatToolHostForTesting(
          controller: controller,
          work: work,
          context: const AiChatContextBundle(
            chapterTitle: '第八章 魔药课老师',
            chapterText: '提问发出时冻结的第八章正文。',
          ),
        );

        final toc = await host.toolGetToc();
        final chapter = await host.toolGetChapter(42);
        final search = await host.toolSearchBook('斯内普');
        final sample = await host.toolSampleBook();
        final current = await host.toolGetCurrentChapter();

        expect(toc, '§41 第七章 分院帽\n§42 第八章 魔药课老师');
        expect(chapter, contains('斯内普在魔药课上'));
        expect(await host.toolGetChapter(8), contains('section 8 not found'));
        expect(search, contains('斯内普在魔药课上'));
        expect(search, isNot(contains('不应泄漏')));
        expect(sample, contains('分院仪式'));
        expect(sample, contains('斯内普在魔药课上'));
        expect(sample, isNot(contains('不应泄漏')));
        expect(current, contains('提问发出时冻结的第八章正文'));
        expect(current, isNot(contains('翻页后另一部作品')));
        expect(loads, [
          (toc: false, startSection: 70, endSectionExclusive: 90),
        ]);
        controller.dispose();
      },
    );

    test(
      'same-spine uncertain structure keeps whole-file AI available',
      () async {
        final item = await insertBook(id: 'same-spine-omnibus');
        final controller = BookReaderController(database: database, item: item);
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => toc
              ? '[§1@4~ 合订正文]\n正文'
              : '''
[§1@4#1 呐喊]
[§2@4#2 狂人日记]
正文一
[§3@4#1 彷徨]
[§4@4#2 祝福]
正文二
''',
        );

        expect(await controller.resolveGraphWorkCandidates(), isNull);
        expect(controller.hasAmbiguousInternalWorks, isTrue);
        expect(controller.canChatAtCurrentPosition, isTrue);
        expect(controller.aiStructureUnavailableMessage, contains('无法可靠判断'));
        controller.dispose();
      },
    );
    test(
      'flat evocative chapter titles keep plain-book chat available',
      () async {
        final item = await insertBook(id: 'flat-single-work');
        final controller = BookReaderController(database: database, item: item);
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => toc
              ? '''
[§1@2~ 风起]
正文一
[§2@3~ 云涌]
正文二
[§3@4~ 潮落]
正文三
'''
              : '''
[§1@2 风起]
正文一
[§2@3 云涌]
正文二
[§3@4 潮落]
正文三
''',
        );

        expect(await controller.resolveGraphWorkCandidates(), isNull);
        expect(
          controller.bookStructureManifest?.kind,
          AiBookStructureKind.singleWork,
        );
        expect(controller.currentReadingWork, isNull);
        expect(controller.hasCollectionWorks, isFalse);
        expect(controller.hasAmbiguousInternalWorks, isFalse);
        expect(controller.canChatAtCurrentPosition, isTrue);
        final scope = await controller.graphScopePlan(null);
        expect(scope.selectable, hasLength(3));
        controller.dispose();
      },
    );
    test(
      'current work follows the renderer section index in a long omnibus',
      () async {
        final item = await insertBook(id: 'long-omnibus-location');
        final controller = BookReaderController(database: database, item: item);
        await controller.attachEngine(
          BookSectionMap(
            startIndices: List<int>.generate(80, (index) => index),
            totalParagraphs: 80,
          ),
          List<String>.generate(80, (index) => '第 ${index + 1} 节'),
        );
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => toc
              ? '''
[§1@2~ 制作说明]
说明
[§2@7~+17 Ⅰ 哈利·波特与魔法石]
第一部
[§3@27~+18 Ⅱ 哈利·波特与密室]
第二部
[§4@51~+22 Ⅲ 哈利·波特与阿兹卡班的囚徒]
第三部
'''
              : '[§1@10 第一章]\n正文',
        );

        expect(await controller.resolveGraphWorkCandidates(), hasLength(3));
        expect(controller.currentReadingWork, isNull); // front matter

        controller.reportRenditionLocation(
          sectionIndex: 9,
          progress: 0.12,
          cfi: 'epubcfi(/6/20!/4/2)',
        );
        expect(controller.currentReadingWork?.title, contains('魔法石'));

        controller.reportRenditionLocation(
          sectionIndex: 29,
          progress: 0.38,
          cfi: 'epubcfi(/6/60!/4/2)',
        );
        expect(controller.currentReadingWork?.title, contains('密室'));
        controller.dispose();
      },
    );
    test(
      'scope keeps front/back matter visible but recommends exclusion',
      () async {
        final item = await insertBook(id: 'graph-sections');
        final controller = BookReaderController(database: database, item: item);
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => '''
[§1@1 封面]
万历十五年
[§2@2 目录]
第一章 万历皇帝
第二章 首辅申时行
[§3@3 前言]
本书缘起…
[§4@4 中文版序言]
黄仁宇序
[§5@5 第一章 万历皇帝]
万历皇帝年幼登基…
[§6@6 附录一 万历十五年大事纪]
1572年…
[§7@7 参考书目]
黄仁宇《万历十五年》
''',
        );

        final scope = await controller.graphScopePlan(null);
        expect(scope.choices.map((choice) => choice.section.label), [
          '封面',
          '目录',
          '前言',
          '中文版序言',
          '第一章 万历皇帝',
          '附录一 万历十五年大事纪',
          '参考书目',
        ]);
        expect(
          scope.choices
              .where((choice) => choice.selectedByDefault)
              .map((choice) => choice.section.label),
          ['中文版序言', '第一章 万历皇帝'],
        );
        controller.dispose();
      },
    );

    test(
      'scope marks series gallery and author biography as suggestions',
      () async {
        final item = await insertBook(id: 'graph-series-metadata');
        final controller = BookReaderController(database: database, item: item);
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => '''
[§1@1 系列封面画廊]
各地区版本封面说明
[§2@2 作者罗琳小传]
作者生平
[§3@3 魔法石：德思礼家的异常]
第一章正文
''',
        );

        final scope = await controller.graphScopePlan(null);
        expect(scope.choices.map((choice) => choice.section.label), [
          '系列封面画廊',
          '作者罗琳小传',
          '魔法石：德思礼家的异常',
        ]);
        expect(scope.choices.map((choice) => choice.role), [
          AiGraphSectionRole.suggestedSupplement,
          AiGraphSectionRole.suggestedSupplement,
          AiGraphSectionRole.body,
        ]);
        controller.dispose();
      },
    );

    test('per-work choices keep the logical heading level', () async {
      final item = await insertBook(id: 'graph-levels');
      final controller = BookReaderController(database: database, item: item);
      controller.attachAnnotationBridge(
        renderAll: (_) {},
        add: (_) {},
        remove: (_) {},
        clearSelection: () {},
        getSelectedText: () async => '',
        setMenuCursorZone: (_) {},
        setMenuOpen: (_) {},
        getBookPlainText:
            (
              maxChars, {
              bool toc = true,
              int? startSection,
              int? endSectionExclusive,
            }) async => '''
[§1@4#1 呐喊]

[§2@4#2 狂人日记]
某君昆仲。

[§3@4#2 孔乙己]
鲁镇的酒店的格局。

[§4@5 故乡]
我冒了严寒。
''',
      );

      // A collection work covering spine 4..5; per-work range reads in spine
      // mode (toc:false), which is what this mock body represents.
      final sections = await controller.graphSectionChoices(
        AiGraphWorkCandidate(
          id: 's4',
          title: '鲁迅小说精品',
          startSection: 4,
          endSectionExclusive: 6,
        ),
      );
      expect(sections, hasLength(4));
      expect(sections[0].label, '呐喊');
      expect(sections[0].text, isEmpty); // container
      expect(sections[0].level, 1);
      expect(sections[1].label, '狂人日记');
      expect(sections[1].level, 2);
      expect(sections[2].level, 2);
      expect(sections[3].label, '故乡');
      expect(sections[3].level, 1); // plain book-less piece
      controller.dispose();
    });

    test(
      'per-work choices replace EPUB resource paths with TOC titles',
      () async {
        final item = await insertBook(id: 'graph-readable-section-titles');
        final controller = BookReaderController(database: database, item: item);
        await controller.attachEngine(
          const BookSectionMap(
            startIndices: [0, 1, 2, 3, 4, 5],
            totalParagraphs: 6,
          ),
          const [
            '封面',
            '目录',
            '哈利·波特与魔法石',
            '第一章 大难不死的男孩',
            '第二章 悄悄消失的玻璃',
            '第三章 猫头鹰传书',
          ],
        );
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => '''
[§1@4 OEBPS/Text/v1ch01.xhtml]
第一章正文。
[§2@5 OEBPS/Text/v1ch02.xhtml]
第二章正文。
''',
        );

        final sections = await controller.graphSectionChoices(
          AiGraphWorkCandidate(
            id: 's4',
            title: '哈利·波特与魔法石',
            startSection: 4,
            endSectionExclusive: 6,
          ),
        );

        expect(sections.map((section) => section.label), [
          '第一章 大难不死的男孩',
          '第二章 悄悄消失的玻璃',
        ]);
        controller.dispose();
      },
    );

    test('manual exclude drops the compound front matter (中文版序言)', () async {
      final item = await insertBook(id: 'graph-sections-exclude');
      final controller = BookReaderController(database: database, item: item);
      controller.attachAnnotationBridge(
        renderAll: (_) {},
        add: (_) {},
        remove: (_) {},
        clearSelection: () {},
        getSelectedText: () async => '',
        setMenuCursorZone: (_) {},
        setMenuOpen: (_) {},
        getBookPlainText:
            (
              maxChars, {
              bool toc = true,
              int? startSection,
              int? endSectionExclusive,
            }) async => '''
[§1@1 中文版序言]
黄仁宇序
[§2@2 第一章 万历皇帝]
万历皇帝年幼登基…
[§3@3 第二章 首辅申时行]
申时行…
''',
      );

      final choices = await controller.graphSectionChoices(null);
      // User unchecks 中文版序言 (§1) in the dialog.
      final kept = BookReaderController.excludeGraphSections(choices, {1});
      expect(kept.map((s) => s.label).toList(), ['第一章 万历皇帝', '第二章 首辅申时行']);

      // Excluding everything must fail loudly, not generate an empty graph.
      expect(
        () => BookReaderController.excludeGraphSections(choices, {1, 2, 3}),
        throwsA(isA<AiProviderException>()),
      );
      controller.dispose();
    });

    test(
      'fine-grained scope keeps logical sections that share one spine',
      () async {
        final item = await insertBook(id: 'graph-sections-dedupe');
        final controller = BookReaderController(database: database, item: item);
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async => '''
[§1@1 第一章 万历皇帝]
第一节正文
[§2@1 第一节 少年天子]
第二节正文
[§3@1 第二节 张居正]
第三节正文
[§4@2 第二章 首辅申时行]
第二章正文
''',
        );

        final sections = await controller.graphSectionChoices(null);
        // The user can select each logical unit even when several share one
        // physical EPUB spine document.
        expect(sections.map((s) => s.label).toList(), [
          '第一章 万历皇帝',
          '第一节 少年天子',
          '第二节 张居正',
          '第二章 首辅申时行',
        ]);
        controller.dispose();
      },
    );

    test(
      'mind map scope removes publishing extras but keeps author framing',
      () async {
        final item = await insertBook(id: 'mind-map-substantive-scope');
        final controller = BookReaderController(database: database, item: item);
        var corpusReads = 0;
        controller.attachAnnotationBridge(
          renderAll: (_) {},
          add: (_) {},
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (_) {},
          getBookPlainText:
              (
                maxChars, {
                bool toc = true,
                int? startSection,
                int? endSectionExclusive,
              }) async {
                corpusReads++;
                return '''
[§1@1 版权信息]
版权所有 出版社 ISBN
[§2@2 第一篇 就业冲击]
第一篇 就业冲击
[§3@3 第一章 保就业还是保发展]
本章通过政策背景、就业数据与长期代价讨论两种目标的取舍。
[§4@4 结语]
作者最后总结短期稳定与长期发展的关系。
[§5@5 参考文献]
参考资料一
[§6@6 前言]
作者解释写作缘起与全书的观察方法。
[§7@7 附录一 万历十五年大事纪]
附录资料与时间表。
[§8@8 名家推荐]
名家对本书的推荐文字。
[§9@9 《万历十五年》出版始末]
编辑回顾本书的出版过程。
[§10@10 两声欢呼，一声倒彩 ——《万历十五年》三十载印象记]
评论者回顾三十年来的社会反响。
[§11@11 《万历十五年》的读法]
编辑提供阅读指南。
[§12@12 《万历十五年》纪事]
本书版本流转纪事。
[§13@13 前沿点评]
外围点评文章。
[§14@14 后记]
作者回顾全书结论及写作限制。
[§15@15 附录 A 统计口径]
补充统计资料。
[§16@16 出版说明：修订版]
出版社说明修订过程。
[§17@17 自序]
作者说明自己的核心问题意识。
''';
              },
        );

        final sections = await controller.bookMindMapSections(
          useFrozenWork: true,
        );

        expect(sections.map((section) => section.label), [
          '第一章 保就业还是保发展',
          '结语',
          '前言',
          '后记',
          '自序',
        ]);
        expect(corpusReads, 1);
        controller.dispose();
      },
    );
  });
}

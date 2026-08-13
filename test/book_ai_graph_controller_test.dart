import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_graph.dart';
import 'package:kaijuan/ai/ai_graph_store.dart';
import 'package:kaijuan/presentation/controllers/book_ai_graph_controller.dart';
import 'package:kaijuan/presentation/controllers/book_ai_workspace_controller.dart';

void main() {
  late Directory tempDir;
  late AiGraphStore store;
  late BookAiWorkspaceController workspace;
  late BookAiGraphController controller;

  AiGraphEntity person(String name) {
    final id = graphEntityIdFor(
      type: AiGraphEntityType.person,
      name: name,
      identityHint: '',
    );
    return AiGraphEntity(
      entityId: id,
      name: name,
      type: AiGraphEntityType.person,
      evidence: const [
        AiGraphEvidence(
          sectionIndex: 1,
          quote: '他走进了房间。',
          progressInSection: 0.1,
          spanResolved: true,
        ),
      ],
      firstSection: 1,
      lastSection: 1,
    );
  }

  AiBookGraph graphWith(String name, {List<String> hidden = const []}) {
    return AiBookGraph(
      contentHash: 'hash-book',
      entities: [person(name)],
      hiddenEntityIds: hidden,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaijuan_graph_ctrl_');
    store = AiGraphStore(tempDir);
    workspace = BookAiWorkspaceController(
      saveChatSession: (_) async {},
      aiStoresReady: true,
    );
    controller = BookAiGraphController(
      contentHash: 'hash-book',
      bookTitle: '测试书',
      workspace: workspace,
      bookAuthorsLabel: () => '',
      canUseAi: () => true,
      allowUnread: () => false,
      readThrough: () => 1,
      loadSections: (_) async => const [],
      resolveWorks: ({cancel}) async => null,
      resolvedWorks: () => null,
      isSuggestedSupplement: (_) => false,
    )..attachStore(store);
  });

  tearDown(() async {
    controller.dispose();
    workspace.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load reads the whole-book snapshot', () async {
    await store.write(graphWith('张三'));
    await controller.load();
    expect(controller.current?.entities.single.name, '张三');
    expect(controller.hasUsableGraph, isTrue);
  });

  test('hide persists hiddenEntityIds', () async {
    await store.write(graphWith('张三'));
    await controller.load();
    final id = controller.current!.entities.single.id;
    await controller.hideEntity(id);
    expect(controller.current!.hiddenEntityIds, contains(id));
    expect(controller.visible, isNull);
    final reread = await store.read('hash-book');
    expect(reread!.hiddenEntityIds, contains(id));
  });

  test('delete clears the current graph', () async {
    await store.write(graphWith('张三'));
    await controller.load();
    await controller.delete();
    expect(controller.current, isNull);
    expect(await store.read('hash-book'), isNull);
  });

  test('empty snapshot cannot resume incrementally', () {
    const empty = AiBookGraph(contentHash: 'hash-book');
    expect(BookAiGraphController.canResumeIncrementally(empty), isFalse);
    expect(
      BookAiGraphController.canResumeIncrementally(graphWith('张三')),
      isTrue,
    );
  });
}

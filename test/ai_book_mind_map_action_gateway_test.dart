import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/ai/ai_book_mind_map_action_gateway.dart';
import 'package:kaijuan/ai/ai_book_structure.dart';
import 'package:kaijuan/ai/ai_chat.dart';
import 'package:kaijuan/ai/ai_models.dart';
import 'package:kaijuan/ai/ai_mind_map.dart';
import 'package:kaijuan/ai/ai_product_action.dart';

void main() {
  const first = AiBookWork(
    id: 'work-1',
    title: '第一部',
    startSection: 1,
    endSectionExclusive: 4,
  );
  const second = AiBookWork(
    id: 'work-2',
    title: '第二部',
    startSection: 4,
    endSectionExclusive: 8,
  );
  const manifest = AiBookStructureManifest(
    kind: AiBookStructureKind.multiWorkOmnibus,
    source: AiBookStructureSource.navigationHierarchy,
    confidence: 0.95,
    reason: 'test',
    works: [first, second],
  );

  test('freezes chapter body and work identity before the model turn', () {
    final snapshot = AiBookMindMapActionGateway.freeze(
      conversationWorkKey: 'work-key-1',
      currentWork: first,
      manifest: manifest,
      context: const AiChatContextBundle(
        chapterTitle: '第一章',
        chapterText: '冻结的正文',
        chapterSectionIndex: 2,
      ),
    );

    expect(snapshot.conversationWorkKey, 'work-key-1');
    expect(snapshot.currentWork, same(first));
    expect(snapshot.availableWorks, [first, second]);
    expect(snapshot.currentChapter?.index, 2);
    expect(snapshot.currentChapter?.text, '冻结的正文');
  });

  test('resolves a specific-work alias only inside frozen capabilities', () {
    final snapshot = AiBookMindMapActionGateway.freeze(
      conversationWorkKey: 'work-key-1',
      currentWork: first,
      manifest: manifest,
      context: const AiChatContextBundle(),
    );
    const action = AiCreateBookMindMapAction(
      instruction: '生成第二部',
      scope: AiBookMindMapActionScope.specificWork,
      workAlias: 'work_2',
      workId: 'work-2',
    );

    final input = AiBookMindMapActionGateway.resolveCreate(action, snapshot);

    expect(input.work, same(second));
    expect(input.scope, AiMindMapRequestScope.currentWork);
    expect(input.frozenCurrentChapter, isNull);
  });

  test('builds temporary product aliases from frozen conversation history', () {
    final snapshot = AiBookMindMapActionGateway.freeze(
      conversationWorkKey: 'work-key-1',
      currentWork: first,
      manifest: manifest,
      context: const AiChatContextBundle(),
    );
    final map = AiBookMindMap(
      contentHash: 'hash',
      workKey: 'work-1',
      createdAt: DateTime.utc(2026, 8, 11),
      model: 'test',
      scopeSectionIndices: const [1],
      scopeFingerprint: 'scope',
      contentKind: AiMindMapContentKind.narrative,
      layout: AiMindMapLayout.bidirectional,
      artifactId: 'map-1',
      revision: 2,
      nodes: const [
        AiBookMindMapNode(
          nodeId: 'root',
          parentId: null,
          order: 0,
          level: 0,
          title: '主题',
          summary: '摘要',
        ),
      ],
    );

    final turn = AiBookMindMapActionGateway.prepareProductTurn(
      history: [
        AiChatMessage(
          role: AiMessageRole.assistant,
          content: '已生成',
          turnId: 'turn-map',
          mindMap: map,
        ),
      ],
      scopeSnapshot: snapshot,
      preferredArtifactId: 'map-1',
    );

    expect(turn.modelContext.artifacts.single.alias, 'artifact_1');
    expect(turn.modelContext.artifacts.single.artifactId, 'map-1');
    expect(turn.modelContext.artifacts.single.isAdjacent, isTrue);
    expect(turn.modelContext.artifacts.single.isPreferred, isTrue);
    expect(turn.modelContext.works.map((work) => work.alias), [
      'work_1',
      'work_2',
    ]);
    expect(turn.artifactsById['map-1'], same(map));
  });

  test('rejects changed work identities and missing frozen chapter body', () {
    final snapshot = AiBookMindMapActionGateway.freeze(
      conversationWorkKey: null,
      currentWork: null,
      manifest: manifest,
      context: const AiChatContextBundle(chapterTitle: '未加载章节'),
    );

    expect(
      () => AiBookMindMapActionGateway.resolveCreate(
        const AiCreateBookMindMapAction(
          instruction: '生成不存在的作品',
          scope: AiBookMindMapActionScope.specificWork,
          workId: 'removed-work',
        ),
        snapshot,
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(
      () => AiBookMindMapActionGateway.resolveCreate(
        const AiCreateBookMindMapAction(
          instruction: '生成当前章',
          scope: AiBookMindMapActionScope.currentChapter,
        ),
        snapshot,
      ),
      throwsA(isA<AiProviderException>()),
    );
  });

  test('rejects revision artifacts not issued by the frozen conversation', () {
    expect(
      () => AiBookMindMapActionGateway.resolveRevision(
        const AiReviseBookMindMapAction(
          instruction: '增加细节',
          artifactAlias: 'artifact_1',
          artifactId: 'missing',
        ),
        const {},
      ),
      throwsA(isA<AiProviderException>()),
    );
  });

  test('resolveRevision falls back to preferred then latest map', () {
    final older = AiBookMindMap(
      contentHash: 'hash',
      workKey: 'work-1',
      createdAt: DateTime.utc(2026, 8, 11),
      model: 'test',
      scopeSectionIndices: const [1],
      scopeFingerprint: 'scope-a',
      contentKind: AiMindMapContentKind.narrative,
      layout: AiMindMapLayout.bidirectional,
      artifactId: 'map-old',
      revision: 1,
      nodes: const [
        AiBookMindMapNode(
          nodeId: 'root',
          parentId: null,
          order: 0,
          level: 0,
          title: '旧',
          summary: '',
        ),
      ],
    );
    final newer = AiBookMindMap(
      contentHash: 'hash',
      workKey: 'work-1',
      createdAt: DateTime.utc(2026, 8, 12),
      model: 'test',
      scopeSectionIndices: const [1],
      scopeFingerprint: 'scope-b',
      contentKind: AiMindMapContentKind.narrative,
      layout: AiMindMapLayout.bidirectional,
      artifactId: 'map-new',
      revision: 1,
      nodes: const [
        AiBookMindMapNode(
          nodeId: 'root',
          parentId: null,
          order: 0,
          level: 0,
          title: '新',
          summary: '',
        ),
      ],
    );
    final byId = {'map-old': older, 'map-new': newer};
    // Action points at unknown id → preferredArtifactId wins.
    final preferred = AiBookMindMapActionGateway.resolveRevision(
      const AiReviseBookMindMapAction(
        instruction: '再详细一点',
        artifactAlias: 'artifact_x',
        artifactId: 'missing',
      ),
      byId,
      preferredArtifactId: 'map-old',
    );
    expect(preferred.artifactId, 'map-old');
    // No preferred → latest value in map.
    final latest = AiBookMindMapActionGateway.resolveRevision(
      const AiReviseBookMindMapAction(
        instruction: '再详细一点',
        artifactAlias: 'artifact_x',
        artifactId: 'missing',
      ),
      byId,
    );
    expect(latest.artifactId, 'map-new');
  });
}

import 'ai_chat_retrieve.dart';
import '../domain/book_structure.dart';

/// File-internal publication structure used by every book AI feature.
///
/// A library collection is deliberately not represented here: its members
/// are separate reading items and each item resolves its own file structure.
enum AiBookStructureKind {
  singleWork,
  segmentedSingleWork,
  multiWorkOmnibus,
  uncertain,
}

enum AiBookStructureSource { navigationHierarchy, spineHeadings, heuristic }

enum AiBookStructureStrategy {
  single,
  volumes,
  topLevelWorks,
  workTrees,
  intermediateGroups,
  flatDirectories,
}

class AiBookStructureHypothesis {
  const AiBookStructureHypothesis({
    required this.strategy,
    required this.kind,
    required this.nodes,
    required this.score,
    required this.evidence,
    required this.rejections,
  });

  final AiBookStructureStrategy strategy;
  final AiBookStructureKind kind;
  final List<BookStructureNavigationNode> nodes;
  final int score;
  final List<String> evidence;
  final List<String> rejections;

  bool get isValid => rejections.isEmpty;
}

class AiBookStructureAnalysis {
  const AiBookStructureAnalysis({
    required this.manifest,
    required this.hypotheses,
    this.selectedStrategy,
  });

  final AiBookStructureManifest manifest;
  final List<AiBookStructureHypothesis> hypotheses;
  final AiBookStructureStrategy? selectedStrategy;
}

abstract final class _StructureScore {
  static const singleBase = 30;
  static const sparseSingle = 45;
  static const chapterMajority = 45;
  static const noOmnibusMetadata = 20;
  static const volumes = 72;
  static const topLevelWorks = 42;
  static const workTrees = 58;
  static const intermediateGroups = 62;
  static const flatDirectories = 54;
  static const omnibusMetadata = 18;
  static const declaredCountMatch = 35;
  static const distinctAnchors = 18;
  static const ambiguityMargin = 8;
}

class AiBookWork {
  const AiBookWork({
    required this.id,
    required this.title,
    required this.startSection,
    required this.endSectionExclusive,
    this.startLogicalIndex,
    this.endLogicalIndexExclusive,
    this.sample = '',
  });

  final String id;
  final String title;
  final int startSection;
  final int? endSectionExclusive;

  /// Present when several works share one physical spine. Current reader
  /// position cannot yet resolve these ranges without a logical locator, so
  /// manifests carrying them remain [AiBookStructureKind.uncertain].
  final int? startLogicalIndex;
  final int? endLogicalIndexExclusive;
  final String sample;

  bool get isOpenEnded => endSectionExclusive == null;
  bool get needsLogicalLocator => startLogicalIndex != null;

  bool contains(int spineSection) =>
      !needsLogicalLocator &&
      spineSection >= startSection &&
      (isOpenEnded || spineSection < endSectionExclusive!);
}

class AiBookStructureManifest {
  const AiBookStructureManifest({
    required this.kind,
    required this.source,
    required this.confidence,
    required this.reason,
    this.works = const [],
  });

  final AiBookStructureKind kind;
  final AiBookStructureSource source;
  final double confidence;
  final String reason;
  final List<AiBookWork> works;

  /// Strong evidence says there are several works, but the reader's physical
  /// locator cannot tell which logical range is active. AI features must not
  /// turn this into an accidental whole-file scope.
  bool get requiresLogicalWorkLocator =>
      kind == AiBookStructureKind.uncertain &&
      (reason == 'multiple logical works share one spine' ||
          works.any((work) => work.needsLogicalLocator));

  /// The deterministic facts cannot prove that the ranges are chapters of one
  /// work rather than independent works. Chat/outline have no range picker, so
  /// they remain uncertain; chat falls back to the whole publication while
  /// outline/graph may continue with user-confirmed units.
  bool get requiresUserScopeConfirmation =>
      kind == AiBookStructureKind.uncertain && works.length >= 2;

  /// Only independent works with unambiguous physical ranges may scope chat,
  /// outline and graph. Parts of one work stay whole-book; uncertain ranges
  /// never silently expose another work as the current one.
  List<AiBookWork> get scopedWorks =>
      kind == AiBookStructureKind.multiWorkOmnibus &&
          works.length >= 2 &&
          works.every((work) => !work.needsLogicalLocator)
      ? works
      : const [];

  AiBookWork? workAtSpine(int spineSection) {
    final matches = scopedWorks
        .where((work) => work.contains(spineSection))
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }
}

/// Deterministic structure resolver over facts extracted by the reader.
/// It never sends book content to a model.
abstract final class AiBookStructureResolver {
  static final RegExp _chapterTitlePattern = RegExp(
    r'^('
    r'第[0-9零一二三四五六七八九十百千两壹贰叁肆伍陆柒捌玖拾]+[章节回篇集讲则]'
    r'|[章节回篇集讲][0-9零一二三四五六七八九十百千两壹贰叁肆伍陆柒捌玖拾]+'
    r'|(序章|楔子|引子|尾声|终章|番外|前言|序言|自序|序|跋|后记|引论|导论|绪论)'
    r'|(chapter|section|prologue|epilogue|introduction)\s*[0-9ivxlcdm]*'
    r')',
    caseSensitive: false,
  );

  static final RegExp _volumeTitlePattern = RegExp(
    r'^('
    r'第[0-9零一二三四五六七八九十百千两壹贰叁肆伍陆柒捌玖拾]+[部卷]'
    r'|[部卷][0-9零一二三四五六七八九十百千两壹贰叁肆伍陆柒捌玖拾]+'
    r'|(part|book|volume|vol\.?)\s*[0-9ivxlcdm]+'
    r')',
    caseSensitive: false,
  );

  static final RegExp _continuationTitlePattern = RegExp(r'^[—–－-]+\s*');

  static final RegExp _omnibusTitlePattern = RegExp(
    r'(全集|合集|合订|套装|全套|作品集|部曲|'
    r'共[0-9零一二三四五六七八九十百千两]+册|'
    r'全[0-9零一二三四五六七八九十百千两]+册|'
    r'卷\s*[0-9零一二三四五六七八九十百千两]+\s*[-—–~至]\s*'
    r'[0-9零一二三四五六七八九十百千两]+)',
    caseSensitive: false,
  );

  static final RegExp _splitInstallmentSuffixPattern = RegExp(
    r'\s*(?:[（(][上中下][）)]|[上中下](?:册|卷))\s*$',
  );

  static final RegExp _intermediateGroupPattern = RegExp(
    r'^(?:第[0-9零一二三四五六七八九十百千两壹贰叁肆伍陆柒捌玖拾]+)?(?:季|辑|系列)$',
    caseSensitive: false,
  );

  static final RegExp _directoryTitlePattern = RegExp(
    r'^(?:主目录|总目录|目录|目次)$',
    caseSensitive: false,
  );

  static bool isChapterTitle(String raw) =>
      _chapterTitlePattern.hasMatch(raw.trim());

  static bool isVolumeTitle(String raw) =>
      _volumeTitlePattern.hasMatch(raw.trim());

  static bool _isIndependentWorkCandidateTitle(String raw) {
    final title = raw.trim();
    return title.isNotEmpty &&
        !isChapterTitle(title) &&
        !_continuationTitlePattern.hasMatch(title);
  }

  /// Preferred classifier over the reader-owned, text-free structure index.
  /// The legacy [resolve] path remains only for engines that cannot expose the
  /// new bridge yet.
  static AiBookStructureManifest resolveIndex({
    required BookStructureIndex index,
    required bool Function(String title) isSupplementTitle,
    String? fallbackPublicationTitle,
  }) => analyzeIndex(
    index: index,
    isSupplementTitle: isSupplementTitle,
    fallbackPublicationTitle: fallbackPublicationTitle,
  ).manifest;

  /// Generates complete competing segmentations before choosing one. Hard
  /// structural conflicts reject a hypothesis; scores only rank legal ones.
  static AiBookStructureAnalysis analyzeIndex({
    required BookStructureIndex index,
    required bool Function(String title) isSupplementTitle,
    String? fallbackPublicationTitle,
  }) {
    if (!index.isUsable) {
      return const AiBookStructureAnalysis(
        manifest: AiBookStructureManifest(
          kind: AiBookStructureKind.singleWork,
          source: AiBookStructureSource.heuristic,
          confidence: 0.5,
          reason: 'structure index is unavailable',
        ),
        hypotheses: [],
      );
    }

    final publicationEvidence = [
      index.publicationTitle,
      fallbackPublicationTitle ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final hasOmnibusTitleEvidence = _omnibusTitlePattern.hasMatch(
      publicationEvidence,
    );
    final expectedCount = _expectedOmnibusCount(publicationEvidence);

    var candidates = index.navigationRoots;
    if (candidates.length == 1) {
      final children = index.childrenOf(candidates.single.nodeId);
      if (children.length >= 2) candidates = children;
    }
    final allCandidates = candidates;
    candidates = candidates
        .where(
          (node) =>
              !isSupplementTitle(node.title) &&
              !_isPublicationContainer(
                node.title,
                index.publicationTitle,
                publicationEvidence,
              ),
        )
        .toList(growable: false);
    if (expectedCount != null && candidates.length > expectedCount) {
      final withoutCollectionHeaders = candidates
          .where((node) => !_isCollectionHeaderTitle(node.title))
          .toList(growable: false);
      if (withoutCollectionHeaders.length == expectedCount) {
        candidates = withoutCollectionHeaders;
      }
    }

    final chapterLikeCount = candidates
        .where(
          (node) =>
              isChapterTitle(node.title) ||
              _continuationTitlePattern.hasMatch(node.title.trim()),
        )
        .length;
    final volumeCandidates = candidates
        .where((node) => isVolumeTitle(node.title))
        .toList(growable: false);
    final mergedTopCandidates = _mergeSplitInstallments(
      candidates
          .where(
            (node) =>
                _isIndependentWorkCandidateTitle(node.title) &&
                !isVolumeTitle(node.title),
          )
          .toList(growable: false),
    );
    final mergedAllCandidates = _mergeSplitInstallments(candidates);
    final hasRepeatedInstallmentEvidence =
        candidates.length >= 4 &&
        mergedAllCandidates.length >= 2 &&
        mergedAllCandidates.length * 2 <= candidates.length;
    final childCounts = <String, int>{};
    for (final node in index.navigation) {
      final parentId = node.parentId;
      if (parentId == null) continue;
      childCounts.update(parentId, (value) => value + 1, ifAbsent: () => 1);
    }
    final treeCandidates = _mergeSplitInstallments(
      candidates
          .where(
            (node) =>
                _isIndependentWorkCandidateTitle(node.title) &&
                !isVolumeTitle(node.title) &&
                (node.directChildCount >= 2 ||
                    (childCounts[node.nodeId] ?? 0) >= 2),
          )
          .toList(growable: false),
    );
    final groupedCandidates = _mergeSplitInstallments(
      expectedCount == null
          ? const <BookStructureNavigationNode>[]
          : _expandIntermediateGroups(
              index: index,
              roots: allCandidates,
              isSupplementTitle: isSupplementTitle,
            ),
    );
    final flatCandidates = _mergeSplitInstallments(
      expectedCount == null
          ? const <BookStructureNavigationNode>[]
          : _flatDirectoryBoundaries(
              index: index,
              isSupplementTitle: isSupplementTitle,
              publicationTitle: index.publicationTitle,
              publicationEvidence: publicationEvidence,
            ),
    );

    final hypotheses = <AiBookStructureHypothesis>[];
    final singleEvidence = <String>[];
    var singleScore = _StructureScore.singleBase;
    if (candidates.length < 2) {
      singleScore += _StructureScore.sparseSingle;
      singleEvidence.add('fewer than two top-level content ranges');
    }
    if (chapterLikeCount * 2 >= candidates.length && candidates.isNotEmpty) {
      singleScore += _StructureScore.chapterMajority;
      singleEvidence.add('top-level ranges are mostly chapters');
    }
    if (!hasOmnibusTitleEvidence) {
      singleScore += _StructureScore.noOmnibusMetadata;
      singleEvidence.add('publication lacks omnibus metadata');
    }
    hypotheses.add(
      AiBookStructureHypothesis(
        strategy: AiBookStructureStrategy.single,
        kind: AiBookStructureKind.singleWork,
        nodes: const [],
        score: singleScore,
        evidence: List.unmodifiable(singleEvidence),
        rejections:
            candidates.length >= 2 &&
                (expectedCount != null ||
                    (hasOmnibusTitleEvidence && treeCandidates.length >= 2) ||
                    hasRepeatedInstallmentEvidence)
            ? ['publication structure evidence remains unresolved']
            : const [],
      ),
    );

    void addHypothesis({
      required AiBookStructureStrategy strategy,
      required AiBookStructureKind kind,
      required List<BookStructureNavigationNode> nodes,
      required int strategyScore,
      required bool hasRequiredEvidence,
      required String evidenceLabel,
    }) {
      final evidence = <String>[];
      final rejections = <String>[];
      if (nodes.length < 2) rejections.add('fewer than two candidate ranges');
      if (!hasRequiredEvidence) {
        rejections.add('missing required structural evidence');
      }
      if (expectedCount != null &&
          kind == AiBookStructureKind.multiWorkOmnibus &&
          nodes.length != expectedCount) {
        rejections.add('expected $expectedCount works, found ${nodes.length}');
      }
      final anchored = nodes.where((node) => node.sectionIndex != null).length;
      final distinctAnchors = nodes
          .map((node) => node.sectionIndex)
          .whereType<int>()
          .toSet()
          .length;
      if (anchored != nodes.length) {
        rejections.add('candidate anchor is missing');
      }
      if (distinctAnchors != nodes.length) {
        rejections.add('candidate ranges share a spine anchor');
      }
      if (nodes.any((node) => isChapterTitle(node.title))) {
        rejections.add('chapter-like node cannot become a work boundary');
      }

      var score = strategyScore;
      if (hasOmnibusTitleEvidence &&
          kind == AiBookStructureKind.multiWorkOmnibus) {
        score += _StructureScore.omnibusMetadata;
        evidence.add('publication metadata indicates an omnibus');
      }
      if (expectedCount != null && nodes.length == expectedCount) {
        score += _StructureScore.declaredCountMatch;
        evidence.add('candidate count matches declared $expectedCount');
      }
      if (nodes.length >= 2 && distinctAnchors == nodes.length) {
        score += _StructureScore.distinctAnchors;
        evidence.add('all candidate ranges have distinct anchors');
      }
      evidence.add(evidenceLabel);
      hypotheses.add(
        AiBookStructureHypothesis(
          strategy: strategy,
          kind: kind,
          nodes: List.unmodifiable(nodes),
          score: score,
          evidence: List.unmodifiable(evidence),
          rejections: List.unmodifiable(rejections),
        ),
      );
    }

    addHypothesis(
      strategy: AiBookStructureStrategy.volumes,
      kind: AiBookStructureKind.segmentedSingleWork,
      nodes: volumeCandidates,
      strategyScore: _StructureScore.volumes,
      hasRequiredEvidence:
          volumeCandidates.length >= 2 &&
          volumeCandidates.length * 2 >= candidates.length,
      evidenceLabel: 'top-level ranges are mostly volumes',
    );
    final omnibusEvidence =
        hasOmnibusTitleEvidence || hasRepeatedInstallmentEvidence;
    addHypothesis(
      strategy: AiBookStructureStrategy.topLevelWorks,
      kind: AiBookStructureKind.multiWorkOmnibus,
      nodes: mergedTopCandidates,
      strategyScore: _StructureScore.topLevelWorks,
      hasRequiredEvidence: omnibusEvidence,
      evidenceLabel: 'top-level independent ranges form works',
    );
    addHypothesis(
      strategy: AiBookStructureStrategy.workTrees,
      kind: AiBookStructureKind.multiWorkOmnibus,
      nodes: treeCandidates,
      strategyScore: _StructureScore.workTrees,
      hasRequiredEvidence: omnibusEvidence,
      evidenceLabel: 'work candidates own chapter subtrees',
    );
    addHypothesis(
      strategy: AiBookStructureStrategy.intermediateGroups,
      kind: AiBookStructureKind.multiWorkOmnibus,
      nodes: groupedCandidates,
      strategyScore: _StructureScore.intermediateGroups,
      hasRequiredEvidence: omnibusEvidence && expectedCount != null,
      evidenceLabel: 'intermediate groups expand into work ranges',
    );
    addHypothesis(
      strategy: AiBookStructureStrategy.flatDirectories,
      kind: AiBookStructureKind.multiWorkOmnibus,
      nodes: flatCandidates,
      strategyScore: _StructureScore.flatDirectories,
      hasRequiredEvidence: omnibusEvidence && expectedCount != null,
      evidenceLabel: 'repeated title-directory boundaries form works',
    );

    final valid = hypotheses.where((item) => item.isValid).toList()
      ..sort((left, right) {
        final score = right.score.compareTo(left.score);
        return score != 0
            ? score
            : left.strategy.index.compareTo(right.strategy.index);
      });
    if (valid.isEmpty) {
      return AiBookStructureAnalysis(
        manifest: AiBookStructureManifest(
          kind: AiBookStructureKind.uncertain,
          source: AiBookStructureSource.navigationHierarchy,
          confidence: 0.6,
          reason: _unresolvedReason(expectedCount, hypotheses),
        ),
        hypotheses: List.unmodifiable(hypotheses),
      );
    }

    final selected = valid.first;
    final selectedSignature = _hypothesisSignature(selected.nodes);
    final competing = valid
        .skip(1)
        .where(
          (item) =>
              item.kind == selected.kind &&
              _hypothesisSignature(item.nodes) != selectedSignature &&
              selected.score - item.score < _StructureScore.ambiguityMargin,
        );
    if (competing.isNotEmpty) {
      return AiBookStructureAnalysis(
        manifest: const AiBookStructureManifest(
          kind: AiBookStructureKind.uncertain,
          source: AiBookStructureSource.navigationHierarchy,
          confidence: 0.55,
          reason: 'similarly scored structure candidates disagree on ranges',
        ),
        hypotheses: List.unmodifiable(hypotheses),
      );
    }

    if (selected.kind == AiBookStructureKind.singleWork) {
      return AiBookStructureAnalysis(
        manifest: AiBookStructureManifest(
          kind: AiBookStructureKind.singleWork,
          source: AiBookStructureSource.navigationHierarchy,
          confidence: singleScore >= 90 ? 0.98 : 0.92,
          reason: selected.evidence.join('; '),
        ),
        hypotheses: List.unmodifiable(hypotheses),
        selectedStrategy: selected.strategy,
      );
    }

    final ranges = _rangesFromIndexCandidates(
      selected.nodes,
      trailingBoundaries: allCandidates.where(
        (node) => isSupplementTitle(node.title),
      ),
    );
    return AiBookStructureAnalysis(
      manifest: AiBookStructureManifest(
        kind: selected.kind,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: selected.score >= 105 ? 0.97 : 0.92,
        reason:
            'selected ${selected.strategy.name}: ${selected.evidence.join('; ')}',
        works: ranges,
      ),
      hypotheses: List.unmodifiable(hypotheses),
      selectedStrategy: selected.strategy,
    );
  }

  static String _hypothesisSignature(List<BookStructureNavigationNode> nodes) {
    final parts =
        nodes
            .map(
              (node) => '${node.sectionIndex}:${_normalizedTitle(node.title)}',
            )
            .toList()
          ..sort();
    return parts.join('|');
  }

  static String _unresolvedReason(
    int? expectedCount,
    List<AiBookStructureHypothesis> hypotheses,
  ) {
    final rejected = hypotheses
        .where((item) => item.strategy != AiBookStructureStrategy.single)
        .map(
          (item) =>
              '${item.strategy.name}=${item.nodes.length}'
              '[${item.rejections.join(',')}]',
        )
        .join('; ');
    final prefix = expectedCount == null
        ? 'no legal structure hypothesis'
        : 'publication expects $expectedCount works but no candidate matches';
    return rejected.isEmpty ? prefix : '$prefix: $rejected';
  }

  /// Previous ordered heuristic retained only for offline shadow comparison.
  static AiBookStructureManifest resolveIndexLegacy({
    required BookStructureIndex index,
    required bool Function(String title) isSupplementTitle,
    String? fallbackPublicationTitle,
  }) {
    if (!index.isUsable) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.heuristic,
        confidence: 0.5,
        reason: 'structure index is unavailable',
      );
    }

    final publicationEvidence = [
      index.publicationTitle,
      fallbackPublicationTitle ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final hasOmnibusTitleEvidence = _omnibusTitlePattern.hasMatch(
      publicationEvidence,
    );
    final expectedCount = _expectedOmnibusCount(publicationEvidence);

    var candidates = index.navigationRoots;
    if (candidates.length == 1) {
      final children = index.childrenOf(candidates.single.nodeId);
      if (children.length >= 2) candidates = children;
    }
    final allCandidates = candidates;
    candidates = candidates
        .where(
          (node) =>
              !isSupplementTitle(node.title) &&
              !_isPublicationContainer(
                node.title,
                index.publicationTitle,
                publicationEvidence,
              ),
        )
        .toList(growable: false);
    if (expectedCount != null && candidates.length > expectedCount) {
      final withoutCollectionHeaders = candidates
          .where((node) => !_isCollectionHeaderTitle(node.title))
          .toList(growable: false);
      if (withoutCollectionHeaders.length == expectedCount) {
        candidates = withoutCollectionHeaders;
      }
    }
    if (candidates.length < 2) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.9,
        reason: 'structure index has fewer than two top-level ranges',
      );
    }

    final chapterLikeCount = candidates
        .where(
          (node) =>
              isChapterTitle(node.title) ||
              _continuationTitlePattern.hasMatch(node.title.trim()),
        )
        .length;
    if (chapterLikeCount * 2 >= candidates.length && expectedCount == null) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.98,
        reason: 'indexed top-level ranges are chapters and subtitles',
      );
    }

    final volumeCandidates = candidates
        .where((node) => isVolumeTitle(node.title))
        .toList(growable: false);
    if (volumeCandidates.length >= 2 &&
        volumeCandidates.length * 2 >= candidates.length) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.segmentedSingleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.95,
        reason: 'indexed top-level ranges are parts or volumes',
        works: _rangesFromIndexCandidates(
          volumeCandidates,
          trailingBoundaries: allCandidates.where(
            (node) => isSupplementTitle(node.title),
          ),
        ),
      );
    }

    // A chapter owning several subsection nodes is normal and cannot prove an
    // omnibus. Require publication-level collection metadata before promoting
    // arbitrary titled roots to independent works.
    final mergedCandidates = _mergeSplitInstallments(candidates);
    final hasRepeatedInstallmentEvidence =
        candidates.length >= 4 &&
        mergedCandidates.length >= 2 &&
        mergedCandidates.length * 2 <= candidates.length;
    if (!hasOmnibusTitleEvidence && !hasRepeatedInstallmentEvidence) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.94,
        reason: 'chapter subtrees lack publication-level omnibus evidence',
      );
    }

    final groupedCandidates = expectedCount == null
        ? const <BookStructureNavigationNode>[]
        : _expandIntermediateGroups(
            index: index,
            roots: allCandidates,
            isSupplementTitle: isSupplementTitle,
          );
    final mergedGroupedCandidates = _mergeSplitInstallments(groupedCandidates);
    final treeCandidates = candidates
        .where(
          (node) =>
              node.directChildCount >= 2 ||
              index.childrenOf(node.nodeId).length >= 2,
        )
        .toList(growable: false);
    final flatCandidates = expectedCount == null
        ? const <BookStructureNavigationNode>[]
        : _flatDirectoryBoundaries(
            index: index,
            isSupplementTitle: isSupplementTitle,
            publicationTitle: index.publicationTitle,
            publicationEvidence: publicationEvidence,
          );
    final mergedFlatCandidates = _mergeSplitInstallments(flatCandidates);
    final workCandidates = _mergeSplitInstallments(
      mergedGroupedCandidates.length == expectedCount
          ? mergedGroupedCandidates
          : treeCandidates.length >= 2
          ? treeCandidates
          : mergedFlatCandidates.length == expectedCount
          ? mergedFlatCandidates
          : candidates,
    );
    if (expectedCount != null && workCandidates.length != expectedCount) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.uncertain,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.65,
        reason:
            'publication expects $expectedCount works but indexed '
            '${workCandidates.length} '
            '(groups=${mergedGroupedCandidates.length}, '
            'trees=${treeCandidates.length}, flat=${mergedFlatCandidates.length})',
      );
    }

    final omnibusRanges = _rangesFromIndexCandidates(
      workCandidates,
      trailingBoundaries: allCandidates.where(
        (node) => isSupplementTitle(node.title),
      ),
    );
    if (omnibusRanges.length < 2) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.uncertain,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.6,
        reason: 'independent indexed ranges lack resolved anchors',
      );
    }
    final starts = omnibusRanges.map((work) => work.startSection).toSet();
    if (starts.length != omnibusRanges.length) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.uncertain,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.72,
        reason: 'independent indexed ranges share one spine',
      );
    }
    return AiBookStructureManifest(
      kind: AiBookStructureKind.multiWorkOmnibus,
      source: AiBookStructureSource.navigationHierarchy,
      confidence: treeCandidates.length >= 2 ? 0.97 : 0.92,
      reason: treeCandidates.length >= 2
          ? 'indexed work ranges own chapter subtrees'
          : hasOmnibusTitleEvidence
          ? 'publication metadata corroborates indexed work ranges'
          : 'repeated split installments corroborate indexed work ranges',
      works: omnibusRanges,
    );
  }

  static bool _isPublicationContainer(
    String raw,
    String publicationTitle,
    String publicationEvidence,
  ) {
    final title = _normalizedTitle(raw);
    if (title.length < 4) return false;
    final primary = _normalizedTitle(publicationTitle);
    final evidence = _normalizedTitle(publicationEvidence);
    final collectionLike = _isCollectionHeaderTitle(title);
    return (primary.isNotEmpty && title == primary) ||
        (collectionLike && evidence.contains(title));
  }

  static bool _isCollectionHeaderTitle(String raw) {
    final title = _normalizedTitle(
      raw,
    ).replaceFirst(RegExp(r'共?[0-9零一二三四五六七八九十百千两]+册$'), '');
    return const ['全集', '合集', '作品集', '大全集', '套装'].any(title.endsWith);
  }

  static String _normalizedTitle(String raw) => raw.toLowerCase().replaceAll(
    RegExp(r'[\s·•:：,，。.!！?？—–_()（）\[\]【】《》]+'),
    '',
  );

  static List<BookStructureNavigationNode> _expandIntermediateGroups({
    required BookStructureIndex index,
    required List<BookStructureNavigationNode> roots,
    required bool Function(String title) isSupplementTitle,
  }) {
    final result = <BookStructureNavigationNode>[];

    void collect(BookStructureNavigationNode group) {
      for (final child in index.childrenOf(group.nodeId)) {
        if (isSupplementTitle(child.title)) continue;
        if (_intermediateGroupPattern.hasMatch(child.title.trim())) {
          collect(child);
        } else if (_isIndependentWorkCandidateTitle(child.title)) {
          result.add(child);
        }
      }
    }

    for (final root in roots) {
      if (_intermediateGroupPattern.hasMatch(root.title.trim())) collect(root);
    }
    return _deduplicateCandidates(result);
  }

  static List<BookStructureNavigationNode> _flatDirectoryBoundaries({
    required BookStructureIndex index,
    required bool Function(String title) isSupplementTitle,
    required String publicationTitle,
    required String publicationEvidence,
  }) {
    final ordered = [...index.navigation]
      ..sort((left, right) => left.order.compareTo(right.order));
    final result = <BookStructureNavigationNode>[];
    for (var indexInList = 1; indexInList < ordered.length; indexInList++) {
      if (!_directoryTitlePattern.hasMatch(ordered[indexInList].title.trim())) {
        continue;
      }
      final candidate = ordered[indexInList - 1];
      final title = candidate.title.trim();
      if (candidate.sectionIndex == null ||
          isSupplementTitle(title) ||
          !_isIndependentWorkCandidateTitle(title) ||
          _isPublicationContainer(
            title,
            publicationTitle,
            publicationEvidence,
          ) ||
          _expectedOmnibusCount(title) != null) {
        continue;
      }
      result.add(candidate);
    }
    return _deduplicateCandidates(result);
  }

  static List<BookStructureNavigationNode> _deduplicateCandidates(
    List<BookStructureNavigationNode> candidates,
  ) {
    final result = <BookStructureNavigationNode>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final key =
          '${candidate.sectionIndex}:${_normalizedTitle(candidate.title)}';
      if (seen.add(key)) result.add(candidate);
    }
    return result;
  }

  static List<BookStructureNavigationNode> _mergeSplitInstallments(
    List<BookStructureNavigationNode> candidates,
  ) {
    final merged = <BookStructureNavigationNode>[];
    String? previousTitle;
    for (final candidate in candidates) {
      final title = candidate.title
          .replaceFirst(_splitInstallmentSuffixPattern, '')
          .trim();
      final normalized = title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      if (normalized.isNotEmpty && normalized == previousTitle) continue;
      previousTitle = normalized;
      merged.add(
        BookStructureNavigationNode(
          nodeId: candidate.nodeId,
          parentId: candidate.parentId,
          title: title.isEmpty ? candidate.title : title,
          depth: candidate.depth,
          order: candidate.order,
          href: candidate.href,
          sectionIndex: candidate.sectionIndex,
          directChildCount: candidate.directChildCount,
          fragment: candidate.fragment,
        ),
      );
    }
    return merged;
  }

  static int? _expectedOmnibusCount(String raw) {
    final title = raw.replaceAll(RegExp(r'\s+'), '');
    final range = RegExp(
      r'(?:卷([0-9]{1,3})[-—–~至]([0-9]{1,3})|'
      r'([0-9]{1,3})[-—–~至]([0-9]{1,3})(?:全集|全套|套装))',
    ).firstMatch(title);
    if (range != null) {
      final start = int.tryParse((range.group(1) ?? range.group(3))!);
      final end = int.tryParse((range.group(2) ?? range.group(4))!);
      if (start != null && end != null && end >= start) return end - start + 1;
    }
    final arabic = RegExp(
      r'(?:套装|全套|共)?([0-9]{1,3})(?:册|部曲)',
    ).firstMatch(title);
    if (arabic != null) return int.tryParse(arabic.group(1)!);
    final chinese = RegExp(
      r'(?:套装|全套|共)?([零一二三四五六七八九十两]{1,3})(?:册|部曲)',
    ).firstMatch(title);
    return chinese == null ? null : _parseChineseCount(chinese.group(1)!);
  }

  static int? _parseChineseCount(String raw) {
    const digits = <String, int>{
      '零': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (raw == '十') return 10;
    final separator = raw.indexOf('十');
    if (separator < 0) return digits[raw];
    final tens = separator == 0 ? 1 : digits[raw.substring(0, separator)];
    final ones = separator + 1 == raw.length
        ? 0
        : digits[raw.substring(separator + 1)];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }

  static List<AiBookWork> _rangesFromIndexCandidates(
    List<BookStructureNavigationNode> candidates, {
    Iterable<BookStructureNavigationNode> trailingBoundaries = const [],
  }) {
    final ordered =
        candidates
            .where((node) => node.sectionIndex != null)
            .toList(growable: false)
          ..sort((left, right) {
            final section = left.sectionIndex!.compareTo(right.sectionIndex!);
            return section != 0 ? section : left.order.compareTo(right.order);
          });
    final boundarySections =
        trailingBoundaries
            .map((node) => node.sectionIndex)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    return [
      for (var index = 0; index < ordered.length; index++)
        AiBookWork(
          id: ordered[index].nodeId,
          title: ordered[index].title,
          startSection: ordered[index].sectionIndex! + 1,
          endSectionExclusive: _nextRangeBoundary(
            currentSection: ordered[index].sectionIndex!,
            nextSelectedSection: index + 1 < ordered.length
                ? ordered[index + 1].sectionIndex
                : null,
            trailingBoundarySections: boundarySections,
          ),
        ),
    ];
  }

  static int? _nextRangeBoundary({
    required int currentSection,
    required int? nextSelectedSection,
    required List<int> trailingBoundarySections,
  }) {
    int? boundary = nextSelectedSection;
    for (final section in trailingBoundarySections) {
      if (section <= currentSection) continue;
      if (boundary == null || section < boundary) boundary = section;
      break;
    }
    return boundary == null ? null : boundary + 1;
  }

  static AiBookStructureManifest resolve({
    required List<AiBookSectionSlice> navigationSections,
    required List<AiBookSectionSlice> spineSections,
    required bool Function(String title) isSupplementTitle,
  }) {
    // Keep supplement anchors as range boundaries even though they are not
    // candidate works. Otherwise the final work would absorb a trailing
    // appendix/author note until EOF.
    final allNavigation = <AiBookSectionSlice>[];
    final navigation = <AiBookSectionSlice>[];
    final seenStarts = <int>{};
    final navigationTitlesByStart = <int, List<String>>{};
    for (final section in navigationSections) {
      final title = section.label.trim();
      final start = section.sourceSectionIndex;
      if (!section.isNavigationUnit || start == null || title.isEmpty) {
        continue;
      }
      if (!isSupplementTitle(title)) {
        navigationTitlesByStart.putIfAbsent(start, () => []).add(title);
      }
      if (!seenStarts.add(start)) {
        continue;
      }
      allNavigation.add(section);
      if (isSupplementTitle(title)) continue;
      navigation.add(section);
    }
    allNavigation.sort(
      (left, right) =>
          left.originSectionIndex.compareTo(right.originSectionIndex),
    );
    navigation.sort(
      (left, right) =>
          left.originSectionIndex.compareTo(right.originSectionIndex),
    );

    final logicalWorks = _logicalWorksInSharedSpines(
      spineSections,
      isSupplementTitle,
    );
    final duplicateIndependentStart = navigationTitlesByStart.values.any(
      (titles) => titles.where(_isIndependentWorkCandidateTitle).length >= 2,
    );
    if (logicalWorks.length >= 2 || duplicateIndependentStart) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.uncertain,
        source: AiBookStructureSource.spineHeadings,
        confidence: 0.45,
        reason: 'multiple logical works share one spine',
        works: logicalWorks,
      );
    }

    if (navigation.length < 2) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.heuristic,
        confidence: 0.8,
        reason: 'fewer than two independent navigation ranges',
      );
    }

    final chapterCount = navigation
        .where((section) => isChapterTitle(section.label))
        .length;
    final volumeCount = navigation
        .where((section) => isVolumeTitle(section.label))
        .length;
    final chapterMajority = chapterCount * 2 > navigation.length;
    final volumeMajority = volumeCount * 2 > navigation.length;
    final childBearing = navigation
        .where((section) => section.navigationChildCount > 0)
        .length;
    final hierarchyMajority = childBearing * 2 >= navigation.length;
    final ranges = _rangesFromNavigation(navigation, allNavigation);

    if (volumeMajority) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.segmentedSingleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: hierarchyMajority ? 0.95 : 0.78,
        reason: 'navigation units are parts or volumes of one work',
        works: ranges,
      );
    }
    if (chapterMajority) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.95,
        reason: 'navigation units are chapters',
      );
    }
    if (hierarchyMajority) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.multiWorkOmnibus,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.95,
        reason: 'top-level navigation units contain their own children',
        works: ranges,
      );
    }

    final carrierSpines = <int>{};
    final groups = <int, List<AiBookSectionSlice>>{};
    for (final section in spineSections) {
      groups.putIfAbsent(section.originSectionIndex, () => []).add(section);
    }
    for (final entry in groups.entries) {
      final pieces = entry.value
          .where(
            (section) =>
                section.text.trim().isNotEmpty &&
                !isSupplementTitle(section.label),
          )
          .length;
      if (pieces >= 3) carrierSpines.add(entry.key);
    }
    final alignedCarriers = navigation.every(
      (section) =>
          carrierSpines.contains(section.originSectionIndex) ||
          carrierSpines.contains(section.originSectionIndex + 1),
    );
    if (carrierSpines.length >= 2 && alignedCarriers) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.multiWorkOmnibus,
        source: AiBookStructureSource.spineHeadings,
        confidence: 0.82,
        reason: 'navigation starts align with multi-piece work carriers',
        works: ranges,
      );
    }

    // A flat TOC with evocative/non-numbered labels is normal for novels.
    // Absence of chapter-shaped titles or child nodes is not positive
    // evidence of an omnibus. The conflict paths above (duplicate physical
    // starts or several top-level logical works in one spine) still fail
    // closed; without one of those facts, keep one publication-wide scope.
    return const AiBookStructureManifest(
      kind: AiBookStructureKind.singleWork,
      source: AiBookStructureSource.heuristic,
      confidence: 0.65,
      reason: 'flat non-chapter navigation has no independent-work evidence',
    );
  }

  static List<AiBookWork> _rangesFromNavigation(
    List<AiBookSectionSlice> sections,
    List<AiBookSectionSlice> allAnchors,
  ) => [
    for (var i = 0; i < sections.length; i++)
      AiBookWork(
        id: 's${sections[i].originSectionIndex}',
        title: sections[i].label.trim(),
        startSection: sections[i].originSectionIndex,
        endSectionExclusive: _nextAnchorAfter(
          allAnchors,
          sections[i].originSectionIndex,
        ),
        sample: _sample(sections[i].text),
      ),
  ];

  static int? _nextAnchorAfter(
    List<AiBookSectionSlice> anchors,
    int startSection,
  ) {
    for (final anchor in anchors) {
      if (anchor.originSectionIndex > startSection) {
        return anchor.originSectionIndex;
      }
    }
    return null;
  }

  static List<AiBookWork> _logicalWorksInSharedSpines(
    List<AiBookSectionSlice> sections,
    bool Function(String title) isSupplementTitle,
  ) {
    final containers = sections
        .where(
          (section) =>
              section.level == 1 &&
              section.text.trim().isEmpty &&
              section.label.trim().isNotEmpty &&
              _isIndependentWorkCandidateTitle(section.label) &&
              !isSupplementTitle(section.label),
        )
        .toList(growable: false);
    final counts = <int, int>{};
    for (final section in containers) {
      counts[section.originSectionIndex] =
          (counts[section.originSectionIndex] ?? 0) + 1;
    }
    final shared = counts.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toSet();
    return [
      for (var i = 0; i < containers.length; i++)
        if (shared.contains(containers[i].originSectionIndex))
          AiBookWork(
            id: 's${containers[i].originSectionIndex}-l${containers[i].index}',
            title: containers[i].label.trim(),
            startSection: containers[i].originSectionIndex,
            endSectionExclusive: containers[i].originSectionIndex + 1,
            startLogicalIndex: containers[i].index,
            endLogicalIndexExclusive:
                i + 1 < containers.length &&
                    containers[i + 1].originSectionIndex ==
                        containers[i].originSectionIndex
                ? containers[i + 1].index
                : null,
          ),
    ];
  }

  static String _sample(String value) {
    final text = value.trim();
    return text.length <= 160 ? text : '${text.substring(0, 159)}…';
  }
}

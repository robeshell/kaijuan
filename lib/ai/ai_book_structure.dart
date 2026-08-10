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
  }) {
    if (!index.isUsable) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.heuristic,
        confidence: 0.5,
        reason: 'structure index is unavailable',
      );
    }

    var candidates = index.navigationRoots;
    if (candidates.length == 1) {
      final children = index.childrenOf(candidates.single.nodeId);
      if (children.length >= 2) candidates = children;
    }
    candidates = candidates
        .where((node) => !isSupplementTitle(node.title))
        .toList(growable: false);
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
    if (chapterLikeCount * 2 >= candidates.length) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.98,
        reason: 'indexed top-level ranges are chapters and subtitles',
      );
    }

    final ranges = _rangesFromIndexCandidates(candidates);
    final volumeCount = candidates
        .where((node) => isVolumeTitle(node.title))
        .length;
    if (volumeCount * 2 >= candidates.length) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.segmentedSingleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.95,
        reason: 'indexed top-level ranges are parts or volumes',
        works: ranges,
      );
    }

    // A chapter owning several subsection nodes is normal and cannot prove an
    // omnibus. Require publication-level collection metadata before promoting
    // arbitrary titled roots to independent works.
    final hasOmnibusTitleEvidence = _omnibusTitlePattern.hasMatch(
      index.publicationTitle,
    );
    final omnibusCandidates = _mergeSplitInstallments(candidates);
    final hasRepeatedInstallmentEvidence =
        candidates.length >= 4 &&
        omnibusCandidates.length >= 2 &&
        omnibusCandidates.length * 2 <= candidates.length;
    if (!hasOmnibusTitleEvidence && !hasRepeatedInstallmentEvidence) {
      return const AiBookStructureManifest(
        kind: AiBookStructureKind.singleWork,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.94,
        reason: 'chapter subtrees lack publication-level omnibus evidence',
      );
    }

    final omnibusRanges = _rangesFromIndexCandidates(omnibusCandidates);

    final independentCount = candidates
        .where(
          (node) =>
              node.directChildCount >= 2 ||
              index.childrenOf(node.nodeId).length >= 2,
        )
        .length;
    if (independentCount * 2 >= candidates.length) {
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
        confidence: 0.97,
        reason: 'indexed top-level ranges own chapter subtrees',
        works: omnibusRanges,
      );
    }

    if (omnibusRanges.length >= 2) {
      return AiBookStructureManifest(
        kind: AiBookStructureKind.multiWorkOmnibus,
        source: AiBookStructureSource.navigationHierarchy,
        confidence: 0.92,
        reason: hasOmnibusTitleEvidence
            ? 'publication metadata corroborates indexed work ranges'
            : 'repeated split installments corroborate indexed work ranges',
        works: omnibusRanges,
      );
    }

    return const AiBookStructureManifest(
      kind: AiBookStructureKind.singleWork,
      source: AiBookStructureSource.heuristic,
      confidence: 0.72,
      reason: 'indexed flat ranges have no independent-work evidence',
    );
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

  static List<AiBookWork> _rangesFromIndexCandidates(
    List<BookStructureNavigationNode> candidates,
  ) {
    final ordered =
        candidates
            .where((node) => node.sectionIndex != null)
            .toList(growable: false)
          ..sort((left, right) {
            final section = left.sectionIndex!.compareTo(right.sectionIndex!);
            return section != 0 ? section : left.order.compareTo(right.order);
          });
    return [
      for (var index = 0; index < ordered.length; index++)
        AiBookWork(
          id: ordered[index].nodeId,
          title: ordered[index].title,
          startSection: ordered[index].sectionIndex! + 1,
          endSectionExclusive:
              index + 1 < ordered.length &&
                  ordered[index + 1].sectionIndex != ordered[index].sectionIndex
              ? ordered[index + 1].sectionIndex! + 1
              : null,
        ),
    ];
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

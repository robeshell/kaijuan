import 'ai_chat_retrieve.dart';

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
    r'第[0-9零一二三四五六七八九十百千两]+[章节回篇集讲则]'
    r'|[章节回篇集讲][0-9零一二三四五六七八九十百千两]+'
    r'|(序章|楔子|引子|尾声|终章|番外|前言|序言|自序|序|跋|后记|引论|导论|绪论)'
    r'|(chapter|section|prologue|epilogue|introduction)\s*[0-9ivxlcdm]*'
    r')',
    caseSensitive: false,
  );

  static final RegExp _volumeTitlePattern = RegExp(
    r'^('
    r'第[0-9零一二三四五六七八九十百千两]+[部卷]'
    r'|[部卷][0-9零一二三四五六七八九十百千两]+'
    r'|(part|book|volume|vol\.?)\s*[0-9ivxlcdm]+'
    r')',
    caseSensitive: false,
  );

  static bool isChapterTitle(String raw) =>
      _chapterTitlePattern.hasMatch(raw.trim());

  static bool isVolumeTitle(String raw) =>
      _volumeTitlePattern.hasMatch(raw.trim());

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
    var duplicateStart = false;
    for (final section in navigationSections) {
      final title = section.label.trim();
      final start = section.sourceSectionIndex;
      if (!section.isNavigationUnit || start == null || title.isEmpty) {
        continue;
      }
      if (!seenStarts.add(start)) {
        duplicateStart = true;
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
    if (logicalWorks.length >= 2 || duplicateStart) {
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

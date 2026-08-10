import 'dart:convert';

/// Complete, text-free structure facts for one opened reflow publication.
///
/// The reader owns extraction. AI consumers may classify and resolve scopes
/// from this index, but must load正文 through the corpus bridge separately.
final class BookStructureIndex {
  const BookStructureIndex({
    required this.indexVersion,
    required this.sections,
    required this.navigation,
    this.publicationTitle = '',
  });

  static const currentVersion = 1;

  final int indexVersion;
  final String publicationTitle;
  final List<BookStructureSection> sections;
  final List<BookStructureNavigationNode> navigation;

  bool get isUsable =>
      indexVersion == currentVersion &&
      sections.isNotEmpty &&
      sections.every((section) => section.sectionIndex >= 0);

  List<BookStructureNavigationNode> get navigationRoots =>
      navigation.where((node) => node.parentId == null).toList(growable: false);

  List<BookStructureNavigationNode> childrenOf(String nodeId) => navigation
      .where((node) => node.parentId == nodeId)
      .toList(growable: false);

  BookStructureSection? sectionAt(int sectionIndex) {
    for (final section in sections) {
      if (section.sectionIndex == sectionIndex) return section;
    }
    return null;
  }

  int get headingCount => sections.fold<int>(
    0,
    (total, section) => total + section.headings.length,
  );

  int get bodyCharCount =>
      sections.fold<int>(0, (total, section) => total + section.bodyCharCount);

  static BookStructureIndex? tryParse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final version = value['indexVersion'];
      final sectionRows = value['sections'];
      final navigationRows = value['navigation'];
      if (version is! num || sectionRows is! List || navigationRows is! List) {
        return null;
      }
      final sections = sectionRows
          .map(BookStructureSection.tryParse)
          .whereType<BookStructureSection>()
          .toList(growable: false);
      final navigation = navigationRows
          .map(BookStructureNavigationNode.tryParse)
          .whereType<BookStructureNavigationNode>()
          .toList(growable: false);
      final index = BookStructureIndex(
        indexVersion: version.toInt(),
        publicationTitle: value['publicationTitle']?.toString().trim() ?? '',
        sections: List.unmodifiable(sections),
        navigation: List.unmodifiable(navigation),
      );
      return index.isUsable ? index : null;
    } catch (_) {
      return null;
    }
  }
}

final class BookStructureSection {
  const BookStructureSection({
    required this.sectionIndex,
    required this.href,
    required this.documentTitle,
    required this.bodyCharCount,
    required this.headings,
  });

  /// Zero-based Foliate spine index, matching [BookLocator.sectionIndex].
  final int sectionIndex;
  final String href;
  final String documentTitle;
  final int bodyCharCount;
  final List<BookStructureHeading> headings;

  static BookStructureSection? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final sectionIndex = raw['sectionIndex'];
    final bodyCharCount = raw['bodyCharCount'];
    final headingRows = raw['headings'];
    if (sectionIndex is! num || sectionIndex < 0 || bodyCharCount is! num) {
      return null;
    }
    final headings = headingRows is List
        ? headingRows
              .map(BookStructureHeading.tryParse)
              .whereType<BookStructureHeading>()
              .toList(growable: false)
        : const <BookStructureHeading>[];
    return BookStructureSection(
      sectionIndex: sectionIndex.toInt(),
      href: raw['href']?.toString() ?? '',
      documentTitle: raw['documentTitle']?.toString().trim() ?? '',
      bodyCharCount: bodyCharCount.toInt().clamp(0, 1 << 31),
      headings: List.unmodifiable(headings),
    );
  }
}

final class BookStructureHeading {
  const BookStructureHeading({
    required this.title,
    required this.level,
    required this.order,
    this.fragment,
    this.cfi,
  });

  final String title;
  final int level;
  final int order;
  final String? fragment;
  final String? cfi;

  static BookStructureHeading? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title']?.toString().trim() ?? '';
    final level = raw['level'];
    final order = raw['order'];
    if (title.isEmpty || level is! num || order is! num) return null;
    final fragment = raw['fragment']?.toString().trim();
    final cfi = raw['cfi']?.toString().trim();
    return BookStructureHeading(
      title: title,
      level: level.toInt().clamp(1, 6),
      order: order.toInt().clamp(0, 1 << 31),
      fragment: fragment == null || fragment.isEmpty ? null : fragment,
      cfi: cfi == null || cfi.isEmpty ? null : cfi,
    );
  }
}

final class BookStructureNavigationNode {
  const BookStructureNavigationNode({
    required this.nodeId,
    required this.title,
    required this.depth,
    required this.order,
    required this.href,
    required this.sectionIndex,
    required this.directChildCount,
    this.parentId,
    this.fragment,
  });

  final String nodeId;
  final String? parentId;
  final String title;
  final int depth;
  final int order;
  final String href;
  final String? fragment;
  final int? sectionIndex;
  final int directChildCount;

  static BookStructureNavigationNode? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final nodeId = raw['nodeId']?.toString().trim() ?? '';
    final title = raw['title']?.toString().trim() ?? '';
    final depth = raw['depth'];
    final order = raw['order'];
    final directChildCount = raw['directChildCount'];
    if (nodeId.isEmpty ||
        title.isEmpty ||
        depth is! num ||
        order is! num ||
        directChildCount is! num) {
      return null;
    }
    final parentId = raw['parentId']?.toString().trim();
    final fragment = raw['fragment']?.toString().trim();
    final rawSection = raw['sectionIndex'];
    return BookStructureNavigationNode(
      nodeId: nodeId,
      parentId: parentId == null || parentId.isEmpty ? null : parentId,
      title: title,
      depth: depth.toInt().clamp(0, 64),
      order: order.toInt().clamp(0, 1 << 31),
      href: raw['href']?.toString() ?? '',
      fragment: fragment == null || fragment.isEmpty ? null : fragment,
      sectionIndex: rawSection is num && rawSection >= 0
          ? rawSection.toInt()
          : null,
      directChildCount: directChildCount.toInt().clamp(0, 1 << 20),
    );
  }
}

import 'ai_book_corpus.dart';
import 'ai_book_structure.dart';
import 'ai_cancel.dart';
import 'ai_chat_retrieve.dart';
import 'ai_log.dart';
import '../domain/book_structure.dart';

/// Resolves and caches the logical-work structure of one opened publication.
///
/// This is the shared scope authority for chat, outline and graph. Keeping it
/// beside the corpus prevents those features from independently recognizing
/// the same file and disagreeing about which work the reader is in.
class AiBookStructureSession {
  AiBookStructureSession({
    required this.corpus,
    required this.isSupplementTitle,
    this.loadIndex,
  });

  final AiBookCorpusCache corpus;
  final bool Function(String title) isSupplementTitle;
  final Future<BookStructureIndex?> Function()? loadIndex;

  AiBookStructureManifest? _manifest;
  List<AiBookWork>? _scopedWorks;
  BookStructureIndex? _index;

  AiBookStructureManifest? get manifest => _manifest;
  List<AiBookWork>? get scopedWorks => _scopedWorks;
  BookStructureIndex? get index => _index;
  bool get isResolved => _manifest != null;

  bool get hasCollectionWorks => _scopedWorks?.isNotEmpty ?? false;

  bool get hasAmbiguousInternalWorks =>
      (_manifest?.requiresLogicalWorkLocator ?? false) ||
      (_manifest?.requiresUserScopeConfirmation ?? false);

  AiBookWork? workAtSection(int sectionIndex1Based) {
    final works = _scopedWorks;
    if (works == null) return null;
    for (final work in works) {
      if (work.contains(sectionIndex1Based)) return work;
    }
    return null;
  }

  Future<List<AiBookWork>?> resolve({
    required int maxChars,
    CancelToken? cancel,
  }) async {
    if (isResolved) return _scopedWorks;
    cancel?.throwIfCancelled();
    final loadStructureIndex = loadIndex;
    if (loadStructureIndex != null) {
      try {
        final index = await loadStructureIndex();
        cancel?.throwIfCancelled();
        if (index != null && index.isUsable) {
          _index = index;
          return _accept(
            AiBookStructureResolver.resolveIndex(
              index: index,
              isSupplementTitle: isSupplementTitle,
            ),
            detail:
                'index sections=${index.sections.length} '
                'navigation=${index.navigation.length} '
                'headings=${index.headingCount}',
          );
        }
      } catch (error) {
        AiLog.d(
          'book structure index unavailable, using legacy fallback: $error',
        );
      }
    }
    final navigationBody = await corpus.loadNavigation(maxChars);
    cancel?.throwIfCancelled();
    final spineBody = await corpus.loadSpine(maxChars);
    cancel?.throwIfCancelled();
    final manifest = AiBookStructureResolver.resolve(
      navigationSections: AiChatRetrieve.splitSections(navigationBody),
      spineSections: AiChatRetrieve.splitSections(spineBody),
      isSupplementTitle: isSupplementTitle,
    );
    return _accept(manifest, detail: 'legacy-body');
  }

  List<AiBookWork>? _accept(
    AiBookStructureManifest manifest, {
    required String detail,
  }) {
    _manifest = manifest;
    final scoped = manifest.scopedWorks;
    _scopedWorks = scoped.isEmpty ? null : scoped;
    AiLog.d(
      'book structure: kind=${manifest.kind.name} '
      'source=${manifest.source.name} confidence=${manifest.confidence} '
      'works=${manifest.works.map((work) => work.title).join(" | ")} '
      'reason=${manifest.reason} facts=$detail',
    );
    return _scopedWorks;
  }
}

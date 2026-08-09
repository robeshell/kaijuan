import 'ai_book_corpus.dart';
import 'ai_book_structure.dart';
import 'ai_cancel.dart';
import 'ai_chat_retrieve.dart';
import 'ai_log.dart';

/// Resolves and caches the logical-work structure of one opened publication.
///
/// This is the shared scope authority for chat, outline and graph. Keeping it
/// beside the corpus prevents those features from independently recognizing
/// the same file and disagreeing about which work the reader is in.
class AiBookStructureSession {
  AiBookStructureSession({
    required this.corpus,
    required this.isSupplementTitle,
  });

  final AiBookCorpusCache corpus;
  final bool Function(String title) isSupplementTitle;

  AiBookStructureManifest? _manifest;
  List<AiBookWork>? _scopedWorks;

  AiBookStructureManifest? get manifest => _manifest;
  List<AiBookWork>? get scopedWorks => _scopedWorks;
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
    final navigationBody = await corpus.loadNavigation(maxChars);
    cancel?.throwIfCancelled();
    final spineBody = await corpus.loadSpine(maxChars);
    cancel?.throwIfCancelled();
    final manifest = AiBookStructureResolver.resolve(
      navigationSections: AiChatRetrieve.splitSections(navigationBody),
      spineSections: AiChatRetrieve.splitSections(spineBody),
      isSupplementTitle: isSupplementTitle,
    );
    _manifest = manifest;
    final scoped = manifest.scopedWorks;
    _scopedWorks = scoped.isEmpty ? null : scoped;
    AiLog.d(
      'book structure: kind=${manifest.kind.name} '
      'source=${manifest.source.name} confidence=${manifest.confidence} '
      'works=${manifest.works.map((work) => work.title).join(" | ")} '
      'reason=${manifest.reason}',
    );
    return _scopedWorks;
  }
}

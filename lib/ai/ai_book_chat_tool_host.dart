import 'ai_book_corpus.dart';
import 'ai_book_structure.dart';
import 'ai_chat.dart';
import 'ai_chat_retrieve.dart';
import 'ai_chat_service.dart';
import 'ai_chat_tools.dart';

/// Reader-backed tools exposed to the book-chat model.
///
/// The host freezes the reading context for one turn and delegates publication
/// extraction/caching to [AiBookCorpusCache]. It deliberately has no dependency
/// on presentation controllers.
class AiBookChatToolHost implements AiChatToolHost {
  AiBookChatToolHost({
    required this.corpus,
    required this.turnContext,
    this.work,
  });

  final AiBookCorpusCache corpus;
  final AiBookWork? work;
  final AiChatContextBundle turnContext;

  Future<String> _body() async {
    final body = await corpus.loadChat(AiChatService.maxBookBodyChars, work);
    // Engines are expected to honor range arguments, but scope once more so a
    // non-conforming engine cannot leak an adjacent work into this turn.
    return scopeAiChatBodyToWork(body, work);
  }

  Future<List<AiBookSectionSlice>> _sections() async {
    return AiChatRetrieve.splitSections(await _body());
  }

  @override
  Future<String> toolGetToc() async {
    final sections = await _sections();
    if (sections.isEmpty) return '(目录不可用)';
    return AiChatBookCorpus.formatTocFromSlices(sections);
  }

  @override
  Future<String> toolGetCurrentChapter({int maxChars = 10000}) async {
    final text = turnContext.chapterText.trim();
    if (text.isEmpty) return '(当前章正文不可用)';
    final title = turnContext.chapterTitle.trim();
    final body = text.length > maxChars
        ? '${text.substring(0, maxChars)}…'
        : text;
    if (title.isEmpty) return body;
    return '[$title]\n$body';
  }

  @override
  Future<String> toolGetChapter(
    int sectionIndex1Based, {
    int maxChars = 10000,
  }) async {
    final sections = await _sections();
    if (sections.isEmpty) {
      return 'Error: chapter corpus unavailable; try get_current_chapter.';
    }
    return AiChatBookCorpus.sectionText(
      sections,
      sectionIndex1Based,
      maxChars: maxChars,
    );
  }

  @override
  Future<String> toolSearchBook(String query, {int maxChars = 12000}) async {
    final body = await _body();
    if (body.isEmpty) return '(书中无正文可检索)';
    final packed = AiChatRetrieve.pack(
      userText: query,
      selection: '',
      bookBody: body,
      maxSections: 10,
      maxRelatedChars: maxChars,
    );
    final formatted = packed.formatRelatedForPrompt(maxChars: maxChars);
    if (formatted.isEmpty) {
      return 'No keyword hits for "$query". Try sample_book or get_toc.';
    }
    return 'Search "$query" (${packed.note}):\n$formatted';
  }

  @override
  Future<String> toolSampleBook({int maxChars = 36000}) async {
    final body = await _body();
    if (body.isEmpty) return '(书中无正文可取样)';
    final packed = AiChatRetrieve.pack(
      userText: '请根据提供的各部分正文，概括整本书的主线与主题',
      selection: '',
      bookBody: body,
      maxSections: 16,
      maxRelatedChars: maxChars,
    );
    final formatted = packed.formatRelatedForPrompt(maxChars: maxChars);
    final outline = packed.sectionOutline.isEmpty
        ? ''
        : 'Parts: ${packed.sectionOutline.join(' · ')}\n\n';
    if (formatted.isEmpty) return '$outline(empty samples)';
    return '$outline$formatted';
  }
}

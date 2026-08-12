import '../../ai/ai_agent_runtime.dart';
import '../../ai/ai_book_chat_tool_host.dart';
import '../../ai/ai_book_corpus.dart';
import '../../ai/ai_book_structure.dart';
import '../../ai/ai_cancel.dart';
import '../../ai/ai_chat.dart';
import '../../ai/ai_chat_tools.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_product_action.dart';
import '../../ai/ai_run.dart';
import '../../ai/ai_search.dart';
import 'book_ai_workspace_controller.dart';

/// Reader-facing capability gateway for ordinary book conversation.
///
/// It receives a frozen reader snapshot from [BookReaderController], builds
/// the App-owned Agent turn and records run events in the AI workspace. It has
/// no Widget, WebView, database or provider-specific dependency.
class BookAiReaderGateway {
  const BookAiReaderGateway(this._workspace, this._corpus);

  final BookAiWorkspaceController _workspace;
  final AiBookCorpusCache _corpus;

  AiChatToolHost createToolHost({
    required AiChatContextBundle context,
    AiBookWork? work,
  }) => AiBookChatToolHost(corpus: _corpus, work: work, turnContext: context);

  Future<AiChatContextBundle> loadContext({
    required int chapterSectionIndex,
    required String chapterTitle,
    required List<String> tocTitles,
    required AiBookWork? workScope,
    AiChatCorpusScope corpusScope = AiChatCorpusScope.currentWork,
    String? selectionOverride,
    String? currentSelection,
    Future<String?> Function()? loadSelectedText,
    Future<String?> Function()? loadChapterText,
    double? readingProgressFraction,
    String publicationTitle = '',
  }) async {
    try {
      var selection = selectionOverride?.trim() ?? '';
      if (selection.isEmpty) selection = currentSelection?.trim() ?? '';
      if (selection.isEmpty) {
        selection = ((await loadSelectedText?.call()) ?? '').trim();
      }
      final chapter = ((await loadChapterText?.call()) ?? '').trim();
      var outline = tocTitles
          .map((title) => title.trim())
          .where((title) => title.isNotEmpty)
          .toList(growable: false);
      // Whole-publication mode keeps the full TOC; current-work trims it.
      if (corpusScope == AiChatCorpusScope.currentWork && workScope != null) {
        outline = [
          for (var index = 0; index < tocTitles.length; index++)
            if (workScope.contains(index + 1) &&
                tocTitles[index].trim().isNotEmpty)
              tocTitles[index].trim(),
        ];
      }
      // scopeLabel always names where the reader is sitting (when known).
      final scopeLabel =
          workScope?.title.trim().isNotEmpty == true ? workScope!.title : null;
      return AiChatContextBundle(
        chapterTitle: chapterTitle,
        chapterText: chapter,
        selectionText: selection,
        tocOutline: outline,
        scopeLabel: scopeLabel,
        chapterSectionIndex: chapterSectionIndex,
        readingProgressFraction: readingProgressFraction,
        publicationTitle: publicationTitle,
        corpusScope: corpusScope,
      );
    } catch (_) {
      return AiChatContextBundle(
        chapterTitle: chapterTitle,
        chapterSectionIndex: chapterSectionIndex,
        readingProgressFraction: readingProgressFraction,
        publicationTitle: publicationTitle,
        corpusScope: corpusScope,
      );
    }
  }

  Stream<AiRunEvent>? streamChat({
    required String contentHash,
    required String bookTitle,
    required String? bookAuthor,
    required String userText,
    required List<AiChatMessage> history,
    required AiChatContextBundle context,
    required AiBookWork? workScope,
    List<AiWebSearchHit>? webHits,
    AiChatProductContext productContext = const AiChatProductContext(),
    bool? reasoningEnabled,
    CancelToken? cancelToken,
    String? runId,
  }) {
    final runtime = _workspace.agentRuntime;
    if (runtime == null || !runtime.isAvailable) return null;
    return _streamResolvedChat(
      runtime: runtime,
      contentHash: contentHash,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      userText: userText,
      history: history,
      context: context,
      workScope: workScope,
      webHits: webHits,
      productContext: productContext,
      reasoningEnabled: reasoningEnabled,
      cancelToken: cancelToken,
      runId: runId,
    );
  }

  Stream<AiRunEvent> _streamResolvedChat({
    required AiAgentRuntime runtime,
    required String contentHash,
    required String bookTitle,
    required String? bookAuthor,
    required String userText,
    required List<AiChatMessage> history,
    required AiChatContextBundle context,
    required AiBookWork? workScope,
    required List<AiWebSearchHit>? webHits,
    required AiChatProductContext productContext,
    required bool? reasoningEnabled,
    required CancelToken? cancelToken,
    required String? runId,
  }) async* {
    await for (final event in runtime.stream(
      AiAgentTurn(
        run: AiRunDescriptor(
          runId: runId ?? AiRunIds.next(),
          task: AiRunTask.bookChat,
          scope: AiRunScope(
            contentHash: contentHash,
            workKey: workScope?.id,
            label: context.scopeLabel,
          ),
        ),
        userText: userText,
        history: history,
        context: context,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        webHits: webHits,
        productContext: productContext,
        reasoningEnabled: reasoningEnabled,
        tools: createToolHost(
          context: context,
          // null work ⇒ host does not crop the corpus (whole publication).
          work: context.corpusScope == AiChatCorpusScope.wholePublication
              ? null
              : workScope,
        ),
        cancelToken: cancelToken,
      ),
    )) {
      _workspace.recordRunEvent(event);
      yield event;
    }
  }

  Future<List<String>> suggestFollowUps({
    required String bookTitle,
    required String? bookAuthor,
    required String userText,
    required String answer,
    required AiChatContextBundle context,
    CancelToken? cancelToken,
  }) async {
    final runtime = _workspace.agentRuntime;
    if (runtime == null || !runtime.isAvailable) return const [];
    return runtime.suggestFollowUpQuestions(
      AiAgentSuggestionRequest(
        userText: userText,
        answer: answer,
        context: context,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        cancelToken: cancelToken,
      ),
    );
  }

  Future<List<AiWebSearchHit>> searchWeb({
    required String query,
    required String bookTitle,
    required String? bookAuthor,
    CancelToken? cancelToken,
  }) async {
    final settings = _workspace.settingsController;
    if (settings == null || !settings.isSearchReady) {
      throw AiProviderException('请先在设置中配置联网搜索 Key');
    }
    final resolvedQuery = buildAiWebSearchQuery(
      userText: query,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
    );
    return settings.searchWeb(resolvedQuery, cancelToken: cancelToken);
  }
}

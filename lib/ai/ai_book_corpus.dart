import 'ai_book_structure.dart';
import 'ai_chat_retrieve.dart';
import 'ai_log.dart';

typedef AiBookBodyLoader =
    Future<String> Function(
      int maxChars, {
      required bool toc,
      int? startSection,
      int? endSectionExclusive,
    });

/// Reader-backed corpus cache shared by chat, outline and graph tasks.
///
/// It owns only extraction/caching policy. The reader remains responsible for
/// actually reading the publication through [loadBookBody]/[loadChapter].
class AiBookCorpusCache {
  AiBookCorpusCache({required this.loadBookBody, required this.loadChapter});

  final AiBookBodyLoader loadBookBody;
  final Future<String> Function() loadChapter;

  String? _navigationBody;
  int _navigationBudget = 0;
  Future<String>? _navigationPending;
  int _navigationPendingBudget = 0;
  String? _spineBody;
  int _spineBudget = 0;
  Future<String>? _spinePending;
  int _spinePendingBudget = 0;
  int _cacheEpoch = 0;
  final Map<String, ({String body, int budget})> _chatBodies = {};

  void clear() {
    _cacheEpoch++;
    _navigationBody = null;
    _navigationBudget = 0;
    _navigationPending = null;
    _navigationPendingBudget = 0;
    _spineBody = null;
    _spineBudget = 0;
    _spinePending = null;
    _spinePendingBudget = 0;
    _chatBodies.clear();
  }

  Future<String> loadNavigation(int maxChars) async {
    final budget = maxChars.clamp(2000, 1500000);
    final cached = _navigationBody;
    if (cached != null && cached.isNotEmpty && _navigationBudget >= budget) {
      return cached.length > budget ? cached.substring(0, budget) : cached;
    }
    final pending = _navigationPending;
    if (pending != null) {
      final pendingBudget = _navigationPendingBudget;
      final loaded = await pending;
      if (pendingBudget >= budget || loaded.isEmpty) {
        return loaded.length > budget ? loaded.substring(0, budget) : loaded;
      }
      if (identical(_navigationPending, pending)) {
        _navigationPending = null;
        _navigationPendingBudget = 0;
      }
      return loadNavigation(maxChars);
    }
    final epoch = _cacheEpoch;
    final operation = () async {
      final loaded = (await loadBookBody(budget, toc: true)).trim();
      if (loaded.isNotEmpty) {
        if (epoch == _cacheEpoch) {
          _navigationBody = loaded;
          _navigationBudget = budget;
        }
        return loaded;
      }
      return (await loadChapter()).trim();
    }();
    _navigationPending = operation;
    _navigationPendingBudget = budget;
    try {
      return await operation;
    } finally {
      if (identical(_navigationPending, operation)) {
        _navigationPending = null;
        _navigationPendingBudget = 0;
      }
    }
  }

  Future<String> loadSpine(int maxChars) async {
    final budget = maxChars.clamp(2000, 1500000);
    final cached = _spineBody;
    if (cached != null && cached.isNotEmpty && _spineBudget >= budget) {
      return cached.length > budget ? cached.substring(0, budget) : cached;
    }
    final pending = _spinePending;
    if (pending != null) {
      final pendingBudget = _spinePendingBudget;
      final loaded = await pending;
      if (pendingBudget >= budget || loaded.isEmpty) {
        return loaded.length > budget ? loaded.substring(0, budget) : loaded;
      }
      if (identical(_spinePending, pending)) {
        _spinePending = null;
        _spinePendingBudget = 0;
      }
      return loadSpine(maxChars);
    }
    final epoch = _cacheEpoch;
    final operation = () async {
      final loaded = (await loadBookBody(budget, toc: false)).trim();
      if (loaded.isNotEmpty) {
        if (epoch == _cacheEpoch) {
          _spineBody = loaded;
          _spineBudget = budget;
        }
        return loaded;
      }
      return loadNavigation(maxChars);
    }();
    _spinePending = operation;
    _spinePendingBudget = budget;
    try {
      return await operation;
    } finally {
      if (identical(_spinePending, operation)) {
        _spinePending = null;
        _spinePendingBudget = 0;
      }
    }
  }

  Future<String> loadChat(int maxChars, AiBookWork? work) async {
    final budget = maxChars.clamp(2000, 1500000);
    final key = work == null
        ? 'whole'
        : '${work.id}:${work.startSection}:${work.endSectionExclusive ?? 'end'}';
    final cached = _chatBodies[key];
    if (cached != null && cached.body.isNotEmpty && cached.budget >= budget) {
      return cached.body.length > budget
          ? cached.body.substring(0, budget)
          : cached.body;
    }
    final loaded = (await loadBookBody(
      budget,
      toc: false,
      startSection: work?.startSection,
      endSectionExclusive: work?.endSectionExclusive,
    )).trim();
    if (loaded.isNotEmpty) {
      _chatBodies[key] = (body: loaded, budget: budget);
      return loaded;
    }
    return (await loadChapter()).trim();
  }
}

/// Restricts a chapter-granular corpus to one work in an omnibus.
String scopeAiChatBodyToWork(String body, AiBookWork? work) {
  if (work == null) return body;
  final sections = AiChatRetrieve.splitSections(body);
  var kept = sections
      .where((section) => work.contains(section.originSectionIndex))
      .toList(growable: false);
  var bySpine = true;
  if (kept.isEmpty) {
    bySpine = false;
    final wanted = work.title.trim();
    kept = sections
        .where((section) => section.label.trim() == wanted)
        .toList(growable: false);
  }
  AiLog.d(
    'scopeAiChatBodyToWork: work=${work.title} '
    'by=${bySpine ? 'spine' : 'label'} '
    'sections=${sections.length} kept=${kept.length}',
  );
  // Location/index disagreement must degrade to a usable whole-publication
  // corpus, not disable every tool. The caller already prefers a resolved
  // work and only reaches this branch when that narrower range cannot be
  // represented by the reader output.
  if (kept.isEmpty) return body;
  if (kept.length == sections.length) return body;
  final buffer = StringBuffer();
  for (final section in kept) {
    final nav = section.isNavigationUnit ? '~' : '';
    final children = section.navigationChildCount > 0
        ? '+${section.navigationChildCount}'
        : '';
    final level = section.level > 1 ? '#${section.level}' : '';
    buffer.writeln(
      '[§${section.index}@${section.sourceSectionIndex ?? section.index}'
      '$nav$children$level ${section.label}]',
    );
    buffer.writeln(section.text.trim());
    buffer.writeln();
  }
  return buffer.toString().trim();
}

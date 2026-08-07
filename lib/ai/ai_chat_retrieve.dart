/// Lightweight retrieval / packing over multi-section book plain text.
library;

/// One spine slice extracted from [window.getBookPlainText] output.
class AiBookSectionSlice {
  const AiBookSectionSlice({
    required this.index,
    required this.label,
    required this.text,
    this.sourceSectionIndex,
    this.isNavigationUnit = false,
    this.level = 1,
  });

  final int index;
  final String label;
  final String text;

  /// The 1-based EPUB spine section that contains this logical AI unit.
  final int? sourceSectionIndex;

  /// True when the reader formed this slice from a navigation target range.
  final bool isNavigationUnit;

  /// Heading depth inside the spine document: 1 = book/volume, 2 = piece.
  /// Container nodes (level 1 with empty [text]) group their level-2 pieces
  /// into the work → book → piece tree the range chooser renders; generation
  /// extracts the leaves only.
  final int level;

  int get originSectionIndex => sourceSectionIndex ?? index;
}

/// How to pack book body into the prompt for this turn.
enum AiChatPackMode {
  /// Even sample across all sections — for「这本书在讲什么」/ 全书人物等.
  wholeBook,

  /// Keyword score + selection boost — for local / "why now" questions.
  focused,
}

/// Packs prompt body: related or whole-book sample sections.
class AiChatPackedBody {
  const AiChatPackedBody({
    required this.relatedSections,
    required this.mode,
    this.note = '',
    this.sectionOutline = const [],
  });

  final List<AiBookSectionSlice> relatedSections;
  final AiChatPackMode mode;
  final String note;

  /// All section labels (for "五讲" structure even when samples are short).
  final List<String> sectionOutline;

  String formatRelatedForPrompt({int maxChars = 28000}) {
    if (relatedSections.isEmpty) return '';
    final buf = StringBuffer();
    var used = 0;
    for (final s in relatedSections) {
      final header = '[§${s.index} ${s.label}]\n';
      final body = s.text.trim();
      if (body.isEmpty) continue;
      final piece = '$header$body\n\n';
      if (used + piece.length > maxChars) {
        final room = maxChars - used;
        if (room > 80) {
          buf.write(piece.substring(0, room));
          buf.write('…');
        }
        break;
      }
      buf.write(piece);
      used += piece.length;
    }
    return buf.toString().trimRight();
  }
}

abstract final class AiChatRetrieve {
  /// Whole-book overview / cast list (not "this lecture only").
  static bool isWholeBookQuery(String userText) {
    final t = userText.trim();
    if (t.isEmpty) return false;
    // Explicit whole-book asks.
    if (t.contains('这本书在讲什么')) return true;
    if (t.contains('整本书') || t.contains('全书')) return true;
    if (t.contains('概括主线') || t.contains('主线与主题')) return true;
    if (t.contains('根据这本书的正文，概括')) return true;
    // Cast / relations for the book (shortcut wording).
    if (t.contains('梳理主要人物') || t.contains('主要人物以及他们之间的关系')) {
      return true;
    }
    if (t.contains('人物关系') &&
        !t.contains('这一章') &&
        !t.contains('本讲') &&
        !t.contains('当前')) {
      return true;
    }
    return false;
  }

  /// Split `getBookPlainText` output (`[§n label]\\n...`) into slices.
  static List<AiBookSectionSlice> splitSections(String bookBody) {
    final text = bookBody.trim();
    if (text.isEmpty) return const [];

    final re =
        RegExp(r'\[§(\d+)(?:@(\d+)(~)?(?:#(\d+))?)?\s*([^\]]*)\]\s*');
    final matches = re.allMatches(text).toList();
    if (matches.isEmpty) {
      return [AiBookSectionSlice(index: 1, label: 'body', text: text)];
    }

    final out = <AiBookSectionSlice>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final start = m.end;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final slice = text.substring(start, end).trim();
      final label = (m.group(5) ?? '').trim();
      // Containers (book/volume level, no body) carry only a marker: keep
      // them so the range chooser can rebuild the work → book → piece tree.
      if (slice.isEmpty && label.isEmpty) continue;
      final sourceSectionIndex = int.tryParse(m.group(2) ?? '');
      out.add(
        AiBookSectionSlice(
          index: int.tryParse(m.group(1) ?? '') ?? (i + 1),
          sourceSectionIndex:
              sourceSectionIndex != null && sourceSectionIndex >= 1
              ? sourceSectionIndex
              : null,
          isNavigationUnit: m.group(3) != null,
          level: int.tryParse(m.group(4) ?? '') ?? 1,
          label: label,
          text: slice,
        ),
      );
    }
    return out;
  }

  static List<String> outlineOf(List<AiBookSectionSlice> sections) {
    return [
      for (final s in sections)
        '§${s.index}${s.label.isEmpty ? '' : ' ${s.label}'}',
    ];
  }

  /// Score and pick sections relevant to [userText] + [selection],
  /// or **evenly sample every section** for whole-book questions.
  static AiChatPackedBody pack({
    required String userText,
    required String selection,
    required String bookBody,
    int maxSections = 8,
    int maxRelatedChars = 28000,
  }) {
    final sections = splitSections(bookBody);
    if (sections.isEmpty) {
      return const AiChatPackedBody(
        relatedSections: [],
        mode: AiChatPackMode.focused,
        note: 'no book body',
      );
    }

    final outline = outlineOf(sections);

    if (isWholeBookQuery(userText) && selection.trim().isEmpty) {
      return AiChatPackedBody(
        relatedSections: _sampleEvenly(sections, maxRelatedChars),
        mode: AiChatPackMode.wholeBook,
        note: 'whole-book even sample across ${sections.length} sections',
        sectionOutline: outline,
      );
    }

    final query = '$userText $selection'.trim();
    if (query.isEmpty) {
      return AiChatPackedBody(
        relatedSections: _takeChars(sections, maxRelatedChars),
        mode: AiChatPackMode.focused,
        note: 'overview prefix (no query terms)',
        sectionOutline: outline,
      );
    }

    final tokens = _tokens(query);
    if (tokens.isEmpty) {
      return AiChatPackedBody(
        relatedSections: _takeChars(sections, maxRelatedChars),
        mode: AiChatPackMode.focused,
        note: 'overview prefix (weak query tokens)',
        sectionOutline: outline,
      );
    }

    final scored = <({AiBookSectionSlice section, double score})>[];
    for (final s in sections) {
      var score = _score(s.text, tokens);
      final sel = selection.trim();
      if (sel.length >= 4 && s.text.contains(sel)) {
        score += 50;
      } else if (sel.length >= 2) {
        final head = sel.length > 12 ? sel.substring(0, 12) : sel;
        if (s.text.contains(head)) score += 20;
      }
      if (score >= 3) {
        scored.add((section: s, score: score));
      }
    }

    if (scored.isEmpty) {
      // Whole-book-ish fallback if user asked overview with odd phrasing.
      if (isWholeBookQuery(userText)) {
        return AiChatPackedBody(
          relatedSections: _sampleEvenly(sections, maxRelatedChars),
          mode: AiChatPackMode.wholeBook,
          note: 'whole-book sample (no keyword hits)',
          sectionOutline: outline,
        );
      }
      return AiChatPackedBody(
        relatedSections: _takeChars(sections, maxRelatedChars),
        mode: AiChatPackMode.focused,
        note: 'no keyword hits; fell back to beginning of book',
        sectionOutline: outline,
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.section.index.compareTo(b.section.index);
    });

    final picked = <AiBookSectionSlice>[];
    var used = 0;
    for (final row in scored) {
      if (picked.length >= maxSections) break;
      final t = row.section.text;
      if (used + t.length > maxRelatedChars && picked.isNotEmpty) break;
      picked.add(row.section);
      used += t.length;
    }
    picked.sort((a, b) => a.index.compareTo(b.index));

    return AiChatPackedBody(
      relatedSections: picked,
      mode: AiChatPackMode.focused,
      note: 'keyword retrieval top ${picked.length}',
      sectionOutline: outline,
    );
  }

  /// Take a slice from **every** section so 汉/唐/宋/明/清 all appear.
  static List<AiBookSectionSlice> _sampleEvenly(
    List<AiBookSectionSlice> sections,
    int maxChars,
  ) {
    if (sections.isEmpty) return const [];
    final n = sections.length;
    // Each section gets a fair share; clamp so tiny books still get meat.
    final per = (maxChars / n).floor().clamp(500, 6000);
    final out = <AiBookSectionSlice>[];
    var used = 0;
    for (final s in sections) {
      if (used >= maxChars) break;
      final room = (maxChars - used).clamp(0, per);
      if (room < 80) break;
      final body = s.text.trim();
      if (body.isEmpty) continue;
      final text = body.length <= room ? body : '${body.substring(0, room)}…';
      out.add(
        AiBookSectionSlice(
          index: s.index,
          label: s.label,
          text: text,
          sourceSectionIndex: s.sourceSectionIndex,
        ),
      );
      used += text.length;
    }
    return out;
  }

  static List<AiBookSectionSlice> _takeChars(
    List<AiBookSectionSlice> sections,
    int maxChars,
  ) {
    final out = <AiBookSectionSlice>[];
    var used = 0;
    for (final s in sections) {
      if (used >= maxChars) break;
      final room = maxChars - used;
      if (s.text.length <= room) {
        out.add(s);
        used += s.text.length;
      } else {
        out.add(
          AiBookSectionSlice(
            index: s.index,
            label: s.label,
            text: '${s.text.substring(0, room)}…',
            sourceSectionIndex: s.sourceSectionIndex,
          ),
        );
        break;
      }
    }
    return out;
  }

  static Set<String> _tokens(String raw) {
    final text = raw.trim();
    final out = <String>{};
    for (final m in RegExp(r'[A-Za-z]{2,}').allMatches(text)) {
      out.add(m.group(0)!.toLowerCase());
    }
    final cjk = RegExp(r'[\u4e00-\u9fff]{1,}');
    for (final m in cjk.allMatches(text)) {
      final run = m.group(0)!;
      for (final r in run.runes) {
        out.add(String.fromCharCode(r));
      }
      if (run.length >= 2) {
        for (var i = 0; i < run.length - 1; i++) {
          out.add(run.substring(i, i + 2));
        }
      }
    }
    const stop = {
      '的',
      '了',
      '是',
      '在',
      '我',
      '他',
      '她',
      '它',
      '们',
      '这',
      '那',
      '有',
      '和',
      '与',
      '及',
      '也',
      '就',
      '都',
      '而',
      '并',
      '被',
      '把',
      '让',
      '对',
      '从',
      '到',
      '为',
      '以',
      '会',
      '能',
      '要',
      '不',
      '吗',
      '呢',
      '啊',
      '么',
      '什么',
      '怎么',
      '为什么',
      '如何',
      '一个',
      '没有',
      '还是',
      '或者',
      '因为',
      '所以',
    };
    out.removeWhere(stop.contains);
    return out;
  }

  static double _score(String sectionText, Set<String> tokens) {
    if (tokens.isEmpty || sectionText.isEmpty) return 0;
    var score = 0.0;
    for (final t in tokens) {
      if (t.isEmpty) continue;
      if (sectionText.contains(t)) {
        score += t.length >= 2 ? 3 : 1;
      }
    }
    return score;
  }
}

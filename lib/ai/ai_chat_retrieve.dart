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
    this.navigationChildCount = 0,
    this.level = 1,
  });

  final int index;
  final String label;
  final String text;

  /// The 1-based EPUB spine section that contains this logical AI unit.
  final int? sourceSectionIndex;

  /// True when the reader formed this slice from a navigation target range.
  final bool isNavigationUnit;

  /// Number of direct children on the original navigation entry. This is a
  /// deterministic signal that a title is a container, not a flat chapter.
  final int navigationChildCount;

  /// Heading depth inside the spine document: 1 = book/volume, 2 = piece.
  /// Empty level-1 containers preserve hierarchy for deterministic structure
  /// recognition; generation and the flat range picker use body leaves only.
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

    final re = RegExp(
      r'\[§(\d+)(?:@(\d+)(~)?(?:\+(\d+))?(?:#(\d+))?)?\s*([^\]]*)\]\s*',
    );
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
      final label = (m.group(6) ?? '').trim();
      // Containers (book/volume level, no body) carry only a marker. Keep
      // them as deterministic evidence for file-internal work recognition.
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
          navigationChildCount: int.tryParse(m.group(4) ?? '') ?? 0,
          level: int.tryParse(m.group(5) ?? '') ?? 1,
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
        relatedSections: _sampleEvenly(
          sections,
          maxRelatedChars,
          maxSections: maxSections,
        ),
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
          relatedSections: _sampleEvenly(
            sections,
            maxRelatedChars,
            maxSections: maxSections,
          ),
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

  /// Take slices spanning the whole book; include every section when it fits.
  static List<AiBookSectionSlice> _sampleEvenly(
    List<AiBookSectionSlice> sections,
    int maxChars, {
    required int maxSections,
  }) {
    final readable = sections
        .where((section) => section.text.trim().isNotEmpty)
        .toList();
    if (readable.isEmpty || maxChars < 80 || maxSections < 1) return const [];

    // If every section does not fit, pick positions spanning the entire book
    // instead of consuming the budget from the front. Both endpoints are
    // retained; intermediate samples are evenly distributed.
    final count = maxSections.clamp(1, readable.length);
    final selected = <AiBookSectionSlice>[];
    if (count == readable.length) {
      selected.addAll(readable);
    } else if (count == 1) {
      selected.add(readable.first);
    } else {
      for (var i = 0; i < count; i++) {
        final index = (i * (readable.length - 1) / (count - 1)).round();
        final section = readable[index];
        if (selected.isEmpty || selected.last.index != section.index) {
          selected.add(section);
        }
      }
    }

    final per = (maxChars / selected.length).floor().clamp(80, 6000);
    final out = <AiBookSectionSlice>[];
    var used = 0;
    for (final s in selected) {
      if (used >= maxChars) break;
      final room = (maxChars - used).clamp(0, per);
      if (room < 80) break;
      final body = s.text.trim();
      final text = body.length <= room ? body : _headAndTail(body, room);
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

  static String _headAndTail(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars < 8) return '${text.substring(0, maxChars)}…';
    final head = (maxChars * 0.7).floor();
    final tail = maxChars - head;
    return '${text.substring(0, head)}…${text.substring(text.length - tail)}';
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

  /// Clip [text] to [maxChars], centering on the best match of [query].
  ///
  /// Without this, long chapters always feed the model their **opening**
  /// (substring 0..maxChars), so mid-chapter evidence is invisible to tools.
  static String windowAroundQuery(
    String text, {
    required String query,
    required int maxChars,
  }) {
    final body = text.trim();
    if (body.isEmpty) return '';
    if (body.length <= maxChars) return body;
    if (maxChars < 16) return '${body.substring(0, maxChars)}…';

    final hit = firstHitOffset(body, query);
    if (hit < 0) {
      // No hit: keep head + tail so late-chapter material still appears.
      return _headAndTail(body, maxChars);
    }

    // Prefer more context after the hit (recall/plot usually continues forward).
    final before = (maxChars * 0.35).floor();
    var start = hit - before;
    if (start < 0) start = 0;
    var end = start + maxChars;
    if (end > body.length) {
      end = body.length;
      start = (end - maxChars).clamp(0, body.length);
    }
    // Snap to nearby newlines so we do not start mid-sentence when possible.
    start = _snapStart(body, start);
    end = _snapEnd(body, end, start + 40);
    if (end <= start) {
      start = hit.clamp(0, body.length - 1);
      end = (start + maxChars).clamp(0, body.length);
    }

    final prefix = start > 0 ? '…' : '';
    final suffix = end < body.length ? '…' : '';
    return '$prefix${body.substring(start, end)}$suffix';
  }

  /// Page through a long section: `[charOffset, charOffset + maxChars)`.
  static String windowAtOffset(
    String text, {
    required int charOffset,
    required int maxChars,
  }) {
    final body = text.trim();
    if (body.isEmpty) return '';
    if (body.length <= maxChars) return body;
    final start = charOffset.clamp(0, body.length);
    if (start >= body.length) {
      return '(charOffset $charOffset past end; section length ${body.length})';
    }
    final end = (start + maxChars).clamp(0, body.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < body.length ? '…' : '';
    return '$prefix${body.substring(start, end)}$suffix';
  }

  /// First character offset of a useful query hit, or -1.
  ///
  /// Prefers longer phrases. [minPhraseLength] raises the bar so search does
  /// not treat every section sharing a 2-char digram as a hit.
  static int firstHitOffset(
    String text,
    String query, {
    int minPhraseLength = 2,
  }) {
    final q = query.trim();
    if (q.isEmpty || text.isEmpty) return -1;
    final minLen = minPhraseLength.clamp(2, 12);

    String? bestPhrase;
    var bestAt = -1;
    void consider(String phrase) {
      if (phrase.length < minLen) return;
      final at = text.indexOf(phrase);
      if (at < 0) return;
      if (bestPhrase == null ||
          phrase.length > bestPhrase!.length ||
          (phrase.length == bestPhrase!.length && at < bestAt)) {
        bestPhrase = phrase;
        bestAt = at;
      }
    }

    final compact = q.replaceAll(RegExp(r'\s+'), '');
    // Exact compact query first (strongest).
    if (compact.length >= minLen) consider(compact);
    for (final phrase in _phraseCandidates(q)) {
      consider(phrase);
    }
    // Contiguous runs from the compact query, longest first.
    for (var len = compact.length.clamp(0, 12); len >= minLen; len--) {
      for (var i = 0; i + len <= compact.length; i++) {
        consider(compact.substring(i, i + len));
      }
    }
    if (bestAt >= 0) return bestAt;

    final tokens = _tokens(q).where((t) => t.length >= minLen).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final t in tokens) {
      final at = text.indexOf(t);
      if (at >= 0) return at;
    }
    return -1;
  }

  /// Local keyword search: mid-chapter windows around hits, not chapter heads.
  static String formatSearchHits({
    required String query,
    required List<AiBookSectionSlice> sections,
    int maxChars = 12000,
    int maxHits = 12,
    int windowChars = 1400,
  }) {
    final q = query.trim();
    if (q.isEmpty) return 'Error: empty query.';
    if (sections.isEmpty) return '(no sections)';

    final compact = q.replaceAll(RegExp(r'\s+'), '');

    int? hitOffsetIn(String body) {
      // Prefer the full compact query so「唯一标记句3」does not also hit「唯一标记句1」.
      if (compact.length >= 2) {
        final exact = body.indexOf(compact);
        if (exact >= 0) return exact;
      }
      // Fallback: longest phrase ≥ 3 chars (or 2 for very short queries).
      final minLen = compact.length >= 3 ? 3 : 2;
      final loose = firstHitOffset(body, q, minPhraseLength: minLen);
      return loose >= 0 ? loose : null;
    }

    final hits = <({int sectionIndex, String label, int offset, String snippet})>[];
    // Pass 1 — exact compact matches only.
    for (final section in sections) {
      final body = section.text.trim();
      if (body.isEmpty || compact.length < 2) continue;
      final exact = body.indexOf(compact);
      if (exact < 0) continue;
      hits.add((
        sectionIndex: section.index,
        label: section.label.trim().isEmpty
            ? '§${section.index}'
            : section.label.trim(),
        offset: exact,
        snippet: windowAroundQuery(
          body,
          query: q,
          maxChars: windowChars.clamp(256, 4000),
        ),
      ));
    }
    // Pass 2 — looser phrases only when the exact query hit nothing.
    if (hits.isEmpty) {
      for (final section in sections) {
        final body = section.text.trim();
        if (body.isEmpty) continue;
        final offset = hitOffsetIn(body);
        if (offset == null) continue;
        hits.add((
          sectionIndex: section.index,
          label: section.label.trim().isEmpty
              ? '§${section.index}'
              : section.label.trim(),
          offset: offset,
          snippet: windowAroundQuery(
            body,
            query: q,
            maxChars: windowChars.clamp(256, 4000),
          ),
        ));
        if (hits.length >= maxHits * 3) break;
      }
    }

    if (hits.isEmpty) {
      return 'No keyword hits for "$q". Try get_toc + get_chapter(charOffset), '
          'or sample_book.';
    }

    // Prefer earlier offsets only as a weak signal; keep section order stable.
    hits.sort((a, b) {
      final bySection = a.sectionIndex.compareTo(b.sectionIndex);
      if (bySection != 0) return bySection;
      return a.offset.compareTo(b.offset);
    });

    final buf = StringBuffer()
      ..writeln(
        'Search "$q": ${hits.length.clamp(0, maxHits)} hit window(s). '
        'Each snippet is centered on the match (not the chapter opening). '
        'Use get_chapter(sectionIndex, charOffset) to page further.',
      );
    var used = buf.length;
    var count = 0;
    for (final hit in hits) {
      if (count >= maxHits) break;
      final block =
          '\n[§${hit.sectionIndex} ${hit.label} · charOffset=${hit.offset}]\n'
          '${hit.snippet}\n';
      if (used + block.length > maxChars && count > 0) break;
      if (used + block.length > maxChars) {
        final room = maxChars - used;
        if (room > 100) {
          buf.write(block.substring(0, room));
          buf.write('…');
        }
        break;
      }
      buf.write(block);
      used += block.length;
      count++;
    }
    return buf.toString().trimRight();
  }

  static Iterable<String> _phraseCandidates(String query) sync* {
    final compact = query.replaceAll(RegExp(r'\s+'), '');
    if (compact.length >= 2 && compact.length <= 24) yield compact;
    // Quoted spans
    for (final m in RegExp(r'[「『"“]([^」』"”]{2,24})[」』"”]').allMatches(query)) {
      final g = m.group(1)?.trim();
      if (g != null && g.isNotEmpty) yield g;
    }
    // Space-separated tokens of length >= 2
    for (final part in query.split(RegExp(r'[\s,，、；;]+'))) {
      final t = part.trim();
      if (t.length >= 2 && t.length <= 16) yield t;
    }
  }

  static int _snapStart(String text, int start) {
    if (start <= 0) return 0;
    final window = text.substring(start, (start + 80).clamp(0, text.length));
    final nl = window.indexOf('\n');
    if (nl >= 0 && nl < 40) return start + nl + 1;
    return start;
  }

  static int _snapEnd(String text, int end, int minEnd) {
    if (end >= text.length) return text.length;
    final from = end.clamp(0, text.length);
    final back = text.substring((from - 60).clamp(0, text.length), from);
    final nl = back.lastIndexOf('\n');
    if (nl >= 0) {
      final candidate = from - (back.length - nl);
      if (candidate >= minEnd) return candidate;
    }
    return end;
  }
}

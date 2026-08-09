/// Validated, internally consistent counters for one local calendar day.
class ReadingDayCounters {
  const ReadingDayCounters({
    required this.activeSeconds,
    required this.comicSeconds,
    required this.bookSeconds,
    required this.sessionsCount,
  });

  factory ReadingDayCounters.normalized({
    required int activeSeconds,
    required int comicSeconds,
    required int bookSeconds,
    required int sessionsCount,
  }) {
    var comic = _boundedNonNegative(comicSeconds);
    var book = _boundedNonNegative(bookSeconds);
    var active = _boundedNonNegative(activeSeconds);
    // Bound the categorized sum as a unit as well; a hostile snapshot could
    // set both categories to the individual maximum.
    if (comic + book > _maxReadingCounter) {
      book = _maxReadingCounter - comic;
    }
    final categorized = comic + book;
    if (active < categorized) active = categorized;
    // Legacy/corrupt rows can have active time without a kind breakdown.
    // Preserve the total and put only the unknown residual in book, the
    // conservative reflow bucket, so active == comic + book remains true.
    book += active - categorized;
    return ReadingDayCounters(
      activeSeconds: active,
      comicSeconds: comic,
      bookSeconds: book,
      sessionsCount: _boundedNonNegative(sessionsCount),
    );
  }

  final int activeSeconds;
  final int comicSeconds;
  final int bookSeconds;
  final int sessionsCount;

  /// Snapshot restore is not additive sync. Select one coherent row instead
  /// of mixing independent fields and breaking the counter invariant.
  static ReadingDayCounters chooseLarger(
    ReadingDayCounters local,
    ReadingDayCounters remote,
  ) {
    if (remote.activeSeconds != local.activeSeconds) {
      return remote.activeSeconds > local.activeSeconds ? remote : local;
    }
    return remote.sessionsCount > local.sessionsCount ? remote : local;
  }
}

bool isValidReadingDayKey(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}

bool isValidReadingCounter(int value) =>
    value > 0 && value <= 0x3FFFFFFFFFFFFFFF;

int _boundedNonNegative(int value) {
  if (value <= 0) return 0;
  // SQLite INTEGER is signed 64-bit. Keep enough headroom for future adds.
  return value > _maxReadingCounter ? _maxReadingCounter : value;
}

const _maxReadingCounter = 0x3FFFFFFFFFFFFFFF;

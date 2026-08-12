// Cached / session outline models. Production generation is the book-chat
// shortcut ("生成本书大纲"), not a structured batch service.
// Historical batch service: lib/ai/legacy/ai_book_outline_service.dart

/// One structural unit in the book's outline: a section of the book the AI
/// identified as a coherent block (an essay in a collection, a part in a
/// novel, a topic cluster in nonfiction).
class AiOutlineUnit {
  const AiOutlineUnit({required this.title, required this.blurb});

  final String title;
  final String blurb;

  Map<String, Object?> toJson() => {'title': title, 'blurb': blurb};

  static AiOutlineUnit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final blurb = raw['blurb'];
    if (title is! String || title.trim().isEmpty) return null;
    if (blurb is! String || blurb.trim().isEmpty) return null;
    return AiOutlineUnit(title: title.trim(), blurb: blurb.trim());
  }
}

/// Structural outline for one exact book file ([contentHash]).
///
/// ## 版本规则
///
/// [currentVersion] 单调递增，永不复用。[fromJson] 只接受严格等于
/// currentVersion 的 JSON——其他版本返回 null。
class AiBookOutline {
  const AiBookOutline({
    required this.createdAt,
    required this.model,
    required this.overview,
    required this.units,
    this.excludedSectionIndices = const [],
  });

  static const currentVersion = 14;

  final DateTime createdAt;
  final String model;
  final String overview;
  final List<AiOutlineUnit> units;
  final List<int> excludedSectionIndices;

  AiBookOutline copyWith({List<int>? excludedSectionIndices}) {
    return AiBookOutline(
      createdAt: createdAt,
      model: model,
      overview: overview,
      units: units,
      excludedSectionIndices:
          excludedSectionIndices ?? this.excludedSectionIndices,
    );
  }

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'model': model,
    'overview': overview,
    'units': [for (final unit in units) unit.toJson()],
    if (excludedSectionIndices.isNotEmpty)
      'excludedSectionIndices': excludedSectionIndices,
  };

  static AiBookOutline? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['version'] != currentVersion) return null;
    final createdAt = DateTime.tryParse('${raw['createdAt'] ?? ''}');
    final model = raw['model'];
    final overview = raw['overview'];
    final unitsRaw = raw['units'];
    if (createdAt == null ||
        model is! String ||
        overview is! String ||
        overview.trim().isEmpty ||
        unitsRaw is! List) {
      return null;
    }
    final units = [for (final row in unitsRaw) ?AiOutlineUnit.fromJson(row)];
    if (units.isEmpty) return null;
    return AiBookOutline(
      createdAt: createdAt,
      model: model,
      overview: overview.trim(),
      units: units,
      excludedSectionIndices:
          (raw['excludedSectionIndices'] as List?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false) ??
          const [],
    );
  }
}

/// Visible status for an outline generation job (legacy UI / tests).
class AiOutlineProgress {
  const AiOutlineProgress({
    required this.completed,
    required this.total,
    required this.label,
    this.finalizing = false,
  });

  final int completed;
  final int total;
  final String label;
  final bool finalizing;
}

/// Sampling budget shared by whole-book chat tools and graph scope.
abstract final class AiBookBodyLimits {
  static const maxBookBodyChars = 1500000;
}

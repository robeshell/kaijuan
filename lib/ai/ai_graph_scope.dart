import 'ai_book_structure.dart';
import 'ai_chat_retrieve.dart';

/// Why one readable unit is or is not selected by default for graph
/// generation. This is advisory metadata: the user remains the final owner
/// of every non-empty unit in the generation scope.
enum AiGraphSectionRole { body, suggestedSupplement, unavailable }

class AiGraphSectionChoice {
  const AiGraphSectionChoice({
    required this.section,
    required this.role,
    this.reason,
  });

  final AiBookSectionSlice section;
  final AiGraphSectionRole role;
  final String? reason;

  /// Logical section indices are emitted globally by the reader and are also
  /// used by spine-mode graph coverage. They remain stable across reloads.
  int get id => section.index;

  bool get canSelect => role != AiGraphSectionRole.unavailable;
  bool get selectedByDefault => role == AiGraphSectionRole.body;
}

class AiGraphScopePlan {
  const AiGraphScopePlan({required this.choices, this.work});

  final AiBookWork? work;
  final List<AiGraphSectionChoice> choices;

  List<AiGraphSectionChoice> get selectable =>
      choices.where((choice) => choice.canSelect).toList(growable: false);

  Set<int> get recommendedExcluded => {
    for (final choice in choices)
      if (!choice.selectedByDefault) choice.id,
  };
}

/// Pure scope planning after publication-structure recognition.
///
/// It never removes a section. Rules may recommend that paratext stays out of
/// a graph, while the chooser can still show and re-enable it. Empty units are
/// retained for transparency but cannot be sent to the model.
abstract final class AiGraphScopePlanner {
  static AiGraphScopePlan build({
    required List<AiBookSectionSlice> sections,
    required bool Function(String title) isSuggestedSupplement,
    AiBookWork? work,
  }) {
    final scoped = work == null
        ? sections
        : sections
              .where((section) => work.contains(section.originSectionIndex))
              .toList(growable: false);
    return AiGraphScopePlan(
      work: work,
      choices: [
        for (final section in scoped)
          if (section.text.trim().isEmpty)
            AiGraphSectionChoice(
              section: section,
              role: AiGraphSectionRole.unavailable,
              reason: '没有可读取的正文',
            )
          else if (isSuggestedSupplement(section.label))
            AiGraphSectionChoice(
              section: section,
              role: AiGraphSectionRole.suggestedSupplement,
              reason: '可能是前言、目录或附录，建议排除',
            )
          else
            AiGraphSectionChoice(
              section: section,
              role: AiGraphSectionRole.body,
            ),
      ],
    );
  }
}

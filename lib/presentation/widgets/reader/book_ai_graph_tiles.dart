import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../ai_typography.dart';

String graphEntityTypeLabel(AiGraphEntityType type) => switch (type) {
  AiGraphEntityType.person => '人物',
  AiGraphEntityType.location => '地点',
  AiGraphEntityType.event => '事件',
  AiGraphEntityType.organization => '组织',
  AiGraphEntityType.item => '物件',
  AiGraphEntityType.concept => '概念',
  AiGraphEntityType.creature => '非人角色',
};

/// Entity-type accent color (dot + highlight tint in list rows).
Color graphEntityTypeColor(BuildContext context, AiGraphEntityType type) {
  final colors = context.appColors;
  return switch (type) {
    AiGraphEntityType.person => colors.primary,
    AiGraphEntityType.location => Colors.teal,
    AiGraphEntityType.event => Colors.amber.shade700,
    AiGraphEntityType.organization => const Color(0xffec4899),
    AiGraphEntityType.item => const Color(0xff8b5cf6),
    AiGraphEntityType.concept => const Color(0xff6366f1),
    AiGraphEntityType.creature => const Color(0xfff97316),
  };
}

/// Event-type accent color (8 event categories).
Color graphEventTypeColor(AiGraphEventType type) => switch (type) {
  AiGraphEventType.combat => const Color(0xffef4444),
  AiGraphEventType.growth => const Color(0xff3b82f6),
  AiGraphEventType.social => const Color(0xff10b981),
  AiGraphEventType.travel => const Color(0xfff97316),
  AiGraphEventType.appearance => const Color(0xff8b5cf6),
  AiGraphEventType.object => const Color(0xffeab308),
  AiGraphEventType.organization => const Color(0xffec4899),
  AiGraphEventType.relationship => const Color(0xff06b6d4),
  AiGraphEventType.other => Colors.blueGrey,
};

/// Shared flat-row shell in the outline-unit language: no card, no border —
/// a transparent [Material] whose only states are an [appTint] hover and an
/// [appTint] highlight (the 2s jump-target flash). The outline tab's unit
/// rows, these tiles and the isolated fold row all read as one list idiom.
class _FlatGraphRow extends StatelessWidget {
  const _FlatGraphRow({
    required this.highlighted,
    required this.onTap,
    required this.child,
  });

  final bool highlighted;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? context.appTint(0.06) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: context.appTint(0.035),
        focusColor: context.appTint(0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: child,
        ),
      ),
    );
  }
}

/// Leading type-color dot, optically aligned with the first title line.
class _TypeDot extends StatelessWidget {
  const _TypeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// One entity row in the persons/locations list (resting plain, highlight on
/// jump-target). Pure presentation — computed values arrive as parameters.
class GraphEntityTile extends StatelessWidget {
  const GraphEntityTile({
    super.key,
    required this.entity,
    required this.metadata,
    required this.typeColor,
    required this.highlighted,
    required this.bodySize,
    required this.onTap,
  });

  final AiGraphEntity entity;
  final String metadata;
  final Color typeColor;
  final bool highlighted;
  final double bodySize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _FlatGraphRow(
        highlighted: highlighted,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TypeDot(color: typeColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: context.appPrimaryText,
                    ),
                  ),
                  if (entity.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entity.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.aiDetailSize,
                        height: 1.55,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    metadata,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      color: context.appSecondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One event row in the events list (importance badge for major events).
class GraphEventTile extends StatelessWidget {
  const GraphEventTile({
    super.key,
    required this.entity,
    required this.bodySize,
    required this.trailingLabel,
    required this.onTap,
    this.highlighted = false,
  });

  final AiGraphEntity entity;
  final double bodySize;
  final String trailingLabel;
  final VoidCallback onTap;

  /// Jump-target flash, same contract as [GraphEntityTile.highlighted] —
  /// force-graph vertices include events, so tapping one highlights its row
  /// here too (previously the events view had no highlight channel).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final typeColor = graphEventTypeColor(entity.eventType);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _FlatGraphRow(
        highlighted: highlighted,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TypeDot(color: typeColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entity.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: bodySize,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: context.appPrimaryText,
                          ),
                        ),
                      ),
                      if (entity.importance >= 3) ...[
                        const SizedBox(width: 6),
                        GraphImportanceBadge(importance: entity.importance),
                      ],
                    ],
                  ),
                  if (entity.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entity.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.aiDetailSize,
                        height: 1.55,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    entity.eventType.label,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      // The category is already redundantly encoded by the
                      // leading dot. Keep small text on a semantic foreground
                      // instead of using accent hues that fail 4.5:1.
                      color: context.appSecondaryText,
                    ),
                  ),
                ],
              ),
            ),
            // Trailing occurrence anchor, optically aligned with the title's
            // first line: events are chapter-scoped, and the right edge was
            // left empty by the flat-row restyle (「第 N 节」matches the
            // evidence-row wording).
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                trailingLabel,
                style: TextStyle(
                  fontSize: context.appCaptionSmallSize,
                  color: context.appMutedText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small「重要/一般」badge next to major events. 重要 uses the primary accent —
/// never error red, which reads as a problem rather than "major".
class GraphImportanceBadge extends StatelessWidget {
  const GraphImportanceBadge({super.key, required this.importance});

  final int importance;

  @override
  Widget build(BuildContext context) {
    final (label, textColor, bgColor) = switch (importance) {
      3 => (
        '重要',
        context.appColors.primary,
        context.appColors.primary.withValues(alpha: 0.1),
      ),
      _ => ('一般', context.appSecondaryText, context.appTint(0.06)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: context.appCaptionSmallSize,
          color: textColor,
        ),
      ),
    );
  }
}

/// Foldable「其余 N 个实体」row. The expanded rows are built by the caller
/// (they carry jump-target GlobalKeys), this widget only owns the header +
/// toggle affordance.
class GraphIsolatedRow extends StatelessWidget {
  const GraphIsolatedRow({
    super.key,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.expandedChildren,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> expandedChildren;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            expanded: expanded,
            label: '其余 $count 个实体',
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(10),
              hoverColor: context.appTint(0.035),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '其余 $count 个实体',
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: context.appSecondaryText,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        expanded
                            ? KaijuanIcons.chevronDown
                            : KaijuanIcons.chevronRight,
                        size: 18,
                        color: context.appSecondaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (expanded) ...expandedChildren,
      ],
    );
  }
}

/// 「地点首次出现顺序」chips: locations in narrative order (first
/// appearance, then in-chapter progress), capped at 20 with an overflow
/// hint. Tapping a pill opens the entity card via [onPillTap].
class GraphLocationChain extends StatelessWidget {
  const GraphLocationChain({
    super.key,
    required this.locations,
    required this.gateByProgress,
    required this.readThrough,
    required this.onPillTap,
  });

  /// Locations already filtered to setting scope.
  final List<AiGraphEntity> locations;
  final bool gateByProgress;
  final int readThrough;
  final ValueChanged<String> onPillTap;

  static const int _cap = 20;

  /// In-chapter appearance progress: the resolved progress of the first
  /// located evidence (0 when nothing resolved — sorts before located ones).
  static double _chainProgress(AiGraphEntity entity) {
    for (final evidence in entity.evidence) {
      final progress = evidence.progressInSection;
      if (progress != null) return progress;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        [
          for (final e in locations)
            if (!gateByProgress || e.firstSection <= readThrough) e,
        ]..sort((a, b) {
          final bySection = a.firstSection.compareTo(b.firstSection);
          if (bySection != 0) return bySection;
          return _chainProgress(a).compareTo(_chainProgress(b));
        });
    if (visible.isEmpty) return const SizedBox.shrink();
    final shown = visible.take(_cap).toList(growable: false);
    final total = visible.length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '地点首次出现顺序（非地理路线）',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0)
                  Text('·', style: TextStyle(color: context.appMutedText)),
                _LocationChainPill(
                  name: shown[i].name,
                  mentionCount: shown[i].chapterFreq.keys.length,
                  onTap: () => onPillTap(shown[i].id),
                ),
              ],
            ],
          ),
          if (total > _cap)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '等 ${total - _cap} 处…',
                style: TextStyle(
                  fontSize: context.appCaptionSmallSize,
                  color: context.appSecondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationChainPill extends StatelessWidget {
  const _LocationChainPill({
    required this.name,
    required this.mentionCount,
    required this.onTap,
  });

  final String name;
  final int mentionCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.surfaceContainerHighest.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  fontWeight: FontWeight.w500,
                  color: context.appPrimaryText,
                ),
              ),
              if (mentionCount > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '×$mentionCount',
                  style: TextStyle(
                    fontSize: context.appCaptionSmallSize,
                    color: context.appMutedText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

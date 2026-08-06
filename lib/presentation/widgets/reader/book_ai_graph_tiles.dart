import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';

/// Entity-type accent color (dot + highlight tint in list rows).
Color graphEntityTypeColor(BuildContext context, AiGraphEntityType type) {
  final colors = context.appColors;
  return switch (type) {
    AiGraphEntityType.person => colors.primary,
    AiGraphEntityType.location => Colors.teal,
    AiGraphEntityType.event => Colors.amber.shade700,
    AiGraphEntityType.organization => const Color(0xffec4899),
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

/// One entity row in the persons/locations list (resting plain, highlight on
/// jump-target). Pure presentation — computed values arrive as parameters.
class GraphEntityTile extends StatelessWidget {
  const GraphEntityTile({
    super.key,
    required this.entity,
    required this.relationCount,
    required this.typeColor,
    required this.highlighted,
    required this.bodySize,
    required this.onTap,
  });

  final AiGraphEntity entity;
  final int relationCount;
  final Color typeColor;
  final bool highlighted;
  final double bodySize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occurrences = entity.chapterFreq.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: highlighted ? typeColor.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Structure only on the highlighted state; resting rows are plain
        // like the rest of the workspace lists.
        side: BorderSide(
          color: highlighted
              ? typeColor.withValues(alpha: 0.6)
              : Colors.transparent,
          width: highlighted ? 1.4 : 0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: typeColor,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          entity.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: bodySize,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: entity.description.isEmpty
            ? null
            : Text(
                entity.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
        trailing: Text(
          '$occurrences 章 · $relationCount 关系',
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
        onTap: onTap,
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
    required this.onTap,
  });

  final AiGraphEntity entity;
  final double bodySize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeColor = graphEventTypeColor(entity.eventType);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: typeColor.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 2, 8, 2),
        leading: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: typeColor,
            shape: BoxShape.circle,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entity.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: bodySize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (entity.importance >= 3) ...[
              const SizedBox(width: 6),
              GraphImportanceBadge(importance: entity.importance),
            ],
          ],
        ),
        subtitle: entity.description.isEmpty
            ? null
            : Text(
                entity.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  height: 1.35,
                  color: context.appSecondaryText,
                ),
              ),
        trailing: Text(
          entity.eventType.label,
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: typeColor,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Small「重要/一般」badge next to major events.
class GraphImportanceBadge extends StatelessWidget {
  const GraphImportanceBadge({super.key, required this.importance});

  final int importance;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (importance) {
      3 => ('重要', context.appColors.error),
      _ => ('一般', context.appColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: context.appCaptionSize - 2,
          color: color,
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
        ListTile(
          contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
          minVerticalPadding: 0,
          title: Text(
            '其余 $count 个实体',
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: context.appSecondaryText,
            ),
          ),
          trailing: Icon(
            expanded ? KaijuanIcons.chevronDown : KaijuanIcons.chevronRight,
            size: 18,
            color: context.appSecondaryText,
          ),
          onTap: onToggle,
        ),
        if (expanded) ...expandedChildren,
      ],
    );
  }
}

/// 「地点链 · 按书中出现顺序」chips: locations in narrative order (first
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
    final visible = [
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
        color: context.appColors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '地点链 · 按书中出现顺序',
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
                  Text(
                    '→',
                    style: TextStyle(
                      fontSize: context.appCaptionSize - 1,
                      color: context.appSecondaryText,
                    ),
                  ),
                _LocationChainPill(
                  name: shown[i].name,
                  mentionCount: shown[i].chapterFreq.values
                      .fold<int>(0, (sum, v) => sum + v),
                  onTap: () => onPillTap(shown[i].name),
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
                  fontSize: context.appCaptionSize - 1,
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.8),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              if (mentionCount > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '×$mentionCount',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
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

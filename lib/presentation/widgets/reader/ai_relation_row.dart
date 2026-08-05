import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';

/// One typed relation rendered as a structured row:
///
///   [source chip]  →  [type pill]  →  [target chip]    N 条证据
///
/// The entity being viewed ([selfName]) is highlighted on its side so the
/// reader sees the relation from the current character's point of view.
class AiRelationRow extends StatelessWidget {
  const AiRelationRow({
    super.key,
    required this.relation,
    required this.selfName,
  });

  final AiGraphRelation relation;

  /// Canonical name of the entity the card is about; highlighted in the row.
  final String selfName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sourceIsSelf = relation.source == selfName;
    final targetIsSelf = relation.target == selfName;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(child: _EntityChip(name: relation.source, highlighted: sourceIsSelf)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              KaijuanIcons.forward,
              size: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
          _TypePill(type: relation.type),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              KaijuanIcons.forward,
              size: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
          Expanded(child: _EntityChip(name: relation.target, highlighted: targetIsSelf)),
          const SizedBox(width: 8),
          Text(
            '${relation.evidence.length} 证据',
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntityChip extends StatelessWidget {
  const _EntityChip({required this.name, required this.highlighted});

  final String name;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primary.withValues(alpha: 0.1)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: highlighted
            ? Border.all(color: colors.primary.withValues(alpha: 0.45))
            : null,
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: highlighted ? colors.primary : colors.onSurface,
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: colors.primary,
        ),
      ),
    );
  }
}

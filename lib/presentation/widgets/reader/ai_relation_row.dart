import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../ai_typography.dart';

/// One typed relation rendered as a structured row:
///
///   [source chip]  →  [type pill]  →  [target chip]    N 条证据
///
/// The entity being viewed ([selfId]) is highlighted on its side so the
/// reader sees the relation from the current character's point of view.
class AiRelationRow extends StatelessWidget {
  const AiRelationRow({
    super.key,
    required this.relation,
    required this.selfId,
    this.onEntityTap,
    this.onEvidenceTap,
  });

  final AiGraphRelation relation;

  final String selfId;
  final ValueChanged<String>? onEntityTap;
  final ValueChanged<AiGraphEvidence>? onEvidenceTap;

  static const _symmetricTypes = {'同盟', '敌对', '婚配', '同事', '朋友', '同学', '相识'};

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sourceIsSelf = relation.sourceId == selfId;
    final targetIsSelf = relation.targetId == selfId;
    final symmetric = _symmetricTypes.contains(relation.type);

    return ExpansionTile(
      tilePadding: const EdgeInsetsDirectional.fromSTEB(10, 4, 8, 4),
      childrenPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      backgroundColor: colors.surfaceContainerLow,
      collapsedBackgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      title: Row(
        children: [
          Expanded(
            child: _EntityChip(
              name: relation.source,
              highlighted: sourceIsSelf,
              onTap: relation.sourceId.isEmpty || sourceIsSelf
                  ? null
                  : () => onEntityTap?.call(relation.sourceId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              symmetric ? Icons.compare_arrows_rounded : KaijuanIcons.forward,
              size: 12,
              color: context.appMutedText,
            ),
          ),
          _TypePill(type: relation.type),
          const SizedBox(width: 4),
          Expanded(
            child: _EntityChip(
              name: relation.target,
              highlighted: targetIsSelf,
              onTap: relation.targetId.isEmpty || targetIsSelf
                  ? null
                  : () => onEntityTap?.call(relation.targetId),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${relation.evidence.length} 条出处${relation.description.isEmpty ? '' : ' · ${relation.description}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appMutedText,
          ),
        ),
      ),
      children: [
        for (final evidence in relation.evidence)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              evidence.quote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: context.appCaptionSize, height: 1.4),
            ),
            subtitle: Text(
              '第 ${evidence.sectionIndex} 节',
              style: TextStyle(fontSize: context.aiCaptionSize),
            ),
            trailing: const Icon(KaijuanIcons.forward, size: 14),
            onTap: onEvidenceTap == null
                ? null
                : () => onEvidenceTap!(evidence),
          ),
      ],
    );
  }
}

class _EntityChip extends StatelessWidget {
  const _EntityChip({
    required this.name,
    required this.highlighted,
    this.onTap,
  });

  final String name;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final content = Container(
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
          fontSize: context.aiLabelSize,
          fontWeight: FontWeight.w600,
          color: highlighted ? colors.primary : context.appPrimaryText,
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: '打开$name详情',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: content,
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
          fontSize: context.appCaptionSize,
          color: colors.primary,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../ai_typography.dart';
import '../app_components.dart';
import '../app_overlays.dart';
import 'ai_relation_row.dart';

/// Entity detail bottom sheet (tapped from any graph list row / family-tree
/// node): name, aliases, description, relations and evidence quotes; tapping
/// an evidence row jumps to the original passage via [onOpenEvidence].
///
/// Pure presentation — everything it needs arrives as parameters so it never
/// touches the controller or the owning sheet's private helpers.
class BookAiEntitySheet extends StatelessWidget {
  const BookAiEntitySheet({
    super.key,
    required this.entity,
    required this.graph,
    required this.gateByProgress,
    required this.readThrough,
    required this.titleSize,
    required this.bodySize,
    required this.onOpenEvidence,
    this.onHideEntity,
    this.onMergeInto,
  });

  final AiGraphEntity entity;
  final AiBookGraph graph;
  final bool gateByProgress;
  final int readThrough;
  final double titleSize;
  final double bodySize;

  /// Jump to the original passage for an evidence quote.
  final ValueChanged<AiGraphEvidence> onOpenEvidence;
  final VoidCallback? onHideEntity;

  /// Merge this entity into [keepId]; the current card is the absorbed side.
  final ValueChanged<String>? onMergeInto;

  List<AiGraphEntity> get _mergeCandidates {
    final others = [
      for (final candidate in graph.entities)
        if (candidate.id != entity.id && candidate.type == entity.type)
          candidate,
    ];
    others.sort((a, b) => a.name.compareTo(b.name));
    return others;
  }

  Future<void> _mergeIntoPickedTarget(BuildContext context) async {
    final keep = await showAppBottomSheet<AiGraphEntity>(
      context,
      useRootNavigator: true,
      anchorPoint: appTrailingBottomOverlayAnchor(context),
      builder: (_) => _MergeTargetPicker(
        absorb: entity,
        candidates: _mergeCandidates,
        bodySize: bodySize,
      ),
    );
    if (keep == null || !context.mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '将「${entity.name}」并入「${keep.name}」？',
      message: '「${entity.name}」会变成「${keep.name}」的别名，关系和出处也会转到「${keep.name}」。',
      confirmLabel: '并入',
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).pop();
    onMergeInto!(keep.id);
  }

  static String _filterLabel(AiGraphEntityType type) => switch (type) {
    AiGraphEntityType.person => '人物',
    AiGraphEntityType.location => '地点',
    AiGraphEntityType.event => '事件',
    AiGraphEntityType.organization => '组织',
    AiGraphEntityType.item => '物件',
    AiGraphEntityType.concept => '概念',
    AiGraphEntityType.creature => '非人角色',
  };

  Widget _countBadge(BuildContext context, int count) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: context.appCaptionSize,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relations = graph.relations
        .where(
          (r) =>
              ((r.sourceId.isNotEmpty &&
                      (r.sourceId == entity.id || r.targetId == entity.id)) ||
                  (r.sourceId.isEmpty &&
                      (r.source == entity.name || r.target == entity.name))) &&
              (!gateByProgress ||
                  r.evidence.any((e) => e.sectionIndex <= readThrough)),
        )
        .toList(growable: false);
    final evidence = entity.evidence
        .where((e) => !gateByProgress || e.sectionIndex <= readThrough)
        .toList(growable: false);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entity.name,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _filterLabel(entity.type),
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
            ],
          ),
          if (entity.aliases.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '别名：${entity.aliases.join('、')}',
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: context.appSecondaryText,
              ),
            ),
          ],
          if (entity.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: context.appColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                entity.description,
                style: TextStyle(fontSize: bodySize, height: 1.5),
              ),
            ),
          ],
          if (relations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '关系',
                  style: TextStyle(
                    fontSize: bodySize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                _countBadge(context, relations.length),
              ],
            ),
            const SizedBox(height: 8),
            for (final relation in relations)
              AiRelationRow(
                relation: relation,
                selfId: entity.id,
                onEntityTap: (entityId) => showBookAiEntitySheetById(
                  context,
                  entityId,
                  graph: graph,
                  gateByProgress: gateByProgress,
                  readThrough: readThrough,
                  onJumpToEvidence: onOpenEvidence,
                ),
                onEvidenceTap: (evidence) {
                  Navigator.of(context).pop();
                  onOpenEvidence(evidence);
                },
              ),
          ],
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '出处',
                  style: TextStyle(
                    fontSize: bodySize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                _countBadge(context, evidence.length),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: context.appColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenEvidence(item);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.appColors.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '第 ${item.sectionIndex} 节',
                              style: TextStyle(
                                fontSize: context.appCaptionSize,
                                fontWeight: FontWeight.w600,
                                color: context.appColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.quote,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: context.appCaptionSize,
                                height: 1.4,
                                color: item.spanResolved
                                    ? context.appPrimaryText
                                    : context.appSecondaryText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(
                              KaijuanIcons.forward,
                              size: 14,
                              color: context.appSecondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if (relations.isEmpty && evidence.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '该实体暂无可见内容。',
                style: TextStyle(
                  fontSize: bodySize,
                  color: context.appSecondaryText,
                ),
              ),
            ),
          if (onMergeInto != null || onHideEntity != null) ...[
            const SizedBox(height: 12),
            if (onMergeInto != null && _mergeCandidates.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  textStyle: TextStyle(fontSize: context.aiLabelSize),
                ),
                onPressed: () => _mergeIntoPickedTarget(context),
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('合并到…'),
              ),
            if (onHideEntity != null)
              TextButton.icon(
                style: TextButton.styleFrom(
                  textStyle: TextStyle(fontSize: context.aiLabelSize),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onHideEntity!();
                },
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('从图谱中隐藏'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Shared entry for the fullscreen explorers (force graph / family tree):
/// look the tapped vertex up by canonical name or alias and open the same
/// entity card the panel uses. The sheet pops itself before the evidence
/// callback fires; the callback's owner closes the hosting route after the
/// jump.
void showBookAiEntitySheetByName(
  BuildContext context,
  String name, {
  required AiBookGraph graph,
  required bool gateByProgress,
  required int readThrough,
  required void Function(AiGraphEvidence evidence)? onJumpToEvidence,
}) {
  final entity = graph.entities
      .where((e) => e.name == name || e.aliases.contains(name))
      .firstOrNull;
  if (entity == null) return;
  showAppBottomSheet<void>(
    context,
    useRootNavigator: true,
    anchorPoint: appTrailingBottomOverlayAnchor(context),
    builder: (_) => BookAiEntitySheet(
      entity: entity,
      graph: graph,
      gateByProgress: gateByProgress,
      readThrough: readThrough,
      titleSize: context.aiTitleSize,
      bodySize: context.aiBodySize,
      onOpenEvidence: (evidence) => onJumpToEvidence?.call(evidence),
    ),
  );
}

void showBookAiHiddenEntitiesSheet(
  BuildContext context, {
  required List<AiGraphEntity> hidden,
  required ValueChanged<String> onUnhide,
}) {
  if (hidden.isEmpty) return;
  showAppBottomSheet<void>(
    context,
    useRootNavigator: true,
    anchorPoint: appTrailingBottomOverlayAnchor(context),
    builder: (sheetContext) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            '已隐藏的实体',
            style: TextStyle(
              fontSize: sheetContext.aiTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '恢复后会重新出现在索引和关系图里。',
            style: TextStyle(
              fontSize: sheetContext.appCaptionSize,
              color: sheetContext.appSecondaryText,
            ),
          ),
          const SizedBox(height: 12),
          for (final entity in hidden)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entity.name),
              subtitle: Text(BookAiEntitySheet._filterLabel(entity.type)),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onUnhide(entity.id);
                },
                child: const Text('恢复显示'),
              ),
            ),
        ],
      ),
    ),
  );
}

void showBookAiEntitySheetById(
  BuildContext context,
  String entityId, {
  required AiBookGraph graph,
  required bool gateByProgress,
  required int readThrough,
  required void Function(AiGraphEvidence evidence)? onJumpToEvidence,
}) {
  final entity = graph.entityById(entityId);
  if (entity == null) return;
  showAppBottomSheet<void>(
    context,
    useRootNavigator: true,
    anchorPoint: appTrailingBottomOverlayAnchor(context),
    builder: (_) => BookAiEntitySheet(
      entity: entity,
      graph: graph,
      gateByProgress: gateByProgress,
      readThrough: readThrough,
      titleSize: context.aiTitleSize,
      bodySize: context.aiBodySize,
      onOpenEvidence: (evidence) => onJumpToEvidence?.call(evidence),
    ),
  );
}

class _MergeTargetPicker extends StatefulWidget {
  const _MergeTargetPicker({
    required this.absorb,
    required this.candidates,
    required this.bodySize,
  });

  final AiGraphEntity absorb;
  final List<AiGraphEntity> candidates;
  final double bodySize;

  @override
  State<_MergeTargetPicker> createState() => _MergeTargetPickerState();
}

class _MergeTargetPickerState extends State<_MergeTargetPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = [
      for (final candidate in widget.candidates)
        if (_query.isEmpty ||
            candidate.name.contains(_query) ||
            candidate.aliases.any((alias) => alias.contains(_query)))
          candidate,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '将「${widget.absorb.name}」合并到',
              style: TextStyle(
                fontSize: context.aiTitleSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.candidates.length > 8)
              TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                style: context.appInputTextStyle,
                decoration: const InputDecoration(
                  hintText: '搜索名称或别名',
                  isDense: true,
                ),
              ),
            if (widget.candidates.length > 8) const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '没有匹配的同类型实体。',
                        style: TextStyle(
                          fontSize: widget.bodySize,
                          color: context.appSecondaryText,
                        ),
                      ),
                    )
                  else
                    for (final candidate in filtered)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(candidate.name),
                        subtitle: candidate.aliases.isEmpty
                            ? null
                            : Text(
                                candidate.aliases.join('、'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => Navigator.of(context).pop(candidate),
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

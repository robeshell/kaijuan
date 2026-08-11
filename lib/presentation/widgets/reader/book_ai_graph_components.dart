import 'package:flutter/material.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../ai/ai_graph.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';

/// Stable graph information architecture. AI may recommend the initial view,
/// but it cannot rearrange or rename these product-owned destinations.
enum BookAiGraphViewMode {
  persons,
  locations,
  events,
  organizations,
  things,
  graph,
  familyTree,
}

String bookAiGraphViewLabel(BookAiGraphViewMode mode) => switch (mode) {
  BookAiGraphViewMode.persons => '人物',
  BookAiGraphViewMode.locations => '地点',
  BookAiGraphViewMode.events => '事件',
  BookAiGraphViewMode.organizations => '组织',
  BookAiGraphViewMode.things => '事物',
  BookAiGraphViewMode.graph => '关系图',
  BookAiGraphViewMode.familyTree => '家族树',
};

class BookAiGraphViewNavigation extends StatelessWidget {
  const BookAiGraphViewNavigation({
    required this.graph,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AiBookGraph graph;
  final BookAiGraphViewMode selected;
  final ValueChanged<BookAiGraphViewMode> onSelected;

  List<BookAiGraphViewMode> get _modes {
    final essayHigh = (graph.narration?.feature('essay') ?? 0) >= 0.5;
    return [
      BookAiGraphViewMode.persons,
      BookAiGraphViewMode.locations,
      BookAiGraphViewMode.events,
      BookAiGraphViewMode.organizations,
      BookAiGraphViewMode.things,
      BookAiGraphViewMode.graph,
      if (!essayHigh) BookAiGraphViewMode.familyTree,
    ];
  }

  int? _countFor(BookAiGraphViewMode mode) => switch (mode) {
    BookAiGraphViewMode.persons =>
      graph.entities
          .where((entity) => entity.type == AiGraphEntityType.person)
          .length,
    BookAiGraphViewMode.locations =>
      graph.entities
          .where((entity) => entity.type == AiGraphEntityType.location)
          .length,
    BookAiGraphViewMode.events =>
      graph.entities
          .where((entity) => entity.type == AiGraphEntityType.event)
          .length,
    BookAiGraphViewMode.organizations =>
      graph.entities
          .where((entity) => entity.type == AiGraphEntityType.organization)
          .length,
    BookAiGraphViewMode.things =>
      graph.entities
          .where(
            (entity) =>
                entity.type == AiGraphEntityType.item ||
                entity.type == AiGraphEntityType.concept ||
                entity.type == AiGraphEntityType.creature,
          )
          .length,
    BookAiGraphViewMode.graph => graph.relations.length,
    BookAiGraphViewMode.familyTree => null,
  };

  @override
  Widget build(BuildContext context) {
    final primary = _modes
        .where(
          (mode) =>
              mode != BookAiGraphViewMode.graph &&
              mode != BookAiGraphViewMode.familyTree,
        )
        .toList(growable: false);
    final explore = _modes
        .where(
          (mode) =>
              mode == BookAiGraphViewMode.graph ||
              mode == BookAiGraphViewMode.familyTree,
        )
        .toList(growable: false);

    Widget selector(List<BookAiGraphViewMode> choices) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<BookAiGraphViewMode>(
          segments: [
            for (final mode in choices)
              ButtonSegment(
                value: mode,
                label: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: bookAiGraphViewLabel(mode)),
                      if (_countFor(mode) case final count?)
                        TextSpan(
                          text: ' $count',
                          style: TextStyle(
                            fontSize: context.appCaptionSmallSize,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
          ],
          selected: choices.contains(selected)
              ? {selected}
              : const <BookAiGraphViewMode>{},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onSelected(selection.first);
          },
          showSelectedIcon: false,
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: context.appCaptionSize),
            ),
          ),
        ),
      );
    }

    Widget section(String label, List<BookAiGraphViewMode> choices) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: context.appCaptionSize,
            color: context.appSecondaryText,
          ),
        ),
        const SizedBox(height: 4),
        selector(choices),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('索引', primary),
        if (explore.isNotEmpty) ...[
          const SizedBox(height: 8),
          section('探索', explore),
        ],
      ],
    );
  }
}

class BookAiGraphWorkList extends StatelessWidget {
  const BookAiGraphWorkList({
    required this.works,
    required this.readingWork,
    required this.generatingWork,
    required this.preparing,
    required this.preparingWorkId,
    required this.busy,
    required this.error,
    required this.progressLabel,
    required this.titleSize,
    required this.isReady,
    required this.onSelect,
    required this.onCancelGeneration,
    super.key,
  });

  final List<AiGraphWorkCandidate> works;
  final AiGraphWorkCandidate? readingWork;
  final AiGraphWorkCandidate? generatingWork;
  final bool preparing;
  final String? preparingWorkId;
  final bool busy;
  final String? error;
  final String? progressLabel;
  final double titleSize;
  final bool Function(AiGraphWorkCandidate) isReady;
  final ValueChanged<AiGraphWorkCandidate> onSelect;
  final VoidCallback onCancelGeneration;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemCount: works.length + 1,
      separatorBuilder: (_, index) =>
          index == 0 ? const SizedBox(height: 10) : const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择作品',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                  color: context.appPrimaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '这份文件包含 ${works.length} 部作品。选择一部后，再确认参与生成的具体内容。',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.appSecondaryText,
                ),
              ),
              if (preparing) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '正在准备图谱…',
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ],
                ),
              ] else if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        }
        final work = works[index - 1];
        final ready = isReady(work);
        final isGenerating = identical(generatingWork, work);
        final isPreparing = preparing && preparingWorkId == work.id;
        final isReading = identical(readingWork, work);
        final status = isPreparing
            ? '正在准备…'
            : isGenerating
            ? (progressLabel ?? '正在生成…')
            : ready
            ? '已生成'
            : '未生成';
        return ListTile(
          key: ValueKey('graph-work-${work.id}'),
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(isReading ? '$status · 正在阅读' : status),
          trailing: isPreparing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : isGenerating
              ? TextButton.icon(
                  onPressed: onCancelGeneration,
                  icon: const Icon(KaijuanIcons.stop, size: 16),
                  label: const Text('停止'),
                )
              : Icon(
                  ready ? Icons.chevron_right : KaijuanIcons.graph,
                  size: 20,
                  color: context.appSecondaryText,
                ),
          onTap: busy ? null : () => onSelect(work),
        );
      },
    );
  }
}

class BookAiGraphOperationStatus extends StatelessWidget {
  const BookAiGraphOperationStatus({
    required this.label,
    required this.completed,
    required this.total,
    required this.generating,
    required this.onCancel,
    super.key,
  });

  final String label;
  final int completed;
  final int total;
  final bool generating;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final value = total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
    final compact = context.appIsCompact;
    return Semantics(
      container: true,
      liveRegion: true,
      label: total > 0 ? '$label，$completed / $total' : label,
      child: Container(
        key: const ValueKey<String>('graph-operation-status'),
        margin: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
        decoration: BoxDecoration(
          color: context.appColors.surfaceContainerHighest.withValues(
            alpha: 0.48,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: ThinkingOrb(
                    state: OrbState.working,
                    size: OrbSize.size20,
                    theme: Theme.of(context).brightness == Brightness.dark
                        ? OrbTheme.dark
                        : OrbTheme.light,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    total > 0 ? '$label  $completed / $total' : label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      fontWeight: FontWeight.w500,
                      color: context.appPrimaryText,
                    ),
                  ),
                ),
                if (generating)
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(KaijuanIcons.stop, size: 16),
                    label: const Text('停止'),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: value, minHeight: 3),
          ],
        ),
      ),
    );
  }
}

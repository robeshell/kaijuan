import 'package:flutter/material.dart';

import '../../../ai/ai_chat_retrieve.dart';
import '../../../ai/ai_graph.dart';
import '../../controllers/book_reader_controller.dart';

/// Pre-generation confirm dialog (spec §3.2): runs the step-0 display-plan
/// call inside the dialog (loading → plan), shows the five-dimension
/// features and lets the user confirm the recommended default view or pick
/// another one; in parallel it loads the auto-filtered graph corpus
/// (metadata/appendix removed, spine-deduped) as a manual section chooser —
/// unchecking excludes a chapter from generation. Pops
/// `(plan, excludedSections)`; null = cancelled.
class NarrationPlanDialog extends StatefulWidget {
  const NarrationPlanDialog({
    super.key,
    required this.controller,
    this.work,
    this.initialExcluded = const {},
  });

  final BookReaderController controller;
  final AiGraphWorkCandidate? work;

  /// Sections excluded on the previous generation — reopen the chooser with
  /// the same manual slice so regenerating doesn't redo the work.
  final Set<int> initialExcluded;

  @override
  State<NarrationPlanDialog> createState() => _NarrationPlanDialogState();
}

class _NarrationPlanDialogState extends State<NarrationPlanDialog> {
  static const _featureLabels = <String, String>{
    'eventDriven': '事件驱动',
    'characterEnsemble': '人物群像',
    'organization': '组织博弈',
    'geography': '地理叙事',
    'essay': '散文随笔',
  };

  static const _viewLabels = <String, String>{
    'persons': '人物',
    'locations': '地点',
    'events': '事件',
    'graph': '关系图',
    'family_tree': '家族树',
    'org_tree': '组织树',
  };

  AiNarrationPlan? _plan;
  bool _failed = false;
  String? _selectedView;

  /// Auto-filtered graph corpus (metadata/appendix removed, spine-deduped).
  /// Shown for the user's manual second pass: uncheck to exclude a section.
  List<AiBookSectionSlice>? _sections;
  bool _sectionsFailed = false;
  final Set<int> _excludedSections = {};

  @override
  void initState() {
    super.initState();
    _excludedSections.addAll(widget.initialExcluded);
    _analyze();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() {
      _sections = null;
      _sectionsFailed = false;
    });
    try {
      final sections = await widget.controller
          .graphSectionChoices(widget.work);
      if (!mounted) return;
      setState(() {
        _sections = sections;
        // Keep only exclusions that still exist in THIS work's section
        // list — initialExcluded may come from the previously shown graph
        // (different work), whose indices would corrupt the count.
        final valid = sections.map((s) => s.index).toSet();
        _excludedSections.retainAll(valid);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sectionsFailed = true);
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _plan = null;
      _failed = false;
    });
    final plan = await widget.controller
        .analyzeActiveGraphNarration(work: widget.work);
    if (!mounted) return;
    setState(() {
      if (plan == null) {
        _failed = true;
      } else {
        _plan = plan;
        // org_tree has no rendered entry yet; if the model still picked it
        // as the default, fall back to the first selectable view so the
        // confirm button applies a view that actually exists.
        final defaultView = plan.defaultView == 'org_tree'
            ? plan.viewOrder.firstWhere(
                (v) => v != 'org_tree',
                orElse: () => 'persons',
              )
            : plan.defaultView;
        _selectedView = defaultView;
      }
    });
  }

  String get _summary {
    final plan = _plan!;
    final ranked = [...AiNarrationPlan.knownFeatures]
      ..sort((a, b) => plan.feature(b).compareTo(plan.feature(a)));
    final top = ranked.firstWhere(
      (key) => plan.feature(key) >= 0.5,
      orElse: () => ranked.first,
    );
    return '${_featureLabels[top] ?? top}为主 · '
        '推荐${_viewLabels[plan.defaultView] ?? plan.defaultView}';
  }

  /// All auto-filtered sections are excluded → generation would be empty.
  bool get _allExcluded =>
      _sections != null &&
      _sections!.isNotEmpty &&
      _excludedSections.length >= _sections!.length;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('展示方案'),
      content: SizedBox(
        width: 360,
        child: _buildBody(context, colors),
      ),
      actions: [
        if (_plan != null || _failed)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        if (_failed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: _analyze, child: const Text('重试')),
              const SizedBox(width: 8),
              TextButton(
                // The display plan only tunes views; failing to analyze it
                // must not block generation (default view fallback).
                onPressed: () => Navigator.of(context).pop((
                  plan: null,
                  excludedSections: Set<int>.unmodifiable(_excludedSections),
                )),
                child: const Text('跳过，按默认生成'),
              ),
            ],
          )
        else if (_plan != null)
          FilledButton(
            onPressed: _selectedView == null || _allExcluded
                ? null
                : () => Navigator.of(context).pop(
                      (
                        plan: _plan!.withDefaultView(_selectedView!),
                        excludedSections: Set<int>.unmodifiable(
                          _excludedSections,
                        ),
                      ),
                    ),
            child: const Text('生成图谱'),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colors) {
    if (_failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 32, color: colors.error),
          const SizedBox(height: 10),
          Text(
            '展示方案分析失败',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '无法分析本书的展示方式，可重试或取消。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    final plan = _plan;
    if (plan == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text('正在分析本书的展示方案…'),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _summary,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          for (final key in AiNarrationPlan.knownFeatures)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      _featureLabels[key] ?? key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: plan.feature(key),
                        minHeight: 5,
                        backgroundColor: colors.surfaceContainerHighest,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      plan.feature(key).toStringAsFixed(1),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            '默认视图',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // org_tree is not a rendered entry yet — offering it as a
              // default-view choice would be a silent no-op (mirrors the
              // entryOrder filter in _buildNarrationCard).
              for (final view in plan.viewOrder)
                if (view != 'org_tree')
                  ChoiceChip(
                    label: Text(_viewLabels[view] ?? view),
                    selected: _selectedView == view,
                    onSelected: (_) => setState(() => _selectedView = view),
                    visualDensity: VisualDensity.compact,
                  ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '选择生成后首先展示的视图，其余入口按方案排序保留。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '图谱正文范围',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (_sections != null) ...[
                const SizedBox(width: 8),
                Text(
                  '已选 ${_sections!.length - _excludedSections.length} / ${_sections!.length} 节',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '已自动过滤前言/目录/附录等辅文；以下章节参与生成，'
            '取消勾选可排除（如 序言/导读/出版说明）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          if (_sectionsFailed)
            Row(
              children: [
                Text(
                  '章节列表加载失败',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _loadSections,
                  child: const Text('重试'),
                ),
              ],
            )
          else if (_sections == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('正在加载章节…'),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final section in _sections!)
                    CheckboxListTile(
                      dense: true,
                      value: !_excludedSections.contains(section.index),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _excludedSections.remove(section.index);
                        } else {
                          _excludedSections.add(section.index);
                        }
                      }),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '§${section.index} ${section.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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

  /// Book/volume container indices currently expanded in the tree chooser.
  final Set<int> _expandedContainers = {};

  /// Leaf sections (containers have no body and are never generated).
  List<AiBookSectionSlice> get _leaves => [
    for (final s in _sections ?? const <AiBookSectionSlice>[])
      if (s.text.trim().isNotEmpty) s,
  ];

  int get _leafCount => _leaves.length;

  int get _selectedLeafCount =>
      _leaves.where((s) => !_excludedSections.contains(s.index)).length;

  /// Groups the chooser list into book/volume containers (level 1, empty
  /// body) with their level-2 pieces as children; plain sections stay roots.
  /// Empty level-2 pieces (adjacent headings with no body) are dropped.
  List<_ChooserNode> get _tree {
    final out = <_ChooserNode>[];
    _ChooserNode? container;
    for (final s in _sections ?? const <AiBookSectionSlice>[]) {
      final empty = s.text.trim().isEmpty;
      if (empty && s.level <= 1) {
        container = _ChooserNode(slice: s);
        out.add(container);
      } else if (empty) {
        continue; // level-2 empty piece — nothing to select
      } else if (s.level > 1 && container != null) {
        container.children.add(_ChooserNode(slice: s));
      } else {
        container = null;
        out.add(_ChooserNode(slice: s));
      }
    }
    return out;
  }

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
      final sections = await widget.controller.graphSectionChoices(widget.work);
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
    final plan = await widget.controller.analyzeActiveGraphNarration(
      work: widget.work,
    );
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

  /// All auto-filtered leaves are excluded → generation would be empty.
  bool get _allExcluded {
    final sections = _sections;
    if (sections == null || sections.isEmpty) return false;
    final leaves = [
      for (final s in sections)
        if (s.text.trim().isNotEmpty) s.index,
    ];
    return leaves.isNotEmpty && leaves.every(_excludedSections.contains);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // PopScope(canPop:false) blocks Esc / system-back during the run — the
    // dialog is a multi-step confirm (plan + range + view) and closing it
    // mid-analyze loses context; the explicit 取消 button still pops.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('展示方案'),
        content: SizedBox(
          // Airy: the collection chooser needs room for the work→book→piece
          // tree; 360 was cramped and made the dialog look like a tooltip.
          width: 480,
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
                  : () => Navigator.of(context).pop((
                      plan: _plan!.withDefaultView(_selectedView!),
                      excludedSections: Set<int>.unmodifiable(
                        _excludedSections,
                      ),
                    )),
              child: const Text('生成图谱'),
            ),
        ],
      ),
    );
  }

  /// One row of the range chooser: a leaf checkbox, or a book/volume
  /// container whose checkbox toggles all its pieces at once. Rows use the
  /// outline-tab ListTile language: airy spacing, one line, no cramming.
  Widget _buildChooserNode(_ChooserNode node) {
    final theme = Theme.of(context);
    final s = node.slice;
    if (node.children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: CheckboxListTile(
          value: !_excludedSections.contains(s.index),
          onChanged: (checked) => setState(() {
            if (checked == true) {
              _excludedSections.remove(s.index);
            } else {
              _excludedSections.add(s.index);
            }
          }),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 4, 0),
          title: Text(
            s.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final selected = node.children
        .where((c) => !_excludedSections.contains(c.slice.index))
        .length;
    final triState = selected == 0
        ? false
        : (selected == node.children.length ? true : null);
    final expanded = _expandedContainers.contains(s.index);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            leading: Checkbox(
              value: triState,
              tristate: true,
              onChanged: (checked) => setState(() {
                // Container click = select all ⇄ select none (never the dash
                // state); the dash only reflects a partial child selection.
                if (checked == true) {
                  for (final c in node.children) {
                    _excludedSections.remove(c.slice.index);
                  }
                } else {
                  for (final c in node.children) {
                    _excludedSections.add(c.slice.index);
                  }
                }
              }),
            ),
            contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 4, 0),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${node.children.length} 篇',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            onTap: () => setState(() {
              if (expanded) {
                _expandedContainers.remove(s.index);
              } else {
                _expandedContainers.add(s.index);
              }
            }),
          ),
        ),
        if (expanded)
          for (final child in node.children)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: CheckboxListTile(
                value: !_excludedSections.contains(child.slice.index),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _excludedSections.remove(child.slice.index);
                  } else {
                    _excludedSections.add(child.slice.index);
                  }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  0,
                  0,
                  4,
                  0,
                ),
                title: Text(
                  child.slice.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
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
          Text('展示方案分析失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '无法分析本书的展示方式，可重试或取消。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
          Text(_summary, style: Theme.of(context).textTheme.titleSmall),
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
          Text('默认视图', style: Theme.of(context).textTheme.labelLarge),
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('图谱正文范围', style: Theme.of(context).textTheme.labelLarge),
              if (_sections != null) ...[
                const SizedBox(width: 8),
                Text(
                  '已选 $_selectedLeafCount / $_leafCount 节',
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          if (_sectionsFailed)
            Row(
              children: [
                Text(
                  '章节列表加载失败',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.error),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _loadSections, child: const Text('重试')),
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
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [for (final node in _tree) _buildChooserNode(node)],
              ),
            ),
        ],
      ),
    );
  }
}

/// One node of the range-chooser tree: a plain section (leaf) or a
/// book/volume container ([AiBookSectionSlice.text] empty) whose [children]
/// are its level-2 pieces.
class _ChooserNode {
  _ChooserNode({required this.slice}) : children = [];
  final AiBookSectionSlice slice;
  final List<_ChooserNode> children;
}

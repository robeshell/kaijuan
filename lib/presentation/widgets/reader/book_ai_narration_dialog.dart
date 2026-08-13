import 'package:flutter/material.dart';

import '../../../ai/ai_cancel.dart';
import '../../../ai/ai_graph.dart';
import '../../../ai/ai_graph_scope.dart';
import '../../../core/theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../ai_typography.dart';

enum _ScopeBulkAction { recommended, selectAll, clear }

/// Pre-generation confirmation after publication structure recognition.
///
/// Every readable unit stays visible. Program rules only supply the initial
/// recommendation; the user owns the final scope. Display-plan analysis is a
/// non-blocking enhancement and can fail or still be loading when generation
/// starts.
class NarrationPlanDialog extends StatefulWidget {
  const NarrationPlanDialog({
    super.key,
    required this.controller,
    this.work,
    this.initialExcluded = const {},
    this.useRecommendedSelection = true,
    this.scopeOnly = false,
    this.sheetLayout = false,
    this.dialogTitle,
    this.confirmLabel,
  });

  final BookReaderController controller;
  final AiGraphWorkCandidate? work;

  /// Sections excluded on the previous generation — reopen the chooser with
  /// the same manual slice so regenerating doesn't redo the work.
  final Set<int> initialExcluded;

  /// Fresh graphs start from the planner's recommendation. Regeneration uses
  /// the exact previously confirmed selection, including an intentional
  /// “select all”.
  final bool useRecommendedSelection;

  /// Reuses the same complete content-range chooser without running the
  /// graph-only display-plan request. Used by manually scoped outlines.
  final bool scopeOnly;

  /// Phone presentation: the chooser is the content of a root bottom sheet,
  /// rather than an AlertDialog nested over the AI bottom sheet.
  final bool sheetLayout;
  final String? dialogTitle;
  final String? confirmLabel;

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
    'organizations': '组织',
    'things': '事物',
    'graph': '关系图',
    'family_tree': '家族树',
    // Legacy cached plan; AiNarrationPlan.fromJson migrates it.
    'org_tree': '组织',
  };

  AiNarrationPlan? _plan;
  bool _failed = false;
  String? _selectedView;

  AiGraphScopePlan? _scope;
  bool _scopeFailed = false;
  final Set<int> _excludedSections = {};
  final ScrollController _bodyScrollController = ScrollController();
  final CancelToken _analyzeCancel = CancelToken();

  List<AiGraphSectionChoice> get _selectable => _scope?.selectable ?? const [];

  int get _leafCount => _selectable.length;

  int get _selectedLeafCount => _selectable
      .where((choice) => !_excludedSections.contains(choice.id))
      .length;

  @override
  void initState() {
    super.initState();
    _excludedSections.addAll(widget.initialExcluded);
    if (!widget.scopeOnly) _analyze();
    _loadScope();
  }

  @override
  void dispose() {
    _analyzeCancel.cancel();
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadScope() async {
    setState(() {
      _scope = null;
      _scopeFailed = false;
    });
    try {
      final scope = await widget.controller.graphScopePlan(widget.work);
      if (!mounted) return;
      setState(() {
        _scope = scope;
        final valid = scope.choices.map((choice) => choice.id).toSet();
        _excludedSections.retainAll(valid);
        if (widget.useRecommendedSelection) {
          _excludedSections.addAll(scope.recommendedExcluded);
          if (!widget.controller.allowUnreadGraphContext) {
            final readThrough = widget.controller.sectionIndex + 1;
            final positionIntersectsScope = scope.selectable.any(
              (choice) => choice.section.originSectionIndex <= readThrough,
            );
            // A renderer still parked on the cover/front matter has not
            // supplied a usable read boundary. In that case keep the whole
            // selectable range open instead of recommending zero chapters.
            if (positionIntersectsScope) {
              _excludedSections.addAll(
                scope.selectable
                    .where(
                      (choice) =>
                          choice.section.originSectionIndex > readThrough,
                    )
                    .map((choice) => choice.id),
              );
            }
          }
        } else {
          // Empty/unreadable containers can never become model input even if
          // an old graph predates the scope planner.
          _excludedSections.addAll(
            scope.choices
                .where((choice) => !choice.canSelect)
                .map((choice) => choice.id),
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _scopeFailed = true);
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _plan = null;
      _failed = false;
    });
    try {
      final plan = await widget.controller.analyzeActiveGraphNarration(
        work: widget.work,
        cancel: _analyzeCancel,
      );
      if (!mounted) return;
      setState(() {
        if (plan == null) {
          _failed = true;
        } else {
          _plan = plan;
          _selectedView = plan.defaultView;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
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

  /// All selectable units are excluded → generation would be empty.
  bool get _allExcluded {
    if (_scope == null) return false;
    return _selectable.isEmpty || _selectedLeafCount == 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actionTextStyle = TextStyle(
      fontSize: context.aiLabelSize,
      fontWeight: FontWeight.w500,
    );
    final title = Text(
      widget.dialogTitle ??
          (widget.work == null ? '生成知识图谱' : '生成《${widget.work!.title}》图谱'),
      style: TextStyle(
        fontSize: context.aiTitleSize,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
    );
    final actions = <Widget>[
      TextButton(
        style: TextButton.styleFrom(textStyle: actionTextStyle),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(textStyle: actionTextStyle),
        onPressed: _scope == null || _scopeFailed || _allExcluded
            ? null
            : () {
                final plan = _plan;
                Navigator.of(context).pop((
                  plan: plan == null || _selectedView == null
                      ? null
                      : plan.withDefaultView(_selectedView!),
                  mode: plan == null || _selectedView == null
                      ? AiNarrationPlanMode.skip
                      : AiNarrationPlanMode.confirmed,
                  excludedSections: Set<int>.unmodifiable(_excludedSections),
                ));
              },
        child: Text(widget.confirmLabel ?? '生成图谱'),
      ),
    ];
    if (!widget.sheetLayout) {
      return PopScope(
        canPop: true,
        child: AlertDialog(
          titlePadding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
          contentPadding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 16),
          title: title,
          content: SizedBox(width: 520, child: _buildBody(context, colors)),
          actions: actions,
        ),
      );
    }

    final media = MediaQuery.of(context);
    final availableHeight = (media.size.height - media.viewInsets.bottom).clamp(
      0.0,
      media.size.height,
    );
    return PopScope(
      canPop: true,
      child: SizedBox(
        key: const ValueKey<String>('narration-plan-sheet'),
        height: availableHeight * 0.92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
              child: title,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
                child: _buildBody(context, colors),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 12),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 10,
                overflowSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectAllSections() {
    setState(() {
      for (final choice in _selectable) {
        _excludedSections.remove(choice.id);
      }
    });
  }

  void _selectRecommendedSections() {
    final scope = _scope;
    if (scope == null) return;
    setState(() {
      _excludedSections
        ..clear()
        ..addAll(scope.recommendedExcluded);
    });
  }

  void _clearAllSections() {
    setState(() {
      _excludedSections.addAll(_selectable.map((choice) => choice.id));
    });
  }

  void _applyBulkAction(_ScopeBulkAction action) {
    switch (action) {
      case _ScopeBulkAction.recommended:
        _selectRecommendedSections();
      case _ScopeBulkAction.selectAll:
        _selectAllSections();
      case _ScopeBulkAction.clear:
        _clearAllSections();
    }
  }

  /// A flat, fully tappable chapter row. The file-internal work has already
  /// been resolved before this dialog opens, so rebuilding another tree here
  /// only hides choices and duplicates structure state.
  Widget _buildSectionRow(AiGraphSectionChoice choice) {
    final theme = Theme.of(context);
    final section = choice.section;
    final selected = choice.canSelect && !_excludedSections.contains(choice.id);
    return CheckboxListTile(
      key: ValueKey('graph-section-${choice.id}'),
      value: selected,
      onChanged: !choice.canSelect
          ? null
          : (checked) => setState(() {
              if (checked == true) {
                _excludedSections.remove(choice.id);
              } else {
                _excludedSections.add(choice.id);
              }
            }),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 4, 0),
      title: Text(
        section.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: context.aiBodySize,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: choice.reason == null
          ? null
          : Text(
              choice.reason!,
              style: TextStyle(
                fontSize: context.aiDetailSize,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colors) {
    final plan = _plan;
    final liveStatus = _scopeFailed
        ? '内容范围加载失败'
        : _scope == null
        ? '正在读取内容范围'
        : widget.scopeOnly
        ? '内容范围已准备好'
        : _failed
        ? '展示方案分析失败，将使用固定默认视图'
        : plan == null
        ? '正在分析适合的展示方式'
        : '内容范围和展示方式已准备好';
    return Scrollbar(
      controller: _bodyScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _bodyScrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              label: liveStatus,
              child: const SizedBox.shrink(),
            ),
            if (_scope != null) ...[
              Row(
                key: const ValueKey<String>('ai-scope-toolbar'),
                children: [
                  Expanded(
                    child: Text(
                      '已选 $_selectedLeafCount / $_leafCount 节',
                      style: TextStyle(
                        fontSize: context.aiBodySize,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<_ScopeBulkAction>(
                    tooltip: '批量选择',
                    position: PopupMenuPosition.under,
                    padding: EdgeInsets.zero,
                    menuPadding: const EdgeInsets.symmetric(vertical: 4),
                    onSelected: _applyBulkAction,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _ScopeBulkAction.recommended,
                        child: Text(
                          '选择推荐',
                          style: TextStyle(fontSize: context.aiLabelSize),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ScopeBulkAction.selectAll,
                        child: Text(
                          '全选可读项',
                          style: TextStyle(fontSize: context.aiLabelSize),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ScopeBulkAction.clear,
                        child: Text(
                          '清空',
                          style: TextStyle(fontSize: context.aiLabelSize),
                        ),
                      ),
                    ],
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: context.appIsCompact ? 44 : 40,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '批量选择',
                              style: TextStyle(
                                fontSize: context.aiLabelSize,
                                fontWeight: FontWeight.w500,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_allExcluded)
                Text(
                  '请至少选择一节可读取内容',
                  style: TextStyle(
                    fontSize: context.aiDetailSize,
                    height: 1.4,
                    color: colors.error,
                  ),
                ),
            ],
            if (_scopeFailed)
              Row(
                children: [
                  Text(
                    '内容范围加载失败',
                    style: TextStyle(
                      fontSize: context.aiDetailSize,
                      height: 1.4,
                      color: colors.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      textStyle: TextStyle(fontSize: context.aiLabelSize),
                    ),
                    onPressed: _loadScope,
                    child: const Text('重试'),
                  ),
                ],
              )
            else if (_scope == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在读取内容范围…',
                      style: TextStyle(fontSize: context.aiBodySize),
                    ),
                  ],
                ),
              )
            else
              for (final choice in _scope!.choices) _buildSectionRow(choice),
            if (!widget.scopeOnly) ...[
              const Divider(height: 28),
              Text(
                '首次展示',
                style: TextStyle(
                  fontSize: context.aiTitleSize,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (_failed)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '展示方案分析失败，将使用固定默认视图。',
                        style: TextStyle(
                          fontSize: context.aiDetailSize,
                          height: 1.45,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        textStyle: TextStyle(fontSize: context.aiLabelSize),
                      ),
                      onPressed: _analyze,
                      child: const Text('重试'),
                    ),
                  ],
                )
              else if (plan == null)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '正在分析适合的展示方式；你可以直接生成。',
                        style: TextStyle(
                          fontSize: context.aiDetailSize,
                          height: 1.45,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                Text(
                  _summary,
                  style: TextStyle(fontSize: context.aiBodySize, height: 1.45),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final view in plan.viewOrder)
                      ChoiceChip(
                        label: Text(
                          _viewLabels[view] ?? view,
                          style: TextStyle(fontSize: context.aiLabelSize),
                        ),
                        selected: _selectedView == view,
                        onSelected: (_) => setState(() => _selectedView = view),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

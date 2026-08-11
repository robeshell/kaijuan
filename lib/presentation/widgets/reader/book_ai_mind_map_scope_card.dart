import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../ai_typography.dart';

typedef BookAiMindMapScopeChoice = ({int value, String label, String subtitle});

class BookAiMindMapScopePrompt {
  BookAiMindMapScopePrompt({required this.title, required this.choices});

  final String title;
  final List<BookAiMindMapScopeChoice> choices;
  final Completer<int?> completer = Completer<int?>();
  int? selectedValue;
}

class BookAiMindMapScopeChoiceCard extends StatelessWidget {
  const BookAiMindMapScopeChoiceCard({
    required this.prompt,
    required this.onSelected,
    required this.onCancel,
    super.key,
  });

  final BookAiMindMapScopePrompt prompt;
  final ValueChanged<int> onSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectedValue = prompt.selectedValue;
    return Material(
      key: const ValueKey<String>('ai-mind-map-scope-choice-card'),
      color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择思维导图范围',
                    style: TextStyle(
                      color: context.appPrimaryText,
                      fontSize: context.aiBodySize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prompt.title,
                    style: TextStyle(
                      color: context.appSecondaryText,
                      fontSize: context.aiDetailSize,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < prompt.choices.length; index++) ...[
              _BookAiMindMapScopeChoiceRow(
                choice: prompt.choices[index],
                selected: selectedValue == prompt.choices[index].value,
                enabled: selectedValue == null,
                onTap: () => onSelected(prompt.choices[index].value),
              ),
              if (index < prompt.choices.length - 1) const SizedBox(height: 6),
            ],
            if (selectedValue == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onCancel, child: const Text('取消')),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Text(
                  '已选择，正在准备正文…',
                  style: TextStyle(
                    color: context.appSecondaryText,
                    fontSize: context.appCaptionSize,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookAiMindMapScopeChoiceRow extends StatelessWidget {
  const _BookAiMindMapScopeChoiceRow({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final BookAiMindMapScopeChoice choice;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: choice.label,
      value: choice.subtitle,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey<String>('ai-mind-map-scope-${choice.value}'),
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colors.primary : context.appDivider,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        choice.label,
                        style: TextStyle(
                          color: context.appPrimaryText,
                          fontSize: context.aiBodySize,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        choice.subtitle,
                        style: TextStyle(
                          color: context.appSecondaryText,
                          fontSize: context.appCaptionSize,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? KaijuanIcons.checkCircleFilled
                      : KaijuanIcons.chevronRight,
                  size: 18,
                  color: selected ? colors.primary : context.appSecondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

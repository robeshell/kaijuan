import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'app_components.dart';

/// One cell in [SelectionActionSheet]'s icon grid.
class SelectionActionItem {
  const SelectionActionItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// `null` ⇒ disabled (greyed).
  final VoidCallback? onTap;
  final bool destructive;
}

/// WeChat-Reading-style multi-select bottom sheet: header + wrapped icon grid.
///
/// Avoids single-row [IconButton] overflow on narrow / fold widths.
class SelectionActionSheet extends StatelessWidget {
  const SelectionActionSheet({
    super.key,
    required this.selectedCount,
    required this.totalVisible,
    required this.onSelectAll,
    required this.onDone,
    required this.actions,
  });

  final int selectedCount;
  final int totalVisible;
  final VoidCallback onSelectAll;
  final VoidCallback onDone;
  final List<SelectionActionItem> actions;

  static const _columns = 4;

  @override
  Widget build(BuildContext context) {
    final rows = <List<SelectionActionItem?>>[];
    for (var i = 0; i < actions.length; i += _columns) {
      final end = (i + _columns).clamp(0, actions.length);
      final slice = <SelectionActionItem?>[
        ...actions.sublist(i, end),
      ];
      while (slice.length < _columns) {
        slice.add(null);
      }
      rows.add(slice);
    }

    return AppGlassSurface(
      strong: true,
      shadowOffset: const Offset(0, -8),
      shadowBlur: 28,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: onSelectAll,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        selectedCount == totalVisible && totalVisible > 0
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '$selectedCount 项',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onDone,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        '完成',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                for (final row in rows) ...[
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final action in row)
                        Expanded(
                          child: action == null
                              ? const SizedBox.shrink()
                              : _ActionCell(action: action),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCell extends StatelessWidget {
  const _ActionCell({required this.action});

  final SelectionActionItem action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = action.onTap != null;
    final Color color;
    if (!enabled) {
      color = context.appSecondaryText.withValues(alpha: 0.4);
    } else if (action.destructive) {
      color = scheme.error;
    } else {
      color = context.appPrimaryText;
    }

    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(AppRadii.menu),
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return context.appDivider;
        }
        return Colors.transparent;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 24, weight: 300, color: color),
            const SizedBox(height: 6),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

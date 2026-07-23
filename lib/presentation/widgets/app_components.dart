import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Shared component kit built on the semantic tokens (see
/// docs/DESIGN_FOUNDATION.md). Components read glass/effects via the
/// context getters and the accent via `ColorScheme.primary` — never
/// hardcode colors or translucency.

/// Shared translucent surface used by the application shell and overlays.
///
/// Backdrop blur is intentionally optional: floating surfaces use it, while
/// repeated rows and cards can share the same visual language without paying
/// the cost of dozens of independent blur filters.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadii.sheet)),
    this.strong = false,
    this.blur = true,
    this.showShadow = true,
    this.shadowOffset = const Offset(0, 10),
    this.shadowBlur,
    this.color,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final bool strong;
  final bool blur;
  final bool showShadow;
  final Offset shadowOffset;
  final double? shadowBlur;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final glass = context.appGlass;
    final effects = context.appSkinEffects;
    final sigma = strong ? glass.strongBlur : glass.blur;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (strong ? glass.strongSurface : glass.surface),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? glass.border),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    final clipped = ClipRRect(
      borderRadius: borderRadius,
      // Skins with blur 0 (e.g. 纯净) get solid surfaces for free.
      child: blur && sigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: surface,
            )
          : surface,
    );
    if (!showShadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: glass.shadow,
            blurRadius:
                (shadowBlur ?? (strong ? 34 : 24)) * effects.shadowScale,
            offset: shadowOffset,
          ),
        ],
      ),
      child: clipped,
    );
  }
}

@immutable
class AppChoiceOption<T> {
  const AppChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.key,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Key? key;
  final bool enabled;
}

/// A borderless option strip shared by filters and segmented choices.
///
/// The selected state is communicated by a quiet accent tint and accent text;
/// unselected choices keep a barely visible neutral fill.
class AppChoiceStrip<T> extends StatelessWidget {
  const AppChoiceStrip({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.wrap = false,
    this.spacing = 8,
    super.key,
  });

  final List<AppChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool wrap;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final option in options)
        _AppChoiceButton<T>(
          key: option.key,
          option: option,
          selected: option.value == selected,
          onTap: option.enabled ? () => onSelected(option.value) : null,
        ),
    ];
    if (wrap) {
      return Wrap(spacing: spacing, runSpacing: spacing, children: children);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) SizedBox(width: spacing),
          ],
        ],
      ),
    );
  }
}

class _AppChoiceButton<T> extends StatelessWidget {
  const _AppChoiceButton({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AppChoiceOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.primary;
    final secondary = context.appSecondaryText;
    final foreground = !option.enabled
        ? context.appMutedText.withValues(alpha: 0.45)
        : selected
        ? accent
        : secondary.withValues(alpha: secondary.a * 0.82);
    return Semantics(
      button: true,
      selected: selected,
      enabled: option.enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.09)
                  : context.appTint(0.025),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.icon case final icon?) ...[
                  Icon(icon, size: 15, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  option.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual child for popup-backed sort and filter actions.
class AppToolbarButton extends StatelessWidget {
  const AppToolbarButton({
    required this.icon,
    required this.tooltip,
    this.label,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
        decoration: BoxDecoration(
          color: context.appTint(0.025),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: context.appSecondaryText),
            if (label case final value?) ...[
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  color: context.appSecondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared low-emphasis empty, loading and error state.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  icon,
                  size: 30,
                  color: context.appMutedText.withValues(
                    alpha: context.appMutedText.a * 0.68,
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.appPrimaryText.withValues(
                    alpha: context.appPrimaryText.a * 0.88,
                  ),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.appMutedText.withValues(
                    alpha: context.appMutedText.a * 0.76,
                  ),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.content,
    this.actions = const [],
    this.maxWidth = 520,
    this.titlePadding = const EdgeInsets.fromLTRB(24, 22, 20, 16),
    this.contentPadding = const EdgeInsets.fromLTRB(24, 0, 24, 20),
    this.actionsPadding = const EdgeInsets.fromLTRB(20, 14, 20, 20),
    super.key,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;
  final EdgeInsetsGeometry titlePadding;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry actionsPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogTheme = DialogTheme.of(context);
    final viewport = MediaQuery.sizeOf(context);
    const horizontalInset = 20.0;
    const verticalInset = 24.0;

    // Keep the route child responsible for its own bounds. Wrapping an
    // AlertDialog with a BackdropFilter makes the wrapper inherit the route's
    // loose full-height constraints, which can stretch otherwise short dialog
    // content (tables are especially visible). The surface now shrink-wraps
    // short content and gives only the content area the remaining height.
    return Dialog(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: viewport.height > verticalInset * 2
              ? viewport.height - verticalInset * 2
              : 0,
        ),
        child: SizedBox(
          key: const ValueKey('app-dialog'),
          width: maxWidth,
          child: AppGlassSurface(
            strong: true,
            borderRadius: BorderRadius.circular(AppRadii.dialog),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: titlePadding,
                    child: DefaultTextStyle(
                      style:
                          dialogTheme.titleTextStyle ??
                          theme.textTheme.headlineSmall!,
                      child: title,
                    ),
                  ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      key: const ValueKey('app-dialog-content-scroll'),
                      padding: contentPadding,
                      child: DefaultTextStyle(
                        style:
                            dialogTheme.contentTextStyle ??
                            theme.textTheme.bodyMedium!,
                        child: KeyedSubtree(
                          key: const ValueKey('app-dialog-content'),
                          child: content,
                        ),
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: actionsPadding,
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 10,
                        overflowSpacing: 10,
                        children: actions,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showHandle = true,
  double maxWidth = 760,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: dark ? 0.62 : 0.38),
    elevation: 0,
    constraints: BoxConstraints(maxWidth: maxWidth),
    builder: (sheetContext) =>
        AppBottomSheet(showHandle: showHandle, child: builder(sheetContext)),
  );
}

class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({required this.child, this.showHandle = true, super.key});

  final Widget child;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGlassSurface(
      strong: true,
      shadowOffset: const Offset(0, -8),
      shadowBlur: 28,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: showHandle ? 14 : 0),
                child: child,
              ),
              if (showHandle)
                Positioned(
                  top: 7,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.38,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One action or selection presented by [AppMenuButton].
///
/// The data model is shared by compact bottom sheets and wide anchored menus,
/// so platform changes never fall back to Material's default popup rows.
class AppMenuAction<T> {
  const AppMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.destructive = false,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final bool destructive;
  final bool dividerBefore;
}

/// 开卷's adaptive menu trigger for every supported window class.
///
/// Compact windows open a bottom action sheet. Wider windows use a custom
/// anchored overlay with the exact same rows, states and semantics.
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    required this.actions,
    required this.onSelected,
    required this.tooltip,
    this.menuTitle,
    this.child,
    this.icon = const Icon(Icons.more_horiz_rounded, size: 21),
    this.padding = EdgeInsets.zero,
    this.enabled = true,
    super.key,
  });

  final List<AppMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final String? menuTitle;
  final Widget? child;
  final Widget icon;
  final EdgeInsetsGeometry padding;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final anchor = origin & (renderBox?.size ?? Size.zero);
    final selected = await showAppMenu<T>(
      context,
      anchor: anchor,
      title: menuTitle,
      actions: actions,
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = enabled && actions.any((action) => action.enabled)
        ? () => _open(context)
        : null;
    if (child case final customChild?) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: tooltip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppRadii.control),
              hoverColor: context.appTint(0.04),
              focusColor: context.appTint(0.05),
              splashColor: Colors.transparent,
              child: customChild,
            ),
          ),
        ),
      );
    }
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: padding,
      icon: icon,
    );
  }
}

Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<AppMenuAction<T>> actions,
  Rect? anchor,
  String? title,
}) {
  final compact = MediaQuery.sizeOf(context).width < 680;
  if (compact || anchor == null) {
    return showAppBottomSheet<T>(
      context,
      builder: (sheetContext) =>
          _AppMenuList<T>(actions: actions, title: title, compact: true),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (routeContext, animation, secondaryAnimation) =>
        _AppAnchoredMenu<T>(anchor: anchor, actions: actions, title: title),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
  );
}

class _AppAnchoredMenu<T> extends StatelessWidget {
  const _AppAnchoredMenu({
    required this.anchor,
    required this.actions,
    this.title,
  });

  final Rect anchor;
  final List<AppMenuAction<T>> actions;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final estimatedHeight =
        actions.length * 48.0 + (title == null ? 12 : 56) + 12;
    const menuWidth = 252.0;
    const edge = 12.0;
    final left = (anchor.right - menuWidth)
        .clamp(edge, math.max(edge, viewport.width - menuWidth - edge))
        .toDouble();
    final opensAbove = anchor.bottom + estimatedHeight > viewport.height - edge;
    final top = opensAbove
        ? math.max(edge, anchor.top - estimatedHeight - 6)
        : anchor.bottom + 6;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(120, viewport.height - edge * 2),
              ),
              child: AppGlassSurface(
                strong: true,
                shadowOffset: const Offset(0, 8),
                shadowBlur: 24,
                borderRadius: BorderRadius.circular(AppRadii.menu),
                child: _AppMenuList<T>(
                  actions: actions,
                  title: title,
                  compact: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppMenuList<T> extends StatelessWidget {
  const _AppMenuList({
    required this.actions,
    required this.compact,
    this.title,
  });

  final List<AppMenuAction<T>> actions;
  final bool compact;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 6),
      children: [
        for (final action in actions) ...[
          if (action.dividerBefore)
            const Divider(height: 9, indent: 16, endIndent: 16),
          _AppMenuActionRow<T>(action: action, compact: compact),
        ],
      ],
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final value?) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 16,
              compact ? 10 : 12,
              compact ? 20 : 16,
              9,
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appSecondaryText,
                fontSize: compact ? 12.5 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(height: 1, color: context.appDivider),
        ],
        Flexible(child: list),
      ],
    );
    if (!compact) return content;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: content,
      ),
    );
  }
}

class _AppMenuActionRow<T> extends StatelessWidget {
  const _AppMenuActionRow({required this.action, required this.compact});

  final AppMenuAction<T> action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.primary;
    final error = context.appColors.error;
    final foreground = !action.enabled
        ? context.appMutedText.withValues(alpha: 0.48)
        : action.destructive
        ? error
        : action.selected
        ? accent
        : context.appPrimaryText;
    return Semantics(
      button: true,
      enabled: action.enabled,
      selected: action.selected,
      child: Material(
        color: action.selected ? context.appTint(0.055) : Colors.transparent,
        child: InkWell(
          onTap: action.enabled
              ? () => Navigator.of(context).pop(action.value)
              : null,
          hoverColor: context.appTint(0.04),
          focusColor: context.appTint(0.055),
          splashColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 52 : 46),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Icon(action.icon, size: 19, color: foreground),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.label,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (action.subtitle case final value?) ...[
                          const SizedBox(height: 2),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appSecondaryText,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (action.selected) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.check_rounded, size: 18, color: accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat, token-driven list row used inside overlays and structured lists.
class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.minHeight = 54,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final double minHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onTap != null;
    return Semantics(
      button: onTap != null,
      enabled: enabled,
      selected: selected,
      child: Material(
        color: selected ? context.appTint(0.05) : Colors.transparent,
        child: InkWell(
          onTap: interactive ? onTap : null,
          hoverColor: context.appTint(0.035),
          focusColor: context.appTint(0.05),
          splashColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  if (leading case final value?) ...[
                    SizedBox(width: 32, child: Center(child: value)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: TextStyle(
                            color: enabled
                                ? context.appPrimaryText
                                : context.appMutedText.withValues(alpha: 0.5),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: title,
                        ),
                        if (subtitle case final value?) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle(
                            style: TextStyle(
                              color: context.appSecondaryText,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: value,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing case final value?) ...[
                    const SizedBox(width: 10),
                    value,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppCheckRow extends StatelessWidget {
  const AppCheckRow({
    required this.value,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final Widget title;
  final Widget? subtitle;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      enabled: enabled,
      child: AppListRow(
        enabled: enabled,
        selected: value,
        onTap: enabled ? () => onChanged(!value) : null,
        leading: Icon(
          value
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: 20,
          color: value ? context.appColors.primary : context.appMutedText,
        ),
        title: title,
        subtitle: subtitle,
      ),
    );
  }
}

class AppNavigationItem {
  const AppNavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.embedded = false,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppNavigationItem> destinations;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(10, embedded ? 3 : 7, 10, embedded ? 4 : 6),
      child: SizedBox(
        height: embedded ? 46 : 56,
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: _AppNavigationButton(
                  item: destinations[index],
                  selected: index == selectedIndex,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
    if (embedded) return content;
    return AppGlassSurface(
      strong: true,
      color: context.appChromeSurface,
      shadowOffset: const Offset(0, -6),
      shadowBlur: 18,
      borderRadius: BorderRadius.zero,
      borderColor: theme.colorScheme.outlineVariant,
      child: content,
    );
  }
}

class _AppNavigationButton extends StatelessWidget {
  const _AppNavigationButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                height: 1,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 21,
                    color: foreground,
                  ),
                  const SizedBox(height: 3),
                  Text(item.label, maxLines: 1, overflow: TextOverflow.fade),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

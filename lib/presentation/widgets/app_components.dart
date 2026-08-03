import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../core/theme/brand_tokens.g.dart';

/// Shared component kit built on the semantic tokens (see
/// docs/DESIGN_FOUNDATION.md). Components read glass/effects via the
/// context getters and the accent via `ColorScheme.primary` — never
/// hardcode colors or translucency.

/// Text input with the component-owned `inputText` typography role.
///
/// Shell inputs share the same type scale, while their decorations remain
/// local to the use case (search, rename, or prompt).
class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.obscureText = false,
    this.readOnly = false,
    this.decoration,
    this.style,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final GestureTapCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final bool obscureText;
  final bool readOnly;
  final InputDecoration? decoration;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokenStyle = context.appInputTextStyle;
    final inputStyle = tokenStyle.copyWith(
      color: style?.color ?? context.appPrimaryText,
      fontWeight: style?.fontWeight ?? tokenStyle.fontWeight,
      fontSize: tokenStyle.fontSize,
      height: tokenStyle.height,
      letterSpacing: tokenStyle.letterSpacing,
    );
    final resolvedDecoration = decoration?.copyWith(
      hintStyle: (decoration?.hintStyle ?? tokenStyle).copyWith(
        color: decoration?.hintStyle?.color ?? context.appSecondaryText,
        fontSize: tokenStyle.fontSize,
        height: tokenStyle.height,
        fontWeight: decoration?.hintStyle?.fontWeight ?? tokenStyle.fontWeight,
        letterSpacing: tokenStyle.letterSpacing,
      ),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      obscureText: obscureText,
      readOnly: readOnly,
      style: inputStyle,
      decoration: resolvedDecoration,
    );
  }
}

/// One finite choice presented by [AppSelectField].
class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? subtitle;
  final bool enabled;
}

/// Token-driven form selector backed by the shared adaptive menu.
///
/// The closed field matches [AppTextField]. Desktop profiles open a compact,
/// anchored strong-glass menu; mobile profiles retain [showAppMenu]'s platform
/// mapping. This avoids Material's full-field-width dropdown route and keeps
/// selected, focus and keyboard semantics in the shared menu implementation.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.tooltip,
    this.hintText = '请选择',
    this.menuTitle,
    this.decoration,
    super.key,
  });

  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String tooltip;
  final String hintText;
  final String? menuTitle;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    AppSelectOption<T>? selected;
    for (final option in options) {
      if (option.value == value) {
        selected = option;
        break;
      }
    }
    final enabled =
        onChanged != null && options.any((option) => option.enabled);
    final foreground = enabled
        ? context.appPrimaryText
        : context.appMutedText.withValues(alpha: 0.48);
    final fieldDecoration = (decoration ?? const InputDecoration()).copyWith(
      enabled: enabled,
    );
    return AppMenuButton<T>(
      actions: [
        for (final option in options)
          AppMenuAction<T>(
            value: option.value,
            label: option.label,
            subtitle: option.subtitle,
            icon: option.icon,
            selected: option.value == value,
            enabled: option.enabled,
          ),
      ],
      onSelected: (next) => onChanged?.call(next),
      tooltip: tooltip,
      menuTitle: menuTitle,
      forceAnchored: appUsesDesktopPlatform,
      enabled: enabled,
      child: InputDecorator(
        decoration: fieldDecoration,
        isEmpty: selected == null,
        child: Row(
          children: [
            if (selected case final option?) ...[
              Icon(option.icon, size: 17, color: context.appSecondaryText),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                selected?.label ?? hintText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appInputTextStyle.copyWith(
                  color: selected == null
                      ? context.appSecondaryText
                      : foreground,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              KaijuanIcons.caretDown,
              size: 16,
              color: enabled ? context.appSecondaryText : foreground,
            ),
          ],
        ),
      ),
    );
  }
}

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
    this.border,
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

  /// When set, replaces the default `Border.all`. Use for chrome
  /// (side rail: right only; nav bar: top only).
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final glass = context.appGlass;
    final effects = context.appSkinEffects;
    final sigma = strong ? glass.strongBlur : glass.blur;
    // Keep BackdropFilter in the tree and toggle [enabled], matching kaiting
    // SoundGlassSurface — avoids different layer compositing for chrome.
    final useBackdropBlur = blur && sigma > 0;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (strong ? glass.strongSurface : glass.surface),
        borderRadius: borderRadius,
        border: border ?? Border.all(color: borderColor ?? glass.border),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    final blurred = BackdropFilter(
      enabled: useBackdropBlur,
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: surface,
    );
    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: blurred,
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
                    fontSize: context.appLabelSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
                  fontSize: context.appLabelSize,
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
    this.actionLabel,
    this.onAction,
    this.padding,
    this.alignment = Alignment.center,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Empty states can sit below a tall chrome stack or inside a short
        // sheet. Hide secondary copy and tighten rhythm before allowing the
        // shared state to overflow its bounded viewport.
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 180;
        final contentPadding =
            padding ??
            EdgeInsets.fromLTRB(
              context.appPageGutter,
              compact ? 12 : 30,
              context.appPageGutter,
              compact ? 12 : context.appContentBottomPadding,
            );

        return Align(
          alignment: alignment,
          child: Padding(
            padding: contentPadding,
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
                      size: compact ? 24 : 30,
                      color: context.appMutedText.withValues(
                        alpha: context.appMutedText.a * 0.68,
                      ),
                    ),
                  SizedBox(height: compact ? 8 : 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.appPrimaryText.withValues(
                        alpha: context.appPrimaryText.a * 0.88,
                      ),
                      fontSize: compact
                          ? context.appTitleSize
                          : context.appSectionTitleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.appMutedText.withValues(
                          alpha: context.appMutedText.a * 0.76,
                        ),
                        fontSize: context.appBodySecondarySize,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    SizedBox(height: compact ? 10 : 20),
                    FilledButton.tonalIcon(
                      onPressed: onAction,
                      icon: const Icon(KaijuanIcons.forward, size: 17),
                      label: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
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
  bool useRootNavigator = false,
  double maxWidth = 760,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
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
  const AppBottomSheet({
    required this.child,
    this.showHandle = true,
    super.key,
  });

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
    this.icon = const Icon(KaijuanIcons.more, size: 21),
    this.padding = EdgeInsets.zero,
    this.forceAnchored = false,
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
  final bool forceAnchored;
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
      forceAnchored: forceAnchored,
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
  bool forceAnchored = false,
}) {
  final compact = MediaQuery.sizeOf(context).width < 680;
  if ((!forceAnchored && compact) || anchor == null) {
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
        actions.fold<double>(
          0,
          (height, action) =>
              height + _appMenuActionHeight(action, compact: false),
        ) +
        (title == null ? 8 : 48) +
        8;
    final menuWidth = _anchoredMenuWidth(context, actions);
    const edge = 12.0;
    // Keep menus triggered from the leading side aligned to the trigger's
    // left edge. Right-aligning every menu makes a wide filter menu expand
    // over the navigation rail; trailing actions should still right-align.
    final preferredLeft = anchor.center.dx < viewport.width / 2
        ? anchor.left
        : anchor.right - menuWidth;
    final left = preferredLeft
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
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
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

/// Content-hugging width for anchored menus (min 160 / max 280).
double _anchoredMenuWidth<T>(
  BuildContext context,
  List<AppMenuAction<T>> actions,
) {
  final labelStyle = TextStyle(
    fontSize: context.appLabelSize,
    fontWeight: FontWeight.w600,
  );
  final subtitleStyle = TextStyle(fontSize: context.appCaptionSmallSize);
  final painter = TextPainter(textDirection: TextDirection.ltr);
  var maxLabel = 0.0;
  try {
    for (final action in actions) {
      painter.text = TextSpan(text: action.label, style: labelStyle);
      painter.layout();
      maxLabel = math.max(maxLabel, painter.width);
      if (action.subtitle case final value?) {
        painter.text = TextSpan(text: value, style: subtitleStyle);
        painter.layout();
        maxLabel = math.max(maxLabel, painter.width);
      }
    }
  } finally {
    painter.dispose();
  }
  final hasSelected = actions.any((action) => action.selected);
  final hasSubtitle = actions.any((action) => action.subtitle != null);
  // 12h×2 + icon 22 + gap 10 + label + optional check (10+16)
  // Two-line items get a little more air without exceeding the brand menu cap.
  final content =
      24 + 22 + 10 + maxLabel + (hasSelected ? 26 : 0) + (hasSubtitle ? 20 : 0);
  return content.clamp(160.0, 280.0);
}

double _appMenuActionHeight<T>(
  AppMenuAction<T> action, {
  required bool compact,
}) {
  if (action.subtitle != null) return compact ? 64 : 56;
  return compact ? 52 : 36;
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
    final hPad = compact ? 20.0 : 12.0;
    final list = ListView(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 4),
      children: [
        for (final action in actions) ...[
          if (action.dividerBefore)
            Divider(height: 9, indent: hPad, endIndent: hPad),
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
            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 9),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appSecondaryText,
                fontSize: compact
                    ? KaiProductTokens.typographyMenuTitleCompact
                    : KaiProductTokens.typographyMenuTitleWide,
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
            constraints: BoxConstraints(
              minHeight: _appMenuActionHeight(action, compact: compact),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 12),
              child: Row(
                children: [
                  SizedBox(
                    width: compact ? 24 : 22,
                    child: Icon(
                      action.icon,
                      size: compact ? 19 : 17,
                      color: foreground,
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: compact
                                ? KaiProductTokens
                                      .typographyMenuItemLabelCompact
                                : KaiProductTokens.typographyMenuItemLabelWide,
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
                              fontSize: context.appCaptionSmallSize,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (action.selected) ...[
                    SizedBox(width: compact ? 12 : 10),
                    Icon(
                      KaijuanIcons.check,
                      size: compact ? 18 : 16,
                      color: accent,
                    ),
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

/// Flat list row — port of kaiting `SoundListRow` (token getters only).
///
/// Sidebar rows pass [minHeight]/[selectedColor]/[borderRadius]/[hoverColor]
/// exactly like kaiting `_SidebarRow`.
class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.minHeight,
    this.leadingWidth = 32,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
    this.selectedColor,
    this.borderRadius,
    this.hoverColor,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final double? minHeight;
  final double leadingWidth;
  final EdgeInsetsGeometry padding;
  final int titleMaxLines;
  final int subtitleMaxLines;

  /// 选中底色；默认前景 5% tint，侧栏等场景传 accent 10% 胶囊。
  final Color? selectedColor;

  /// 行体圆角（选中/hover 一并裁剪）；默认直角整行填充。
  final BorderRadius? borderRadius;

  /// Hover 底色；默认前景 3.5%（list-row）；侧栏传 4.5%。
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && (onTap != null || onLongPress != null);
    return Semantics(
      button: onTap != null || onLongPress != null,
      enabled: enabled,
      selected: selected,
      child: Material(
        color: selected
            ? selectedColor ?? context.appTint(0.05)
            : Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: borderRadius == null ? Clip.none : Clip.antiAlias,
        child: InkWell(
          onTap: interactive ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          hoverColor: hoverColor ?? context.appTint(0.035),
          focusColor: context.appTint(0.05),
          splashColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minHeight ??
                  (context.appComponentProfile == AppComponentProfile.desktop
                      ? KaiBrandDesktopMetrics.listRowSingle
                      : KaiBrandMobileMetrics.listRowSingle),
            ),
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  if (leading case final value?) ...[
                    SizedBox(width: leadingWidth, child: Center(child: value)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Match SoundListRow: default w500 listTitle; title
                        // child overrides (sidebar uses bodyMedium + w500/600).
                        DefaultTextStyle(
                          style: TextStyle(
                            color: enabled
                                ? context.appPrimaryText
                                : context.appSecondaryText.withValues(
                                    alpha: appDisabledForegroundOpacity,
                                  ),
                            fontSize: context.appListTitleSize,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          child: title,
                        ),
                        if (subtitle case final value?) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle(
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: context.appSecondaryText),
                            maxLines: subtitleMaxLines,
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
          value ? KaijuanIcons.checkboxChecked : KaijuanIcons.checkbox,
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
    // Phone landscape / short split: icon-only bar frees vertical space.
    // Heights must match [AppNavigationChromeMetrics] / content bottom inset.
    final short = !embedded && context.appIsShortViewport;
    final barHeight = embedded
        ? 46.0
        : (short
              ? AppNavigationChromeMetrics.barHeightShort
              : AppNavigationChromeMetrics.barHeight);
    final minBottom = embedded
        ? 4.0
        : (short
              ? AppNavigationChromeMetrics.barMinBottomShort
              : AppNavigationChromeMetrics.barMinBottom);
    final content = SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(
        10,
        embedded ? 3 : (short ? 4 : 7),
        10,
        minBottom,
      ),
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: _AppNavigationButton(
                  item: destinations[index],
                  selected: index == selectedIndex,
                  onTap: () => onDestinationSelected(index),
                  iconOnly: short,
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
      border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: content,
    );
  }
}

class _AppNavigationButton extends StatelessWidget {
  const _AppNavigationButton({
    required this.item,
    required this.selected,
    required this.onTap,
    this.iconOnly = false,
  });

  final AppNavigationItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool iconOnly;

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
            child: Tooltip(
              message: item.label,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: foreground,
                  fontSize: KaiProductTokens.typographyNavigationMobileLabel,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: iconOnly ? 24 : 21,
                      color: foreground,
                    ),
                    if (!iconOnly) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

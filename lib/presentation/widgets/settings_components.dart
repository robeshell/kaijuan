import 'package:flutter/material.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../core/theme/brand_tokens.g.dart';

abstract final class AppSettingsMetrics {
  static const maxContentWidth = KaiBrandLayout.standardContentWidth;
  static const formMaxWidth = KaiBrandLayout.formContentWidth;
  static const sectionGap = AppSpacing.x6;

  /// Space between the page header and the first content block.
  ///
  /// Smaller than [sectionGap] so the chrome does not read as an empty band
  /// above the first group.
  static const headerGap = AppSpacing.x4;

  /// Top inset for settings-style content columns (header included).
  static double pageTop(BuildContext context) =>
      context.appIsCompact ? AppSpacing.x3 : AppSpacing.x4;
}

extension AppSettingsContext on BuildContext {
  Color get settingsPrimary => appPrimaryText;
  Color get settingsSecondary => appSecondaryText;
  Color get settingsMuted => appMutedText;
  Color get settingsHairline =>
      appDivider.withValues(alpha: appDivider.a * 0.72);

  /// Management pages share the app canvas instead of adding a second grey
  /// full-page layer. Local groups own the subtle surface contrast.
  Color get settingsCanvas => Theme.of(this).scaffoldBackgroundColor;

  /// Keep light groups barely lifted from the white canvas. Dark groups retain
  /// the stronger elevated surface needed to separate them from the night
  /// canvas without introducing a second raw palette.
  Color get settingsGroupSurface => Theme.of(this).brightness == Brightness.dark
      ? appColors.surfaceContainer
      : appColors.surfaceContainerLow;

  /// 卡内行间分隔线：比 hairline 再淡一档，只暗示行的边界。
  Color get settingsRowDivider => Theme.of(this).brightness == Brightness.dark
      ? const Color(0x0DFFFFFF)
      : const Color(0x0A000000);
}

class AppSettingsContent extends StatelessWidget {
  const AppSettingsContent({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.maxWidth = AppSettingsMetrics.maxContentWidth,
    this.shrinkWrapHeight = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final bool shrinkWrapHeight;

  @override
  Widget build(BuildContext context) {
    if (shrinkWrapHeight) {
      // Scaffold lays out bottomNavigationBar with the full screen as a
      // loose height constraint. Keep action bars intrinsic-height instead of
      // letting the centering wrapper claim the entire viewport; otherwise a
      // floating SnackBar has no room above the bar on compact screens.
      return Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(
            width: double.infinity,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class AppSettingsScrollView extends StatelessWidget {
  const AppSettingsScrollView({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.maxWidth = AppSettingsMetrics.maxContentWidth,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AppSettingsContent(
          padding: padding,
          maxWidth: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Safe-area wrapper for settings-style content routes.
///
/// The app shell protects its root destinations, while routes pushed into the
/// content navigator still own their top and bottom insets. Keeping this at the
/// page boundary prevents the header from sliding under a notch or the desktop
/// traffic-light band.
class AppSettingsSafeArea extends StatelessWidget {
  const AppSettingsSafeArea({
    required this.child,
    this.bottom = false,
    super.key,
  });

  final Widget child;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(top: true, bottom: bottom, child: child);
  }
}

/// Sticky action area shared by settings-style subpages.
///
/// It owns the bottom safe area and uses the same constrained content column
/// as [AppSettingsScrollView], so actions do not drift away from the form or
/// list above them on larger windows.
class AppSettingsBottomBar extends StatelessWidget {
  const AppSettingsBottomBar({
    required this.child,
    this.maxWidth = AppSettingsMetrics.maxContentWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(top: AppSpacing.x2, bottom: AppSpacing.x4),
      child: AppSettingsContent(
        shrinkWrapHeight: true,
        maxWidth: maxWidth,
        padding: EdgeInsets.symmetric(horizontal: context.appPageGutter),
        child: child,
      ),
    );
  }
}

class AppSettingsPageHeader extends StatelessWidget {
  const AppSettingsPageHeader({
    required this.title,
    this.onBack,
    this.backButtonKey,
    this.actions = const [],
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final Key? backButtonKey;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final inlineBack = onBack != null && context.appIsCompact;
    final titleText = Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.settingsPrimary,
          fontSize: context.appSectionTitleSize,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.15,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );

    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (inlineBack) ...[
          _SettingsBackControl(
            key: backButtonKey,
            onPressed: onBack!,
            labeled: false,
          ),
          const SizedBox(width: AppSpacing.x1),
        ],
        Expanded(child: titleText),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.x3),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ],
    );

    if (onBack == null || inlineBack) return titleRow;

    // Desktop: light back control above the title. Keep a full 40px hit target
    // but no extra air between the two rows — the previous 4–8px gap read as an
    // empty band on short management pages.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsBackControl(
          key: backButtonKey,
          onPressed: onBack!,
          labeled: true,
        ),
        titleRow,
      ],
    );
  }
}

/// Compact settings back control: 40×40 hit area, no fill, icon+label centered.
class _SettingsBackControl extends StatelessWidget {
  const _SettingsBackControl({
    required this.onPressed,
    required this.labeled,
    super.key,
  });

  final VoidCallback onPressed;
  final bool labeled;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: context.appLabelSize,
      fontWeight: FontWeight.w500,
      height: 1.0,
      leadingDistribution: TextLeadingDistribution.even,
    );

    return Tooltip(
      message: '返回',
      child: TextButton(
        onPressed: onPressed,
        style:
            TextButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: labeled
                  ? const EdgeInsetsDirectional.only(end: 6)
                  : EdgeInsets.zero,
              alignment: AlignmentDirectional.centerStart,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              textStyle: labelStyle,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed)) {
                  return context.settingsPrimary;
                }
                return context.settingsSecondary;
              }),
              backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              side: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.focused)
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : BorderSide.none;
              }),
            ),
        child: labeled
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(KaijuanIcons.back, size: 16),
                  const SizedBox(width: 5),
                  Text('返回', style: labelStyle),
                ],
              )
            : const Icon(KaijuanIcons.back, size: 20),
      ),
    );
  }
}

/// A settings form field with its label outside the input surface.
///
/// Keeping the label out of [InputDecoration] gives settings forms one stable
/// hierarchy across text fields, dropdowns, and read-only pickers.
class AppSettingsFormField extends StatelessWidget {
  const AppSettingsFormField({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.settingsSecondary,
            fontSize: context.appCaptionSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// A grouped settings section: a near-white surface on the light canvas and an
/// elevated surface in dark appearance, with faint separators between rows.
/// Selection state is communicated by checks / accent text inside the rows —
/// never by full-bleed fill blocks.
class AppSettingsGroup extends StatelessWidget {
  const AppSettingsGroup({
    required this.children,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.settingsGroupSurface,
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: context.settingsRowDivider,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

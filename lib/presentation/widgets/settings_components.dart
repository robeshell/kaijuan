import 'package:flutter/material.dart';

import '../../core/theme.dart';

abstract final class AppSettingsMetrics {
  static const maxContentWidth = 920.0;
  static const sectionGap = 28.0;
  static const rowMinHeight = 64.0;
  static const compactRowMinHeight = 58.0;
}

extension AppSettingsContext on BuildContext {
  Color get settingsPrimary => appPrimaryText;
  Color get settingsSecondary => appSecondaryText;
  Color get settingsMuted => appMutedText;
  Color get settingsHairline =>
      appDivider.withValues(alpha: appDivider.a * 0.72);
  Color get settingsInlineSurface =>
      appColors.surfaceContainerLow.withValues(alpha: 0.72);

  double get settingsPageTitleSize =>
      MediaQuery.sizeOf(this).width <= 600 ? 26 : 28;
}

class AppSettingsContent extends StatelessWidget {
  const AppSettingsContent({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.maxWidth = AppSettingsMetrics.maxContentWidth,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppSettingsScrollView extends StatelessWidget {
  const AppSettingsScrollView({
    required this.children,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AppSettingsContent(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class AppSettingsPageHeader extends StatelessWidget {
  const AppSettingsPageHeader({
    required this.title,
    this.subtitle,
    this.onBack,
    this.backButtonKey,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Key? backButtonKey;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              IconButton(
                key: backButtonKey,
                onPressed: onBack,
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: context.settingsPrimary,
                  fontSize: context.settingsPageTitleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.55,
                ),
              ),
            ),
            if (actions.isNotEmpty) ...actions,
          ],
        ),
        if (subtitle case final value?) ...[
          SizedBox(height: onBack == null ? 6 : 4),
          Padding(
            padding: EdgeInsets.only(left: onBack == null ? 0 : 56),
            child: Text(
              value,
              style: TextStyle(
                color: context.settingsSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class AppSettingsInlinePanel extends StatelessWidget {
  const AppSettingsInlinePanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.settingsInlineSurface,
        border: Border.symmetric(
          horizontal: BorderSide(color: context.settingsHairline),
        ),
      ),
      child: child,
    );
  }
}

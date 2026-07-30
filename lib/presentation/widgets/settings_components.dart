import 'package:flutter/material.dart';

import '../../core/theme.dart';

abstract final class AppSettingsMetrics {
  static const maxContentWidth = 920.0;
  static const sectionGap = 28.0;
}

extension AppSettingsContext on BuildContext {
  Color get settingsPrimary => appPrimaryText;
  Color get settingsSecondary => appSecondaryText;
  Color get settingsMuted => appMutedText;
  Color get settingsHairline =>
      appDivider.withValues(alpha: appDivider.a * 0.72);

  /// 设置画布：比主画布再浅灰一档，纯白分组卡靠色差分层（无边框无阴影）。
  Color get settingsCanvas => Theme.of(this).brightness == Brightness.dark
      ? appColors.surfaceContainerLowest
      : const Color(0xFFF4F5F7);

  /// 卡内行间分隔线：比 hairline 再淡一档，只暗示行的边界。
  Color get settingsRowDivider => Theme.of(this).brightness == Brightness.dark
      ? const Color(0x0DFFFFFF)
      : const Color(0x0A000000);

  double get settingsPageTitleSize => appPageTitleSize;
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
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
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

/// A grouped settings section: rounded opaque card on the grey settings
/// canvas — no border, no shadow; faint separators between rows. Selection
/// state should be communicated by checks / accent text inside the rows —
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
        color: context.appColors.surfaceContainer,
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

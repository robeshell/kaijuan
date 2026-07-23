import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/pipeline_diagnostics.dart';
import '../../core/theme.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.brand,
    required this.themePreferences,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final hPad = wide ? 32.0 : 16.0;

    return Scaffold(
      body: ListenableBuilder(
        listenable: themePreferences,
        builder: (context, _) {
          return AppSettingsScrollView(
            padding: EdgeInsets.fromLTRB(hPad, wide ? 24 : 16, hPad, 40),
            children: [
              const AppSettingsPageHeader(title: '设置'),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('外观'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _SkinCard(
                    label: '跟随系统',
                    previews: const [AppSkins.standard, AppSkins.deepNight],
                    selected: themePreferences.skinId == AppSkins.systemId,
                    onTap: () => themePreferences.setSkinId(AppSkins.systemId),
                  ),
                  for (final skin in AppSkins.presets)
                    _SkinCard(
                      label: skin.name,
                      previews: [skin],
                      selected: themePreferences.skinId == skin.id,
                      onTap: () => themePreferences.setSkinId(skin.id),
                    ),
                ],
              ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('强调色'),
              const SizedBox(height: 12),
              AppSettingsGroup(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final preset in AppColors.accentPresets)
                        _AccentSwatch(
                          preset: preset,
                          selected: preset.id == themePreferences.accent.id,
                          onTap: () => themePreferences.setAccent(preset),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('关于'),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '本机阅读 · 不上传',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.settingsSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSettingsGroup(children: [_AboutBlock(brand: brand)]),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: context.settingsSecondary,
        ),
      ),
    );
  }
}

/// Selectable skin preview: a miniature canvas + card mock of the skin, with
/// the name below. Selected state is an accent frame + accent label — never
/// a fill block.
class _SkinCard extends StatelessWidget {
  const _SkinCard({
    required this.label,
    required this.previews,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// One skin, or two shown side-by-side (跟随系统 = 默认 + 深夜).
  final List<AppSkinPreset> previews;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.primary;
    final radius = BorderRadius.circular(AppRadii.menu);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 124,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: selected ? accent : context.appDivider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.menu - 1.5),
                child: Row(
                  children: [
                    for (final skin in previews)
                      Expanded(
                        child: _SkinPreview(skin: skin, accent: accent),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : context.settingsSecondary,
          ),
        ),
      ],
    );
  }
}

/// Miniature mock of a skin: canvas behind a small elevated card with fake
/// text lines and an accent mark.
class _SkinPreview extends StatelessWidget {
  const _SkinPreview({required this.skin, required this.accent});

  final AppSkinPreset skin;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget line(double widthFactor, Color color) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 3.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    return ColoredBox(
      color: skin.canvas,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.74,
          heightFactor: 0.64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: skin.elevated,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: skin.glass.border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 13,
                    height: 4,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  line(0.78, skin.glass.primaryText.withValues(alpha: 0.28)),
                  const SizedBox(height: 5),
                  line(0.52, skin.glass.secondaryText.withValues(alpha: 0.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: preset.label,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: preset.color,
            border: Border.all(
              color: selected ? context.appPrimaryText : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: SizedBox(
            width: 28,
            height: 28,
            child: selected
                ? const Icon(Icons.circle, size: 8, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

class _AboutBlock extends StatefulWidget {
  const _AboutBlock({required this.brand});

  final BrandConfig brand;

  @override
  State<_AboutBlock> createState() => _AboutBlockState();
}

class _AboutBlockState extends State<_AboutBlock> {
  late final Future<PackageInfo> _infoFuture = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _infoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info == null
            ? '…'
            : '${info.version} (${info.buildNumber})';
        final formats = widget.brand.importExtensions
            .map((e) => e.toUpperCase())
            .join(' · ');

        final rows = <(String, String, VoidCallback?)>[
          (
            '版本',
            version,
            info == null ? null : () => _copy(context, version, '已复制版本号'),
          ),
          (
            '包名',
            widget.brand.applicationId,
            () => _copy(context, widget.brand.applicationId, '已复制包名'),
          ),
          ('格式', formats, null),
          if (!kIsWeb) ('平台', defaultTargetPlatform.name, null),
          (
            '诊断',
            '导入 / 打开耗时',
            () => _copy(
              context,
              PipelineDiagnostics.instance.exportText(),
              '已复制诊断',
            ),
          ),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 14,
                  color: context.settingsHairline,
                ),
              _AboutRow(
                label: rows[i].$1,
                value: rows[i].$2,
                onCopy: rows[i].$3,
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _copy(BuildContext context, String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppSnackBar(context, toast);
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value, this.onCopy});

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: context.settingsSecondary,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onCopy != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  Icons.copy_outlined,
                  size: 15,
                  weight: 300,
                  color: context.settingsMuted,
                ),
                onPressed: onCopy,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/pipeline_diagnostics.dart';
import '../../core/theme.dart';
import '../widgets/app_components.dart';
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
          final skins = <(String, String, String?)>[
            (AppSkins.systemId, '跟随系统', '按系统外观自动切换默认与深夜'),
            for (final skin in AppSkins.presets)
              (skin.id, skin.name, skin.description),
          ];
          return AppSettingsScrollView(
            padding: EdgeInsets.fromLTRB(hPad, wide ? 24 : 16, hPad, 40),
            children: [
              const AppSettingsPageHeader(title: '设置'),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('外观'),
              const SizedBox(height: 4),
              for (final option in skins)
                AppListRow(
                  title: Text(option.$2),
                  subtitle: option.$3 == null ? null : Text(option.$3!),
                  trailing: themePreferences.skinId == option.$1
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: context.appColors.primary,
                        )
                      : null,
                  selected: themePreferences.skinId == option.$1,
                  onTap: () => themePreferences.setSkinId(option.$1),
                ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('强调色'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in AppColors.accentPresets)
                    Tooltip(
                      message: preset.label,
                      child: GestureDetector(
                        onTap: () => themePreferences.setAccent(preset),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: preset.color,
                            border: Border.all(
                              color: preset.id == themePreferences.accent.id
                                  ? context.appPrimaryText
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: preset.id == themePreferences.accent.id
                                ? const Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('关于'),
              const SizedBox(height: 8),
              Text(
                brand.displayName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本机阅读 · 不上传',
                style: TextStyle(
                  fontSize: 13,
                  color: context.settingsSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: context.settingsHairline),
              _AboutBlock(brand: brand),
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
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: context.settingsSecondary,
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

        return Column(
          children: [
            _AboutRow(
              label: '版本',
              value: version,
              onCopy: info == null
                  ? null
                  : () => _copy(context, version, '已复制版本号'),
            ),
            _AboutRow(
              label: '包名',
              value: widget.brand.applicationId,
              onCopy: () =>
                  _copy(context, widget.brand.applicationId, '已复制包名'),
            ),
            _AboutRow(label: '格式', value: formats),
            if (!kIsWeb)
              _AboutRow(label: '平台', value: defaultTargetPlatform.name),
            _AboutRow(
              label: '诊断',
              value: '导入 / 打开耗时',
              onCopy: () => _copy(
                context,
                PipelineDiagnostics.instance.exportText(),
                '已复制诊断',
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: context.settingsSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: '复制',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.copy_outlined,
                size: 16,
                weight: 300,
                color: context.settingsSecondary,
              ),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}

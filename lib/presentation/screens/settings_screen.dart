import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../app/theme_preferences.dart';
import '../controllers/backup_controller.dart';
import '../controllers/library_controller.dart';
import '../navigation/app_page_route.dart';
import 'backup_settings_screen.dart';
import 'reading_stats_screen.dart';
import '../../app_update/app_update_service.dart';
import '../../app_update/app_update_ui.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themePreferences,
    required this.backupController,
    required this.libraryController,
    this.comicReadingPreferences,
    this.bookReadingPreferences,
  });

  final ThemePreferences themePreferences;
  final BackupController backupController;
  final LibraryController libraryController;
  final ComicReadingPreferences? comicReadingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;

    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: ListenableBuilder(
        listenable: Listenable.merge([themePreferences, backupController]),
        builder: (context, _) {
          // Full content width like shelf / library (only page gutters).
          return AppSettingsScrollView(
            maxWidth: double.infinity,
            padding: EdgeInsets.fromLTRB(
              hPad,
              AppSettingsMetrics.pageTop(context),
              hPad,
              context.appContentBottomPadding,
            ),
            children: [
              const AppSettingsPageHeader(title: '设置'),
              const SizedBox(height: AppSettingsMetrics.headerGap),
              const _SectionLabel('外观'),
              const SizedBox(height: 12),
              AppSettingsGroup(
                padding: const EdgeInsets.symmetric(vertical: 14),
                children: [
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: AppSkins.presets.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _SkinCard(
                            label: '跟随系统',
                            previews: const [
                              AppSkins.standard,
                              AppSkins.deepNight,
                            ],
                            selected:
                                themePreferences.skinId == AppSkins.systemId,
                            onTap: () =>
                                themePreferences.setSkinId(AppSkins.systemId),
                          );
                        }
                        final skin = AppSkins.presets[index - 1];
                        return _SkinCard(
                          label: skin.name,
                          previews: [skin],
                          selected: themePreferences.skinId == skin.id,
                          onTap: () => themePreferences.setSkinId(skin.id),
                        );
                      },
                    ),
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
              const _SectionLabel('阅读'),
              const SizedBox(height: 12),
              AppSettingsGroup(
                children: [
                  _SettingsActionRow(
                    label: '阅读统计',
                    description: '在读、已读完与馆藏概览',
                    onTap: () => ReadingStatsScreen.open(
                      context,
                      libraryController: libraryController,
                      comicReadingPreferences: comicReadingPreferences,
                      bookReadingPreferences: bookReadingPreferences,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('数据与备份'),
              const SizedBox(height: 12),
              AppSettingsGroup(
                children: [
                  _SettingsActionRow(
                    label: 'WebDAV 备份',
                    description:
                        backupController.settings.lastSuccessfulAt == null
                        ? '备份书籍、进度、书签和笔记'
                        : '上次备份：${_formatBackupDate(backupController.settings.lastSuccessfulAt!)}',
                    onTap: () => Navigator.of(context).push<void>(
                      appPageRoute<void>(
                        (_) => BackupSettingsScreen(
                          controller: backupController,
                          libraryController: libraryController,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              const _SectionLabel('关于'),
              const SizedBox(height: 12),
              const AppSettingsGroup(children: [_AboutBlock()]),
            ],
          );
        },
      ),
    );
  }

  static String _formatBackupDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.label,
    required this.description,
    required this.onTap,
  });

  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: context.appListTitleSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        color: context.settingsSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                KaijuanIcons.chevronRight,
                size: 18,
                color: context.settingsMuted,
              ),
            ],
          ),
        ),
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
          fontSize: context.appCaptionSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
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
              width: 104,
              height: 68,
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
            fontSize: context.appCaptionSize,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
      child: Semantics(
        button: true,
        selected: selected,
        label: preset.label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
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
                    ? const Icon(
                        KaijuanIcons.circleFilled,
                        size: 8,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutBlock extends StatefulWidget {
  const _AboutBlock();

  @override
  State<_AboutBlock> createState() => _AboutBlockState();
}

class _AboutBlockState extends State<_AboutBlock> {
  late final Future<PackageInfo> _infoFuture = PackageInfo.fromPlatform();
  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _infoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info == null
            ? '…'
            : '${info.version} (${info.buildNumber})';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AboutRow(
              label: '版本',
              value: version,
              onCopy: info == null
                  ? null
                  : () => _copy(context, version, '已复制版本号'),
            ),
            if (!kIsWeb) ...[
              Divider(height: 1, indent: 14, color: context.settingsHairline),
              _AboutRow(
                label: '更新',
                value: _checkingUpdate ? '检查中…' : '检查更新',
                onTap: _checkingUpdate
                    ? null
                    : () => unawaited(_checkForUpdate(context)),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    setState(() => _checkingUpdate = true);
    try {
      final result = await AppUpdateService().checkForUpdate();
      if (!context.mounted) return;
      await showAppUpdateFlow(context, result: result);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _copy(BuildContext context, String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppSnackBar(context, toast);
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.value,
    this.onCopy,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap ?? onCopy;
    final row = ConstrainedBox(
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
                  fontSize: context.appCaptionSize,
                  color: context.settingsSecondary,
                ),
              ),
            ),
            Expanded(
              child: interactive == null
                  ? SelectableText(
                      value,
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Text(
                      value,
                      style: TextStyle(
                        fontSize: context.appCaptionSize,
                        fontWeight: FontWeight.w500,
                        // Update action uses accent; copy keeps neutral text.
                        color: onTap != null
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    if (interactive == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: interactive, child: row),
    );
  }
}

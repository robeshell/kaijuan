import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/backup/backup_format.dart';
import '../../library/remote/remote_models.dart';
import '../controllers/backup_controller.dart';
import '../controllers/library_controller.dart';
import '../navigation/app_page_route.dart';
import '../widgets/app_overlays.dart';
import '../widgets/app_components.dart';
import '../widgets/settings_components.dart';
import 'remote_source_screen.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({
    super.key,
    required this.controller,
    required this.libraryController,
  });

  final BackupController controller;
  final LibraryController libraryController;

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  late final TextEditingController _path;
  late final TextEditingController _deviceName;

  BackupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: controller.settings.remotePath);
    _deviceName = TextEditingController(text: controller.settings.deviceName);
  }

  @override
  void dispose() {
    _path.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;
    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: AppSettingsSafeArea(
        bottom: true,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final connections = controller.webDavConnections;
            return AppSettingsScrollView(
              maxWidth: AppSettingsMetrics.formMaxWidth,
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSettingsMetrics.pageTop(context),
                hPad,
                AppSpacing.x6,
              ),
              children: [
                AppSettingsPageHeader(
                  title: 'WebDAV 备份',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: AppSettingsMetrics.headerGap),
                _BackupSectionHeader(
                  title: '存储位置',
                  actionLabel: connections.isEmpty ? '添加连接' : '管理连接',
                  onAction: controller.isBusy
                      ? null
                      : () => _openConnections(context),
                ),
                const SizedBox(height: 10),
                _buildDestinationGroup(context),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _BackupSectionHeader(title: '备份选项'),
                const SizedBox(height: 10),
                _buildOptionsGroup(context),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _BackupSectionHeader(title: '备份与恢复'),
                const SizedBox(height: 10),
                _buildBackupStatus(context),
                const SizedBox(height: 14),
                _buildActions(context),
                const SizedBox(height: 20),
                _buildBackupFootnote(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDestinationGroup(BuildContext context) {
    final connections = controller.webDavConnections;
    final selectedConnection = connections
        .where(
          (connection) => connection.id == controller.settings.connectionId,
        )
        .firstOrNull;

    final connectionRow = connections.isEmpty
        ? _BackupNavigationRow(
            title: 'WebDAV 连接',
            value: '尚未添加连接',
            detail: '添加连接后即可选择远程备份目录',
            trailing: KaijuanIcons.chevronRight,
            enabled: !controller.isBusy,
            onTap: controller.isBusy ? null : () => _openConnections(context),
          )
        : AppMenuButton<String>(
            actions: [
              for (final connection in connections)
                AppMenuAction<String>(
                  value: connection.id,
                  label: connection.displayName,
                  subtitle: connection.url,
                  selected: connection.id == controller.settings.connectionId,
                ),
            ],
            onSelected: (value) => unawaited(controller.setConnection(value)),
            tooltip: '选择 WebDAV 连接',
            forceAnchored: appUsesDesktopPlatform,
            enabled: !controller.isBusy,
            child: _BackupNavigationRow(
              title: 'WebDAV 连接',
              value: selectedConnection?.displayName ?? '选择连接',
              detail: selectedConnection?.url,
              trailing: KaijuanIcons.caretDown,
              enabled: !controller.isBusy,
            ),
          );

    return AppSettingsGroup(
      children: [
        connectionRow,
        _BackupNavigationRow(
          title: '备份目录',
          value: _path.text.trim().isEmpty ? '选择远程目录' : _path.text,
          detail: selectedConnection == null ? '请先选择 WebDAV 连接' : null,
          trailing: KaijuanIcons.chevronRight,
          enabled: selectedConnection != null && !controller.isBusy,
          onTap: selectedConnection == null || controller.isBusy
              ? null
              : () => unawaited(_selectBackupFolder(selectedConnection)),
        ),
      ],
    );
  }

  Widget _buildOptionsGroup(BuildContext context) {
    final transparentBorder = UnderlineInputBorder(
      borderSide: const BorderSide(color: Colors.transparent),
    );
    return AppSettingsGroup(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: AppSettingsFormField(
            label: '设备名称',
            child: AppTextField(
              controller: _deviceName,
              readOnly: controller.isBusy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_saveDraft()),
              decoration: InputDecoration(
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 2, bottom: 6),
                border: transparentBorder,
                enabledBorder: transparentBorder,
                disabledBorder: transparentBorder,
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
        AppSettingsSwitchRow(
          title: '自动备份',
          subtitle: '每天启动时自动备份',
          value: controller.settings.autoBackup,
          onChanged: controller.isBusy
              ? null
              : (value) => unawaited(controller.setAutoBackup(value)),
        ),
      ],
    );
  }

  Future<void> _selectBackupFolder(RemoteConnection connection) async {
    final selectedPath = await Navigator.of(context).push<String>(
      appPageRoute<String>(
        (_) => RemoteBrowserScreen(
          connection: connection,
          remote: controller.remote,
          libraryController: widget.libraryController,
          mode: RemoteBrowserMode.chooseBackupFolder,
        ),
      ),
    );
    if (!mounted || selectedPath == null) return;
    try {
      await controller.setRemotePath(selectedPath);
      if (!mounted) return;
      _path.value = TextEditingValue(
        text: selectedPath,
        selection: TextSelection.collapsed(offset: selectedPath.length),
      );
    } catch (error) {
      if (mounted) showAppSnackBar(context, error.toString());
    }
  }

  Widget _buildActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          FilledButton(
            onPressed: controller.isBusy ? null : () => unawaited(_runBackup()),
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: colors.primary.withValues(alpha: 0.12),
              disabledForegroundColor: colors.primary.withValues(
                alpha: appDisabledForegroundOpacity,
              ),
            ),
            child: const Text('立即备份'),
          ),
          OutlinedButton(
            onPressed: controller.isBusy
                ? null
                : () => unawaited(_openRestore()),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.settingsPrimary,
              backgroundColor: Colors.transparent,
              side: BorderSide(color: context.settingsHairline),
            ),
            child: const Text('从备份恢复'),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupStatus(BuildContext context) {
    final settings = controller.settings;
    final progress = controller.progress;
    final status = controller.status;
    final statusText = switch (status) {
      BackupUiStatus.running => controller.message ?? '正在备份…',
      BackupUiStatus.error =>
        settings.lastError ?? controller.message ?? '备份失败',
      BackupUiStatus.idle || BackupUiStatus.success =>
        settings.lastSuccessfulAt == null
            ? '尚未备份'
            : '上次成功：${_formatDate(settings.lastSuccessfulAt!)}',
    };
    final statusColor = status == BackupUiStatus.error
        ? context.appColors.error
        : context.settingsSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (status == BackupUiStatus.running) ...[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress?.fraction,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: context.appBodySecondarySize,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupFootnote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '包含书籍、进度、书签、笔记、书单和合集；书籍文件会自动去重。',
            style: TextStyle(
              color: context.settingsMuted,
              fontSize: context.appCaptionSize,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '密码、缓存和临时文件不会上传。',
            style: TextStyle(
              color: context.settingsMuted,
              fontSize: context.appCaptionSize,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _saveDraft() async {
    try {
      await controller.setRemotePath(_path.text);
      await controller.setDeviceName(_deviceName.text);
      return true;
    } catch (error) {
      if (!mounted) return false;
      showAppSnackBar(context, error.toString());
      return false;
    }
  }

  Future<void> _runBackup() async {
    if (!await _saveDraft()) return;
    if (!mounted) return;
    await controller.runBackup();
    if (!mounted) return;
    if (controller.status == BackupUiStatus.success) {
      final run = controller.lastRun;
      showAppSnackBar(
        context,
        run == null ? '备份完成' : '备份完成，新增 ${run.uploadedObjects} 个书籍对象',
      );
    } else if (controller.message != null) {
      showAppSnackBar(context, controller.message!);
    }
  }

  Future<void> _openRestore() async {
    if (!await _saveDraft()) return;
    if (!mounted) return;
    await controller.refreshSnapshots();
    if (!mounted) return;
    if (controller.snapshots.isEmpty) {
      showAppSnackBar(context, '没有找到可恢复的备份');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.appColors.surfaceContainer,
      builder: (sheetContext) => _SnapshotSheet(
        controller: controller,
        onSelect: (manifest) async {
          Navigator.of(sheetContext).pop();
          await _confirmRestore(manifest);
        },
      ),
    );
  }

  Future<void> _confirmRestore(BackupSnapshotManifest manifest) async {
    final preview = await controller.preview(manifest);
    if (!mounted || preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复这份备份？'),
        content: Text(
          '${_formatDate(manifest.createdAt)} · ${manifest.deviceName}\n'
          '新增书籍 ${preview.newBooks} 本，已有书籍 ${preview.existingBooks} 本\n'
          '将合并进度、书签、划线、笔记、书单和 ${preview.aiChatRows} 项 AI 内容；不会删除本地内容。',
          style: TextStyle(
            color: context.settingsSecondary,
            fontSize: context.appBodySecondarySize,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开始恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await controller.restore(manifest);
    if (!mounted) return;
    if (result != null) {
      final chatText = result.restoredAiChats == 0
          ? ''
          : '，恢复 ${result.restoredAiChats} 项 AI 内容';
      showAppSnackBar(context, '恢复完成，新增 ${result.addedBooks} 本书$chatText');
    } else if (controller.message != null) {
      showAppSnackBar(context, controller.message!);
    }
  }

  Future<void> _openConnections(BuildContext context) async {
    await RemoteSourceManagementScreen.open(
      context,
      type: RemoteSourceType.webDav,
      remote: controller.remote,
      libraryController: widget.libraryController,
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _BackupSectionHeader extends StatelessWidget {
  const _BackupSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.settingsPrimary,
              fontSize: context.appListTitleSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (actionLabel case final label?)
          TextButton(
            onPressed: onAction,
            style:
                TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ).copyWith(
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  splashFactory: NoSplash.splashFactory,
                ),
            child: Text(label),
          ),
      ],
    ),
  );
}

class _BackupNavigationRow extends StatelessWidget {
  const _BackupNavigationRow({
    required this.title,
    required this.value,
    required this.trailing,
    this.detail,
    this.enabled = true,
    this.onTap,
  });

  final String title;
  final String value;
  final String? detail;
  final IconData trailing;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = enabled
        ? context.settingsPrimary
        : context.settingsMuted.withValues(alpha: 0.55);
    final secondary = enabled
        ? context.settingsSecondary
        : context.settingsMuted.withValues(alpha: 0.48);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: secondary,
                    fontSize: context.appCaptionSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary,
                    fontSize: context.appListTitleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail case final text?) ...[
                  const SizedBox(height: 2),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
                      fontSize: context.appCaptionSize,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(trailing, size: 18, color: secondary),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.appTint(0.025),
        focusColor: context.appTint(0.04),
        splashColor: Colors.transparent,
        child: content,
      ),
    );
  }
}

class _SnapshotSheet extends StatelessWidget {
  const _SnapshotSheet({required this.controller, required this.onSelect});

  final BackupController controller;
  final ValueChanged<BackupSnapshotManifest> onSelect;

  @override
  Widget build(BuildContext context) {
    final snapshots = controller.snapshots;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '选择备份',
                style: TextStyle(
                  fontSize: context.appSectionTitleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '恢复会合并到当前书库，不会删除本地内容。',
                style: TextStyle(
                  color: context.settingsSecondary,
                  fontSize: context.appCaptionSize,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: snapshots.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: context.settingsRowDivider),
                  itemBuilder: (context, index) {
                    final manifest = snapshots[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _formatDate(manifest.createdAt),
                        style: TextStyle(
                          fontSize: context.appListTitleSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${manifest.deviceName} · ${manifest.counts['items'] ?? 0} 本书',
                        style: TextStyle(
                          color: context.settingsSecondary,
                          fontSize: context.appCaptionSize,
                        ),
                      ),
                      trailing: Icon(
                        KaijuanIcons.chevronRight,
                        size: 18,
                        color: context.settingsMuted,
                      ),
                      onTap: () => onSelect(manifest),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

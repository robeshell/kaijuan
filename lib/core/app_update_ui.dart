import 'package:flutter/material.dart';

import 'app_update_installer.dart';
import 'app_update_models.dart';
import 'app_update_service.dart';

Future<void> showAppUpdateFlow(
  BuildContext context, {
  required AppUpdateCheckResult result,
  bool silentWhenUpToDate = false,
  AppUpdateInstaller? installer,
}) async {
  switch (result) {
    case AppUpdateUnavailable(:final message):
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('检查更新'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好')),
          ],
        ),
      );
    case AppUpdateUpToDate(:final currentVersion):
      if (silentWhenUpToDate || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('检查更新'),
          content: Text('已是最新版本（$currentVersion）'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好')),
          ],
        ),
      );
    case AppUpdateAvailable(:final currentVersion, :final release):
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: !release.force,
        builder: (ctx) => _UpdateAvailableDialog(
          currentVersion: currentVersion,
          release: release,
          installer: installer ?? AppUpdateInstaller(),
        ),
      );
  }
}

Future<void> runSilentAppUpdateCheck(BuildContext context) async {
  final result = await AppUpdateService().checkForUpdate();
  if (!context.mounted) return;
  if (result is! AppUpdateAvailable) return;
  await showAppUpdateFlow(context, result: result, silentWhenUpToDate: true);
}

class _UpdateAvailableDialog extends StatefulWidget {
  const _UpdateAvailableDialog({
    required this.currentVersion,
    required this.release,
    required this.installer,
  });

  final String currentVersion;
  final AppUpdateRelease release;
  final AppUpdateInstaller installer;

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      await widget.installer.applyUpdate(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted && !widget.release.force) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    return AlertDialog(
      title: Text(release.force ? '需要更新' : '发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.currentVersion} → ${release.version}'),
          if (release.changelog.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(release.changelog),
          ],
          if (_progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (!release.force)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
        TextButton(
          onPressed: _busy ? null : _install,
          child: Text(_busy ? '处理中…' : '更新'),
        ),
      ],
    );
  }
}

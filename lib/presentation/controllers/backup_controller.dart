import 'package:flutter/foundation.dart';

import '../../library/backup/backup_format.dart';
import '../../library/backup/backup_service.dart';
import '../../library/remote/remote_models.dart';
import '../../library/remote/remote_source_controller.dart';

enum BackupUiStatus { idle, running, success, error }

/// Presentation state for the settings backup page. It deliberately exposes
/// no Drift or HTTP objects to widgets.
class BackupController extends ChangeNotifier {
  BackupController({required this.service, required this.remote}) {
    remote.addListener(_onRemoteChanged);
  }

  final BackupService service;
  final RemoteSourceController remote;

  BackupUiStatus _status = BackupUiStatus.idle;
  BackupProgress? _progress;
  String? _message;
  BackupRunResult? _lastRun;
  List<BackupSnapshotManifest> _snapshots = const [];
  bool _loaded = false;
  bool _autoAttempted = false;

  BackupUiStatus get status => _status;
  BackupProgress? get progress => _progress;
  String? get message => _message;
  BackupRunResult? get lastRun => _lastRun;
  List<BackupSnapshotManifest> get snapshots => _snapshots;
  BackupTargetSettings get settings => service.settings;
  bool get isBusy => _status == BackupUiStatus.running;

  void _onRemoteChanged() => notifyListeners();

  List<RemoteConnection> get webDavConnections =>
      remote.connectionsFor(RemoteSourceType.webDav);

  Future<void> load() async {
    if (_loaded) return;
    await service.load();
    _loaded = true;
    notifyListeners();
  }

  /// Opportunistic foreground backup. Mobile OSes do not guarantee an
  /// "on-exit" callback, so this is intentionally attempted once per app
  /// session after the shell has painted.
  Future<void> maybeAutoBackup() async {
    await load();
    if (_autoAttempted ||
        !settings.autoBackup ||
        settings.connectionId == null) {
      return;
    }
    _autoAttempted = true;
    final last = settings.lastSuccessfulAt;
    if (last != null &&
        DateTime.now().toUtc().difference(last) < const Duration(hours: 24)) {
      return;
    }
    await runBackup();
  }

  Future<void> setConnection(String? id) async {
    final normalizedId = id == null || id.isEmpty ? null : id;
    final targetChanged = settings.connectionId != normalizedId;
    await service.updateSettings(
      settings.copyWith(
        connectionId: normalizedId,
        clearConnectionId: normalizedId == null,
        clearLastError: true,
        clearLastSnapshotId: targetChanged,
        clearLastSuccessfulAt: targetChanged,
      ),
    );
    if (targetChanged) _resetTargetState();
    notifyListeners();
  }

  Future<void> setRemotePath(String path) async {
    final targetChanged = settings.remotePath != path.trim();
    await service.updateSettings(
      settings.copyWith(
        remotePath: path,
        clearLastError: true,
        clearLastSnapshotId: targetChanged,
        clearLastSuccessfulAt: targetChanged,
      ),
    );
    if (targetChanged) _resetTargetState();
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    await service.updateSettings(
      settings.copyWith(
        deviceName: KaijuanBackupFormat.truncateDeviceName(name),
      ),
    );
    notifyListeners();
  }

  Future<void> setAutoBackup(bool enabled) async {
    await service.updateSettings(settings.copyWith(autoBackup: enabled));
    notifyListeners();
  }

  Future<void> setWifiOnly(bool enabled) async {
    await service.updateSettings(settings.copyWith(wifiOnly: enabled));
    notifyListeners();
  }

  Future<void> runBackup() async {
    if (isBusy) return;
    _status = BackupUiStatus.running;
    _message = null;
    _progress = null;
    notifyListeners();
    try {
      _lastRun = await service.backup(
        onProgress: (progress) {
          _progress = progress;
          _message = progress.message;
          notifyListeners();
        },
      );
      _status = BackupUiStatus.success;
      _message = '备份完成';
    } catch (error) {
      debugPrint('[Backup] backup failed: $error');
      _status = BackupUiStatus.error;
      _message = service.settings.lastError ?? '备份未完成，请检查网络和备份设置后重试';
    }
    notifyListeners();
  }

  Future<void> refreshSnapshots() async {
    try {
      _snapshots = await service.listSnapshots();
      _message = null;
      notifyListeners();
    } catch (error) {
      debugPrint('[Backup] list snapshots failed: $error');
      _snapshots = const [];
      _status = BackupUiStatus.error;
      _message = service.userMessageFor(error, fallback: '无法获取备份记录。请检查网络后重试');
      notifyListeners();
    }
  }

  Future<BackupRestorePreview?> preview(BackupSnapshotManifest manifest) async {
    try {
      return await service.preview(manifest);
    } catch (error) {
      debugPrint('[Backup] preview failed: $error');
      _status = BackupUiStatus.error;
      _message = service.userMessageFor(error, fallback: '无法读取备份信息。请重试');
      notifyListeners();
      return null;
    }
  }

  Future<BackupRestoreResult?> restore(BackupSnapshotManifest manifest) async {
    if (isBusy) return null;
    _status = BackupUiStatus.running;
    _message = null;
    _progress = null;
    notifyListeners();
    try {
      final result = await service.restore(
        manifest,
        onProgress: (progress) {
          _progress = progress;
          _message = progress.message;
          notifyListeners();
        },
      );
      _status = BackupUiStatus.success;
      _message = '恢复完成';
      await refreshSnapshots();
      return result;
    } catch (error) {
      debugPrint('[Backup] restore failed: $error');
      _status = BackupUiStatus.error;
      final reason = service.userMessageFor(error, fallback: '请检查网络后重试');
      _message = '恢复未完成。已恢复的内容会保留；$reason';
      notifyListeners();
      return null;
    }
  }

  void clearMessage() {
    if (_message == null && _status == BackupUiStatus.idle) return;
    _message = null;
    _status = BackupUiStatus.idle;
    notifyListeners();
  }

  void _resetTargetState() {
    _snapshots = const [];
    _lastRun = null;
    _autoAttempted = false;
    _status = BackupUiStatus.idle;
    _message = null;
  }

  @override
  void dispose() {
    remote.removeListener(_onRemoteChanged);
    super.dispose();
  }
}

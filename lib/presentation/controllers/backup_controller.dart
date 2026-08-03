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
    await service.updateSettings(
      settings.copyWith(
        connectionId: id,
        clearConnectionId: id == null || id.isEmpty,
        clearLastError: true,
      ),
    );
    notifyListeners();
  }

  Future<void> setRemotePath(String path) async {
    await service.updateSettings(
      settings.copyWith(remotePath: path, clearLastError: true),
    );
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    await service.updateSettings(
      settings.copyWith(deviceName: name.trim().isEmpty ? '我的设备' : name.trim()),
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
      _status = BackupUiStatus.error;
      _message = error.toString();
    }
    notifyListeners();
  }

  Future<void> refreshSnapshots() async {
    try {
      _snapshots = await service.listSnapshots();
      _message = null;
      notifyListeners();
    } catch (error) {
      _status = BackupUiStatus.error;
      _message = error.toString();
      notifyListeners();
    }
  }

  Future<BackupRestorePreview?> preview(BackupSnapshotManifest manifest) async {
    try {
      return await service.preview(manifest);
    } catch (error) {
      _status = BackupUiStatus.error;
      _message = error.toString();
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
      _status = BackupUiStatus.error;
      _message = error.toString();
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

  @override
  void dispose() {
    remote.removeListener(_onRemoteChanged);
    super.dispose();
  }
}

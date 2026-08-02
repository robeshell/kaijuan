import 'package:flutter/foundation.dart';

import '../import/import_models.dart';
import '../import/import_sources.dart';
import 'remote_models.dart';
import 'remote_source_controller.dart';

enum RemoteQueueStatus { waiting, downloading, importing, completed, failed }

extension RemoteQueueStatusLabel on RemoteQueueStatus {
  String get label => switch (this) {
    RemoteQueueStatus.waiting => '等待开始',
    RemoteQueueStatus.downloading => '正在下载',
    RemoteQueueStatus.importing => '正在导入',
    RemoteQueueStatus.completed => '已完成',
    RemoteQueueStatus.failed => '失败',
  };
}

class RemoteImportQueueItem {
  RemoteImportQueueItem({required this.connection, required this.entry});

  final RemoteConnection connection;
  final RemoteEntry entry;
  RemoteQueueStatus status = RemoteQueueStatus.waiting;
  String? error;
  ImportResult? result;
}

class RemoteImportQueueController extends ChangeNotifier {
  RemoteImportQueueController({
    required this.remote,
    required this.importOne,
    Iterable<RemoteImportQueueItem> items = const [],
  }) : _items = List.of(items);

  final RemoteSourceController remote;
  final Future<ImportResult> Function(ImportCandidate candidate) importOne;
  final List<RemoteImportQueueItem> _items;
  bool _running = false;
  bool _disposed = false;

  List<RemoteImportQueueItem> get items => List.unmodifiable(_items);
  bool get isRunning => _running;
  bool get hasPending => _items.any(
    (item) =>
        item.status == RemoteQueueStatus.waiting ||
        item.status == RemoteQueueStatus.failed,
  );
  bool get allCompleted =>
      _items.isNotEmpty &&
      _items.every((item) => item.status == RemoteQueueStatus.completed);

  void add({required RemoteConnection connection, required RemoteEntry entry}) {
    final url = entry.effectiveDownloadUri;
    if (_items.any(
      (item) =>
          item.connection.id == connection.id &&
          item.entry.effectiveDownloadUri == url,
    )) {
      return;
    }
    _items.add(RemoteImportQueueItem(connection: connection, entry: entry));
    _notify();
  }

  Future<void> start({int? onlyIndex}) async {
    if (_running) return;
    _running = true;
    _notify();
    try {
      for (var i = 0; i < _items.length; i++) {
        if (onlyIndex != null && i != onlyIndex) continue;
        final item = _items[i];
        if (item.status == RemoteQueueStatus.completed) continue;
        await _runOne(item);
      }
    } finally {
      _running = false;
      _notify();
    }
  }

  Future<void> _runOne(RemoteImportQueueItem item) async {
    item
      ..status = RemoteQueueStatus.downloading
      ..error = null
      ..result = null;
    _notify();
    try {
      final candidate = ImportCandidate(
        source: RemoteImportSource(
          remote: remote,
          connection: item.connection,
          entry: item.entry,
        ),
      );
      item.status = RemoteQueueStatus.importing;
      _notify();
      final result = await importOne(candidate);
      item.result = result;
      if (result.hasFailures) {
        item
          ..status = RemoteQueueStatus.failed
          ..error = result.failures.first.reason;
      } else {
        item.status = RemoteQueueStatus.completed;
      }
    } catch (error) {
      item
        ..status = RemoteQueueStatus.failed
        ..error = error.toString();
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class RemoteImportSource implements ImportSource {
  const RemoteImportSource({
    required this.remote,
    required this.connection,
    required this.entry,
  });

  final RemoteSourceController remote;
  final RemoteConnection connection;
  final RemoteEntry entry;

  @override
  ImportMethod get method => connection.type.importMethod;

  @override
  String get displayName => entry.displayName;

  @override
  String? get mimeType => entry.mimeType;

  @override
  Stream<List<int>> openRead() => remote.download(connection, entry);
}

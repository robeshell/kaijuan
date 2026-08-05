import 'dart:convert';

/// The backup format is deliberately independent from the Drift schema.
/// Database migrations must not make existing user-owned snapshots unreadable.
abstract final class KaijuanBackupFormat {
  static const id = 'com.kaijuan.backup';
  static const version = 1;
  static const chunkSize = 32 * 1024 * 1024;

  static bool isSha256(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  static bool isPathSegment(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value);

  static bool isExtension(String value) =>
      RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(value);
}

class BackupChunkDescriptor {
  const BackupChunkDescriptor({
    required this.index,
    required this.hash,
    required this.size,
  });

  final int index;
  final String hash;
  final int size;

  Map<String, Object?> toJson() => {'index': index, 'hash': hash, 'size': size};

  static BackupChunkDescriptor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['index'];
    final hash = raw['hash'];
    final size = raw['size'];
    if (index is! int ||
        hash is! String ||
        size is! int ||
        index < 0 ||
        !KaijuanBackupFormat.isSha256(hash) ||
        size < 0 ||
        size > KaijuanBackupFormat.chunkSize) {
      return null;
    }
    return BackupChunkDescriptor(index: index, hash: hash, size: size);
  }
}

class BackupObjectDescriptor {
  const BackupObjectDescriptor({
    required this.hash,
    required this.extension,
    required this.size,
    required this.chunks,
  });

  final String hash;
  final String extension;
  final int size;
  final List<BackupChunkDescriptor> chunks;

  Map<String, Object?> toJson() => {
    'hash': hash,
    'extension': extension,
    'size': size,
    'chunkSize': KaijuanBackupFormat.chunkSize,
    'chunks': [for (final chunk in chunks) chunk.toJson()],
  };

  static BackupObjectDescriptor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final hash = raw['hash'];
    final extension = raw['extension'];
    final size = raw['size'];
    final chunks = raw['chunks'];
    final chunkSize = raw['chunkSize'];
    if (hash is! String ||
        !KaijuanBackupFormat.isSha256(hash) ||
        extension is! String ||
        !KaijuanBackupFormat.isExtension(extension) ||
        size is! int ||
        size < 0 ||
        chunks is! List ||
        (chunkSize != null && chunkSize != KaijuanBackupFormat.chunkSize)) {
      return null;
    }
    final parsed = <BackupChunkDescriptor>[];
    var total = 0;
    for (
      var expectedIndex = 0;
      expectedIndex < chunks.length;
      expectedIndex++
    ) {
      final value = chunks[expectedIndex];
      final chunk = BackupChunkDescriptor.fromJson(value);
      if (chunk == null || chunk.index != expectedIndex) return null;
      total += chunk.size;
      if (total > size) return null;
      parsed.add(chunk);
    }
    if (total != size || (size > 0 && parsed.isEmpty)) return null;
    return BackupObjectDescriptor(
      hash: hash,
      extension: extension,
      size: size,
      chunks: parsed,
    );
  }
}

class BackupSnapshotManifest {
  const BackupSnapshotManifest({
    required this.snapshotId,
    required this.deviceId,
    required this.deviceName,
    required this.createdAt,
    required this.recordsSha256,
    required this.recordsBytes,
    required this.objects,
    required this.counts,
    this.appVersion,
    this.databaseSchemaVersion = 0,
  });

  final String snapshotId;
  final String deviceId;
  final String deviceName;
  final DateTime createdAt;
  final String recordsSha256;
  final int recordsBytes;
  final List<BackupObjectDescriptor> objects;
  final Map<String, int> counts;
  final String? appVersion;
  final int databaseSchemaVersion;

  Map<String, Object?> toJson() => {
    'format': KaijuanBackupFormat.id,
    'version': KaijuanBackupFormat.version,
    'snapshotId': snapshotId,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'databaseSchemaVersion': databaseSchemaVersion,
    'records': {
      'path': 'data.json.gz',
      'sha256': recordsSha256,
      'bytes': recordsBytes,
    },
    'objects': [for (final object in objects) object.toJson()],
    'counts': counts,
  };

  String encode() => jsonEncode(toJson());

  static BackupSnapshotManifest? fromJson(Object? raw) {
    if (raw is! Map ||
        raw['format'] != KaijuanBackupFormat.id ||
        raw['version'] != KaijuanBackupFormat.version) {
      return null;
    }
    final snapshotId = raw['snapshotId'];
    final deviceId = raw['deviceId'];
    final deviceName = raw['deviceName'];
    final createdAt = DateTime.tryParse('${raw['createdAt'] ?? ''}');
    final records = raw['records'];
    final objects = raw['objects'];
    final counts = raw['counts'];
    if (snapshotId is! String ||
        snapshotId.isEmpty ||
        !KaijuanBackupFormat.isPathSegment(snapshotId) ||
        deviceId is! String ||
        deviceId.isEmpty ||
        !KaijuanBackupFormat.isPathSegment(deviceId) ||
        deviceName is! String ||
        deviceName.length > 256 ||
        createdAt == null ||
        records is! Map ||
        objects is! List ||
        counts is! Map) {
      return null;
    }
    final recordsSha256 = records['sha256'];
    final recordsBytes = records['bytes'];
    if (recordsSha256 is! String ||
        !KaijuanBackupFormat.isSha256(recordsSha256) ||
        recordsBytes is! int ||
        recordsBytes < 0) {
      return null;
    }
    if (records['path'] != null && records['path'] != 'data.json.gz') {
      return null;
    }
    final parsedObjects = <BackupObjectDescriptor>[];
    final objectHashes = <String>{};
    for (final value in objects) {
      final object = BackupObjectDescriptor.fromJson(value);
      if (object == null) return null;
      if (!objectHashes.add(object.hash)) return null;
      parsedObjects.add(object);
    }
    final parsedCounts = <String, int>{};
    for (final entry in counts.entries) {
      if (entry.key is! String ||
          entry.value is! int ||
          (entry.value as int) < 0) {
        return null;
      }
      parsedCounts[entry.key as String] = entry.value as int;
    }
    final databaseSchemaVersion = raw['databaseSchemaVersion'];
    if (databaseSchemaVersion != null &&
        (databaseSchemaVersion is! int || databaseSchemaVersion < 0)) {
      return null;
    }
    final appVersion = raw['appVersion'];
    if (appVersion != null && appVersion is! String) return null;
    return BackupSnapshotManifest(
      snapshotId: snapshotId,
      deviceId: deviceId,
      deviceName: deviceName,
      createdAt: createdAt,
      recordsSha256: recordsSha256,
      recordsBytes: recordsBytes,
      objects: parsedObjects,
      counts: parsedCounts,
      appVersion: appVersion as String?,
      databaseSchemaVersion: databaseSchemaVersion as int? ?? 0,
    );
  }
}

/// Logical database export. Keys are content hashes instead of local integer
/// IDs or absolute paths, which makes the payload portable across installs.
class BackupRecords {
  const BackupRecords({
    required this.items,
    required this.progress,
    required this.bookmarks,
    required this.annotations,
    required this.readingLists,
    required this.readingListMembers,
    required this.collections,
    required this.collectionMembers,
    this.dayStats = const [],
    this.itemTime = const [],
    this.aiChats = const [],
    this.aiGraphs = const [],
  });

  final List<Map<String, Object?>> items;
  final List<Map<String, Object?>> progress;
  final List<Map<String, Object?>> bookmarks;
  final List<Map<String, Object?>> annotations;
  final List<Map<String, Object?>> readingLists;
  final List<Map<String, Object?>> readingListMembers;
  final List<Map<String, Object?>> collections;
  final List<Map<String, Object?>> collectionMembers;

  /// Local-day reading duration rows (`reading_day_stats`). Optional for v1
  /// snapshots written before duration export existed.
  final List<Map<String, Object?>> dayStats;

  /// Per-item cumulative seconds (`reading_item_time`), keyed by contentHash.
  final List<Map<String, Object?>> itemTime;

  /// User-authored book chat history, keyed by contentHash. API keys and
  /// provider credentials are never part of this payload.
  final List<Map<String, Object?>> aiChats;

  /// Book knowledge graphs, keyed by contentHash (see specs/ai-graph.md).
  /// Never contains API keys or provider credentials.
  final List<Map<String, Object?>> aiGraphs;

  Map<String, Object?> toJson() => {
    'format': KaijuanBackupFormat.id,
    'version': KaijuanBackupFormat.version,
    'items': items,
    'progress': progress,
    'bookmarks': bookmarks,
    'annotations': annotations,
    'readingLists': readingLists,
    'readingListMembers': readingListMembers,
    'collections': collections,
    'collectionMembers': collectionMembers,
    'dayStats': dayStats,
    'itemTime': itemTime,
    'aiChats': aiChats,
    'aiGraphs': aiGraphs,
  };

  String encode() => jsonEncode(toJson());

  static BackupRecords? fromJson(Object? raw) {
    if (raw is! Map ||
        raw['format'] != KaijuanBackupFormat.id ||
        raw['version'] != KaijuanBackupFormat.version) {
      return null;
    }

    List<Map<String, Object?>>? list(String key) {
      final value = raw[key];
      if (value is! List) return null;
      final result = <Map<String, Object?>>[];
      for (final item in value) {
        if (item is! Map) return null;
        result.add({
          for (final entry in item.entries) '${entry.key}': entry.value,
        });
      }
      return result;
    }

    /// Present list, empty when key omitted (older snapshots).
    List<Map<String, Object?>>? optionalList(String key) {
      if (!raw.containsKey(key) || raw[key] == null) return const [];
      return list(key);
    }

    final items = list('items');
    final progress = list('progress');
    final bookmarks = list('bookmarks');
    final annotations = list('annotations');
    final readingLists = list('readingLists');
    final readingListMembers = list('readingListMembers');
    final collections = list('collections');
    final collectionMembers = list('collectionMembers');
    final dayStats = optionalList('dayStats');
    final itemTime = optionalList('itemTime');
    final aiChats = optionalList('aiChats');
    final aiGraphs = optionalList('aiGraphs');
    if (items == null ||
        progress == null ||
        bookmarks == null ||
        annotations == null ||
        readingLists == null ||
        readingListMembers == null ||
        collections == null ||
        collectionMembers == null ||
        dayStats == null ||
        itemTime == null ||
        aiChats == null ||
        aiGraphs == null) {
      return null;
    }
    return BackupRecords(
      items: items,
      progress: progress,
      bookmarks: bookmarks,
      annotations: annotations,
      readingLists: readingLists,
      readingListMembers: readingListMembers,
      collections: collections,
      collectionMembers: collectionMembers,
      dayStats: dayStats,
      itemTime: itemTime,
      aiChats: aiChats,
      aiGraphs: aiGraphs,
    );
  }
}

class BackupTargetSettings {
  const BackupTargetSettings({
    this.connectionId,
    this.remotePath = 'KaijuanBackup/v1',
    this.deviceId = '',
    this.deviceName = '我的设备',
    this.autoBackup = false,
    this.wifiOnly = true,
    this.lastSnapshotId,
    this.lastSuccessfulAt,
    this.lastError,
  });

  final String? connectionId;
  final String remotePath;
  final String deviceId;
  final String deviceName;
  final bool autoBackup;
  final bool wifiOnly;
  final String? lastSnapshotId;
  final DateTime? lastSuccessfulAt;
  final String? lastError;

  BackupTargetSettings copyWith({
    String? connectionId,
    bool clearConnectionId = false,
    String? remotePath,
    String? deviceId,
    String? deviceName,
    bool? autoBackup,
    bool? wifiOnly,
    String? lastSnapshotId,
    DateTime? lastSuccessfulAt,
    String? lastError,
    bool clearLastError = false,
  }) => BackupTargetSettings(
    connectionId: clearConnectionId
        ? null
        : (connectionId ?? this.connectionId),
    remotePath: remotePath ?? this.remotePath,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    autoBackup: autoBackup ?? this.autoBackup,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    lastSnapshotId: lastSnapshotId ?? this.lastSnapshotId,
    lastSuccessfulAt: lastSuccessfulAt ?? this.lastSuccessfulAt,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );

  Map<String, Object?> toJson() => {
    'connectionId': connectionId,
    'remotePath': remotePath,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'autoBackup': autoBackup,
    'wifiOnly': wifiOnly,
    'lastSnapshotId': lastSnapshotId,
    'lastSuccessfulAt': lastSuccessfulAt?.toUtc().toIso8601String(),
    'lastError': lastError,
  };

  static BackupTargetSettings fromJson(Object? raw) {
    if (raw is! Map) return const BackupTargetSettings();
    String? string(Object? value) => value is String ? value : null;
    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return BackupTargetSettings(
      connectionId: string(raw['connectionId']),
      remotePath: string(raw['remotePath']) ?? 'KaijuanBackup/v1',
      deviceId: string(raw['deviceId']) ?? '',
      deviceName: string(raw['deviceName']) ?? '我的设备',
      autoBackup: raw['autoBackup'] == true,
      wifiOnly: raw['wifiOnly'] != false,
      lastSnapshotId: string(raw['lastSnapshotId']),
      lastSuccessfulAt: date(raw['lastSuccessfulAt']),
      lastError: string(raw['lastError']),
    );
  }
}

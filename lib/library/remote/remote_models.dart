import '../../domain/reader_models.dart';
import '../import/import_sources.dart';

enum RemoteSourceType { webDav, opds }

extension RemoteSourceTypeLabel on RemoteSourceType {
  String get label => switch (this) {
    RemoteSourceType.webDav => 'WebDAV',
    RemoteSourceType.opds => 'OPDS',
  };

  String get managementTitle => switch (this) {
    RemoteSourceType.webDav => '云端存储',
    RemoteSourceType.opds => '在线书库',
  };

  ImportMethod get importMethod => switch (this) {
    RemoteSourceType.webDav => ImportMethod.webDav,
    RemoteSourceType.opds => ImportMethod.opds,
  };
}

enum RemoteConnectionStatus {
  idle,
  checking,
  connected,
  unreachable,
  authenticationFailed,
  error,
}

extension RemoteConnectionStatusLabel on RemoteConnectionStatus {
  String get label => switch (this) {
    RemoteConnectionStatus.idle => '未测试',
    RemoteConnectionStatus.checking => '连接中',
    RemoteConnectionStatus.connected => '正常',
    RemoteConnectionStatus.unreachable => '无法连接',
    RemoteConnectionStatus.authenticationFailed => '认证失败',
    RemoteConnectionStatus.error => '连接异常',
  };
}

class RemoteCredentials {
  const RemoteCredentials({this.username = '', this.password = ''});

  final String username;
  final String password;

  bool get isEmpty => username.isEmpty && password.isEmpty;
}

class RemoteConnection {
  const RemoteConnection({
    required this.id,
    required this.type,
    required this.displayName,
    required this.url,
    required this.status,
    this.lastError,
    this.lastCheckedAt,
    this.createdAt,
    this.updatedAt,
    this.allowBadCertificate = false,
  });

  final String id;
  final RemoteSourceType type;
  final String displayName;
  final String url;
  final RemoteConnectionStatus status;
  final String? lastError;
  final DateTime? lastCheckedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool allowBadCertificate;

  RemoteConnection copyWith({
    String? displayName,
    String? url,
    RemoteConnectionStatus? status,
    String? lastError,
    bool clearLastError = false,
    DateTime? lastCheckedAt,
    DateTime? updatedAt,
    bool? allowBadCertificate,
  }) {
    return RemoteConnection(
      id: id,
      type: type,
      displayName: displayName ?? this.displayName,
      url: url ?? this.url,
      status: status ?? this.status,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      allowBadCertificate: allowBadCertificate ?? this.allowBadCertificate,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'displayName': displayName,
    'url': url,
    'status': status.name,
    'lastError': lastError,
    'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'allowBadCertificate': allowBadCertificate,
  };

  static RemoteConnection? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final typeName = json['type'];
    final displayName = json['displayName'];
    final url = json['url'];
    if (id is! String ||
        typeName is! String ||
        displayName is! String ||
        url is! String) {
      return null;
    }
    final type = RemoteSourceType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (type == null) return null;
    final status = RemoteConnectionStatus.values
        .where((value) => value.name == json['status'])
        .firstOrNull;
    DateTime? parseDate(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return RemoteConnection(
      id: id,
      type: type,
      displayName: displayName,
      url: url,
      status: status ?? RemoteConnectionStatus.idle,
      lastError: json['lastError'] as String?,
      lastCheckedAt: parseDate(json['lastCheckedAt']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      allowBadCertificate: json['allowBadCertificate'] == true,
    );
  }
}

/// A normalized item exposed by either a WebDAV directory or an OPDS feed.
class RemoteEntry {
  const RemoteEntry({
    required this.uri,
    required this.displayName,
    required this.isDirectory,
    this.title,
    this.size = -1,
    this.mimeType,
    this.modifiedAt,
    this.description,
    this.author,
    this.coverUri,
    this.downloadUri,
    this.navigationUri,
  });

  final String uri;
  final String displayName;
  final bool isDirectory;
  final String? title;
  final int size;
  final String? mimeType;
  final DateTime? modifiedAt;
  final String? description;
  final String? author;
  final String? coverUri;
  final String? downloadUri;
  final String? navigationUri;

  String get effectiveDownloadUri => downloadUri ?? uri;
  String get effectiveNavigationUri => navigationUri ?? uri;
  String get displayTitle => title ?? displayName;

  bool get isSupportedFile {
    final format = ReaderFormat.fromFileName(displayName);
    return format != null &&
        const {
          ReaderFormat.cbz,
          ReaderFormat.zip,
          ReaderFormat.epub,
          ReaderFormat.fb2,
          ReaderFormat.mobi,
          ReaderFormat.azw3,
          ReaderFormat.pdf,
          ReaderFormat.txt,
          ReaderFormat.markdown,
        }.contains(format);
  }
}

class RemoteProbeResult {
  const RemoteProbeResult({
    required this.entries,
    this.error,
    this.authenticationFailed = false,
    this.nextUri,
    this.searchUri,
  });

  final List<RemoteEntry> entries;
  final String? error;
  final bool authenticationFailed;
  final String? nextUri;
  final String? searchUri;

  bool get isSuccess => error == null;
}

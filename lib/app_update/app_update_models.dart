class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.url,
    required this.force,
    required this.changelog,
    this.versionCode,
    this.size,
    this.md5,
  });

  final String version;
  final int? versionCode;
  final bool force;
  final String changelog;
  final String url;
  final int? size;
  final String? md5;

  factory AppUpdateRelease.fromJson(Map<String, dynamic> json) {
    return AppUpdateRelease(
      version: (json['version'] as String? ?? '').trim(),
      versionCode: json['versionCode'] is int
          ? json['versionCode'] as int
          : int.tryParse('${json['versionCode'] ?? ''}'),
      force: json['force'] == true,
      changelog: (json['changelog'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse('${json['size'] ?? ''}'),
      md5: (json['md5'] as String?)?.trim(),
    );
  }
}

sealed class AppUpdateCheckResult {
  const AppUpdateCheckResult();
}

class AppUpdateUnavailable extends AppUpdateCheckResult {
  const AppUpdateUnavailable([this.message = '暂时无法检查更新']);
  final String message;
}

class AppUpdateUpToDate extends AppUpdateCheckResult {
  const AppUpdateUpToDate({required this.currentVersion});
  final String currentVersion;
}

class AppUpdateAvailable extends AppUpdateCheckResult {
  const AppUpdateAvailable({
    required this.currentVersion,
    required this.release,
  });

  final String currentVersion;
  final AppUpdateRelease release;
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_config.dart';
import 'app_update_models.dart';

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (kIsWeb) {
      return const AppUpdateUnavailable('当前平台不支持应用内更新');
    }

    final info = await PackageInfo.fromPlatform();
    final platformKey = _platformKey();
    if (platformKey == null) {
      return const AppUpdateUnavailable('当前平台不支持应用内更新');
    }

    late final Map<String, dynamic> root;
    try {
      final res = await _client
          .get(Uri.parse(AppUpdateConfig.updateJsonUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return AppUpdateUnavailable('检查失败（${res.statusCode}）');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const AppUpdateUnavailable('更新信息格式无效');
      }
      root = decoded;
    } catch (_) {
      return const AppUpdateUnavailable('暂时无法检查更新');
    }

    final platformJson = root[platformKey];
    if (platformJson is! Map<String, dynamic>) {
      return AppUpdateUpToDate(currentVersion: info.version);
    }

    final release = AppUpdateRelease.fromJson(platformJson);
    if (release.version.isEmpty || release.url.isEmpty) {
      return AppUpdateUpToDate(currentVersion: info.version);
    }

    final newer = _isNewer(
      localVersion: info.version,
      localBuild: int.tryParse(info.buildNumber),
      remote: release,
      preferBuildNumber: platformKey == 'android',
    );
    if (!newer) {
      return AppUpdateUpToDate(currentVersion: info.version);
    }
    return AppUpdateAvailable(currentVersion: info.version, release: release);
  }

  static String? _platformKey() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'mac';
    return null;
  }

  static bool _isNewer({
    required String localVersion,
    required int? localBuild,
    required AppUpdateRelease remote,
    required bool preferBuildNumber,
  }) {
    if (preferBuildNumber &&
        remote.versionCode != null &&
        localBuild != null) {
      return remote.versionCode! > localBuild;
    }
    return compareVersions(remote.version, localVersion) > 0;
  }

  /// Returns negative / zero / positive like Comparator.
  static int compareVersions(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _parseVersion(String raw) {
    final core = raw.split(RegExp(r'[-+]')).first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}

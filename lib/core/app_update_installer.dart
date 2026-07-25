import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_models.dart';

class AppUpdateInstaller {
  AppUpdateInstaller({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Opens store / downloads package and hands off to the OS installer.
  Future<void> applyUpdate(
    AppUpdateRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw StateError('Web 不支持应用内更新');
    }

    if (Platform.isIOS) {
      final uri = Uri.parse(release.url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('无法打开更新链接');
      return;
    }

    final file = await _download(release, onProgress: onProgress);
    if (Platform.isMacOS) {
      await Process.start('open', [file.path]);
      return;
    }
    if (Platform.isWindows) {
      await Process.start(file.path, [], runInShell: true);
      return;
    }
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw StateError(result.message);
      }
      return;
    }
    throw StateError('当前平台不支持安装更新包');
  }

  Future<File> _download(
    AppUpdateRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse(release.url);
    final request = http.Request('GET', uri);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('下载失败（${response.statusCode}）');
    }

    final total = response.contentLength ?? release.size;
    final dir = await getTemporaryDirectory();
    final name = p.basename(uri.path);
    final safeName = name.isEmpty ? 'update.bin' : name;
    final file = File(p.join(dir.path, 'kai-update-$safeName'));
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total != null && total > 0) {
        onProgress?.call((received / total).clamp(0.0, 1.0));
      }
    }
    await sink.close();
    onProgress?.call(1);
    return file;
  }
}

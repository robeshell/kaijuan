import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createDefaultRemoteClient() {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  return IOClient(client);
}

http.Client createLenientRemoteClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..badCertificateCallback = (_, _, _) => true;
  return IOClient(client);
}

DateTime? parseRemoteHttpDate(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return HttpDate.parse(value).toUtc();
  } catch (_) {
    return null;
  }
}

String? remoteTlsError(Object error) {
  if (error is! TlsException) return null;
  final text = error.message.toLowerCase();
  if (text.contains('certificate')) {
    return '服务器证书不被信任，可在连接设置中允许自签名证书';
  }
  return 'SSL/TLS 连接失败：${error.message}';
}

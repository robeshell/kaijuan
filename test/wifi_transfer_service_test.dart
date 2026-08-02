import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/library/import/import_models.dart';
import 'package:kaijuan/library/import/import_sources.dart';
import 'package:kaijuan/library/import/wifi_transfer_service.dart';

void main() {
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('kaijuan_wifi_');
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('starts a token-protected upload page and stops cleanly', () async {
    final service = WifiTransferService(
      supportDirectory: supportDirectory,
      onImport: (_) async => const ImportResult(added: 1),
      ipProvider: () async => '192.168.1.20',
      sessionDuration: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    await service.start();
    final pageUri = Uri.parse(service.url!);
    final client = HttpClient();
    addTearDown(client.close);

    final localPageUri = pageUri.replace(
      host: InternetAddress.loopbackIPv4.address,
    );
    final response = await (await client.getUrl(localPageUri)).close();
    expect(response.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(response).join(), contains('WiFi 传书'));

    final unauthorized = await (await client.getUrl(
      localPageUri.replace(queryParameters: {'token': 'wrong'}),
    )).close();
    expect(unauthorized.statusCode, HttpStatus.unauthorized);

    await service.stop();
    expect(service.isRunning, isFalse);
    expect(service.url, isNull);
  });

  test(
    'streams an upload into the shared import callback and cleans temp file',
    () async {
      LocalFileImportSource? receivedSource;
      final service = WifiTransferService(
        supportDirectory: supportDirectory,
        onImport: (candidate) async {
          receivedSource = candidate.source as LocalFileImportSource;
          final bytes = await receivedSource!.file.readAsBytes();
          expect(bytes, utf8.encode('hello book'));
          expect(candidate.method, ImportMethod.wifi);
          expect(candidate.displayName, 'book.txt');
          return const ImportResult(added: 1);
        },
        ipProvider: () async => '192.168.1.20',
        sessionDuration: const Duration(minutes: 5),
      );
      addTearDown(service.dispose);
      await service.start();

      final pageUri = Uri.parse(service.url!);
      final uploadUri = pageUri.replace(
        host: InternetAddress.loopbackIPv4.address,
        path: '/upload',
      );
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(uploadUri);
      request.headers.set(
        'X-Kaijuan-File-Name',
        Uri.encodeComponent('../private/book.txt'),
      );
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.add(utf8.encode('hello book'));
      final response = await request.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(receivedSource, isNotNull);
      expect(await receivedSource!.file.exists(), isFalse);
      expect(service.phase, WifiTransferPhase.completed);
      expect(service.lastResult?.added, 1);
    },
  );

  test('rejects an upload that exceeds the configured limit', () async {
    var callbackCount = 0;
    final service = WifiTransferService(
      supportDirectory: supportDirectory,
      onImport: (_) async {
        callbackCount++;
        return const ImportResult(added: 1);
      },
      ipProvider: () async => '192.168.1.20',
      maxFileBytes: 4,
    );
    addTearDown(service.dispose);
    await service.start();

    final pageUri = Uri.parse(service.url!);
    final uploadUri = pageUri.replace(
      host: InternetAddress.loopbackIPv4.address,
      path: '/upload',
    );
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.postUrl(uploadUri);
    request.headers.set(
      'X-Kaijuan-File-Name',
      Uri.encodeComponent('too-large.txt'),
    );
    request.add([1, 2, 3, 4, 5]);
    final response = await request.close();

    expect(response.statusCode, HttpStatus.requestEntityTooLarge);
    expect(callbackCount, 0);
  });
}

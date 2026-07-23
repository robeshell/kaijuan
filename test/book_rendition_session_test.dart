import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/readers/book/book_loopback_server.dart';
import 'package:kaijuan/readers/book/book_rendition_session.dart';

void main() {
  _NetworkTestBinding();

  late Directory tempDirectory;
  late File bookFile;
  final sessions = <BookRenditionSession>[];

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'kaika_rendition_session_',
    );
    bookFile = File('${tempDirectory.path}/book.epub');
    await bookFile.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4]);
  });

  tearDown(() async {
    for (final session in sessions) {
      await session.close();
    }
    sessions.clear();
    await BookLoopbackServer.debugStop();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<BookRenditionSession> openSession({
    BookRenditionTimingListener? onTiming,
  }) async {
    final session = await BookRenditionSession.open(
      bookFile,
      onTiming: onTiming,
    );
    sessions.add(session);
    return session;
  }

  test('loopback exposes only the mounted book route', () async {
    final session = await openSession();
    final client = HttpClient();
    addTearDown(client.close);

    final response = await (await client.getUrl(session.bookUri)).close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'application/epub+zip');
    expect(bytes, await bookFile.readAsBytes());
    expect(session.bookUri.path, matches(r'^/books/\d+\.epub$'));

    final missing = await (await client.getUrl(
      session.bookUri.resolve('/not-a-book.epub'),
    )).close();
    expect(missing.statusCode, HttpStatus.notFound);

    final absolutePath = await (await client.getUrl(
      session.bookUri.resolve('/book/${Uri.encodeComponent(bookFile.path)}'),
    )).close();
    expect(absolutePath.statusCode, HttpStatus.notFound);

    final post = await (await client.postUrl(session.bookUri)).close();
    expect(post.statusCode, HttpStatus.methodNotAllowed);
  });

  test('closing a session unmounts the book but keeps the shared origin', () async {
    final first = await openSession();
    final origin = first.indexUri.origin;
    final bookUri = first.bookUri;
    final client = HttpClient();
    addTearDown(client.close);

    await first.close();
    sessions.remove(first);

    final unmounted = await (await client.getUrl(bookUri)).close();
    expect(unmounted.statusCode, HttpStatus.notFound);

    final second = await openSession();
    expect(second.indexUri.origin, origin);

    final assets = await (await client.getUrl(second.indexUri)).close();
    expect(assets.statusCode, HttpStatus.ok);
  });

  test('two sessions can mount different books on the shared server', () async {
    final other = File('${tempDirectory.path}/other.epub');
    await other.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 9, 8, 7, 6]);

    final first = await openSession();
    final second = await BookRenditionSession.open(other);
    sessions.add(second);
    final client = HttpClient();
    addTearDown(client.close);

    expect(first.bookUri, isNot(second.bookUri));
    expect(first.indexUri.origin, second.indexUri.origin);

    final firstBytes = await (await client.getUrl(first.bookUri))
        .close()
        .then(
          (response) => response.fold<List<int>>(
            <int>[],
            (all, chunk) => all..addAll(chunk),
          ),
        );
    final secondBytes = await (await client.getUrl(second.bookUri))
        .close()
        .then(
          (response) => response.fold<List<int>>(
            <int>[],
            (all, chunk) => all..addAll(chunk),
          ),
        );
    expect(firstBytes, await bookFile.readAsBytes());
    expect(secondBytes, await other.readAsBytes());
  });

  test(
    'loopback serves declared Foliate assets and rejects traversal',
    () async {
      final session = await openSession();
      final client = HttpClient();
      addTearDown(client.close);

      final index = await (await client.getUrl(session.indexUri)).close();
      expect(index.statusCode, HttpStatus.ok);
      expect(index.headers.contentType?.mimeType, 'text/html');

      final probe = await (await client.getUrl(session.probeUri)).close();
      final probeMarkup = await probe.transform(const Utf8Decoder()).join();
      expect(probe.statusCode, HttpStatus.ok);
      expect(probe.headers.contentType?.mimeType, 'text/html');
      expect(probeMarkup, contains('./src/metadata-probe.js'));

      final traversal = session.indexUri.replace(
        path: '/foliate-js/%2e%2e/pubspec.yaml',
      );
      final rejected = await (await client.getUrl(traversal)).close();
      expect(rejected.statusCode, HttpStatus.notFound);
    },
  );

  test('new WebView lease invalidates every older callback', () async {
    final timings = <BookRenditionTiming>[];
    final session = await openSession(onTiming: timings.add);
    final evaluated = <String>[];

    final first = session.attachWebView((source) async {
      evaluated.add('first:$source');
      return 'first-result';
    });
    expect(await session.evaluate(first, 'one'), 'first-result');

    final second = session.attachWebView((source) async {
      evaluated.add('second:$source');
      return 'second-result';
    });
    expect(first.isCurrent, isFalse);
    expect(await session.evaluate(first, 'late'), isNull);
    expect(await session.evaluate(second, 'two'), 'second-result');
    expect(evaluated, ['first:one', 'second:two']);

    session.invalidateWebView(first);
    expect(
      second.isCurrent,
      isTrue,
      reason: 'stale lease cannot kill new view',
    );
    session.invalidateWebView(second);
    expect(second.isCurrent, isFalse);

    expect(timings.first.step, 'server-ready');
    expect(
      timings.where((timing) => timing.step == 'webview-created'),
      hasLength(2),
    );
    expect(timings.every((timing) => !timing.sincePrevious.isNegative), isTrue);
  });

  test('close is idempotent and rejects new attachments', () async {
    final session = await openSession();
    await session.close();
    await session.close();

    expect(session.isClosed, isTrue);
    expect(() => session.attachWebView((_) async => null), throwsStateError);
  });
}

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

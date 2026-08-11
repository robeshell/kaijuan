import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/presentation/controllers/book_tts_controller.dart';

void main() {
  test('reports unavailable bridge without creating a speech engine', () async {
    var changes = 0;
    final controller = BookTtsController(
      isReaderDisposed: () => false,
      isReaderReady: () => true,
      beforeStart: () {},
      onPlaybackStarted: () {},
      onChanged: () => changes++,
    );

    await controller.start();

    expect(controller.status, BookTtsStatus.idle);
    expect(controller.userMessage, '听书引擎未就绪');
    expect(changes, 1);
    await controller.dispose();
  });

  test(
    'empty Foliate sentence remains idle and exposes recovery copy',
    () async {
      var beforeStart = 0;
      var playbackStarted = 0;
      final controller = BookTtsController(
        isReaderDisposed: () => false,
        isReaderReady: () => true,
        beforeStart: () => beforeStart++,
        onPlaybackStarted: () => playbackStarted++,
        onChanged: () {},
      );
      controller.attachBridge(
        here: () async => '  ',
        next: () async => null,
        previous: () async => null,
        stop: () async {},
      );

      await controller.start();

      expect(beforeStart, 1);
      expect(playbackStarted, 0);
      expect(controller.active, isFalse);
      expect(controller.userMessage, '当前位置没有可读文本');
      await controller.dispose();
    },
  );

  test('idle rate updates are bounded and disposal is idempotent', () async {
    final controller = BookTtsController(
      isReaderDisposed: () => false,
      isReaderReady: () => true,
      beforeStart: () {},
      onPlaybackStarted: () {},
      onChanged: () {},
    );

    await controller.setRate(8);
    expect(controller.rate, 2);
    await controller.setRate(-1);
    expect(controller.rate, 0.5);

    await controller.dispose();
    await controller.dispose();
    expect(controller.status, BookTtsStatus.idle);
  });
}

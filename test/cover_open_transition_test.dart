import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/presentation/navigation/cover_open_page_route.dart';
import 'package:kaijuan/presentation/widgets/reader/book_cover_hero.dart';

void main() {
  tearDown(CoverFlightSession.end);

  group('CoverFlightGeometry', () {
    test('rejects tiny or empty rects', () {
      expect(CoverFlightGeometry.isUsable(null), isFalse);
      expect(CoverFlightGeometry.isUsable(Rect.zero), isFalse);
      expect(
        CoverFlightGeometry.isUsable(const Rect.fromLTWH(0, 0, 4, 40)),
        isFalse,
      );
      expect(
        CoverFlightGeometry.isUsable(const Rect.fromLTWH(10, 20, 80, 110)),
        isTrue,
      );
    });

    test('destination keeps source aspect and sits in padded safe area', () {
      const viewport = Size(400, 800);
      const safe = EdgeInsets.fromLTRB(0, 50, 0, 30);
      final dest = CoverFlightGeometry.destinationRect(
        viewport: viewport,
        safePadding: safe,
        aspectRatio: 80 / 110,
        shortViewport: false,
      );
      expect(dest.width / dest.height, closeTo(80 / 110, 0.001));
      expect(dest.left, greaterThanOrEqualTo(safe.left));
      expect(dest.top, greaterThanOrEqualTo(safe.top));
      expect(dest.right, lessThanOrEqualTo(viewport.width - safe.right));
      expect(dest.bottom, lessThanOrEqualTo(viewport.height - safe.bottom));
    });

    test('flight rect starts at source, ends at dest, and lifts mid-path', () {
      const source = Rect.fromLTWH(20, 600, 80, 110);
      const dest = Rect.fromLTWH(100, 80, 200, 275);
      expect(CoverFlightGeometry.flightRect(source, dest, 0), source);
      final end = CoverFlightGeometry.flightRect(source, dest, 1);
      expect(end.left, closeTo(dest.left, 0.001));
      expect(end.top, closeTo(dest.top, 0.001));
      expect(end.width, closeTo(dest.width, 0.001));
      expect(end.height, closeTo(dest.height, 0.001));

      final mid = CoverFlightGeometry.flightRect(source, dest, 0.5);
      final straight = Offset.lerp(source.center, dest.center, 0.5)!;
      expect(mid.center.dy, lessThan(straight.dy));
    });

    test('cubic bezier hits endpoints', () {
      const a = Offset(0, 100);
      const b = Offset(10, 40);
      const c = Offset(90, 20);
      const d = Offset(100, 0);
      expect(CoverFlightGeometry.cubicBezier(a, b, c, d, 0), a);
      expect(CoverFlightGeometry.cubicBezier(a, b, c, d, 1), d);
    });

    test('arc-length t advances the cover at even speed', () {
      const source = Rect.fromLTWH(20, 600, 80, 110);
      const dest = Rect.fromLTWH(100, 80, 200, 275);
      final path = CoverFlightPath(source: source, dest: dest);
      final d01 = (path.centerAt(0.25) - path.centerAt(0)).distance;
      final d12 = (path.centerAt(0.50) - path.centerAt(0.25)).distance;
      final d23 = (path.centerAt(0.75) - path.centerAt(0.50)).distance;
      final d34 = (path.centerAt(1.00) - path.centerAt(0.75)).distance;
      expect(d01, greaterThan(0));
      expect(d12 / d01, closeTo(1, 0.12));
      expect(d23 / d12, closeTo(1, 0.12));
      expect(d34 / d23, closeTo(1, 0.12));
    });

    test('flight time curve is linear', () {
      expect(CoverFlightGeometry.flightTime.transform(0), 0);
      expect(CoverFlightGeometry.flightTime.transform(0.25), 0.25);
      expect(CoverFlightGeometry.flightTime.transform(0.5), 0.5);
      expect(CoverFlightGeometry.flightTime.transform(1), 1);
    });
  });

  testWidgets('CoverFlightHandle.resolve prefers the matching item', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              CoverFlightHandle(
                itemId: 'a',
                child: SizedBox(width: 40, height: 60),
              ),
              CoverFlightHandle(
                itemId: 'b',
                child: SizedBox(width: 40, height: 60),
              ),
            ],
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    final a = CoverFlightHandle.resolve(context, 'a');
    final b = CoverFlightHandle.resolve(context, 'b');
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(a!.left, lessThan(b!.left));
    expect(a.width, closeTo(40, 0.5));
    expect(b.width, closeTo(40, 0.5));
  });

  testWidgets('cover flight paints the moving cover at mid-path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CoverFlightTransition(
          animation: AlwaysStoppedAnimation<double>(0.45),
          sourceRect: Rect.fromLTWH(24, 80, 72, 100),
          coverPath: null,
          title: 'Demo',
          backdropColor: Color(0xFFF7F7F7),
          child: Scaffold(body: Text('reader')),
        ),
      ),
    );

    expect(find.byType(CoverFlightLeaf), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('reader', skipOffstage: false), findsOneWidget);
    const source = Rect.fromLTWH(24, 80, 72, 100);
    final dest = CoverFlightGeometry.destinationRect(
      viewport: const Size(800, 600),
      safePadding: EdgeInsets.zero,
      aspectRatio: source.size.aspectRatio,
      shortViewport: false,
    );
    final mid = CoverFlightPath(source: source, dest: dest).rectAt(0.45);
    final box = tester.renderObject<RenderBox>(find.byType(CoverFlightLeaf));
    expect(box.size.width, closeTo(mid.width, 4));
    expect(box.size.height, closeTo(mid.height, 4));
    expect(box.size.width, lessThan(dest.width + 1));
  });

  testWidgets('cover open route flies when a source rect is present', (
    tester,
  ) async {
    late CoverOpenPageRoute<void> route;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                route = CoverOpenPageRoute<void>(
                  sourceRect: const Rect.fromLTWH(24, 80, 72, 100),
                  coverPath: null,
                  title: 'Demo',
                  backdropColor: const Color(0xFFF7F7F7),
                  itemId: 'demo',
                  builder: (_) => const Scaffold(body: Text('reader')),
                );
                Navigator.of(context).push<void>(route);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(route.transitionDuration, CoverOpenPageRoute.flightDuration);
    expect(
      route.reverseTransitionDuration,
      CoverOpenPageRoute.flightReverseDuration,
    );
    await tester.pump();
    expect(CoverFlightSession.inFlightItemId.value, 'demo');

    await tester.pump(CoverOpenPageRoute.flightDuration);
    await tester.pump(const Duration(milliseconds: 16));
    expect(route.opaque, isTrue);
    expect(find.text('reader'), findsOneWidget);

    route.preparePreviousRoute();
    expect(route.opaque, isFalse);

    Navigator.of(tester.element(find.text('reader'))).pop();
    await tester.pump();
    await tester.pump(CoverOpenPageRoute.flightReverseDuration);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('reader'), findsNothing);
    expect(CoverFlightSession.inFlightItemId.value, isNull);
  });

  testWidgets('cover open route fades when there is no source rect', (
    tester,
  ) async {
    late CoverOpenPageRoute<void> route;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                route = CoverOpenPageRoute<void>(
                  coverPath: null,
                  title: 'Demo',
                  backdropColor: const Color(0xFFF7F7F7),
                  builder: (_) => const Scaffold(body: Text('reader')),
                );
                Navigator.of(context).push<void>(route);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, CoverOpenPageRoute.fadeDuration);
    expect(CoverFlightSession.inFlightItemId.value, isNull);
    expect(find.text('reader'), findsOneWidget);
  });
}

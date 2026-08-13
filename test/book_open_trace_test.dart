import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/pipeline_diagnostics.dart';
import 'package:kaijuan/readers/book/book_open_trace.dart';

void main() {
  setUp(PipelineDiagnostics.instance.clear);

  test('parseConsole reads KaikaOpen marks', () {
    final parsed = BookOpenTrace.parseConsole(
      'KaikaOpen step=fetch-ready t=430 d=12 bytes=20480',
    );
    expect(parsed, isNotNull);
    expect(parsed!.step, 'fetch-ready');
    expect(parsed.jsElapsedMs, 430);
    expect(parsed.jsDeltaMs, 12);
    expect(parsed.extra, 'bytes=20480');
    expect(BookOpenTrace.parseConsole('book.js'), isNull);
  });

  test('absorbConsole and summary show one open-chain table', () {
    final clock = Stopwatch()..start();
    final trace = BookOpenTrace(
      title: 'Demo',
      format: 'epub',
      clock: clock,
    );
    trace.mark('open-start');
    trace.mark('paths-ready');
    expect(
      trace.absorbConsole('KaikaOpen step=book-js-deps t=280 d=200'),
      isTrue,
    );
    trace.mark('first-relocation');

    final summary = trace.formatSummary(reason: 'first-relocation');
    expect(summary, contains('open chain (Demo · epub)'));
    expect(summary, contains('open-start'));
    expect(summary, contains('js:book-js-deps'));
    expect(summary, contains('js=280ms'));
    expect(summary, contains('TOTAL to first-relocation'));
    expect(summary, contains('slowest:'));

    final dumped = trace.dumpSummary();
    expect(dumped, isNotEmpty);
    expect(trace.dumpSummary(), isEmpty, reason: 'summary prints once');
    expect(PipelineDiagnostics.instance.exportText(), contains('[BookOpen]'));
  });

  test('summary does not rank teardown idle as the hotspot', () {
    final trace = BookOpenTrace(title: 'Demo', format: 'epub');
    trace.addStepForTest(
      const BookOpenStep(
        step: 'open-start',
        elapsed: Duration.zero,
        delta: Duration.zero,
      ),
    );
    trace.addStepForTest(
      const BookOpenStep(
        step: 'publication-parsed',
        elapsed: Duration(milliseconds: 200),
        delta: Duration(milliseconds: 200),
      ),
    );
    trace.addStepForTest(
      const BookOpenStep(
        step: 'webview-invalidated',
        elapsed: Duration(milliseconds: 4000),
        delta: Duration(milliseconds: 3800),
      ),
    );
    final summary = trace.formatSummary(reason: 'disposed');
    expect(summary, contains('webview-invalidated'));
    expect(summary, isNot(contains('slowest: webview-invalidated')));
    expect(summary, contains('slowest: publication-parsed Δ200ms'));
  });
}

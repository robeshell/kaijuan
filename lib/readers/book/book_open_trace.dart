import 'package:flutter/foundation.dart';

import '../../core/pipeline_diagnostics.dart';

/// End-to-end book-open timeline: tap → first painted page.
///
/// [BookRenditionSession] still records its own loopback/WebView marks. This
/// trace starts earlier (path resolve) and also absorbs JS `KaikaOpen` lines
/// so one table shows where the open actually waits.
class BookOpenTrace {
  BookOpenTrace({
    this.title = '',
    this.format = '',
    Stopwatch? clock,
  }) : _clock = clock ?? (Stopwatch()..start());

  static final _jsLine = RegExp(
    r'^KaikaOpen step=(\S+)(?: t=(\d+))?(?: d=(\d+))?(?: (.+))?$',
  );

  /// Steps slower than this are flagged in the summary table.
  static const slowDelta = Duration(milliseconds: 80);

  /// Idle / teardown gaps — keep in the table, ignore when ranking hotspots.
  static const _ignoreInSlowest = {
    'webview-invalidated',
    'renderer-gone',
  };

  final String title;
  final String format;
  final Stopwatch _clock;
  final List<BookOpenStep> _steps = <BookOpenStep>[];
  bool _summarized = false;

  List<BookOpenStep> get steps => List.unmodifiable(_steps);

  Duration get elapsed => _clock.elapsed;

  @visibleForTesting
  void addStepForTest(BookOpenStep step) => _steps.add(step);

  void mark(String step, {String? detail}) {
    final elapsed = _clock.elapsed;
    final previous = _steps.isEmpty ? Duration.zero : _steps.last.elapsed;
    final recorded = BookOpenStep(
      step: step,
      elapsed: elapsed,
      delta: elapsed - previous,
      detail: detail,
    );
    _steps.add(recorded);
    final line = recorded.toLogLine();
    PipelineDiagnostics.instance.record('[BookOpen] $line');
    if (kDebugMode) debugPrint('[BookOpen] $line');
  }

  /// Parses a WebView `console.log` line. Returns true when consumed.
  bool absorbConsole(String message) {
    final parsed = parseConsole(message);
    if (parsed == null) return false;
    final jsBits = <String>[
      if (parsed.jsElapsedMs != null) 'js=${parsed.jsElapsedMs}ms',
      if (parsed.jsDeltaMs != null) 'jsΔ=${parsed.jsDeltaMs}ms',
      if (parsed.extra != null && parsed.extra!.isNotEmpty) parsed.extra!,
    ];
    mark(
      'js:${parsed.step}',
      detail: jsBits.isEmpty ? null : jsBits.join(' '),
    );
    return true;
  }

  void noteMilestone(String name) {
    final line =
        '$name at ${_clock.elapsed.inMilliseconds}ms '
        '(${_steps.length} steps so far)';
    PipelineDiagnostics.instance.record('[BookOpen] $line');
    if (kDebugMode) debugPrint('[BookOpen] $line');
  }

  /// Prints a readable table once. Safe to call again — later calls no-op.
  String dumpSummary({String reason = 'first-relocation'}) {
    if (_summarized) return '';
    _summarized = true;
    final text = formatSummary(reason: reason);
    PipelineDiagnostics.instance.record(text);
    if (kDebugMode) debugPrint(text);
    return text;
  }

  String formatSummary({String reason = 'first-relocation'}) {
    final label = [
      if (title.isNotEmpty) title,
      if (format.isNotEmpty) format,
    ].join(' · ');
    final buffer = StringBuffer()
      ..writeln(
        '[BookOpen] -------- open chain'
        '${label.isEmpty ? '' : ' ($label)'} · $reason --------',
      );
    if (_steps.isEmpty) {
      buffer.writeln('  (no marks)');
    } else {
      for (final step in _steps) {
        final flag = step.delta >= slowDelta ? '  <<' : '';
        final detail = (step.detail == null || step.detail!.isEmpty)
            ? ''
            : '  ${step.detail}';
        buffer.writeln(
          '  ${_pad(step.step, 28)}'
          '+${_padMs(step.elapsed.inMilliseconds)}  '
          'Δ${_padMs(step.delta.inMilliseconds)}'
          '$flag$detail',
        );
      }
    }
    final total = _clock.elapsed.inMilliseconds;
    buffer.writeln('  TOTAL to $reason: ${total}ms');
    final slowest = [
      ..._steps.where((s) => !_ignoreInSlowest.contains(s.step)),
    ]..sort((a, b) => b.delta.compareTo(a.delta));
    final hot = slowest.take(3).where((s) => s.delta.inMilliseconds > 0);
    if (hot.isNotEmpty) {
      buffer.writeln(
        '  slowest: ${hot.map((s) => '${s.step} Δ${s.delta.inMilliseconds}ms').join(', ')}',
      );
    }
    buffer.write('[BookOpen] --------------------------------');
    return buffer.toString();
  }

  static BookOpenJsMark? parseConsole(String message) {
    final match = _jsLine.firstMatch(message.trim());
    if (match == null) return null;
    return BookOpenJsMark(
      step: match.group(1)!,
      jsElapsedMs: int.tryParse(match.group(2) ?? ''),
      jsDeltaMs: int.tryParse(match.group(3) ?? ''),
      extra: match.group(4),
    );
  }

  static String _pad(String value, int width) {
    if (value.length >= width) return '$value ';
    return value.padRight(width);
  }

  static String _padMs(int ms) => '${ms}ms'.padLeft(7);
}

class BookOpenStep {
  const BookOpenStep({
    required this.step,
    required this.elapsed,
    required this.delta,
    this.detail,
  });

  final String step;
  final Duration elapsed;
  final Duration delta;
  final String? detail;

  String toLogLine() {
    final extra = (detail == null || detail!.isEmpty) ? '' : ' $detail';
    return 'step=$step +${elapsed.inMilliseconds}ms '
        'Δ${delta.inMilliseconds}ms$extra';
  }
}

class BookOpenJsMark {
  const BookOpenJsMark({
    required this.step,
    this.jsElapsedMs,
    this.jsDeltaMs,
    this.extra,
  });

  final String step;
  final int? jsElapsedMs;
  final int? jsDeltaMs;
  final String? extra;
}

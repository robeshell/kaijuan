import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef ImportTimingListener = void Function(ImportPipelineTiming timing);

class ImportPipelineTiming {
  const ImportPipelineTiming({
    required this.pipeline,
    required this.fileName,
    required this.step,
    required this.elapsed,
    required this.sincePrevious,
  });

  final String pipeline;
  final String fileName;
  final String step;
  final Duration elapsed;
  final Duration sincePrevious;

  @override
  String toString() =>
      '[$pipeline][$fileName] step=$step '
      'elapsed=${elapsed.inMilliseconds}ms '
      'delta=${sincePrevious.inMilliseconds}ms';
}

class ImportPipelineTrace {
  ImportPipelineTrace({
    required this.pipeline,
    required String sourcePath,
    this.onTiming,
  }) : fileName = p.basename(sourcePath),
       _clock = Stopwatch()..start();

  final String pipeline;
  final String fileName;
  final ImportTimingListener? onTiming;
  final Stopwatch _clock;
  Duration _previous = Duration.zero;

  void mark(String step) {
    final elapsed = _clock.elapsed;
    final timing = ImportPipelineTiming(
      pipeline: pipeline,
      fileName: fileName,
      step: step,
      elapsed: elapsed,
      sincePrevious: elapsed - _previous,
    );
    _previous = elapsed;
    (onTiming ?? _debugTiming)(timing);
  }

  static void _debugTiming(ImportPipelineTiming timing) {
    if (kDebugMode) debugPrint('[Import] $timing');
  }
}

class ImportFailure {
  const ImportFailure({required this.path, required this.reason});

  final String path;
  final String reason;

  String get fileName => p.basename(path);
}

class ImportResult {
  const ImportResult({
    this.added = 0,
    this.updated = 0,
    this.failures = const [],
  });

  final int added;
  final int updated;
  final List<ImportFailure> failures;

  bool get isEmpty => added == 0 && updated == 0 && failures.isEmpty;
  bool get hasFailures => failures.isNotEmpty;
}

class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

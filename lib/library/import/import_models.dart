import 'package:path/path.dart' as p;

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

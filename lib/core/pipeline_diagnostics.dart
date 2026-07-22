import 'package:flutter/foundation.dart' show visibleForTesting;

/// In-memory ring buffer for import / open pipeline timings.
///
/// Debug console still prints the same lines; this keeps a copy that Settings
/// can export without requiring a debugger attachment.
class PipelineDiagnostics {
  PipelineDiagnostics({this.capacity = 200});

  static final PipelineDiagnostics instance = PipelineDiagnostics();

  final int capacity;
  final List<String> _lines = <String>[];

  int get length => _lines.length;

  void record(String line) {
    final stamped = '${DateTime.now().toIso8601String()} $line';
    _lines.add(stamped);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
  }

  String exportText() {
    if (_lines.isEmpty) return '（暂无导入 / 打开诊断记录）';
    return _lines.join('\n');
  }

  void clear() => _lines.clear();

  /// Test-only helper to seed / reset the shared buffer.
  @visibleForTesting
  void replaceAll(Iterable<String> lines) {
    _lines
      ..clear()
      ..addAll(lines);
  }
}

import 'ai_models.dart';

/// Cancellation signal shared by every step in one AI task.
///
/// Transports can register a listener to abort an underlying request. Higher
/// layers reuse the same instance across search, model, tools and follow-ups.
class CancelToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  void addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeCancelListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {
        // Cancellation must remain best-effort and idempotent.
      }
    }
  }

  void throwIfCancelled() {
    if (_cancelled) throw AiProviderException('已取消');
  }
}

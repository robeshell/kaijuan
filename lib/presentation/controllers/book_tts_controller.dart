import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum BookTtsStatus { idle, playing, paused }

typedef BookTtsBridge = ({
  Future<String?> Function() here,
  Future<String?> Function() next,
  Future<String?> Function() previous,
  Future<void> Function() stop,
});

/// Owns the system TTS engine and sentence playback loop.
///
/// Foliate remains responsible for sentence navigation/highlighting. The
/// reader controller only attaches that bridge and exposes compatibility
/// getters/actions to the presentation layer.
class BookTtsController {
  BookTtsController({
    required bool Function() isReaderDisposed,
    required bool Function() isReaderReady,
    required void Function() beforeStart,
    required VoidCallback onPlaybackStarted,
    required VoidCallback onChanged,
  }) : this._(
         isReaderDisposed,
         isReaderReady,
         beforeStart,
         onPlaybackStarted,
         onChanged,
       );

  BookTtsController._(
    this._isReaderDisposed,
    this._isReaderReady,
    this._beforeStart,
    this._onPlaybackStarted,
    this._onChanged,
  );

  static const ratePresets = <double>[0.8, 1.0, 1.25, 1.5];

  final bool Function() _isReaderDisposed;
  final bool Function() _isReaderReady;
  final void Function() _beforeStart;
  final VoidCallback _onPlaybackStarted;
  final VoidCallback _onChanged;

  BookTtsBridge? _bridge;
  FlutterTts? _engine;
  BookTtsStatus _status = BookTtsStatus.idle;
  double _rate = 1.0;
  String? _currentText;
  int _generation = 0;
  Completer<void>? _loopIdle;
  Completer<void>? _utteranceDone;
  bool _utteranceArmed = false;
  bool _disposed = false;

  String? userMessage;

  BookTtsStatus get status => _status;
  bool get active => _status != BookTtsStatus.idle;
  bool get playing => _status == BookTtsStatus.playing;
  bool get paused => _status == BookTtsStatus.paused;
  double get rate => _rate;

  bool get _readerUnavailable => _disposed || _isReaderDisposed();

  void attachBridge({
    required Future<String?> Function() here,
    required Future<String?> Function() next,
    required Future<String?> Function() previous,
    required Future<void> Function() stop,
  }) {
    _bridge = (here: here, next: next, previous: previous, stop: stop);
  }

  void detachBridge() {
    _bridge = null;
  }

  void _notify() {
    if (!_readerUnavailable) _onChanged();
  }

  Future<FlutterTts> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final engine = FlutterTts();
    _engine = engine;
    if (!kIsWeb && Platform.isIOS) {
      await engine.setSharedInstance(true);
      await engine.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    // Apple: awaitSpeakCompletion(true) + stop() can leave speak pending.
    await engine.awaitSpeakCompletion(false);
    await _applyRate(engine);
    engine.setStartHandler(() => _utteranceArmed = true);
    engine.setCompletionHandler(_onEngineSignal);
    engine.setCancelHandler(_onEngineSignal);
    engine.setErrorHandler((message) {
      _onEngineSignal();
      debugPrint('[TTS] error: $message');
    });
    return engine;
  }

  void _onEngineSignal() {
    if (!_utteranceArmed) return;
    _utteranceArmed = false;
    final gate = _utteranceDone;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void _forceUnblockUtteranceWait() {
    _utteranceArmed = false;
    final gate = _utteranceDone;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _applyRate(FlutterTts engine) async {
    await engine.setSpeechRate((_rate * 0.5).clamp(0.1, 1.0));
  }

  Future<bool> _speakSentence(
    FlutterTts engine,
    String text,
    int generation,
  ) async {
    if (text.isEmpty) return false;
    _utteranceArmed = false;
    final gate = Completer<void>();
    _utteranceDone = gate;
    try {
      await engine.speak(text);
      await gate.future;
    } finally {
      if (identical(_utteranceDone, gate)) _utteranceDone = null;
      _utteranceArmed = false;
    }
    return !_readerUnavailable &&
        generation == _generation &&
        _status == BookTtsStatus.playing;
  }

  Future<void> _drainLoop() async {
    final idle = _loopIdle?.future;
    if (idle == null) return;
    try {
      await idle.timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<void> _interruptAudio({required bool bumpGeneration}) async {
    if (bumpGeneration) _generation++;
    _forceUnblockUtteranceWait();
    try {
      await _engine?.stop();
    } catch (_) {}
    await _drainLoop();
  }

  Future<void> start() async {
    if (_readerUnavailable || !_isReaderReady()) return;
    _beforeStart();
    await _interruptAudio(bumpGeneration: true);
    final generation = _generation;
    final bridge = _bridge;
    if (bridge == null) {
      userMessage = '听书引擎未就绪';
      _notify();
      return;
    }
    final text = (await bridge.here())?.trim();
    if (_readerUnavailable || generation != _generation) return;
    if (text == null || text.isEmpty) {
      userMessage = '当前位置没有可读文本';
      _notify();
      return;
    }
    _currentText = text;
    _status = BookTtsStatus.playing;
    _onPlaybackStarted();
    _notify();
    unawaited(_runLoop(generation));
  }

  Future<void> _runLoop(int generation) async {
    final idle = Completer<void>();
    _loopIdle = idle;
    try {
      final engine = await _ensureEngine();
      if (_readerUnavailable || generation != _generation) return;

      while (!_readerUnavailable &&
          generation == _generation &&
          _status == BookTtsStatus.playing) {
        final text = _currentText?.trim() ?? '';
        if (text.isEmpty) {
          userMessage = '已读完';
          await stop();
          return;
        }
        final finished = await _speakSentence(engine, text, generation);
        if (!finished ||
            _readerUnavailable ||
            generation != _generation ||
            _status != BookTtsStatus.playing) {
          return;
        }

        final bridge = _bridge;
        if (bridge == null) {
          await stop();
          return;
        }
        String? nextText;
        try {
          nextText = (await bridge.next())?.trim();
        } catch (error) {
          debugPrint('[TTS] ttsNext failed: $error');
        }
        if (_readerUnavailable || generation != _generation) {
          if (nextText != null && nextText.isNotEmpty) {
            try {
              await bridge.previous();
            } catch (_) {}
          }
          return;
        }
        if (nextText == null || nextText.isEmpty) {
          userMessage = '已读完';
          await stop();
          return;
        }
        _currentText = nextText;
        _notify();
      }
    } finally {
      if (!idle.isCompleted) idle.complete();
      if (identical(_loopIdle, idle)) _loopIdle = null;
    }
  }

  Future<void> pause() async {
    if (_readerUnavailable || _status != BookTtsStatus.playing) return;
    _status = BookTtsStatus.paused;
    _notify();
    await _interruptAudio(bumpGeneration: true);
  }

  Future<void> resume() async {
    if (_readerUnavailable || _status != BookTtsStatus.paused) return;
    final text = _currentText?.trim();
    if (text == null || text.isEmpty) {
      await start();
      return;
    }
    final generation = ++_generation;
    _status = BookTtsStatus.playing;
    _notify();
    unawaited(_runLoop(generation));
  }

  Future<void> togglePlayPause() async {
    switch (_status) {
      case BookTtsStatus.idle:
        await start();
      case BookTtsStatus.playing:
        await pause();
      case BookTtsStatus.paused:
        await resume();
    }
  }

  Future<void> stop() async {
    if (_readerUnavailable) return;
    await _interruptAudio(bumpGeneration: true);
    await _bridge?.stop();
    if (_readerUnavailable) return;
    _status = BookTtsStatus.idle;
    _currentText = null;
    _notify();
  }

  Future<void> setRate(double value) async {
    final next = value.clamp(0.5, 2.0);
    if ((next - _rate).abs() < 0.001) return;
    _rate = next;
    _notify();

    if (_status == BookTtsStatus.idle) {
      final engine = _engine;
      if (engine != null) await _applyRate(engine);
      return;
    }
    final keep = _currentText;
    final wasPaused = _status == BookTtsStatus.paused;
    await _interruptAudio(bumpGeneration: true);
    if (_readerUnavailable) return;
    final engine = await _ensureEngine();
    await _applyRate(engine);
    if (_readerUnavailable) return;

    _currentText = keep;
    if (wasPaused || keep == null || keep.trim().isEmpty) {
      _status = wasPaused ? BookTtsStatus.paused : BookTtsStatus.idle;
      _notify();
      return;
    }
    final generation = _generation;
    _status = BookTtsStatus.playing;
    _notify();
    unawaited(_runLoop(generation));
  }

  Future<void> skipNext() => _skip(next: true);

  Future<void> skipPrevious() => _skip(next: false);

  Future<void> _skip({required bool next}) async {
    if (_readerUnavailable || !active) return;
    await _interruptAudio(bumpGeneration: true);
    if (_readerUnavailable) return;
    final generation = _generation;
    final bridge = _bridge;
    if (bridge == null) {
      await stop();
      return;
    }
    final text = (await (next ? bridge.next() : bridge.previous()))?.trim();
    if (_readerUnavailable || generation != _generation) return;
    if (text == null || text.isEmpty) {
      userMessage = next ? '已读完' : '已到开头';
      await stop();
      return;
    }
    _currentText = text;
    _status = BookTtsStatus.playing;
    _notify();
    unawaited(_runLoop(generation));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _forceUnblockUtteranceWait();
    _bridge = null;
    final engine = _engine;
    _engine = null;
    _status = BookTtsStatus.idle;
    _currentText = null;
    if (engine != null) {
      try {
        await engine.stop();
      } catch (_) {}
    }
  }
}

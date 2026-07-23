import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Channel name must match Windows runner (`flutter_window.cpp`).
const _channel = MethodChannel('com.kaijuan.reader/window');

StreamController<bool>? _maximizedController;
bool _windowEventHandlerInstalled = false;

Future<void> _invokeOrIgnore(String method, [dynamic arguments]) async {
  try {
    await _channel.invokeMethod<void>(method, arguments);
  } on MissingPluginException {
    // No native handler (e.g. Linux until wired).
  }
}

Future<bool> _invokeBoolOrFalse(String method) async {
  try {
    final result = await _channel.invokeMethod<bool>(method);
    return result ?? false;
  } on MissingPluginException {
    return false;
  }
}

void _ensureWindowEventHandler() {
  if (_windowEventHandlerInstalled) return;
  _windowEventHandlerInstalled = true;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'maximizedChanged') {
      final maximized = call.arguments == true;
      _maximizedController?.add(maximized);
    }
  });
}

Future<void> minimizeWindow() async {
  if (!_supportsWindowControls) return;
  await _invokeOrIgnore('minimize');
}

Future<void> maximizeWindow() async {
  if (!_supportsWindowControls) return;
  await _invokeOrIgnore('maximize');
}

Future<void> restoreWindow() async {
  if (!_supportsWindowControls) return;
  await _invokeOrIgnore('restore');
}

Future<void> closeWindow() async {
  if (!_supportsWindowControls) return;
  await _invokeOrIgnore('close');
}

Future<bool> isWindowMaximized() async {
  if (!_supportsWindowControls) return false;
  return _invokeBoolOrFalse('isMaximized');
}

Future<void> startWindowDrag() async {
  if (!_supportsWindowControls) return;
  await _invokeOrIgnore('startDrag');
}

bool get supportsCustomWindowChrome => _supportsWindowControls;

Stream<bool> get windowMaximizedChanges {
  _maximizedController ??= StreamController<bool>.broadcast();
  _ensureWindowEventHandler();
  return _maximizedController!.stream;
}

bool get _supportsWindowControls => !kIsWeb && Platform.isWindows;

/// Keep in sync with native title-bar metrics.
double get platformTitleBarHeight {
  if (kIsWeb) return 0;
  if (Platform.isMacOS) return 38;
  if (Platform.isWindows) return 44;
  return 0;
}

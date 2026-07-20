import 'dart:async';

Future<void> minimizeWindow() async {}
Future<void> maximizeWindow() async {}
Future<void> restoreWindow() async {}
Future<void> closeWindow() async {}
Future<bool> isWindowMaximized() async => false;
Future<void> startWindowDrag() async {}

bool get supportsCustomWindowChrome => false;

Stream<bool> get windowMaximizedChanges => const Stream<bool>.empty();

double get platformTitleBarHeight => 0;

import 'package:flutter/material.dart';

/// Route used by management subpages inside AppShell's content navigator.
///
/// The shell keeps its adaptive root navigation while this opaque route
/// replaces only the content pane. Avoiding the default Material slide keeps a
/// large library grid from being animated during a simple directory switch.
Route<T> appPageRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    opaque: true,
    maintainState: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

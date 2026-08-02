import 'package:flutter/material.dart';

/// Route used by full-screen library subpages.
///
/// These pages replace the shell rather than layering a modal surface over it.
/// Avoiding the default Material slide keeps a large library grid from being
/// animated during a simple directory switch.
Route<T> appPageRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    opaque: true,
    maintainState: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

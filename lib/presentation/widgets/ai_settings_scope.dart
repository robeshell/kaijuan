import 'package:flutter/widgets.dart';

import '../controllers/ai_settings_controller.dart';

/// Exposes [AiSettingsController] to the subtree without prop-drilling every
/// open-reader call site.
class AiSettingsScope extends InheritedWidget {
  const AiSettingsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final AiSettingsController controller;

  /// Safe in [State.initState]: does **not** register a dependency.
  static AiSettingsController? maybeOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AiSettingsScope>();
    return scope?.controller;
  }

  /// For [State.build] / [State.didChangeDependencies] when the subtree should
  /// rebuild if the scope identity changes.
  static AiSettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AiSettingsScope>();
    assert(scope != null, 'AiSettingsScope not found');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(AiSettingsScope oldWidget) =>
      controller != oldWidget.controller;
}

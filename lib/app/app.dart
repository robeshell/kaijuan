import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../library/persistence/app_database.dart';
import '../presentation/app_shell.dart';
import 'theme_preferences.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.themePreferences,
    required this.database,
  });

  final ThemePreferences themePreferences;

  /// Opened at bootstrap; injected into repositories as import/reader
  /// features land.
  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themePreferences,
      builder: (context, _) {
        return MaterialApp(
          title: 'Kaika',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(themePreferences.accent),
          darkTheme: AppTheme.dark(themePreferences.accent),
          themeMode: themePreferences.themeMode,
          home: AppShell(themePreferences: themePreferences),
        );
      },
    );
  }
}

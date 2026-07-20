import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../presentation/app_shell.dart';
import '../presentation/controllers/library_controller.dart';
import 'theme_preferences.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.themePreferences,
    required this.libraryController,
  });

  final ThemePreferences themePreferences;
  final LibraryController libraryController;

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
          home: AppShell(
            themePreferences: themePreferences,
            libraryController: libraryController,
          ),
        );
      },
    );
  }
}

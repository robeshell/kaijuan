import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../library/import/comic_import_service.dart';
import '../library/persistence/app_database.dart';
import '../presentation/app_shell.dart';
import 'theme_preferences.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.themePreferences,
    required this.database,
    required this.importService,
  });

  final ThemePreferences themePreferences;
  final AppDatabase database;
  final ComicImportService importService;

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
            database: database,
            importService: importService,
          ),
        );
      },
    );
  }
}

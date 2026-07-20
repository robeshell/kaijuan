import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/theme_preferences.dart';
import 'library/persistence/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themePreferences = await ThemePreferences.load();
  // Opened at bootstrap so a late disk read cannot race the first frame.
  // Passed into repositories once import/reader features land.
  final database = AppDatabase.defaults();
  runApp(App(themePreferences: themePreferences, database: database));
}

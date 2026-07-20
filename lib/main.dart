import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/theme_preferences.dart';
import 'library/import/comic_import_service.dart';
import 'library/persistence/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themePreferences = await ThemePreferences.load();
  final database = AppDatabase.defaults();
  final importService = ComicImportService(
    database: database,
    supportDirectory: await getApplicationSupportDirectory(),
  );
  runApp(
    App(
      themePreferences: themePreferences,
      database: database,
      importService: importService,
    ),
  );
}

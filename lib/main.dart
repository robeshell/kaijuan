import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/theme_preferences.dart';
import 'library/import/comic_import_service.dart';
import 'library/persistence/app_database.dart';
import 'presentation/controllers/library_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themePreferences = await ThemePreferences.load();
  final database = AppDatabase.defaults();
  final importService = ComicImportService(
    database: database,
    supportDirectory: await getApplicationSupportDirectory(),
  );
  final libraryController = LibraryController(
    database: database,
    importService: importService,
  );
  runApp(
    App(
      themePreferences: themePreferences,
      libraryController: libraryController,
    ),
  );
}

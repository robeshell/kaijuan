import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/comic_reading_preferences.dart';
import 'app/theme_preferences.dart';
import 'brand/brand_config.dart';
import 'library/import/comic_import_service.dart';
import 'library/persistence/app_database.dart';
import 'presentation/controllers/library_controller.dart';

/// Shared process entry for comic / book shells.
///
/// Isolates support files and DB by [BrandConfig]; see docs/ENGINEERING.md.
Future<void> bootstrap(BrandConfig brand) async {
  WidgetsFlutterBinding.ensureInitialized();

  final root = await getApplicationSupportDirectory();
  final supportDir = brand.storageNamespace.isEmpty
      ? root
      : Directory(p.join(root.path, brand.storageNamespace));
  if (brand.storageNamespace.isNotEmpty) {
    await supportDir.create(recursive: true);
  }

  final themePreferences = await ThemePreferences.load(
    supportDirectory: supportDir,
    defaultAccent: brand.defaultAccent,
  );
  final readingPreferences = await ComicReadingPreferences.load(
    supportDirectory: supportDir,
    defaultReadingTheme: brand.defaultReadingTheme,
  );
  final database = AppDatabase.named(brand.databaseName);
  final importService = ComicImportService(
    database: database,
    supportDirectory: supportDir,
  );
  final libraryController = LibraryController(
    database: database,
    importService: importService,
    importExtensions: brand.importExtensions,
  );

  runApp(
    App(
      brand: brand,
      themePreferences: themePreferences,
      readingPreferences: readingPreferences,
      libraryController: libraryController,
    ),
  );
}

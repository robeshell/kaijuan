import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/book_reading_preferences.dart';
import 'app/comic_reading_preferences.dart';
import 'app/theme_preferences.dart';
import 'brand/brand_config.dart';
import 'library/import/book_import_service.dart';
import 'library/import/comic_import_service.dart';
import 'library/persistence/app_database.dart';
import 'presentation/controllers/library_controller.dart';
import 'readers/book/book_theme.dart';

/// Single App bootstrap for Kaika.
///
/// Both page-image and reflow reader engines are always available; file import
/// routes by extension, with EPUB auto-detected between page-image and reflow
/// content.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  const brand = BrandConfig.app;
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
  final comicReadingPreferences = await ComicReadingPreferences.load(
    supportDirectory: supportDir,
    defaultReadingTheme: brand.defaultReadingTheme,
  );
  final bookReadingPreferences = await BookReadingPreferences.load(
    supportDirectory: supportDir,
    defaultReadingTheme: BookReadingTheme.paper,
  );

  final database = AppDatabase.named(brand.databaseName);
  final libraryController = LibraryController(
    database: database,
    comicImportService: ComicImportService(
      database: database,
      supportDirectory: supportDir,
    ),
    bookImportService: BookImportService(
      database: database,
      supportDirectory: supportDir,
    ),
    importExtensions: brand.importExtensions,
  );

  runApp(
    App(
      brand: brand,
      themePreferences: themePreferences,
      readingPreferences: comicReadingPreferences,
      bookReadingPreferences: bookReadingPreferences,
      libraryController: libraryController,
    ),
  );
}

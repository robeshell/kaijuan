import 'dart:async';
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
import 'library/import/import_staging.dart';
import 'library/persistence/app_database.dart';
import 'presentation/controllers/library_controller.dart';
import 'readers/book/book_loopback_server.dart';
import 'readers/book/book_theme.dart';

/// Single App bootstrap for Kaika.
///
/// Both page-image and reflow reader engines are always available; file import
/// routes by extension, with EPUB auto-detected between page-image and reflow
/// content.
///
/// [runApp] runs immediately with a splash shell so the native window is never
/// an empty black surface while prefs / DB / loopback warm up.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<_BootServices> _services = _loadBootServices();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootServices>(
      future: _services,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _BootError(error: snapshot.error!),
          );
        }
        final services = snapshot.data;
        if (services == null) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _BootSplash(),
          );
        }
        return App(
          brand: services.brand,
          themePreferences: services.themePreferences,
          readingPreferences: services.comicReadingPreferences,
          bookReadingPreferences: services.bookReadingPreferences,
          libraryController: services.libraryController,
        );
      },
    );
  }
}

class _BootServices {
  const _BootServices({
    required this.brand,
    required this.themePreferences,
    required this.comicReadingPreferences,
    required this.bookReadingPreferences,
    required this.libraryController,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;
  final ComicReadingPreferences comicReadingPreferences;
  final BookReadingPreferences bookReadingPreferences;
  final LibraryController libraryController;
}

Future<_BootServices> _loadBootServices() async {
  const brand = BrandConfig.app;
  final root = await getApplicationSupportDirectory();
  final supportDir = brand.storageNamespace.isEmpty
      ? root
      : Directory(p.join(root.path, brand.storageNamespace));
  if (brand.storageNamespace.isNotEmpty) {
    await supportDir.create(recursive: true);
  }

  await BookLoopbackServer.configureSupportDirectory(supportDir);
  // Warm the shared Foliate origin before the first open/import.
  unawaited(BookLoopbackServer.ensureStarted());
  // Drop orphaned staging leftovers from crashed / killed imports.
  unawaited(ImportStagingArea(supportDir).purgeStalePartials());

  final loaded = await Future.wait<Object>([
    ThemePreferences.load(
      supportDirectory: supportDir,
      defaultAccent: brand.defaultAccent,
    ),
    ComicReadingPreferences.load(
      supportDirectory: supportDir,
      defaultReadingTheme: brand.defaultReadingTheme,
    ),
    BookReadingPreferences.load(
      supportDirectory: supportDir,
      defaultReadingTheme: BookReadingTheme.paper,
    ),
  ]);

  final themePreferences = loaded[0] as ThemePreferences;
  final comicReadingPreferences = loaded[1] as ComicReadingPreferences;
  final bookReadingPreferences = loaded[2] as BookReadingPreferences;

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

  return _BootServices(
    brand: brand,
    themePreferences: themePreferences,
    comicReadingPreferences: comicReadingPreferences,
    bookReadingPreferences: bookReadingPreferences,
    libraryController: libraryController,
  );
}

/// First Flutter frame: brand on a system-aware canvas (never native black).
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final bg = dark ? const Color(0xFF141416) : const Color(0xFFFFFFFF);
    final fg = dark ? const Color(0xFFF2F2F4) : const Color(0xFF111113);

    return ColoredBox(
      color: bg,
      child: Center(
        child: Text(
          BrandConfig.app.displayName,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: fg,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '启动失败\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

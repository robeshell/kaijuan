import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/book_reading_preferences.dart';
import 'app/comic_reading_preferences.dart';
import 'app/kaijuan_launch_screen.dart';
import 'app/theme_preferences.dart';
import 'brand/brand_config.dart';
import 'library/import/book_import_service.dart';
import 'library/import/comic_import_service.dart';
import 'library/import/import_pipeline.dart';
import 'library/import/import_staging.dart';
import 'library/import/wifi_transfer_service.dart';
import 'library/backup/backup_service.dart';
import 'library/backup/backup_store.dart';
import 'library/remote/remote_source_controller.dart';
import 'library/remote/remote_store.dart';
import 'library/persistence/app_database.dart';
import 'library/storage/library_paths.dart';
import 'ai/ai_settings.dart';
import 'presentation/controllers/library_controller.dart';
import 'presentation/controllers/backup_controller.dart';
import 'presentation/controllers/ai_settings_controller.dart';
import 'readers/book/book_loopback_server.dart';
import 'readers/book/book_theme.dart';

/// Single App bootstrap for 开卷.
///
/// Both page-image and reflow reader engines are always available; file import
/// routes by extension, with EPUB auto-detected between page-image and reflow
/// content.
///
/// Launch surfaces:
/// - **Android** — system SplashScreen / windowBackground owns the first paint.
///   Init runs before [runApp] so Flutter never paints a second splash (same as
///   开听).
/// - **iOS / macOS / desktop** — native launch storyboard / window canvas hands
///   off to [KaijuanLaunchScreen] until services are ready.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mirror kaiting: Android keeps one native splash until the app is ready.
  if (!kIsWeb && Platform.isAndroid) {
    try {
      final services = await _loadBootServices();
      runApp(_readyApp(services));
    } catch (error, stack) {
      debugPrint('bootstrap failed: $error\n$stack');
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: _BootError(error: error),
        ),
      );
    }
    return;
  }

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
            home: KaijuanLaunchScreen(),
          );
        }
        return _readyApp(services);
      },
    );
  }
}

Widget _readyApp(_BootServices services) {
  return App(
    brand: services.brand,
    themePreferences: services.themePreferences,
    readingPreferences: services.comicReadingPreferences,
    bookReadingPreferences: services.bookReadingPreferences,
    libraryController: services.libraryController,
    wifiTransferService: services.wifiTransferService,
    remoteSourceController: services.remoteSourceController,
    backupController: services.backupController,
    aiSettingsController: services.aiSettingsController,
  );
}

class _BootServices {
  const _BootServices({
    required this.brand,
    required this.themePreferences,
    required this.comicReadingPreferences,
    required this.bookReadingPreferences,
    required this.libraryController,
    required this.wifiTransferService,
    required this.remoteSourceController,
    required this.backupController,
    required this.aiSettingsController,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;
  final ComicReadingPreferences comicReadingPreferences;
  final BookReadingPreferences bookReadingPreferences;
  final LibraryController libraryController;
  final WifiTransferService wifiTransferService;
  final RemoteSourceController remoteSourceController;
  final BackupController backupController;
  final AiSettingsController aiSettingsController;
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
  // Warm loopback + Foliate asset cache before the first open/import.
  unawaited(BookLoopbackServer.warmHotAssets());
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
  // Documents (DB) and Application Support (files) can get different container
  // UUIDs after an iOS reinstall; rewrite absolute file/cover paths first.
  final rebound = await LibraryPaths(supportDir).rebindDatabase(database);
  if (rebound > 0) {
    debugPrint(
      '[Library] rebound $rebound item path(s) to current support root',
    );
  }
  final comicImportService = ComicImportService(
    database: database,
    supportDirectory: supportDir,
  );
  final bookImportService = BookImportService(
    database: database,
    supportDirectory: supportDir,
  );
  final importPipeline = ImportPipeline(
    comicImport: comicImportService,
    bookImport: bookImportService,
  );
  final repairedCovers = await bookImportService.ensureDefaultCovers();
  if (repairedCovers > 0) {
    debugPrint('[Library] generated $repairedCovers missing book cover(s)');
  }
  final libraryController = LibraryController(
    database: database,
    comicImportService: comicImportService,
    bookImportService: bookImportService,
    importPipeline: importPipeline,
    importExtensions: brand.importExtensions,
  );
  final wifiTransferService = WifiTransferService(
    supportDirectory: supportDir,
    onImport: (candidate) => libraryController.importCandidates([candidate]),
  );
  final connectionStore = JsonRemoteConnectionStore(
    File(p.join(supportDir.path, 'remote_connections.json')),
  );
  final credentialStore = SecureRemoteCredentialStore();
  final remoteSourceController = RemoteSourceController(
    connectionStore: connectionStore,
    credentialStore: credentialStore,
  );
  await remoteSourceController.load();
  final backupService = BackupService(
    database: database,
    supportDirectory: supportDir,
    connectionStore: connectionStore,
    credentialStore: credentialStore,
    importPipeline: importPipeline,
    settingsStore: JsonBackupTargetSettingsStore(
      File(p.join(supportDir.path, 'backup_settings.json')),
    ),
  );
  final backupController = BackupController(
    service: backupService,
    remote: remoteSourceController,
  );
  await backupController.load();
  final aiSettingsController = AiSettingsController(
    settingsStore: JsonAiSettingsStore(
      File(p.join(supportDir.path, 'ai_settings.json')),
    ),
    credentialStore: SecureAiCredentialStore(),
  );
  await aiSettingsController.load();

  return _BootServices(
    brand: brand,
    themePreferences: themePreferences,
    comicReadingPreferences: comicReadingPreferences,
    bookReadingPreferences: bookReadingPreferences,
    libraryController: libraryController,
    wifiTransferService: wifiTransferService,
    remoteSourceController: remoteSourceController,
    backupController: backupController,
    aiSettingsController: aiSettingsController,
  );
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
          child: Text('启动失败\n$error', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

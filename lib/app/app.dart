import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../brand/brand_config.dart';
import '../core/platform_window.dart';
import '../core/theme.dart';
import '../library/import/wifi_transfer_service.dart';
import '../library/remote/remote_source_controller.dart';
import '../presentation/app_shell.dart';
import '../presentation/controllers/library_controller.dart';
import '../presentation/controllers/backup_controller.dart';
import '../presentation/controllers/ai_settings_controller.dart';
import '../presentation/navigation/app_route_observer.dart';
import '../presentation/widgets/ai_settings_scope.dart';
import 'book_reading_preferences.dart';
import 'comic_reading_preferences.dart';
import 'theme_preferences.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.brand,
    required this.themePreferences,
    required this.readingPreferences,
    this.bookReadingPreferences,
    required this.libraryController,
    this.wifiTransferService,
    required this.remoteSourceController,
    required this.backupController,
    required this.aiSettingsController,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;
  final ComicReadingPreferences readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;
  final LibraryController libraryController;
  final WifiTransferService? wifiTransferService;
  final RemoteSourceController remoteSourceController;
  final BackupController backupController;
  final AiSettingsController aiSettingsController;

  @override
  Widget build(BuildContext context) {
    return AiSettingsScope(
      controller: aiSettingsController,
      child: ListenableBuilder(
        listenable: themePreferences,
        builder: (context, _) {
          final accent = themePreferences.accent;
          final skinId = themePreferences.skinId;
          // "跟随系统" maps to the light/dark skins via Flutter's own
          // ThemeMode.system, so OS brightness changes apply automatically.
          final followSystem = skinId == AppSkins.systemId;
          final skin = followSystem ? AppSkins.standard : AppSkins.byId(skinId);
          return MaterialApp(
            title: brand.displayName,
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            navigatorObservers: [appRouteObserver],
            theme: AppTheme.forSkin(skin, accent),
            darkTheme: AppTheme.forSkin(
              followSystem ? AppSkins.deepNight : skin,
              accent,
            ),
            themeMode: followSystem
                ? ThemeMode.system
                : (skin.brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light),
            builder: (context, child) {
              return DesktopTitleBarMediaQuery(
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: AppShell(
              brand: brand,
              themePreferences: themePreferences,
              readingPreferences: readingPreferences,
              bookReadingPreferences: bookReadingPreferences,
              libraryController: libraryController,
              wifiTransferService: wifiTransferService,
              remoteSourceController: remoteSourceController,
              backupController: backupController,
              aiSettingsController: aiSettingsController,
            ),
          );
        },
      ),
    );
  }
}

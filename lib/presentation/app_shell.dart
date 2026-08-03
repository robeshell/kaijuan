import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/book_reading_preferences.dart';
import '../app/comic_reading_preferences.dart';
import '../app/theme_preferences.dart';
import '../brand/brand_config.dart';
import '../app_update/app_update_ui.dart';
import '../core/kaijuan_icons.dart';
import '../core/platform_window.dart';
import '../core/theme.dart';
import '../core/theme/brand_tokens.g.dart';
import '../library/import/wifi_transfer_service.dart';
import '../library/remote/remote_source_controller.dart';
import 'controllers/library_controller.dart';
import 'controllers/backup_controller.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shelf_screen.dart';
import 'widgets/app_components.dart';
import 'widgets/desktop_title_bar.dart';

/// Match kaiting: fall back to brand mac title inset when the platform reports 0.
double get _effectiveDesktopTitleBarHeight {
  final platformHeight = platformTitleBarHeight;
  return platformHeight > 0 ? platformHeight : KaiBrandLayout.macOSTitlebarInset;
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.brand,
    required this.themePreferences,
    required this.libraryController,
    this.wifiTransferService,
    required this.remoteSourceController,
    required this.backupController,
    required this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;
  final LibraryController libraryController;
  final WifiTransferService? wifiTransferService;
  final RemoteSourceController remoteSourceController;
  final BackupController backupController;
  final ComicReadingPreferences readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  final ValueNotifier<int> _contentIndex = ValueNotifier<int>(0);
  late final List<Widget> _screens;
  late final Widget _rootContent;

  static const _destinations = [
    AppNavigationItem(
      icon: KaijuanIcons.open,
      selectedIcon: KaijuanIcons.openFilled,
      label: '书架',
    ),
    AppNavigationItem(
      icon: KaijuanIcons.grid,
      selectedIcon: KaijuanIcons.gridFilled,
      label: '书库',
    ),
    AppNavigationItem(
      icon: KaijuanIcons.settings,
      selectedIcon: KaijuanIcons.settingsFilled,
      label: '设置',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      ShelfScreen(
        brand: widget.brand,
        libraryController: widget.libraryController,
        readingPreferences: widget.readingPreferences,
        bookReadingPreferences: widget.bookReadingPreferences,
        onOpenLibrary: () => _selectDestination(1),
      ),
      LibraryScreen(
        brand: widget.brand,
        controller: widget.libraryController,
        wifiTransferService: widget.wifiTransferService,
        remoteSourceController: widget.remoteSourceController,
        readingPreferences: widget.readingPreferences,
        bookReadingPreferences: widget.bookReadingPreferences,
      ),
      SettingsScreen(
        themePreferences: widget.themePreferences,
        backupController: widget.backupController,
        libraryController: widget.libraryController,
      ),
    ];
    _rootContent = ValueListenableBuilder<int>(
      valueListenable: _contentIndex,
      builder: (context, index, _) =>
          IndexedStack(index: index, children: _screens),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(runSilentAppUpdateCheck(context));
      unawaited(widget.backupController.maybeAutoBackup());
    });
  }

  @override
  void dispose() {
    _contentIndex.dispose();
    super.dispose();
  }

  void _selectDestination(int index) {
    _contentNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (_index == index) return;
    _contentIndex.value = index;
    setState(() => _index = index);
  }

  Route<void> _rootContentRoute(RouteSettings settings) {
    return PageRouteBuilder<void>(
      settings: settings,
      opaque: true,
      maintainState: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => _rootContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = NavigatorPopHandler<void>(
      onPopWithResult: (_) => _contentNavigatorKey.currentState?.pop(),
      child: Navigator(
        key: _contentNavigatorKey,
        onGenerateRoute: _rootContentRoute,
      ),
    );
    final useSideRail = context.appUsesSideRail;
    // Title-bar metrics come from [DesktopTitleBarMediaQuery] (app builder).
    final titleInset = platformTitleBarHeight;
    final sidebarWidth = useSideRail ? _sidebarWidthOf(context) : 0.0;

    final content = useSideRail
        ? Row(
            children: [
              _SideRail(
                index: _index,
                onSelect: _selectDestination,
                brandName: widget.brand.displayName,
              ),
              Expanded(
                child: SafeArea(
                  left: false,
                  right: false,
                  bottom: false,
                  child: body,
                ),
              ),
            ],
          )
        : SafeArea(bottom: false, child: body);

    return Scaffold(
      extendBody: true,
      // Transparent so desktop sidebar glass can sample the native window /
      // wallpaper (macOS) instead of a solid product fill — same as kaiting.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Brand shell gradient only under the *content* column. On desktop
          // the sidebar sits left of this rect so its translucent chrome is
          // not washed by a solid white slab.
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            left: sidebarWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor,
                    context.appGlass.canvasHighlight,
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(child: content),
          if (useSideRail && titleInset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DesktopTitleBar(title: widget.brand.displayName),
            ),
        ],
      ),
      bottomNavigationBar: useSideRail
          ? null
          : AppNavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectDestination,
              destinations: _destinations,
            ),
    );
  }
}

/// Desktop sidebar width — brand tokens via [BuildContext.appSidebarWidth].
double _sidebarWidthOf(BuildContext context) => context.appSidebarWidth;

/// Copied from kaiting `_Sidebar` — only product data + token names differ.
///
/// Groups (product IA):
/// - 浏览: 书架 / 书库
/// - 我的: 设置（阅读统计等后续加这里）
class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.index,
    required this.onSelect,
    required this.brandName,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final String brandName;

  /// Indices aligned with [AppShell._destinations] / `_screens`.
  static const _browse = <(int, IconData, String)>[
    (0, KaijuanIcons.open, '书架'),
    (1, KaijuanIcons.grid, '书库'),
  ];
  static const _mine = <(int, IconData, String)>[
    (2, KaijuanIcons.settings, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final usesNativeBackdrop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    return SizedBox(
      width: _sidebarWidthOf(context),
      child: AppGlassSurface(
        strong: true,
        // Keep the same dense surface language as the mini player while letting
        // a restrained amount of native behind-window color show through.
        color: usesNativeBackdrop
            ? context.appGlass.strongSurface.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.76
                    : 0.86,
              )
            : context.appChromeSurface,
        blur: !usesNativeBackdrop,
        borderRadius: BorderRadius.zero,
        shadowOffset: const Offset(1, 0),
        shadowBlur: 6,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            minimum: EdgeInsets.only(top: _effectiveDesktopTitleBarHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                    child: Row(
                      children: [
                        Image.asset(
                          'brands/icons/comic/master_1024.png',
                          width: 28,
                          height: 28,
                          filterQuality: FilterQuality.high,
                          semanticLabel: brandName,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          brandName,
                          style: TextStyle(
                            color: context.appPrimaryText,
                            fontSize:
                                KaiProductTokens.typographyShellBrandTitle,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      // kaiting clears overlaid chrome; same idea on kaijuan.
                      padding: EdgeInsets.only(
                        bottom: context.appContentBottomPadding,
                      ),
                      children: [
                        const _SidebarHeading('浏览'),
                        for (final item in _browse)
                          _SidebarRow(
                            label: item.$3,
                            icon: item.$2,
                            active: index == item.$1,
                            onTap: () => onSelect(item.$1),
                          ),
                        const _SidebarHeading('我的'),
                        for (final item in _mine)
                          _SidebarRow(
                            label: item.$3,
                            icon: item.$2,
                            active: index == item.$1,
                            onTap: () => onSelect(item.$1),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copied from kaiting `_SidebarHeading`.
class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 13, 10, 3),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.appMutedText,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Copied from kaiting `_SidebarRow` → `SoundListRow` call site.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AppListRow(
      minHeight: KaiBrandDesktopMetrics.controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      selected: active,
      selectedColor: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadii.control),
      hoverColor: context.appTint(0.045),
      leading: Icon(
        icon,
        size: KaiBrandIcons.regular,
        color: active ? accent : context.appSecondaryText,
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: active ? context.appPrimaryText : context.appSecondaryText,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

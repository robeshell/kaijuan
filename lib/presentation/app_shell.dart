import 'dart:async';

import 'package:flutter/material.dart';

import '../app/book_reading_preferences.dart';
import '../app/comic_reading_preferences.dart';
import '../app/theme_preferences.dart';
import '../brand/brand_config.dart';
import '../app_update/app_update_ui.dart';
import '../core/platform_window.dart';
import '../core/theme.dart';
import 'controllers/library_controller.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shelf_screen.dart';
import 'widgets/app_components.dart';
import 'widgets/desktop_title_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.brand,
    required this.themePreferences,
    required this.libraryController,
    required this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;
  final LibraryController libraryController;
  final ComicReadingPreferences readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  late final List<Widget> _screens;

  static const _destinations = [
    AppNavigationItem(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_outlined,
      label: '书架',
    ),
    AppNavigationItem(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_outlined,
      label: '书库',
    ),
    AppNavigationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_outlined,
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
      ),
      LibraryScreen(
        brand: widget.brand,
        controller: widget.libraryController,
        readingPreferences: widget.readingPreferences,
        bookReadingPreferences: widget.bookReadingPreferences,
      ),
      SettingsScreen(themePreferences: widget.themePreferences),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(runSilentAppUpdateCheck(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(index: _index, children: _screens);
    final useSideRail = context.appUsesSideRail;
    // Title-bar metrics come from [DesktopTitleBarMediaQuery] (app builder).
    final titleInset = platformTitleBarHeight;

    final content = useSideRail
        ? Row(
            children: [
              _SideRail(
                index: _index,
                onSelect: (i) => setState(() => _index = i),
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
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: _ShellCanvasGradient()),
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
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
    );
  }
}

/// All skins use their semantic canvas gradient.
class _ShellCanvasGradient extends StatelessWidget {
  const _ShellCanvasGradient();

  @override
  Widget build(BuildContext context) {
    final canvas = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            canvas,
            context.appGlass.canvasHighlight,
            context.appOverlay,
          ],
          stops: const [0, 0.46, 1],
        ),
      ),
    );
  }
}

/// Desktop sidebar width — brand tokens via [BuildContext.appSidebarWidth].
double _sidebarWidthOf(BuildContext context) => context.appSidebarWidth;

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.index,
    required this.onSelect,
    required this.brandName,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final String brandName;

  static const _items = [
    (Icons.menu_book_outlined, Icons.menu_book_outlined, '书架'),
    (Icons.grid_view_outlined, Icons.grid_view_outlined, '书库'),
    (Icons.settings_outlined, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    // Glass chrome full height (under title bar); content clears via SafeArea.
    return SizedBox(
      width: _sidebarWidthOf(context),
      child: AppGlassSurface(
        strong: true,
        color: context.appChromeSurface,
        borderRadius: BorderRadius.zero,
        shadowOffset: const Offset(1, 0),
        shadowBlur: 6,
        border: Border(right: BorderSide(color: context.appDivider)),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            left: false,
            right: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                    child: Text(
                      brandName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appPrimaryText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.35,
                      ),
                    ),
                  ),
                  for (var i = 0; i < _items.length; i++)
                    _SidebarRow(
                      selected: index == i,
                      icon: _items[i].$1,
                      selectedIcon: _items[i].$2,
                      label: _items[i].$3,
                      accent: accent,
                      onTap: () => onSelect(i),
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

/// Side-rail row — brand metrics: h38, pad 10h/2v, icon 18/slot 32, label 13.5.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? accent : context.appSecondaryText;
    final labelColor = selected
        ? context.appPrimaryText
        : context.appSecondaryText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        hoverColor: context.appTint(0.045),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Center(
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 18,
                    color: iconColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

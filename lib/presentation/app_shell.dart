import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app/book_reading_preferences.dart';
import '../app/comic_reading_preferences.dart';
import '../app/theme_preferences.dart';
import '../brand/brand_config.dart';
import '../core/platform_window.dart';
import '../core/theme.dart';
import 'controllers/library_controller.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shelf_screen.dart';
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

  static bool get _isDesktopHost {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  static const Size desktopMinSize = Size(1024, 700);

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
      SettingsScreen(
        brand: widget.brand,
        themePreferences: widget.themePreferences,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final body = IndexedStack(index: _index, children: _screens);
    final useSideRail =
        _isDesktopHost ||
        MediaQuery.sizeOf(context).width >= desktopMinSize.width;
    // Title-bar metrics come from [DesktopTitleBarMediaQuery] (app builder).
    final titleInset = platformTitleBarHeight;

    if (useSideRail) {
      // Reverie layout: full-height side rail under a transparent overlay
      // title bar (traffic lights / custom window controls sit on top).
      return Scaffold(
        backgroundColor: semantics.canvas,
        body: Stack(
          children: [
            Positioned.fill(
              child: Row(
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
              ),
            ),
            if (titleInset > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DesktopTitleBar(title: widget.brand.displayName),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: semantics.canvas,
      body: SafeArea(child: body),
      bottomNavigationBar: _CompactBottomBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Desktop sidebar width (Reverie-style list rail, not icon-only strip).
const double _desktopSidebarWidth = 220;

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
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    // Surface runs full height (under title bar); content clears via SafeArea.
    return Container(
      width: _desktopSidebarWidth,
      decoration: BoxDecoration(
        color: semantics.surface,
        border: Border(right: BorderSide(color: semantics.hairline)),
      ),
      child: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                child: Text(
                  brandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: semantics.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
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
    );
  }
}

/// Horizontal icon + label row with soft selected pill (Image #2 / Reverie).
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
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final color = selected ? accent : semantics.textSecondary;
    final labelColor = selected
        ? semantics.textPrimary
        : semantics.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: semantics.hairline,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(selected ? selectedIcon : icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBottomBar extends StatelessWidget {
  const _CompactBottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.menu_book_outlined, Icons.menu_book_outlined, '书架'),
    (Icons.grid_view_outlined, Icons.grid_view_outlined, '书库'),
    (Icons.settings_outlined, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Material(
      color: semantics.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: semantics.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavButton(
                      selected: index == i,
                      icon: _items[i].$1,
                      selectedIcon: _items[i].$2,
                      label: _items[i].$3,
                      accent: accent,
                      muted: semantics.textSecondary,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon-over-label control for the mobile bottom bar only.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

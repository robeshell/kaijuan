import 'package:flutter/material.dart';

import '../app/theme_preferences.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shelf_screen.dart';

/// Root navigation: shelf / library / settings. Bottom navigation on narrow
/// layouts, a side rail on wide (desktop-first) layouts.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.themePreferences});

  final ThemePreferences themePreferences;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.auto_stories_outlined, selectedIcon: Icons.auto_stories, label: '书架'),
    (icon: Icons.library_books_outlined, selectedIcon: Icons.library_books, label: '书库'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
  ];

  List<Widget> get _screens => [
    const ShelfScreen(),
    const LibraryScreen(),
    SettingsScreen(themePreferences: widget.themePreferences),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _screens[_index]),
          ],
        ),
      );
    }
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';

/// User-facing appearance choices, persisted as JSON in the app support
/// directory (same convention as Reverie's theme.json).
class ThemePreferences extends ChangeNotifier {
  ThemePreferences._(this._file, this._themeMode, this._accent);

  final File _file;
  ThemeMode _themeMode;
  AccentPreset _accent;

  ThemeMode get themeMode => _themeMode;
  AccentPreset get accent => _accent;

  static Future<ThemePreferences> load({
    Directory? supportDirectory,
    AccentPreset? defaultAccent,
  }) async {
    final dir = supportDirectory ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'theme.json'));
    final fallbackAccent = defaultAccent ?? AppColors.defaultAccent;
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return ThemePreferences._(
          file,
          _themeModeFromId(json['themeMode'] as String?),
          AppColors.presetById(json['accentPreset'] as String?),
        );
      }
    } catch (_) {
      // Corrupted file — fall back to defaults.
    }
    return ThemePreferences._(file, ThemeMode.system, fallbackAccent);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setAccent(AccentPreset preset) async {
    if (preset.id == _accent.id) return;
    _accent = preset;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'themeMode': _themeMode.name,
        'accentPreset': _accent.id,
      }),
      flush: true,
    );
  }

  static ThemeMode _themeModeFromId(String? id) => switch (id) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

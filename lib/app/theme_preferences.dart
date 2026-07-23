import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';

/// User-facing appearance choices, persisted as JSON in the app support
/// directory (same convention as Reverie's theme.json).
///
/// The skin selection is either [AppSkins.systemId] (follow the platform
/// brightness) or a concrete [AppSkinPreset] id — skins own their own
/// brightness, so there is no separate ThemeMode.
class ThemePreferences extends ChangeNotifier {
  ThemePreferences._(this._file, this._skinId, this._accent);

  final File _file;
  String _skinId;
  AccentPreset _accent;

  /// Persisted selection: [AppSkins.systemId] or an [AppSkinPreset] id.
  String get skinId => _skinId;
  AccentPreset get accent => _accent;

  /// The skin to build a theme for, resolving "follow system" against the
  /// platform brightness.
  AppSkinPreset skinFor(Brightness platformBrightness) =>
      AppSkins.resolve(_skinId, platformBrightness);

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
          _skinIdFromJson(json),
          AppColors.presetById(json['accentPreset'] as String?),
        );
      }
    } catch (_) {
      // Corrupted file — fall back to defaults.
    }
    return ThemePreferences._(file, AppSkins.systemId, fallbackAccent);
  }

  Future<void> setSkinId(String id) async {
    final normalized = id == AppSkins.systemId ? id : AppSkins.byId(id).id;
    if (normalized == _skinId) return;
    _skinId = normalized;
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
        'skinPreset': _skinId,
        'accentPreset': _accent.id,
      }),
      flush: true,
    );
  }

  static String _skinIdFromJson(Map<String, dynamic> json) {
    final skin = json['skinPreset'] as String?;
    if (skin != null) {
      return skin == AppSkins.systemId ? skin : AppSkins.byId(skin).id;
    }
    // Migrate the legacy ThemeMode storage: an explicit dark choice maps to
    // the deep-night skin, light to the default skin, system stays system.
    return switch (json['themeMode'] as String?) {
      'dark' => AppSkins.deepNight.id,
      'light' => AppSkins.standard.id,
      _ => AppSkins.systemId,
    };
  }
}

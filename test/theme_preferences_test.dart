import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/app/theme_preferences.dart';
import 'package:kaijuan/core/theme.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaijuan_theme_prefs_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('defaults to follow-system and the default accent', () async {
    final prefs = await ThemePreferences.load(supportDirectory: tempDir);
    expect(prefs.skinId, AppSkins.systemId);
    expect(prefs.accent.id, AppColors.defaultAccent.id);
  });

  test('persists skin and accent', () async {
    final prefs = await ThemePreferences.load(supportDirectory: tempDir);
    await prefs.setSkinId(AppSkins.deepNight.id);
    await prefs.setAccent(AppColors.presetById('forest'));

    final reloaded = await ThemePreferences.load(supportDirectory: tempDir);
    expect(reloaded.skinId, AppSkins.deepNight.id);
    expect(reloaded.accent.id, 'forest');
  });

  test('normalizes unknown skin ids to the default skin', () async {
    final file = File('${tempDir.path}/theme.json');
    await file.writeAsString('{"skinPreset":"bogus"}', flush: true);

    final prefs = await ThemePreferences.load(supportDirectory: tempDir);
    expect(prefs.skinId, AppSkins.standard.id);
  });

  test('migrates legacy themeMode storage', () async {
    Future<String> skinForLegacy(String mode) async {
      final dir = await Directory.systemTemp.createTemp('kaijuan_migrate_');
      addTearDown(() => dir.delete(recursive: true));
      await File(
        '${dir.path}/theme.json',
      ).writeAsString('{"themeMode":"$mode"}', flush: true);
      final prefs = await ThemePreferences.load(supportDirectory: dir);
      return prefs.skinId;
    }

    expect(await skinForLegacy('dark'), AppSkins.deepNight.id);
    expect(await skinForLegacy('light'), AppSkins.standard.id);
    expect(await skinForLegacy('system'), AppSkins.systemId);
  });

  test('skinFor resolves follow-system by platform brightness', () async {
    final prefs = await ThemePreferences.load(supportDirectory: tempDir);
    expect(prefs.skinFor(Brightness.light).id, AppSkins.standard.id);
    expect(prefs.skinFor(Brightness.dark).id, AppSkins.deepNight.id);

    await prefs.setSkinId(AppSkins.pure.id);
    expect(prefs.skinFor(Brightness.dark).id, AppSkins.pure.id);
  });

  test('corrupted file falls back to defaults', () async {
    final file = File('${tempDir.path}/theme.json');
    await file.writeAsString('not-json', flush: true);

    final prefs = await ThemePreferences.load(supportDirectory: tempDir);
    expect(prefs.skinId, AppSkins.systemId);
    expect(prefs.accent.id, AppColors.defaultAccent.id);
  });
}

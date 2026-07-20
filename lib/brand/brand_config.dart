import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../readers/comic/comic_models.dart';

/// Single-app product configuration for Kaika.
///
/// The previous dual-brand (comic / book) split has been collapsed into one
/// local reader App with two reader engines. Existing comic installs keep their
/// data because [databaseName] and [storageNamespace] still point at the legacy
/// comic layout (`app_library` in the support root).
class BrandConfig {
  const BrandConfig({
    required this.displayName,
    required this.applicationId,
    required this.databaseName,
    required this.storageNamespace,
    required this.defaultAccent,
    required this.defaultReadingTheme,
    required this.importExtensions,
  });

  final String displayName;

  /// Android applicationId / Apple PRODUCT_BUNDLE_IDENTIFIER.
  final String applicationId;

  /// Drift database file key. Kept as `app_library` so existing comic installs
  /// do not lose data.
  final String databaseName;

  /// Subdirectory under application support. Empty = support root.
  final String storageNamespace;

  final AccentPreset defaultAccent;

  /// Comic engine default. Book defaults are loaded from
  /// [BookReadingPreferences].
  final ComicReadingTheme defaultReadingTheme;

  /// File picker extensions without dots, lower-case.
  final List<String> importExtensions;

  /// The only supported app configuration.
  static const app = BrandConfig(
    displayName: 'Kaika',
    applicationId: 'com.kaika.comic',
    databaseName: 'app_library',
    storageNamespace: '',
    defaultAccent: AccentPreset(
      id: 'ember',
      label: '暖橙',
      color: Color(0xFFEA580C),
    ),
    defaultReadingTheme: ComicReadingTheme.comicDefault,
    importExtensions: ['cbz', 'zip', 'epub'],
  );
}

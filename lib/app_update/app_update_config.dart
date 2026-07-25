/// Kai Update CDN contract for 开卷.
abstract final class AppUpdateConfig {
  static const appId = 'kaijuan';

  /// Public CDN base (no trailing slash). Published JSON lives at
  /// `$updateBase/$appId/update.json`.
  static const updateBase = 'https://dl.ainull.tech/kai-update';

  static String get updateJsonUrl => '$updateBase/$appId/update.json';
}

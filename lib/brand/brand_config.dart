import '../core/theme.dart';
import '../readers/comic/comic_models.dart';

/// Which store binary / product shell is running.
/// See docs/PRODUCT.md and docs/ENGINEERING.md.
enum AppBrand {
  comic,
  book;

  String get storageValue => name;
}

/// Per-app product shell: name, storage isolation, import policy, defaults.
///
/// Two brands ship as two apps; this config is chosen at process entry
/// (`main_comic.dart` / `main_book.dart`), not by an in-app toggle.
class BrandConfig {
  const BrandConfig({
    required this.brand,
    required this.displayName,
    required this.applicationId,
    required this.databaseName,
    required this.storageNamespace,
    required this.defaultAccent,
    required this.defaultReadingTheme,
    required this.importExtensions,
    required this.dartEntry,
  });

  final AppBrand brand;
  final String displayName;

  /// Android applicationId / Apple PRODUCT_BUNDLE_IDENTIFIER.
  final String applicationId;

  /// Drift database file key (isolates comic vs book libraries).
  final String databaseName;

  /// Subdirectory under application support. Empty = support root
  /// (comic keeps legacy layout so existing installs keep data).
  final String storageNamespace;

  final AccentPreset defaultAccent;

  /// Comic engine default; book app may ignore until reflow ships.
  final ComicReadingTheme defaultReadingTheme;

  /// File picker extensions without dots, lower-case.
  final List<String> importExtensions;

  /// Dart entry relative to package root (`lib/main_….dart`).
  final String dartEntry;

  bool get isComic => brand == AppBrand.comic;
  bool get isBook => brand == AppBrand.book;

  /// Flutter CLI flavor name (matches Android productFlavor / Xcode scheme).
  String get flavorName => brand.storageValue;

  /// 漫画产品（上架显示名待定；工程代号 comic）。
  static final comic = BrandConfig(
    brand: AppBrand.comic,
    displayName: 'Kaika Comic',
    applicationId: 'com.kaika.comic',
    databaseName: 'app_library',
    storageNamespace: '',
    defaultAccent: AppColors.defaultAccent,
    defaultReadingTheme: ComicReadingTheme.comicDefault,
    // Page-image comics: CBZ/ZIP + image/fixed-layout EPUB (manga packs).
    importExtensions: const ['cbz', 'zip', 'epub'],
    dartEntry: 'lib/main_comic.dart',
  );

  /// 图书产品占位（上架显示名待定；工程代号 book）。
  static final book = BrandConfig(
    brand: AppBrand.book,
    displayName: 'Kaika Book',
    applicationId: 'com.kaika.book',
    databaseName: 'book_library',
    storageNamespace: 'book',
    defaultAccent: AppColors.presetById('slate'),
    defaultReadingTheme: ComicReadingTheme.paper,
    importExtensions: const ['epub'],
    dartEntry: 'lib/main_book.dart',
  );
}

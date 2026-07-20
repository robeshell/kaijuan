import 'bootstrap.dart';
import 'brand/brand_config.dart';

/// Explicit comic app entry (future `--flavor comic -t lib/main_comic.dart`).
Future<void> main() => bootstrap(BrandConfig.comic);

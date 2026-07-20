import 'bootstrap.dart';
import 'brand/brand_config.dart';

/// Book app entry (placeholder product shell; reflow engine not wired yet).
///
/// Uses isolated DB/support namespace. Import whitelist is epub-only at brand
/// level; import service still comic-oriented until book pipeline lands.
Future<void> main() => bootstrap(BrandConfig.book);

/// Design tokens for kaijuan, following docs/DESIGN_FOUNDATION.md.
///
/// Three layers: primitive tokens (theme/tokens.dart) → semantic tokens
/// (theme/glass.dart + theme/skins.dart, read via theme/context.dart) →
/// theme assembly (theme/app_theme.dart). Business UI must only reference
/// the semantic layer.
library;

export 'theme/tokens.dart';
export 'theme/glass.dart';
export 'theme/skins.dart';
export 'theme/context.dart';
export 'theme/app_theme.dart';

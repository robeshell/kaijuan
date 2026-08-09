import 'package:flutter/widgets.dart';

import '../../core/theme.dart';

/// Compact, semantic type roles shared by AI panels and dialogs.
///
/// The app-wide mobile scale is intentionally reading-oriented (17sp body),
/// which is comfortable on book pages but too loose in dense AI workspaces.
/// AI surfaces cap their own visual hierarchy at 16sp on compact windows while
/// continuing to honor the platform text scaler for accessibility.
extension AiTypographyContext on BuildContext {
  /// Dialog titles, panel section titles and entity names.
  double get aiTitleSize => appIsCompact ? 16 : appTitleSize;

  /// Primary generated content and list-row titles.
  double get aiBodySize => appIsCompact ? 15 : appBodySize;

  /// Buttons, tabs, chips and compact interactive labels.
  double get aiLabelSize => appIsCompact ? 14 : appLabelSize;

  /// Supporting descriptions and metadata.
  double get aiDetailSize => appIsCompact ? 13 : appBodySecondarySize;

  /// Small counters and provenance labels; never below the app's 12sp floor.
  double get aiCaptionSize => appCaptionSize;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/core/theme/brand_tokens.g.dart';

void main() {
  test('runtime theme consumes generated brand tokens', () {
    expect(kaiBrandSpecVersion, '0.8.0');
    expect(KaiBrandMobileType.inputTextSize, 16);
    expect(
      KaiBrandMobileType.inputTextSize,
      lessThan(KaiBrandMobileType.bodySize),
    );
    expect(KaiBrandMobileType.gridTitleSize, 15);
    expect(KaiBrandMobileType.listTitleSize, 15);
    expect(AppSpacing.x4, KaiBrandSpacing.x4);
    expect(AppRadii.card, KaiBrandRadii.card);
    expect(AppProductRadii.cover, KaiProductTokens.coverRadius);
    expect(AppProductRadii.cover, lessThan(AppRadii.card));
    expect(AppSkins.standard.canvas, KaiBrandDefaultSkin.canvas);
    expect(
      AppSkins.deepNight.glass.mutedText,
      KaiBrandDeepNightSkin.glassMutedText,
    );
    expect(AppColors.defaultAccent.color, KaiProductAccents.ember);
  });
}

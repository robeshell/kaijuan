import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/brand_tokens.g.dart';

/// Shared launch canvas colors — match the app's white light canvas.
const kaijuanLaunchBackground = Colors.white;
const kaijuanLaunchTitleColor = KaiBrandDefaultSkin.glassPrimaryText;
const kaijuanLaunchSubtitleColor = KaiBrandDefaultSkin.glassMutedText;

/// First Flutter frame while prefs / DB warm up (non-Android shells).
class KaijuanLaunchScreen extends StatelessWidget {
  const KaijuanLaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: kaijuanLaunchBackground,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: kaijuanLaunchBackground,
        body: Center(child: _KaijuanLaunchLockup()),
      ),
    );
  }
}

class _KaijuanLaunchLockup extends StatelessWidget {
  const _KaijuanLaunchLockup();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '开卷 正在启动',
      child: SizedBox(
        width: 280,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: const Offset(0, -50),
              child: Image.asset(
                'brands/launch/launch_mark.png',
                width: 144,
                height: 144,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 144, height: 144),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, 28),
              child: Text(
                '开卷',
                style: TextStyle(
                  color: kaijuanLaunchTitleColor,
                  fontSize: KaiProductTokens.typographyLaunchLockupTitle,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  height: 1.15,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, 58),
              child: Text(
                '读自己的书',
                style: TextStyle(
                  color: kaijuanLaunchSubtitleColor,
                  fontSize: KaiProductTokens.typographyLaunchLockupSubtitle,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.4,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

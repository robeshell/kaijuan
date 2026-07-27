import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared launch canvas colors — match kai-brand-design light canvas.
const kaijuanLaunchBackground = Color(0xFFF7F9FC);
const kaijuanLaunchTitleColor = Color(0xFF1C1C22);
const kaijuanLaunchSubtitleColor = Color(0xFF70707A);

const _cjkFallback = <String>[
  'PingFang SC',
  'Hiragino Sans GB',
  'Heiti SC',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'sans-serif',
];

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
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 144,
                  height: 144,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, 28),
              child: const Text(
                '开卷',
                style: TextStyle(
                  color: kaijuanLaunchTitleColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  height: 1.15,
                  fontFamilyFallback: _cjkFallback,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, 58),
              child: const Text(
                '读自己的书',
                style: TextStyle(
                  color: kaijuanLaunchSubtitleColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.2,
                  height: 1.25,
                  fontFamilyFallback: _cjkFallback,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

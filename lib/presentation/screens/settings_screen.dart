import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../app/theme_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/theme.dart';
import '../widgets/app_overlays.dart';
import '../widgets/reading_theme_chip.dart';
import '../../readers/book/book_theme.dart';
import '../../readers/comic/comic_models.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.brand,
    required this.themePreferences,
    this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final ThemePreferences themePreferences;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final listenables = <Listenable>[themePreferences];
    if (readingPreferences != null) {
      listenables.add(readingPreferences!);
    }
    if (bookReadingPreferences != null) {
      listenables.add(bookReadingPreferences!);
    }

    return Scaffold(
      backgroundColor: semantics.canvas,
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (context, _) {
          // Parent shell SafeArea already applies desktop top inset; keep
          // bottom/start padding only. Nested SafeArea would zero out top.
          return ListView(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
            children: [
              const Text(
                '设置',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '外观',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ],
                selected: {themePreferences.themeMode},
                onSelectionChanged: (s) =>
                    themePreferences.setThemeMode(s.first),
              ),
              const SizedBox(height: 24),
              const Text(
                '强调色',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final preset in AppColors.accentPresets)
                    GestureDetector(
                      onTap: () => themePreferences.setAccent(preset),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: preset.color,
                          shape: BoxShape.circle,
                          border: preset.id == themePreferences.accent.id
                              ? Border.all(
                                  color: semantics.textPrimary,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: preset.id == themePreferences.accent.id
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    ),
                ],
              ),
              if (readingPreferences != null) ...[
                const SizedBox(height: 32),
                const Text(
                  '漫画阅读默认',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '新打开漫画时使用；在阅读器内修改会同步保存到这里。',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '翻页模式',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<ComicReaderMode>(
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  segments: [
                    for (final m in ComicReaderMode.values)
                      ButtonSegment(
                        value: m,
                        label: Text(m.label, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                  selected: {readingPreferences!.mode},
                  onSelectionChanged: (s) =>
                      readingPreferences!.setMode(s.first),
                ),
                const SizedBox(height: 20),
                Text(
                  '阅读方向',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<ComicReadDirection>(
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  segments: [
                    for (final d in ComicReadDirection.values)
                      ButtonSegment(
                        value: d,
                        label: Text(d.label, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                  selected: {readingPreferences!.direction},
                  onSelectionChanged: (s) =>
                      readingPreferences!.setDirection(s.first),
                ),
                const SizedBox(height: 20),
                Text(
                  '阅读背景',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in ComicReadingTheme.values)
                      ReadingThemeChip(
                        background: Color(t.backgroundArgb),
                        isDark: t.isDark,
                        label: t.label,
                        selected: readingPreferences!.readingTheme == t,
                        onTap: () => readingPreferences!.setReadingTheme(t),
                      ),
                  ],
                ),
              ],
              if (bookReadingPreferences != null) ...[
                const SizedBox(height: 32),
                const Text(
                  '图书阅读默认',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '新打开图书时使用；在阅读器内修改会同步保存到这里。',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '字号 ${bookReadingPreferences!.fontSize.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                Slider(
                  value: bookReadingPreferences!.fontSize,
                  min: BookReadingPreferences.minFontSize,
                  max: BookReadingPreferences.maxFontSize,
                  divisions: (BookReadingPreferences.maxFontSize -
                          BookReadingPreferences.minFontSize)
                      .toInt(),
                  label: bookReadingPreferences!.fontSize.toStringAsFixed(0),
                  onChanged: (v) => bookReadingPreferences!.setFontSize(v),
                ),
                const SizedBox(height: 8),
                Text(
                  '行距 ${bookReadingPreferences!.lineHeight.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                Slider(
                  value: bookReadingPreferences!.lineHeight,
                  min: BookReadingPreferences.minLineHeight,
                  max: BookReadingPreferences.maxLineHeight,
                  divisions: ((BookReadingPreferences.maxLineHeight -
                              BookReadingPreferences.minLineHeight) *
                          5)
                      .round(),
                  label: bookReadingPreferences!.lineHeight.toStringAsFixed(1),
                  onChanged: (v) => bookReadingPreferences!.setLineHeight(v),
                ),
                const SizedBox(height: 12),
                Text(
                  '阅读模式',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<BookReadingMode>(
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  segments: [
                    for (final m in BookReadingMode.values)
                      ButtonSegment(
                        value: m,
                        label: Text(m.label, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                  selected: {bookReadingPreferences!.readingMode},
                  onSelectionChanged: (s) =>
                      bookReadingPreferences!.setReadingMode(s.first),
                ),
                const SizedBox(height: 16),
                Text(
                  '版心',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 0; i < BookReadingPreferences.marginPresets.length; i++)
                      ButtonSegment(
                        value: BookReadingPreferences.marginPresets[i],
                        label: Text(
                          ['窄', '中', '宽'][i],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                  selected: {bookReadingPreferences!.margin},
                  onSelectionChanged: (s) =>
                      bookReadingPreferences!.setMargin(s.first),
                ),
                const SizedBox(height: 12),
                Text(
                  '阅读背景',
                  style: TextStyle(
                    fontSize: 13,
                    color: semantics.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in BookReadingTheme.values)
                      ReadingThemeChip(
                        background: Color(t.backgroundArgb),
                        isDark: t.isDark,
                        label: t.label,
                        selected:
                            bookReadingPreferences!.readingTheme == t,
                        onTap: () =>
                            bookReadingPreferences!.setReadingTheme(t),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              const Text(
                '关于',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _AboutCard(brand: brand),
            ],
          );
        },
      ),
    );
  }
}

class _AboutCard extends StatefulWidget {
  const _AboutCard({required this.brand});

  final BrandConfig brand;

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  late final Future<PackageInfo> _infoFuture = PackageInfo.fromPlatform();

  String get _tagline => '本地漫画与图书阅读 · CBZ / ZIP / EPUB';

  String get _blurb =>
      '文件与进度保存在本机，不上传、不刮削云端。EPUB 按内容自动进入页图或正文阅读器。';

  String get _formatsLabel =>
      widget.brand.importExtensions.map((e) => e.toUpperCase()).join(' · ');

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: semantics.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: semantics.hairline),
      ),
      child: FutureBuilder<PackageInfo>(
        future: _infoFuture,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final version = info == null
              ? '…'
              : '${info.version} (${info.buildNumber})';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_stories_outlined,
                      color: accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.brand.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tagline,
                          style: TextStyle(
                            color: semantics.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _blurb,
                style: TextStyle(
                  color: semantics.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: semantics.hairline),
              const SizedBox(height: 8),
              _AboutRow(
                label: '版本',
                value: version,
                onCopy: info == null
                    ? null
                    : () => _copy(context, version, '已复制版本号'),
              ),
              _AboutRow(
                label: '包名',
                value: widget.brand.applicationId,
                onCopy: () => _copy(
                  context,
                  widget.brand.applicationId,
                  '已复制包名',
                ),
              ),
              _AboutRow(label: '支持格式', value: _formatsLabel),
              if (!kIsWeb)
                _AboutRow(
                  label: '平台',
                  value: defaultTargetPlatform.name,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showAppSnackBar(context, toast);
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: semantics.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: '复制',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.copy_outlined,
                size: 16,
                color: semantics.textSecondary,
              ),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}

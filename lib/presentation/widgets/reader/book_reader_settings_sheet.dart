import 'package:flutter/material.dart';

import '../../../app/book_reading_preferences.dart';
import '../../../readers/book/book_theme.dart';
import '../../controllers/book_reader_controller.dart';
import '../reading_theme_chip.dart';

/// Opens the unified book typography / reading-mode panel from the reader.
void showBookReaderSettingsSheet(
  BuildContext context,
  BookReaderController controller,
) {
  final theme = controller.readingTheme;
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Color(theme.backgroundArgb),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BookReaderSettingsSheet(controller: controller),
  );
}

class _BookReaderSettingsSheet extends StatelessWidget {
  const _BookReaderSettingsSheet({required this.controller});

  final BookReaderController controller;

  static const List<double> _lineHeightPresets = [1.4, 1.6, 1.8, 2.0];
  static const List<String> _marginLabels = ['窄', '中', '宽'];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = controller.readingTheme;
        final fg = Color(theme.foregroundArgb);
        final fgMuted = theme.isDark
            ? const Color(0x99F2F2F4)
            : const Color(0x991C1C1E);

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: fgMuted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '排版',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _label('阅读模式', fgMuted),
                const SizedBox(height: 8),
                SegmentedButton<BookReadingMode>(
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    foregroundColor: fg,
                    selectedForegroundColor: fg,
                    selectedBackgroundColor: accent.withValues(alpha: 0.2),
                  ),
                  segments: [
                    for (final m in BookReadingMode.values)
                      ButtonSegment(
                        value: m,
                        label: Text(m.label, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  selected: {controller.readingMode},
                  onSelectionChanged: (s) => controller.setReadingMode(s.first),
                ),
                const SizedBox(height: 16),
                _label('字号 ${controller.fontSize.toStringAsFixed(0)}', fgMuted),
                Slider(
                  value: controller.fontSize,
                  min: BookReadingPreferences.minFontSize,
                  max: BookReadingPreferences.maxFontSize,
                  divisions: (BookReadingPreferences.maxFontSize -
                          BookReadingPreferences.minFontSize)
                      .toInt(),
                  label: controller.fontSize.toStringAsFixed(0),
                  activeColor: accent,
                  inactiveColor: fgMuted.withValues(alpha: 0.2),
                  onChanged: controller.setFontSize,
                ),
                const SizedBox(height: 8),
                _label('行距', fgMuted),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final h in _lineHeightPresets)
                      ChoiceChip(
                        label: Text(h.toStringAsFixed(1)),
                        selected: (controller.lineHeight - h).abs() < 0.05,
                        onSelected: (_) => controller.setLineHeight(h),
                        backgroundColor:
                            theme.isDark ? Colors.white12 : Colors.black12,
                        selectedColor: accent.withValues(alpha: 0.2),
                        labelStyle: TextStyle(color: fg),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _label('版心', fgMuted),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    foregroundColor: fg,
                    selectedForegroundColor: fg,
                    selectedBackgroundColor: accent.withValues(alpha: 0.2),
                  ),
                  segments: [
                    for (var i = 0; i < BookReadingPreferences.marginPresets.length; i++)
                      ButtonSegment(
                        value: BookReadingPreferences.marginPresets[i],
                        label: Text(
                          _marginLabels[i],
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  selected: {controller.margin},
                  onSelectionChanged: (s) => controller.setMargin(s.first),
                ),
                const SizedBox(height: 16),
                _label('阅读背景', fgMuted),
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
                        selected: controller.readingTheme == t,
                        onTap: () => controller.setReadingTheme(t),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      },
    );
  }

  Widget _label(String text, Color color) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: color),
    );
  }
}

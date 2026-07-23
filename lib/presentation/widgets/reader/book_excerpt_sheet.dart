import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/theme.dart';
import '../../../readers/book/book_excerpt_style.dart';
import '../app_overlays.dart';
import 'book_excerpt_card.dart';
import 'book_excerpt_export.dart';

Future<void> showBookExcerptSheet(
  BuildContext context, {
  required String quote,
  required String bookTitle,
  String? chapterTitle,
  String? subtitle,
}) {
  final text = quote.trim();
  if (text.isEmpty) {
    showAppSnackBar(context, '没有可摘录的文字');
    return Future.value();
  }
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final sheet = BookExcerptSheet(
        quote: text,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
        subtitle: subtitle,
      );
      // Desktop: InAppWebView Platform View eats sheet hits without this.
      if (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux) {
        return PointerInterceptor(child: sheet);
      }
      return sheet;
    },
  );
}

class BookExcerptSheet extends StatefulWidget {
  const BookExcerptSheet({
    super.key,
    required this.quote,
    required this.bookTitle,
    this.chapterTitle,
    this.subtitle,
  });

  final String quote;
  final String bookTitle;
  final String? chapterTitle;
  final String? subtitle;

  @override
  State<BookExcerptSheet> createState() => _BookExcerptSheetState();
}

class _BookExcerptSheetState extends State<BookExcerptSheet> {
  final _boundaryKey = GlobalKey();
  var _layout = BookExcerptLayout.classic;
  var _palette = BookExcerptPalette.paper;
  var _busy = false;

  Future<Uint8List?> _capture() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    return BookExcerptExport.capturePng(_boundaryKey);
  }

  Future<void> _withBytes(
    Future<String?> Function(Uint8List bytes) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        showAppSnackBar(context, '生成图片失败');
        return;
      }
      final message = await action(bytes);
      if (!mounted) return;
      if (message != null && message.isNotEmpty) {
        showAppSnackBar(context, message);
      }
    } catch (error) {
      if (!mounted) return;
      final text = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
      showAppSnackBar(context, text.isEmpty ? '操作失败' : text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _withBytes(BookExcerptExport.saveImage);

  Future<void> _share(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    Rect? origin;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    // macOS NSSharingServicePicker needs a non-empty anchor rect.
    if (origin == null || origin.isEmpty) {
      final size = MediaQuery.sizeOf(buttonContext);
      origin = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.75),
        width: 8,
        height: 8,
      );
    }
    return _withBytes((bytes) async {
      await BookExcerptExport.shareImage(
        bytes,
        sharePositionOrigin: origin,
      );
      return '已打开分享';
    });
  }

  Future<void> _copy() => _withBytes((bytes) async {
    final ok = await BookExcerptExport.copyImage(bytes);
    if (!ok) throw StateError('复制图片失败');
    return '已复制图片';
  });

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final fg = semantics.textPrimary;
    final muted = semantics.textSecondary;
    final accent = Theme.of(context).colorScheme.primary;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final cardWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(260.0, 360.0);
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: RepaintBoundary(
                          key: _boundaryKey,
                          child: BookExcerptCard(
                            quote: widget.quote,
                            bookTitle: widget.bookTitle,
                            chapterTitle: widget.chapterTitle,
                            subtitle: widget.subtitle,
                            layout: _layout,
                            palette: _palette,
                            width: cardWidth,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '排版',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final layout in BookExcerptLayout.all)
                            _Chip(
                              label: layout.label,
                              selected: _layout == layout,
                              accent: accent,
                              fg: fg,
                              onTap: () => setState(() => _layout = layout),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '配色',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final palette in BookExcerptPalette.all)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _PaletteDot(
                                  palette: palette,
                                  selected: _palette.id == palette.id,
                                  onTap: () =>
                                      setState(() => _palette = palette),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.download_outlined,
                        label: '保存图片',
                        enabled: !_busy,
                        onPressed: () => unawaited(_save()),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (buttonContext) {
                          return _ActionButton(
                            icon: Icons.ios_share_outlined,
                            label: '分享',
                            enabled: !_busy,
                            onPressed: () =>
                                unawaited(_share(buttonContext)),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.copy_outlined,
                        label: '复制',
                        enabled: !_busy,
                        onPressed: () => unawaited(_copy()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : fg.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: accent, weight: 300),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? accent : fg,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteDot extends StatelessWidget {
  const _PaletteDot({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final BookExcerptPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: palette.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: palette.gradient,
            border: Border.all(
              color: selected ? palette.foreground : palette.accent,
              width: selected ? 2.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'Aa',
            style: TextStyle(
              color: palette.foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: semantics.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, weight: 300),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

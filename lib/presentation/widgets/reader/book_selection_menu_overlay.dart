import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../app/book_reading_preferences.dart';
import '../../../domain/reader_models.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_overlays.dart';
import 'book_annotation_note_sheet.dart';

/// Two-phase selection menu (actions → markup) with edge-aware placement.
class BookSelectionMenuOverlay extends StatelessWidget {
  const BookSelectionMenuOverlay({super.key, required this.controller});

  final BookReaderController controller;

  static const _card = Color(0xFFFFFFF8);
  static const _fg = Color(0xFF1C1C1E);
  static const _fgMuted = Color(0xFF8E8E93);
  static const _shadow = Color(0x28000000);
  static const _gap = 12.0;

  /// Preferred bubble widths — never stretch to full screen.
  static const _actionsPreferred = 304.0;
  static const _markupPreferred = 288.0;
  static const _widthCap = 340.0;
  static const _actionsHeight = 64.0;
  static const _markupHeight = 148.0;

  static const _markupColors = <BookHighlightColor>[
    BookHighlightColor.pink,
    BookHighlightColor.yellow,
    BookHighlightColor.green,
    BookHighlightColor.purple,
  ];

  /// Desktop Platform Views already own hit-testing; a Flutter full-screen
  /// barrier above the WebView steals/confused clicks (needs two taps). Dismiss
  /// there is JS `OutsidePointerDown`. Mobile keeps a Flutter barrier.
  static bool get _useFlutterDismissBarrier {
    if (kIsWeb) return true;
    return Platform.isIOS || Platform.isAndroid;
  }

  /// Cursor I-beam vs arrow is a desktop Platform View concern only.
  static bool get _needsMenuCursorZone {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// Clamp to safe area and a hard cap so phone / tablet / desktop stay compact.
  static double _menuWidth({
    required double preferred,
    required double safeSpan,
  }) {
    final capped = math.min(preferred, _widthCap);
    if (safeSpan <= 0) return capped;
    return math.min(capped, safeSpan);
  }

  @override
  Widget build(BuildContext context) {
    final menu = controller.selectionMenu;
    if (menu == null) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final phase = menu.phase;

    final safeLeft = padding.left + _gap;
    final safeRight = size.width - padding.right - _gap;
    final safeTop = padding.top + _gap;
    final safeBottom = size.height - padding.bottom - _gap;
    final safeSpan = math.max(0.0, safeRight - safeLeft);

    final menuW = _menuWidth(
      preferred: phase == BookSelectionMenuPhase.markup
          ? _markupPreferred
          : _actionsPreferred,
      safeSpan: safeSpan,
    );
    final menuH = phase == BookSelectionMenuPhase.markup
        ? _markupHeight
        : _actionsHeight;

    final anchorLeft = menu.left.clamp(0.0, 1.0) * size.width;
    final anchorRight = menu.right.clamp(0.0, 1.0) * size.width;
    final anchorTop = menu.top.clamp(0.0, 1.0) * size.height;
    final anchorBottom = menu.bottom.clamp(0.0, 1.0) * size.height;
    final anchorMidX = (anchorLeft + anchorRight) / 2;

    final spaceAbove = anchorTop - safeTop;
    final spaceBelow = safeBottom - anchorBottom;
    final placeAbove =
        spaceAbove >= menuH + _gap || spaceAbove >= spaceBelow;

    final maxLeft = math.max(safeLeft, safeRight - menuW);
    var left = anchorMidX - menuW / 2;
    left = left.clamp(safeLeft, maxLeft);
    final top = placeAbove
        ? (anchorTop - menuH - _gap).clamp(safeTop, safeBottom - menuH)
        : (anchorBottom + _gap).clamp(safeTop, safeBottom - menuH);

    final caretX = (anchorMidX - left).clamp(16.0, menuW - 16.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.selectionMenu == null) return;
      if (!_needsMenuCursorZone) return;
      controller.setMenuCursorZone(
        left: left / size.width,
        top: top / size.height,
        right: (left + menuW) / size.width,
        bottom: (top + menuH) / size.height,
      );
    });

    final cfi = menu.cfi;
    final text = menu.text;

    final bubble = Positioned(
      left: left,
      top: top,
      width: menuW,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) =>
            controller.retainSelectionMenuForInteraction(),
        child: PointerInterceptor(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Material(
              color: Colors.transparent,
              child: phase == BookSelectionMenuPhase.markup
                  ? _MarkupCard(
                      menu: menu,
                      placeAbove: placeAbove,
                      caretX: caretX,
                      onStyle: (type, color) {
                        unawaited(
                          controller.applyAnnotationStyle(
                            type: type,
                            color: color,
                            cfiOverride: cfi,
                            textOverride: text,
                            dismissMenu: false,
                          ),
                        );
                      },
                      onClear: () {
                        unawaited(controller.removeActiveAnnotation());
                      },
                      onCopy: () => _copy(context, text),
                      onExcerpt: () => _excerpt(context, text),
                      onNote: () => unawaited(_openNote(context)),
                      onDict: () => _soon(context, '词典'),
                      onTranslate: () => _soon(context, '翻译'),
                    )
                  : _ActionsCard(
                      placeAbove: placeAbove,
                      caretX: caretX,
                      onUnderline: () =>
                          unawaited(controller.openMarkupPhase()),
                      onNote: () => unawaited(_openNote(context)),
                      onCopy: () => _copy(context, text),
                      onDict: () => _soon(context, '词典'),
                      onTranslate: () => _soon(context, '翻译'),
                      onExcerpt: () => _excerpt(context, text),
                    ),
            ),
          ),
        ),
      ),
    );

    // Mobile: Flutter barrier. Desktop: JS outside-pointer only (see above).
    if (!_useFlutterDismissBarrier) {
      return Stack(children: [bubble]);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final width = MediaQuery.sizeOf(context).width;
              final x = width <= 0 ? 0.5 : details.globalPosition.dx / width;
              controller.clearSelectionMenu();
              // Same tap: if in page-turn zone, flip immediately (mobile barrier
              // otherwise eats the gesture and the next tap felt "dead").
              if (controller.readingMode == BookReadingMode.page) {
                if (x < 0.25) {
                  controller.goPreviousPage();
                } else if (x > 0.75) {
                  controller.goNextPage();
                }
              }
            },
          ),
        ),
        bubble,
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    final ok = await controller.copySelection(textOverride: text);
    if (!context.mounted) return;
    showAppSnackBar(context, ok ? '已复制' : '没有可复制的文字');
  }

  Future<void> _excerpt(BuildContext context, String text) async {
    final ok = await controller.copyExcerpt(textOverride: text);
    if (!context.mounted) return;
    showAppSnackBar(context, ok ? '已摘录到剪贴板' : '没有可摘录的文字');
  }

  Future<void> _openNote(BuildContext context) async {
    final menu = controller.selectionMenu;
    if (menu == null || menu.cfi.trim().isEmpty) return;
    final cfi = menu.cfi;
    final text = menu.text;
    final type = menu.annotationType;
    final colorCss = menu.annotationColorCss;
    var note = menu.note?.trim() ?? '';
    if (note.isEmpty) {
      for (final row in controller.annotations) {
        if (row.cfi == cfi) {
          note = row.note?.trim() ?? '';
          break;
        }
      }
    }
    controller.clearSelectionMenu();
    if (!context.mounted) return;
    await showBookAnnotationNoteSheet(
      context,
      controller: controller,
      cfi: cfi,
      selectedText: text,
      initialNote: note,
      type: type,
      colorCss: colorCss,
    );
  }

  void _soon(BuildContext context, String name) {
    showAppSnackBar(context, '$name即将推出');
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.placeAbove,
    required this.caretX,
    required this.onUnderline,
    required this.onNote,
    required this.onCopy,
    required this.onDict,
    required this.onTranslate,
    required this.onExcerpt,
  });

  final bool placeAbove;
  final double caretX;
  final VoidCallback onUnderline;
  final VoidCallback onNote;
  final VoidCallback onCopy;
  final VoidCallback onDict;
  final VoidCallback onTranslate;
  final VoidCallback onExcerpt;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Row(
        children: [
          _ActionItem(
            icon: Icons.format_underlined_rounded,
            label: '划线',
            onPressed: onUnderline,
          ),
          _ActionItem(
            icon: Icons.edit_note_rounded,
            label: '笔记',
            onPressed: onNote,
          ),
          _ActionItem(
            icon: Icons.copy_rounded,
            label: '复制',
            onPressed: onCopy,
          ),
          _ActionItem(
            icon: Icons.menu_book_rounded,
            label: '词典',
            onPressed: onDict,
          ),
          _ActionItem(
            icon: Icons.translate_rounded,
            label: '翻译',
            onPressed: onTranslate,
          ),
          _ActionItem(
            icon: Icons.format_quote_rounded,
            label: '书摘',
            onPressed: onExcerpt,
          ),
        ],
      ),
    );

    return _Bubble(
      placeAbove: placeAbove,
      caretX: caretX,
      child: body,
    );
  }
}

class _MarkupCard extends StatelessWidget {
  const _MarkupCard({
    required this.menu,
    required this.placeAbove,
    required this.caretX,
    required this.onStyle,
    required this.onClear,
    required this.onCopy,
    required this.onExcerpt,
    required this.onNote,
    required this.onDict,
    required this.onTranslate,
  });

  final BookSelectionMenu menu;
  final bool placeAbove;
  final double caretX;
  final void Function(BookAnnotationType type, BookHighlightColor color)
  onStyle;
  final VoidCallback onClear;
  final VoidCallback onCopy;
  final VoidCallback onExcerpt;
  final VoidCallback onNote;
  final VoidCallback onDict;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    final activeType = menu.annotationType ?? BookAnnotationType.underline;
    final activeColor = menu.annotationColorCss == null
        ? BookHighlightColor.yellow
        : BookHighlightColor.fromCss(menu.annotationColorCss!);

    final tools = Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
          _StyleChip(
            selected: activeType == BookAnnotationType.underline,
            child: const Icon(Icons.format_underlined, size: 18),
            onPressed: () => onStyle(BookAnnotationType.underline, activeColor),
          ),
          const SizedBox(width: 6),
          _StyleChip(
            selected: activeType == BookAnnotationType.wavy,
            child: const Icon(Icons.waves_rounded, size: 18),
            onPressed: () => onStyle(BookAnnotationType.wavy, activeColor),
          ),
          const SizedBox(width: 6),
          _StyleChip(
            selected: activeType == BookAnnotationType.highlight,
            child: const Icon(Icons.format_color_fill_rounded, size: 18),
            onPressed: () => onStyle(BookAnnotationType.highlight, activeColor),
          ),
          const Spacer(),
          for (var i = 0; i < BookSelectionMenuOverlay._markupColors.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
              child: _ColorDot(
                color: Color(BookSelectionMenuOverlay._markupColors[i].argb),
                selected:
                    activeColor == BookSelectionMenuOverlay._markupColors[i],
                onPressed: () => onStyle(
                  activeType,
                  BookSelectionMenuOverlay._markupColors[i],
                ),
              ),
            ),
        ],
      ),
    );

    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
      child: Row(
        children: [
          _ActionItem(
            icon: Icons.delete_outline_rounded,
            label: '清空',
            onPressed: onClear,
          ),
          _ActionItem(
            icon: Icons.edit_note_rounded,
            label: '笔记',
            onPressed: onNote,
          ),
          _ActionItem(
            icon: Icons.copy_rounded,
            label: '复制',
            onPressed: onCopy,
          ),
          _ActionItem(
            icon: Icons.menu_book_rounded,
            label: '词典',
            onPressed: onDict,
          ),
          _ActionItem(
            icon: Icons.translate_rounded,
            label: '翻译',
            onPressed: onTranslate,
          ),
          _ActionItem(
            icon: Icons.format_quote_rounded,
            label: '书摘',
            onPressed: onExcerpt,
          ),
        ],
      ),
    );

    // Triangle always on the side facing the text.
    final column = placeAbove
        ? Column(mainAxisSize: MainAxisSize.min, children: [tools, actions])
        : Column(mainAxisSize: MainAxisSize.min, children: [actions, tools]);

    return _Bubble(
      placeAbove: placeAbove,
      caretX: caretX,
      child: column,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.placeAbove,
    required this.caretX,
    required this.child,
  });

  final bool placeAbove;
  final double caretX;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!placeAbove) _CaretSlot(caretX: caretX, pointDown: false),
        DecoratedBox(
          decoration: BoxDecoration(
            color: BookSelectionMenuOverlay._card,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: BookSelectionMenuOverlay._shadow,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
        if (placeAbove) _CaretSlot(caretX: caretX, pointDown: true),
      ],
    );
  }
}

class _CaretSlot extends StatelessWidget {
  const _CaretSlot({required this.caretX, required this.pointDown});

  final double caretX;
  final bool pointDown;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: caretX - 7,
            top: pointDown ? -1 : 1,
            child: CustomPaint(
              size: const Size(14, 7),
              painter: _CaretPainter(
                color: BookSelectionMenuOverlay._card,
                pointDown: pointDown,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter({required this.color, required this.pointDown});

  final Color color;
  final bool pointDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointDown) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CaretPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointDown != pointDown;
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onPressed(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: BookSelectionMenuOverlay._fg),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  color: BookSelectionMenuOverlay._fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    required this.selected,
    required this.child,
    required this.onPressed,
  });

  final bool selected;
  final Widget child;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onPressed(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5E9) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF34C759) : const Color(0x00000000),
          ),
        ),
        child: IconTheme(
          data: IconThemeData(
            color: selected
                ? const Color(0xFF34C759)
                : BookSelectionMenuOverlay._fgMuted,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onPressed(),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected
                    ? BookSelectionMenuOverlay._fg
                    : const Color(0x22000000),
                width: selected ? 2 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 11, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

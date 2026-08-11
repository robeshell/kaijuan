import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';
import '../../../domain/reader_models.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_overlays.dart';
import 'book_ai_chat_sheet.dart';
import 'book_ai_language_sheet.dart';
import 'book_annotation_note_sheet.dart';
import 'book_excerpt_sheet.dart';
import '../../../readers/book/book_language_actions.dart';

/// Two-phase selection menu (actions → markup) with edge-aware placement.
class BookSelectionMenuOverlay extends StatelessWidget {
  const BookSelectionMenuOverlay({super.key, required this.controller});

  final BookReaderController controller;

  static const _gap = 12.0;

  /// Preferred bubble widths — never stretch to full screen.
  static const _actionsPreferred = 304.0;
  static const _markupPreferred = 288.0;
  static const _widthCap = 340.0;

  /// Paint-approximate heights (card + caret). Used for above/below decision
  /// and clamps only — vertical gap is pinned to the selection edge.
  ///
  /// Actions: pad 6×2 + icon 20 + gap 2 + caption (~14@1.15) + caret 7 ≈ 55–64.
  /// Markup is two rows; keep a generous estimate so we do not force a too-short
  /// [slotHeight] (that caused RenderFlex bottom overflow near the top edge).
  static const _actionsHeightEstimate = 64.0;
  static const _markupHeightEstimate = 128.0;

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
    final menu = controller.annotations.selectionMenu;
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
    final menuHEstimate = phase == BookSelectionMenuPhase.markup
        ? _markupHeightEstimate
        : _actionsHeightEstimate;

    final anchorLeft = menu.left.clamp(0.0, 1.0) * size.width;
    final anchorRight = menu.right.clamp(0.0, 1.0) * size.width;
    final anchorTop = menu.top.clamp(0.0, 1.0) * size.height;
    final anchorBottom = menu.bottom.clamp(0.0, 1.0) * size.height;
    final anchorMidX = (anchorLeft + anchorRight) / 2;

    // Full selection box: above first line / below last line — never cover
    // mid-lines of a multi-line mark (focus-line anchoring caused that).
    final spaceAbove = anchorTop - safeTop;
    final spaceBelow = safeBottom - anchorBottom;
    var placeAbove =
        spaceAbove >= menuHEstimate + _gap || spaceAbove >= spaceBelow;
    if (placeAbove &&
        spaceAbove < menuHEstimate + _gap &&
        spaceBelow >= menuHEstimate + _gap) {
      placeAbove = false;
    } else if (!placeAbove &&
        spaceBelow < menuHEstimate + _gap &&
        spaceAbove >= menuHEstimate + _gap) {
      placeAbove = true;
    }

    final maxLeft = math.max(safeLeft, safeRight - menuW);
    var left = anchorMidX - menuW / 2;
    left = left.clamp(safeLeft, maxLeft);

    // Pin near edge with fixed gap. placeAbove uses a top→anchor slot +
    // Align(bottom) so real paint height does not inflate the gap (old bug:
    // top = anchor - estimatedH - gap sat too far when estimate was high).
    // Never use Positioned(bottom-only) — expands the child mid-screen.
    //
    // Important: only apply [slotHeight] when the slot is tall enough for the
    // bubble. A short max-height (e.g. 31px) makes the inner Column overflow
    // instead of growing — yellow/black stripes on selection near the top.
    final double posTop;
    final double? slotHeight;
    final double zoneTop;
    final double zoneBottom;
    if (placeAbove) {
      final edge = anchorTop - _gap;
      final available = edge - safeTop;
      if (available >= menuHEstimate) {
        posTop = safeTop;
        slotHeight = available;
        zoneTop = math.max(safeTop, edge - menuHEstimate);
        zoneBottom = edge;
      } else {
        // Not enough room for a tight slot: pin by top without max-height so
        // the bubble paints full size (may sit slightly over the selection).
        posTop = math.max(safeTop, edge - menuHEstimate);
        slotHeight = null;
        zoneTop = posTop;
        zoneBottom = posTop + menuHEstimate;
      }
    } else {
      posTop = (anchorBottom + _gap).clamp(safeTop, safeBottom - menuHEstimate);
      slotHeight = null;
      zoneTop = posTop;
      zoneBottom = posTop + menuHEstimate;
    }

    final caretX = (anchorMidX - left).clamp(16.0, menuW - 16.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.annotations.selectionMenu == null) return;
      if (!_needsMenuCursorZone) return;
      controller.annotations.setMenuCursorZone(
        left: left / size.width,
        top: zoneTop.clamp(0.0, size.height) / size.height,
        right: (left + menuW) / size.width,
        bottom: zoneBottom.clamp(0.0, size.height) / size.height,
      );
    });

    final cfi = menu.cfi;
    final text = menu.text;

    final card = phase == BookSelectionMenuPhase.markup
        ? _MarkupCard(
            menu: menu,
            placeAbove: placeAbove,
            caretX: caretX,
            onStyle: (type, color) {
              unawaited(
                controller.annotations.applyAnnotationStyle(
                  type: type,
                  color: color,
                  cfiOverride: cfi,
                  textOverride: text,
                  dismissMenu: false,
                ),
              );
            },
            onClear: () {
              unawaited(controller.annotations.removeActiveAnnotation());
            },
            onCopy: () => _copy(context, text),
            onExcerpt: () => _excerpt(context, text),
            onNote: () => unawaited(_openNote(context)),
            onDict: () => unawaited(
              _openLanguage(context, BookLanguageOperation.dictionary, text),
            ),
            onTranslate: () => unawaited(
              _openLanguage(
                context,
                BookLanguageOperation.selectionTranslation,
                text,
              ),
            ),
          )
        : _ActionsCard(
            placeAbove: placeAbove,
            caretX: caretX,
            onUnderline: () =>
                unawaited(controller.annotations.openMarkupPhase()),
            onNote: () => unawaited(_openNote(context)),
            onCopy: () => _copy(context, text),
            onDict: () => unawaited(
              _openLanguage(context, BookLanguageOperation.dictionary, text),
            ),
            onTranslate: () => unawaited(
              _openLanguage(
                context,
                BookLanguageOperation.selectionTranslation,
                text,
              ),
            ),
            onSearch: () {
              final q = text.trim();
              controller.annotations.clearSelectionMenu();
              controller.search.openSearch(initialQuery: q.isEmpty ? null : q);
            },
            onExcerpt: () => _excerpt(context, text),
            onAiChat: () => unawaited(_openAiChat(context, text)),
          );

    final interactive = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) =>
          controller.annotations.retainSelectionMenuForInteraction(),
      child: PointerInterceptor(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(color: Colors.transparent, child: card),
        ),
      ),
    );

    final bubble = Positioned(
      left: left,
      top: posTop,
      width: menuW,
      child: slotHeight != null
          ? SizedBox(
              height: slotHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: interactive,
              ),
            )
          : interactive,
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
            onTapUp: (_) {
              // Absorb the finger-up that finished the selection (menu open race).
              if (!controller.annotations.selectionMenuBarrierAcceptsDismiss) {
                return;
              }
              // Dismiss only — never page-turn here. Edge zones are ~28% wide;
              // coupling flip to dismiss made left-side selections jump 上一页
              // on iOS/Android as soon as the bubble appeared.
              controller.annotations.clearSelectionMenu();
            },
          ),
        ),
        bubble,
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    final ok = await controller.annotations.copySelection(textOverride: text);
    if (!context.mounted) return;
    showAppSnackBar(context, ok ? '已复制' : '没有可复制的文字');
  }

  Future<void> _excerpt(BuildContext context, String text) async {
    final quote = text.trim();
    if (quote.isEmpty) {
      showAppSnackBar(context, '没有可摘录的文字');
      return;
    }
    final title = controller.item.title;
    final chapter = controller.currentChapterTitle;
    final subtitle = controller.item.seriesName;
    controller.annotations.clearSelectionMenu();
    if (!context.mounted) return;
    await showBookExcerptSheet(
      context,
      quote: quote,
      bookTitle: title,
      chapterTitle: chapter,
      subtitle: subtitle,
    );
  }

  Future<void> _openNote(BuildContext context) async {
    final menu = controller.annotations.selectionMenu;
    if (menu == null || menu.cfi.trim().isEmpty) return;
    final cfi = menu.cfi;
    final text = menu.text;
    final type = menu.annotationType;
    final colorCss = menu.annotationColorCss;
    var note = menu.note?.trim() ?? '';
    if (note.isEmpty) {
      for (final row in controller.annotations.annotations) {
        if (row.cfi == cfi) {
          note = row.note?.trim() ?? '';
          break;
        }
      }
    }
    controller.annotations.clearSelectionMenu();
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

  Future<void> _openAiChat(BuildContext context, String text) async {
    final sel = text.trim();
    // Keep page highlight; only drop the action bubble.
    controller.annotations.dismissSelectionMenuKeepHighlight();
    if (!context.mounted) return;
    await showBookAiChatSheet(
      context,
      controller: controller,
      initialSelection: sel.isEmpty ? null : sel,
    );
  }

  Future<void> _openLanguage(
    BuildContext context,
    BookLanguageOperation operation,
    String text,
  ) async {
    final cfi = controller.annotations.selectionMenu?.cfi;
    final wantAi =
        controller.canUseAiLanguage &&
        operation != BookLanguageOperation.fullBookTranslation;
    // Capture surrounding text BEFORE the WebView selection is cleared
    // (translation 附带选区前后文). Only when the user enabled it.
    String? before;
    String? after;
    if (wantAi &&
        operation == BookLanguageOperation.selectionTranslation &&
        controller.translationPreferences.includeContext) {
      final prefs = controller.translationPreferences;
      final ctx = await controller.bridge.loadSelectionContext(
        before: prefs.contextChars,
        after: prefs.contextChars,
      );
      before = ctx?.before;
      after = ctx?.after;
    }
    controller.annotations.clearSelectionMenu();
    if (wantAi) {
      if (!context.mounted) return;
      await showBookAiLanguageSheet(
        context,
        controller: controller,
        operation: operation,
        text: text,
        cfi: cfi,
        contextBefore: before,
        contextAfter: after,
      );
      return;
    }
    final result = await controller.annotations.performPlatformLanguageAction(
      operation: operation,
      textOverride: text,
    );
    if (!context.mounted || result.handled) return;
    showAppSnackBar(context, result.message ?? '当前设备暂不可用');
  }
}

class _ActionsCard extends StatefulWidget {
  const _ActionsCard({
    required this.placeAbove,
    required this.caretX,
    required this.onUnderline,
    required this.onNote,
    required this.onCopy,
    required this.onDict,
    required this.onTranslate,
    required this.onSearch,
    required this.onExcerpt,
    required this.onAiChat,
  });

  final bool placeAbove;
  final double caretX;
  final VoidCallback onUnderline;
  final VoidCallback onNote;
  final VoidCallback onCopy;
  final VoidCallback onDict;
  final VoidCallback onTranslate;
  final VoidCallback onSearch;
  final VoidCallback onExcerpt;
  final VoidCallback onAiChat;

  @override
  State<_ActionsCard> createState() => _ActionsCardState();
}

class _ActionsCardState extends State<_ActionsCard> {
  /// Compact phones: primary row +「更多」for secondary actions.
  /// Tablet / desktop list every action in one row.
  var _showMore = false;

  @override
  Widget build(BuildContext context) {
    // Prefer window class over bubble width — preferred menu width is ~304,
    // which would always look "wide" even on phones.
    final compact = context.appIsCompact;

    // Wide: primary actions including 问 AI.
    // Compact primary: 划线·笔记·复制·搜索·更多.
    // Compact more: 词典·翻译·问 AI·书摘·收起.
    final List<Widget> items;
    if (!compact) {
      items = [
        _ActionItem(
          icon: KaijuanIcons.underline,
          label: '划线',
          onPressed: widget.onUnderline,
        ),
        _ActionItem(
          icon: KaijuanIcons.edit,
          label: '笔记',
          onPressed: widget.onNote,
        ),
        _ActionItem(
          icon: KaijuanIcons.copy,
          label: '复制',
          onPressed: widget.onCopy,
        ),
        _ActionItem(
          icon: KaijuanIcons.aiChat,
          label: '问 AI',
          onPressed: widget.onAiChat,
        ),
        _ActionItem(
          icon: KaijuanIcons.open,
          label: '词典',
          onPressed: widget.onDict,
        ),
        _ActionItem(
          icon: KaijuanIcons.translate,
          label: '翻译',
          onPressed: widget.onTranslate,
        ),
        _ActionItem(
          icon: KaijuanIcons.search,
          label: '搜索',
          onPressed: widget.onSearch,
        ),
        _ActionItem(
          icon: KaijuanIcons.quote,
          label: '书摘',
          onPressed: widget.onExcerpt,
        ),
      ];
    } else if (_showMore) {
      items = [
        _ActionItem(
          icon: KaijuanIcons.open,
          label: '词典',
          onPressed: widget.onDict,
        ),
        _ActionItem(
          icon: KaijuanIcons.translate,
          label: '翻译',
          onPressed: widget.onTranslate,
        ),
        _ActionItem(
          icon: KaijuanIcons.aiChat,
          label: '问 AI',
          onPressed: widget.onAiChat,
        ),
        _ActionItem(
          icon: KaijuanIcons.quote,
          label: '书摘',
          onPressed: widget.onExcerpt,
        ),
        _ActionItem(
          icon: KaijuanIcons.chevronLeft,
          label: '收起',
          onPressed: () => setState(() => _showMore = false),
        ),
      ];
    } else {
      items = [
        _ActionItem(
          icon: KaijuanIcons.underline,
          label: '划线',
          onPressed: widget.onUnderline,
        ),
        _ActionItem(
          icon: KaijuanIcons.edit,
          label: '笔记',
          onPressed: widget.onNote,
        ),
        _ActionItem(
          icon: KaijuanIcons.copy,
          label: '复制',
          onPressed: widget.onCopy,
        ),
        _ActionItem(
          icon: KaijuanIcons.search,
          label: '搜索',
          onPressed: widget.onSearch,
        ),
        _ActionItem(
          icon: KaijuanIcons.more,
          label: '更多',
          onPressed: () => setState(() => _showMore = true),
        ),
      ];
    }

    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Row(children: items),
    );

    return _Bubble(
      placeAbove: widget.placeAbove,
      caretX: widget.caretX,
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
            label: '实线划线',
            selected: activeType == BookAnnotationType.underline,
            child: const Icon(KaijuanIcons.underline, size: 18),
            onPressed: () => onStyle(BookAnnotationType.underline, activeColor),
          ),
          const SizedBox(width: 6),
          _StyleChip(
            label: '波浪线',
            selected: activeType == BookAnnotationType.wavy,
            child: const Icon(KaijuanIcons.wavy, size: 18),
            onPressed: () => onStyle(BookAnnotationType.wavy, activeColor),
          ),
          const SizedBox(width: 6),
          _StyleChip(
            label: '高亮',
            selected: activeType == BookAnnotationType.highlight,
            child: const Icon(KaijuanIcons.highlight, size: 18),
            onPressed: () => onStyle(BookAnnotationType.highlight, activeColor),
          ),
          const Spacer(),
          for (
            var i = 0;
            i < BookSelectionMenuOverlay._markupColors.length;
            i++
          )
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
              child: _ColorDot(
                label: BookSelectionMenuOverlay._markupColors[i].label,
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
            icon: KaijuanIcons.delete,
            label: '清空',
            onPressed: onClear,
          ),
          _ActionItem(icon: KaijuanIcons.edit, label: '笔记', onPressed: onNote),
          _ActionItem(icon: KaijuanIcons.copy, label: '复制', onPressed: onCopy),
          _ActionItem(icon: KaijuanIcons.open, label: '词典', onPressed: onDict),
          _ActionItem(
            icon: KaijuanIcons.translate,
            label: '翻译',
            onPressed: onTranslate,
          ),
          _ActionItem(
            icon: KaijuanIcons.quote,
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

    return _Bubble(placeAbove: placeAbove, caretX: caretX, child: column);
  }
}

class _Bubble extends StatelessWidget {
  static const _minimumSurfaceOpacity = 0.96;

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
    final glass = context.appGlass;
    // The selection menu sits directly over the reading page, so the shared
    // strong glass surface still lets a little too much text show through.
    // Keep skin-specific colors, but make this transient menu slightly more
    // opaque without changing every other strong glass surface in the app.
    final surface = glass.strongSurface.withValues(
      alpha: math.max(glass.strongSurface.a, _minimumSurfaceOpacity),
    );
    // mainAxisSize.min + no max-height parent: intrinsic size only.
    // Callers must not wrap this in a shorter max-height box (see placement).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!placeAbove)
          _CaretSlot(caretX: caretX, pointDown: false, color: surface),
        DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: glass.border),
            boxShadow: [
              BoxShadow(
                color: glass.shadow,
                blurRadius: 16 * context.appSkinEffects.shadowScale,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
        if (placeAbove)
          _CaretSlot(caretX: caretX, pointDown: true, color: surface),
      ],
    );
  }
}

class _CaretSlot extends StatelessWidget {
  const _CaretSlot({
    required this.caretX,
    required this.pointDown,
    required this.color,
  });

  final double caretX;
  final bool pointDown;
  final Color color;

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
              painter: _CaretPainter(color: color, pointDown: pointDown),
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
    final fg = context.appPrimaryText;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize:
                            KaiProductTokens.typographyReaderSelectionMenu,
                        height: 1.15,
                        color: fg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    required this.label,
    required this.selected,
    required this.child,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Widget child;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.09)
                    : context.appTint(0.025),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: selected ? accent : context.appSecondaryText,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.label,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label色',
      child: Tooltip(
        message: '$label色',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: selected
                          ? context.appPrimaryText
                          : const Color(0x22000000),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          KaijuanIcons.check,
                          size: 11,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

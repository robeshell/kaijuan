import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether [node] is editing text (or sits inside an [EditableText]).
///
/// Used by reader chrome to avoid eating Space / arrows / letter shortcuts
/// while the user is in a TextField (search, AI chat, notes, settings).
bool focusIsTextEditing(FocusNode? node) {
  if (node == null) return false;
  final context = node.context;
  if (context == null) return false;
  if (!context.mounted) return false;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}

/// Primary focus is currently a text field / editable.
bool primaryFocusIsTextEditing() =>
    focusIsTextEditing(FocusManager.instance.primaryFocus);

bool get _isDesktop {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
}

/// Desktop keyboard (macOS / Windows / Linux), not compact layout.
bool get isDesktopTextEditingPlatform => _isDesktop;

/// True while the platform IME / dictation still owns a composing region.
///
/// Programmatic [TextEditingController] writes or WebView `clearFocus` during
/// composition drop the first dictation chunk and can garble Backspace/Enter.
bool textEditingIsComposing(TextEditingController controller) {
  final range = controller.value.composing;
  return range.isValid && !range.isCollapsed;
}

/// Replace [controller] text only when it is safe for IME (not mid-compose).
///
/// Returns false when the write was skipped because composition is active.
bool setControllerTextIfIdle(
  TextEditingController controller,
  String text, {
  int? selectionOffset,
}) {
  if (textEditingIsComposing(controller)) return false;
  final offset = (selectionOffset ?? text.length).clamp(0, text.length);
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
    composing: TextRange.empty,
  );
  return true;
}

/// Insert clipboard text into [controller] at the current selection.
Future<void> pasteIntoController(TextEditingController controller) async {
  if (textEditingIsComposing(controller)) return;
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final clip = data?.text;
  if (clip == null || clip.isEmpty) return;
  final value = controller.value;
  final text = value.text;
  final sel = value.selection;
  final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
  final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
  final next = text.replaceRange(start, end, clip);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + clip.length),
    composing: TextRange.empty,
  );
}

void copyFromController(TextEditingController controller) {
  final sel = controller.selection;
  if (!sel.isValid || sel.isCollapsed) return;
  final text = controller.text;
  final start = sel.start.clamp(0, text.length);
  final end = sel.end.clamp(0, text.length);
  if (start >= end) return;
  Clipboard.setData(ClipboardData(text: text.substring(start, end)));
}

void cutFromController(TextEditingController controller) {
  if (textEditingIsComposing(controller)) return;
  final sel = controller.selection;
  if (!sel.isValid || sel.isCollapsed) return;
  final text = controller.text;
  final start = sel.start.clamp(0, text.length);
  final end = sel.end.clamp(0, text.length);
  if (start >= end) return;
  Clipboard.setData(ClipboardData(text: text.substring(start, end)));
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, ''),
    selection: TextSelection.collapsed(offset: start),
    composing: TextRange.empty,
  );
}

void selectAllInController(TextEditingController controller) {
  if (textEditingIsComposing(controller)) return;
  final text = controller.text;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

/// Desktop copy/paste/cut/select-all that mutates [controller] directly.
///
/// Prefer this over [PasteTextIntent] alone: Intent/Actions can miss when a
/// PlatformView (WKWebView) has been first responder, while a focused field
/// still receives some Flutter key events.
Widget withDesktopTextEditingShortcuts(
  Widget child, {
  TextEditingController? controller,
}) {
  if (!_isDesktop || controller == null) {
    return child;
  }
  return CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
        pasteIntoController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
        pasteIntoController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
        copyFromController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
        copyFromController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
        cutFromController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
        cutFromController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
        selectAllInController(controller);
      },
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
        selectAllInController(controller);
      },
    },
    child: child,
  );
}

/// Desktop chat submit: Enter sends when IME is idle; Shift+Enter newlines.
///
/// Must not bind Enter as a [CallbackShortcuts] key — that would swallow
/// IME confirm. Ignored events fall through to [EditableText].
Widget withDesktopChatSubmit(
  Widget child, {
  required TextEditingController controller,
  required VoidCallback onSubmit,
  bool enabled = true,
}) {
  if (!_isDesktop) return child;
  return Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key != LogicalKeyboardKey.enter &&
          key != LogicalKeyboardKey.numpadEnter) {
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      if (!enabled || textEditingIsComposing(controller)) {
        return KeyEventResult.ignored;
      }
      onSubmit();
      return KeyEventResult.handled;
    },
    child: child,
  );
}

import 'package:flutter/widgets.dart';

/// Reads the global bounds of a mounted cover widget.
///
/// Kept for callers that still measure covers; open transition no longer
/// expands from this rect (Apple Books style waiting cover instead).
Rect? captureGlobalRect(BuildContext? context) {
  final box = context?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

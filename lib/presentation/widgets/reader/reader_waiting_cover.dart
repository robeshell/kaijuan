import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme.dart'; // appIsShortViewport + appPrimaryText

/// Window-fitted cover shown while a reader prepares content (Apple Books–style
/// open). Backdrop is painted by the reveal layer behind this widget.
class ReaderWaitingCover extends StatelessWidget {
  const ReaderWaitingCover({
    super.key,
    required this.coverPath,
    required this.title,
  });

  final String? coverPath;
  final String title;

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    // Phone landscape: less inset so the cover still reads at usable size.
    final short = context.appIsShortViewport;
    final hPad = short ? 28.0 : 40.0;
    final vPad = short ? 16.0 : 48.0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: Center(
          child: path != null && path.isNotEmpty
              ? Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => _TitleFallback(title: title),
                )
              : _TitleFallback(title: title),
        ),
      ),
    );
  }
}

class _TitleFallback extends StatelessWidget {
  const _TitleFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final fg = context.appPrimaryText;
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fg.withValues(alpha: 0.72),
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
  }
}

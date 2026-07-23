import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'cover_card_ink.dart';

/// Collage cover for a 合集 card (≈ single book cover size, up to 4 thumbs).
class CollectionCover extends StatelessWidget {
  const CollectionCover({
    super.key,
    required this.coverPaths,
    this.borderRadius = 12,
  });

  final List<String> coverPaths;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final paths = coverPaths.take(4).toList();

    return SoftCoverFrame(
      key: ValueKey(paths.join('|')),
      radius: borderRadius,
      child: ColoredBox(
        color: semantics.canvas == Colors.white
            ? AppColors.lightWash
            : semantics.surface,
        child: paths.isEmpty
            ? Center(
                child: Icon(
                  Icons.collections_bookmark_outlined,
                  weight: 300,
                  size: 28,
                  color: semantics.textSecondary.withValues(alpha: 0.5),
                ),
              )
            : paths.length == 1
                ? _thumb(paths[0], semantics)
                : _grid(paths, semantics),
      ),
    );
  }

  Widget _grid(List<String> paths, AppSemantics semantics) {
    // 2×2 cells; missing slots stay wash.
    Widget cell(int i) {
      if (i >= paths.length) {
        return ColoredBox(color: AppColors.lightWash.withValues(alpha: 0.5));
      }
      return _thumb(paths[i], semantics);
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: cell(0)),
              const SizedBox(width: 1),
              Expanded(child: cell(1)),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(child: cell(2)),
              const SizedBox(width: 1),
              Expanded(child: cell(3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumb(String path, AppSemantics semantics) {
    return Image.file(
      File(path),
      key: ValueKey(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => ColoredBox(color: semantics.canvas),
    );
  }
}

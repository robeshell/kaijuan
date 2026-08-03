import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import 'cover_card_ink.dart';

/// Collage cover for a 合集 card (≈ single book cover size, up to 4 thumbs).
class CollectionCover extends StatelessWidget {
  const CollectionCover({
    super.key,
    required this.coverPaths,
    this.borderRadius = AppProductRadii.cover,
  });

  final List<String> coverPaths;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final paths = coverPaths.take(4).toList();
    final light = Theme.of(context).brightness == Brightness.light;
    final base = light ? AppColors.lightWash : context.appColors.surface;
    final emptySlot = light
        ? AppColors.lightWash.withValues(alpha: 0.5)
        : context.appColors.surfaceContainerHighest.withValues(alpha: 0.55);

    return SoftCoverFrame(
      key: ValueKey(paths.join('|')),
      radius: borderRadius,
      child: ColoredBox(
        color: base,
        child: paths.isEmpty
            ? Center(
                child: Icon(
                  KaijuanIcons.collections,
                  weight: 300,
                  size: 28,
                  color: context.appSecondaryText.withValues(alpha: 0.5),
                ),
              )
            : paths.length == 1
            ? _thumb(context, paths[0])
            : _grid(context, paths, emptySlot: emptySlot),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    List<String> paths, {
    required Color emptySlot,
  }) {
    // 2×2 cells; missing slots stay on the surface ramp (not a light wash in dark).
    Widget cell(int i) {
      if (i >= paths.length) {
        return ColoredBox(color: emptySlot);
      }
      return _thumb(context, paths[i]);
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

  Widget _thumb(BuildContext context, String path) {
    return Image.file(
      File(path),
      key: ValueKey(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) =>
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
    );
  }
}

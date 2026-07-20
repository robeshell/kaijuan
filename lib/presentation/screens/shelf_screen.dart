import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/theme.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../widgets/app_overlays.dart';
import 'book_reader_screen.dart';
import 'comic_reader_screen.dart';

/// Shelf: 继续阅读 + 最近 + 我的书架（仅单本钉选；合集在书库展示）.
class ShelfScreen extends StatelessWidget {
  const ShelfScreen({
    super.key,
    required this.brand,
    required this.libraryController,
    this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final LibraryController libraryController;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  void _openReal(BuildContext context, ReadingItem item) {
    if (item.kind == ReaderKind.book.storageValue || brand.isBook) {
      BookReaderScreen.open(
        context,
        database: libraryController.database,
        item: item,
        readingPreferences: bookReadingPreferences,
      );
      return;
    }
    if (item.kind != ReaderKind.comic.storageValue) return;
    ComicReaderScreen.open(
      context,
      database: libraryController.database,
      item: item,
      readingPreferences: readingPreferences,
    );
  }

  Future<void> _removeFromShelf(BuildContext context, ReadingItem item) async {
    await libraryController.setOnShelf(item.id, onShelf: false);
    if (!context.mounted) return;
    showAppSnackBar(context, '已从书架移出「${item.title}」');
  }

  Future<void> _showShelfItemMenu(
    BuildContext context,
    ReadingItem item,
  ) async {
    await showAppSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetTile(
                icon: Icons.menu_book_outlined,
                title: '打开',
                onTap: () {
                  Navigator.pop(ctx);
                  _openReal(context, item);
                },
              ),
              AppSheetTile(
                icon: Icons.bookmark_remove_outlined,
                title: '移出我的书架',
                onTap: () {
                  Navigator.pop(ctx);
                  _removeFromShelf(context, item);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: semantics.canvas,
      body: StreamBuilder<List<ContinueReadingEntry>>(
        stream: libraryController.watchContinueReading(),
        builder: (context, recentSnap) {
          return StreamBuilder<List<ReadingItem>>(
            stream: libraryController.watchOnShelf(),
            builder: (context, shelfSnap) {
              final recent =
                  recentSnap.data ?? const <ContinueReadingEntry>[];
              final onShelf = shelfSnap.data ?? const <ReadingItem>[];

              if (recent.isEmpty && onShelf.isEmpty) {
                return const _EmptyShelf();
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                children: [
                  if (recent.isNotEmpty) ...[
                    const _SectionTitle('继续阅读'),
                    const SizedBox(height: 12),
                    _HeroCard(
                      title: recent.first.item.title,
                      progress: recent.first.progressFraction ?? 0,
                      accent: accent,
                      surface: semantics.surface,
                      hairline: semantics.hairline,
                      muted: semantics.textSecondary,
                      cover: _FileOrFallbackCover(
                        path: recent.first.item.coverPath,
                      ),
                      onTap: () => _openReal(context, recent.first.item),
                    ),
                    if (recent.length > 1) ...[
                      const SizedBox(height: 32),
                      const _SectionTitle('最近阅读'),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recent.length - 1,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final e = recent[i + 1];
                            return _CoverCard(
                              title: e.item.title,
                              progress: e.progressFraction,
                              accent: accent,
                              hairline: semantics.hairline,
                              cover: _FileOrFallbackCover(
                                path: e.item.coverPath,
                              ),
                              onTap: () => _openReal(context, e.item),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                  if (onShelf.isNotEmpty) ...[
                    if (recent.isNotEmpty) const SizedBox(height: 32),
                    const _SectionTitle('我的书架'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: onShelf.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final item = onShelf[i];
                          return _CoverCard(
                            title: item.title,
                            progress: null,
                            accent: accent,
                            hairline: semantics.hairline,
                            cover: _FileOrFallbackCover(
                              path: item.coverPath,
                            ),
                            onTap: () => _openReal(context, item),
                            onLongPress: () =>
                                _showShelfItemMenu(context, item),
                            trailing: IconButton(
                              tooltip: '移出书架',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: const Icon(
                                Icons.bookmark_remove_outlined,
                                size: 18,
                                weight: 300,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  _removeFromShelf(context, item),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.progress,
    required this.accent,
    required this.surface,
    required this.hairline,
    required this.muted,
    required this.cover,
    required this.onTap,
  });

  final String title;
  final double progress;
  final Color accent;
  final Color surface;
  final Color hairline;
  final Color muted;
  final Widget cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 96, height: 128, child: cover),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 128,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.15,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '继续阅读',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: accent,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(1),
                            child: LinearProgressIndicator(
                              value: p,
                              minHeight: 2,
                              backgroundColor: hairline,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(p * 100).round()}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.title,
    required this.cover,
    required this.accent,
    required this.hairline,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.progress,
  });

  final String title;
  final Widget cover;
  final double? progress;
  final Color accent;
  final Color hairline;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: cover,
                  ),
                  if (trailing != null)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        child: trailing,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 16,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: hairline,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileOrFallbackCover extends StatelessWidget {
  const _FileOrFallbackCover({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: path != null
          ? Image.file(
              File(path!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => ColoredBox(color: semantics.canvas),
            )
          : ColoredBox(color: semantics.canvas),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return Center(
      child: Text(
        '还没有阅读记录\n在书库打开一本后会出现在这里',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: semantics.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}

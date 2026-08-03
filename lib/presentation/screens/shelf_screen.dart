import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../core/theme/brand_tokens.g.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../navigation/open_reading_item.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/cover_card_ink.dart';

/// Shelf: 继续阅读 + 最近 + 我的书架（仅单本钉选；合集在书库展示）.
class ShelfScreen extends StatelessWidget {
  const ShelfScreen({
    super.key,
    required this.brand,
    required this.libraryController,
    this.readingPreferences,
    this.bookReadingPreferences,
    this.onOpenLibrary,
  });

  final BrandConfig brand;
  final LibraryController libraryController;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  /// Switches the shell to the library tab (empty-state CTA).
  final VoidCallback? onOpenLibrary;

  void _openReal(BuildContext context, ReadingItem item) {
    openReadingItem(
      context,
      database: libraryController.database,
      item: item,
      comicReadingPreferences: readingPreferences,
      bookReadingPreferences: bookReadingPreferences,
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
                icon: KaijuanIcons.open,
                title: '打开',
                onTap: () {
                  Navigator.pop(ctx);
                  _openReal(context, item);
                },
              ),
              AppSheetTile(
                icon: KaijuanIcons.bookmarkRemove,
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
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<List<ContinueReadingEntry>>(
        stream: libraryController.watchContinueReading(),
        builder: (context, recentSnap) {
          return StreamBuilder<List<ReadingItem>>(
            stream: libraryController.watchOnShelf(),
            builder: (context, shelfSnap) {
              // Honest loading: don't flash the empty state before first emit.
              if (!recentSnap.hasData || !shelfSnap.hasData) {
                return const AppEmptyState(
                  icon: KaijuanIcons.bookOpen,
                  title: '加载中',
                  message: '正在读取书架…',
                  loading: true,
                );
              }

              final recent = recentSnap.data!;
              final onShelf = shelfSnap.data!;

              if (recent.isEmpty && onShelf.isEmpty) {
                return _EmptyShelf(onOpenLibrary: onOpenLibrary);
              }

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  context.appPageGutter,
                  24,
                  context.appPageGutter,
                  context.appContentBottomPadding,
                ),
                children: [
                  if (recent.isNotEmpty) ...[
                    const _SectionTitle('继续阅读'),
                    const SizedBox(height: 12),
                    _HeroCard(
                      title: recent.first.item.title,
                      progress: recent.first.progressFraction ?? 0,
                      accent: accent,
                      hairline: context.appDivider,
                      muted: context.appSecondaryText,
                      cover: _FileOrFallbackCover(
                        itemId: recent.first.item.id,
                        path: recent.first.item.coverPath,
                        title: recent.first.item.title,
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
                          // End inset so the last cover can clear the edge and
                          // the next item peeks when more remain.
                          padding: const EdgeInsetsDirectional.only(end: 24),
                          itemCount: recent.length - 1,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final e = recent[i + 1];
                            return _CoverCard(
                              title: e.item.title,
                              progress: e.progressFraction,
                              accent: accent,
                              hairline: context.appDivider,
                              cover: _FileOrFallbackCover(
                                itemId: e.item.id,
                                path: e.item.coverPath,
                                title: e.item.title,
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
                        padding: const EdgeInsetsDirectional.only(end: 24),
                        itemCount: onShelf.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final item = onShelf[i];
                          return _CoverCard(
                            title: item.title,
                            progress: null,
                            accent: accent,
                            hairline: context.appDivider,
                            cover: _FileOrFallbackCover(
                              itemId: item.id,
                              path: item.coverPath,
                              title: item.title,
                            ),
                            onTap: () => _openReal(context, item),
                            onLongPress: () =>
                                _showShelfItemMenu(context, item),
                            onRemove: () => _removeFromShelf(context, item),
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
      style: TextStyle(
        fontSize: KaiProductTokens.typographyShelfSectionTitle,
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
    required this.hairline,
    required this.muted,
    required this.cover,
    required this.onTap,
  });

  final String title;
  final double progress;
  final Color accent;
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
        child: Semantics(
          button: true,
          label: '继续阅读$title',
          child: CoverCardInk(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    height: 128,
                    child: SoftCoverFrame(child: cover),
                  ),
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
                            style: TextStyle(
                              fontSize: context.appTitleSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.15,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '继续阅读',
                            style: TextStyle(
                              fontSize: context.appCaptionSize,
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
                              fontSize: context.appCaptionSmallSize,
                              color: muted,
                              letterSpacing: 0.2,
                              fontFeatures: const [FontFeature.tabularFigures()],
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
    this.onRemove,
    this.progress,
  });

  final String title;
  final Widget cover;
  final double? progress;
  final Color accent;
  final Color hairline;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Optional cover control to remove a pinned shelf item (spec: 封面按钮).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: CoverCardInk(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppProductRadii.cover),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              height: 150,
              child: SoftCoverFrame(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover,
                    if (onRemove != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _CoverRemoveButton(onPressed: onRemove!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 20,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appGridTitleStyle.copyWith(
                  color: context.appPrimaryText,
                ),
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 2,
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

/// Compact remove control on pinned covers (meets hit target with padding).
class _CoverRemoveButton extends StatelessWidget {
  const _CoverRemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '移出我的书架',
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          // Absorb the tap so the parent cover onTap does not also fire.
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Icon(
                KaijuanIcons.bookmarkRemove,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileOrFallbackCover extends StatelessWidget {
  const _FileOrFallbackCover({
    required this.itemId,
    required this.path,
    required this.title,
  });
  final String itemId;
  final String? path;
  final String title;

  @override
  Widget build(BuildContext context) {
    final canvas = Theme.of(context).scaffoldBackgroundColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppProductRadii.cover),
      child: path != null
          ? Image.file(
              File(path!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => ColoredBox(color: canvas),
            )
          : ColoredBox(color: canvas),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({this.onOpenLibrary});

  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: KaijuanIcons.bookOpen,
      title: '还没有阅读记录',
      message: '从书库打开一本书后，会在这里继续阅读。',
      actionLabel: onOpenLibrary != null ? '去书库' : null,
      onAction: onOpenLibrary,
    );
  }
}

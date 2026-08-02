import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../navigation/app_page_route.dart';
import '../navigation/open_reading_item.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';

/// Reading lists hub (书库二级).
class ListsScreen extends StatelessWidget {
  const ListsScreen({
    super.key,
    required this.brand,
    required this.controller,
    this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final LibraryController controller;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  static Future<void> open(
    BuildContext context, {
    required BrandConfig brand,
    required LibraryController controller,
    ComicReadingPreferences? readingPreferences,
    BookReadingPreferences? bookReadingPreferences,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      appPageRoute<void>(
        (_) => ListsScreen(
          brand: brand,
          controller: controller,
          readingPreferences: readingPreferences,
          bookReadingPreferences: bookReadingPreferences,
        ),
      ),
    );
  }

  void _openItem(BuildContext context, ReadingItem item) {
    openReadingItem(
      context,
      database: controller.database,
      item: item,
      comicReadingPreferences: readingPreferences,
      bookReadingPreferences: bookReadingPreferences,
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await _promptName(context, title: '新建书单');
    if (name == null || name.isEmpty) return;
    await controller.createReadingList(name);
    if (!context.mounted) return;
    showAppSnackBar(context, '已创建「$name」');
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    return showAppTextPrompt(
      context,
      title: title,
      hint: '名称',
      initial: initial,
    );
  }

  Future<void> _listMenu(BuildContext context, ReadingListSummary s) async {
    await showAppSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetTile(
                icon: KaijuanIcons.edit,
                title: '重命名',
                onTap: () async {
                  Navigator.pop(ctx);
                  final name = await _promptName(
                    context,
                    title: '重命名书单',
                    initial: s.list.name,
                  );
                  if (name == null || name.isEmpty) return;
                  await controller.renameReadingList(s.list.id, name);
                },
              ),
              AppSheetTile(
                icon: KaijuanIcons.delete,
                title: '删除书单',
                destructive: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showAppConfirmDialog(
                    context,
                    title: '删除书单？',
                    message: '删除「${s.list.name}」不会删除书库里的条目。',
                    confirmLabel: '删除',
                    destructive: true,
                  );
                  if (ok == true) {
                    await controller.deleteReadingList(s.list.id);
                  }
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
    final hPad = context.appPageGutter;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                4,
                context.appIsCompact ? 8 : 12,
                8,
                4,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      KaijuanIcons.back,
                      weight: 300,
                      color: context.appPrimaryText,
                    ),
                  ),
                  Text(
                    '书单',
                    style: TextStyle(
                      fontSize: context.appPageTitleSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: context.appPrimaryText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '新建书单',
                    onPressed: () => _create(context),
                    icon: Icon(
                      KaijuanIcons.add,
                      weight: 300,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ReadingListSummary>>(
              stream: controller.watchReadingLists(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AppEmptyState(
                    icon: KaijuanIcons.error,
                    title: '书单加载失败',
                    message: '返回书库后再试一次。',
                    actionLabel: '返回书库',
                    onAction: () => Navigator.of(context).maybePop(),
                  );
                }
                final lists = snapshot.data ?? const <ReadingListSummary>[];
                if (lists.isEmpty) {
                  return AppEmptyState(
                    icon: KaijuanIcons.playlistAdd,
                    title: '还没有书单',
                    message: '新建书单后，可以从书库把书加入进来。',
                    actionLabel: '新建书单',
                    onAction: () => _create(context),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    hPad,
                    8,
                    hPad,
                    context.appContentBottomPadding,
                  ),
                  itemCount: lists.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: context.appDivider),
                  itemBuilder: (context, i) {
                    final s = lists[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      leading: Icon(
                        KaijuanIcons.playlists,
                        color: context.appSecondaryText,
                        weight: 300,
                      ),
                      title: Text(
                        s.list.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${s.memberCount} 本',
                        style: TextStyle(
                          fontSize: context.appBodySecondarySize,
                          color: context.appSecondaryText,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          appPageRoute<void>(
                            (_) => _ListDetailScreen(
                              brand: brand,
                              controller: controller,
                              list: s.list,
                              readingPreferences: readingPreferences,
                              bookReadingPreferences: bookReadingPreferences,
                              openItem: _openItem,
                            ),
                          ),
                        );
                      },
                      onLongPress: () => _listMenu(context, s),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ListDetailScreen extends StatelessWidget {
  const _ListDetailScreen({
    required this.brand,
    required this.controller,
    required this.list,
    this.readingPreferences,
    this.bookReadingPreferences,
    required this.openItem,
  });

  final BrandConfig brand;
  final LibraryController controller;
  final ReadingList list;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;
  final void Function(BuildContext context, ReadingItem item) openItem;

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                4,
                context.appIsCompact ? 8 : 12,
                8,
                4,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      KaijuanIcons.back,
                      weight: 300,
                      color: context.appPrimaryText,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.appPageTitleSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: context.appPrimaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ReadingItem>>(
              stream: controller.watchListMembers(list.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AppEmptyState(
                    icon: KaijuanIcons.error,
                    title: '书单内容加载失败',
                    message: '返回书库后再试一次。',
                    actionLabel: '返回书库',
                    onAction: () => Navigator.of(context).maybePop(),
                  );
                }
                final items = snapshot.data ?? const <ReadingItem>[];
                if (items.isEmpty) {
                  return AppEmptyState(
                    icon: KaijuanIcons.playlistAdd,
                    title: '书单里还没有书',
                    message: '回到书库，多选书籍后加入这个书单。',
                    actionLabel: '返回书库',
                    onAction: () => Navigator.of(context).maybePop(),
                  );
                }
                // Spec: 书单内容 = 竖向长列表（小封面 + 标题）.
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    hPad,
                    8,
                    hPad,
                    context.appContentBottomPadding,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: context.appDivider),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      leading: SizedBox(
                        width: 40,
                        height: 56,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: item.coverPath != null
                              ? Image.file(
                                  File(item.coverPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => ColoredBox(
                                    color: Theme.of(
                                      context,
                                    ).scaffoldBackgroundColor,
                                  ),
                                )
                              : ColoredBox(color: AppColors.lightWash),
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        item.format.toUpperCase(),
                        style: TextStyle(
                          fontSize: context.appBodySecondarySize,
                          color: context.appSecondaryText,
                        ),
                      ),
                      onTap: () => openItem(context, item),
                      onLongPress: () async {
                        final ok = await showAppConfirmDialog(
                          context,
                          title: '移出书单？',
                          message: '从「${list.name}」移除「${item.title}」',
                          confirmLabel: '移出',
                        );
                        if (ok == true) {
                          await controller.removeItemFromList(
                            listId: list.id,
                            itemId: item.id,
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

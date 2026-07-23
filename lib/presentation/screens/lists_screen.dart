import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../navigation/open_reading_item.dart';
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
      MaterialPageRoute<void>(
        builder: (_) => ListsScreen(
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
                icon: Icons.edit_outlined,
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
                icon: Icons.delete_outline,
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
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final hPad = wide ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, wide ? 12 : 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_outlined,
                      weight: 300,
                      color: context.appPrimaryText,
                    ),
                  ),
                  const Text(
                    '书单',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '新建书单',
                    onPressed: () => _create(context),
                    icon: Icon(
                      Icons.add,
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
                  return Center(
                    child: Text(
                      '加载失败：${snapshot.error}',
                      style: TextStyle(color: context.appSecondaryText),
                    ),
                  );
                }
                final lists = snapshot.data ?? const <ReadingListSummary>[];
                if (lists.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '还没有书单',
                            style: TextStyle(
                              fontSize: 15,
                              color: context.appSecondaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '在书库多选里加入即可',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.appSecondaryText.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextButton(
                            onPressed: () => _create(context),
                            child: const Text('新建书单'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 40),
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
                        Icons.playlist_play_outlined,
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
                          fontSize: 12,
                          color: context.appSecondaryText,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ListDetailScreen(
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
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final hPad = wide ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, wide ? 12 : 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_outlined,
                      weight: 300,
                      color: context.appPrimaryText,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
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
                final items = snapshot.data ?? const <ReadingItem>[];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      '书单为空\n在书库多选里加入',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.appSecondaryText,
                        height: 1.5,
                      ),
                    ),
                  );
                }
                // Spec: 书单内容 = 竖向长列表（小封面 + 标题）.
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 40),
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
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
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
                          fontSize: 12,
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

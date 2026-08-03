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
import '../widgets/settings_components.dart';

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
    return Navigator.of(context).push<void>(
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
    final name = await _promptName(context, title: '新建书单', confirmLabel: '创建');
    if (name == null || name.isEmpty) return;
    await controller.createReadingList(name);
    if (!context.mounted) return;
    showAppSnackBar(context, '已创建「$name」');
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String initial = '',
    String confirmLabel = '保存',
  }) {
    return showAppTextPrompt(
      context,
      title: title,
      hint: '书单名称',
      initial: initial,
      confirmLabel: confirmLabel,
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
                    confirmLabel: '保存',
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
                    confirmLabel: '删除书单',
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
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSettingsContent(
              maxWidth: AppSettingsMetrics.formMaxWidth,
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSettingsMetrics.pageTop(context),
                hPad,
                AppSpacing.x3,
              ),
              child: AppSettingsPageHeader(
                title: '书单',
                onBack: () => Navigator.of(context).maybePop(),
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => _create(context),
                    icon: const Icon(KaijuanIcons.add),
                    label: const Text('新建书单'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ReadingListSummary>>(
                stream: controller.watchReadingLists(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppEmptyState(
                      alignment: Alignment.topCenter,
                      padding: EdgeInsets.fromLTRB(
                        hPad,
                        AppSpacing.x8 * 2,
                        hPad,
                        context.appContentBottomPadding,
                      ),
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
                      alignment: Alignment.topCenter,
                      padding: EdgeInsets.fromLTRB(
                        hPad,
                        AppSpacing.x8 * 2,
                        hPad,
                        context.appContentBottomPadding,
                      ),
                      icon: KaijuanIcons.playlistAdd,
                      title: '还没有书单',
                      message: '新建书单后，可以从书库把书加入进来。',
                      actionLabel: '新建书单',
                      onAction: () => _create(context),
                    );
                  }
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSettingsMetrics.formMaxWidth,
                      ),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          hPad,
                          AppSpacing.x3,
                          hPad,
                          context.appContentBottomPadding,
                        ),
                        children: [
                          AppSettingsGroup(
                            children: [
                              for (final summary in lists)
                                AppListRow(
                                  minHeight: 68,
                                  leading: Icon(
                                    KaijuanIcons.playlists,
                                    color: context.appSecondaryText,
                                    weight: 300,
                                  ),
                                  title: Text(summary.list.name),
                                  subtitle: Text(
                                    '${summary.memberCount} 本 · ${_formatListDate(summary.list.updatedAt)}更新',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppIconButton(
                                        icon: KaijuanIcons.more,
                                        tooltip: '管理书单',
                                        onPressed: () =>
                                            _listMenu(context, summary),
                                      ),
                                      Icon(
                                        KaijuanIcons.chevronRight,
                                        size: 18,
                                        color: context.appMutedText,
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      appPageRoute<void>(
                                        (_) => _ListDetailScreen(
                                          brand: brand,
                                          controller: controller,
                                          list: summary.list,
                                          readingPreferences:
                                              readingPreferences,
                                          bookReadingPreferences:
                                              bookReadingPreferences,
                                          openItem: _openItem,
                                        ),
                                      ),
                                    );
                                  },
                                  onLongPress: () =>
                                      _listMenu(context, summary),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatListDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day}';
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

  Future<void> _removeItem(BuildContext context, ReadingItem item) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '移出书单？',
      message: '从「${list.name}」移除「${item.title}」。',
      confirmLabel: '移出书单',
    );
    if (ok == true) {
      await controller.removeItemFromList(listId: list.id, itemId: item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSettingsContent(
              maxWidth: AppSettingsMetrics.formMaxWidth,
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSettingsMetrics.pageTop(context),
                hPad,
                AppSpacing.x3,
              ),
              child: AppSettingsPageHeader(
                title: list.name,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ReadingItem>>(
                stream: controller.watchListMembers(list.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppEmptyState(
                      alignment: Alignment.topCenter,
                      padding: EdgeInsets.fromLTRB(
                        hPad,
                        AppSpacing.x8 * 2,
                        hPad,
                        context.appContentBottomPadding,
                      ),
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
                      alignment: Alignment.topCenter,
                      padding: EdgeInsets.fromLTRB(
                        hPad,
                        AppSpacing.x8 * 2,
                        hPad,
                        context.appContentBottomPadding,
                      ),
                      icon: KaijuanIcons.playlistAdd,
                      title: '书单里还没有书',
                      message: '回到书库，多选书籍后加入这个书单。',
                      actionLabel: '返回书库',
                      onAction: () => Navigator.of(context).maybePop(),
                    );
                  }
                  // Spec: 书单内容 = 竖向长列表（小封面 + 标题）.
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSettingsMetrics.formMaxWidth,
                      ),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          hPad,
                          AppSpacing.x3,
                          hPad,
                          context.appContentBottomPadding,
                        ),
                        children: [
                          AppSettingsGroup(
                            children: [
                              for (final item in items)
                                AppListRow(
                                  minHeight: 84,
                                  leadingWidth: 48,
                                  titleMaxLines: 2,
                                  leading: SizedBox(
                                    width: 42,
                                    height: 58,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        AppProductRadii.cover,
                                      ),
                                      child: item.coverPath != null
                                          ? Image.file(
                                              File(item.coverPath!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  ColoredBox(
                                                    color: AppColors.lightWash,
                                                  ),
                                            )
                                          : const ColoredBox(
                                              color: AppColors.lightWash,
                                            ),
                                    ),
                                  ),
                                  title: Text(item.title),
                                  subtitle: Text(
                                    item.kind == 'comic' ? '漫画' : '图书',
                                  ),
                                  trailing: AppIconButton(
                                    icon: KaijuanIcons.more,
                                    tooltip: '管理条目',
                                    onPressed: () => _removeItem(context, item),
                                  ),
                                  onTap: () => openItem(context, item),
                                  onLongPress: () => _removeItem(context, item),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

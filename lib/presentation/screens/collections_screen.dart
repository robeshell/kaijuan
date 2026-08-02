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
import '../widgets/collection_cover.dart';
import '../widgets/cover_card_ink.dart';
import '../widgets/selection_action_sheet.dart';

/// 合集 directory (book-cover-sized collage cards).
class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({
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
        (_) => CollectionsScreen(
          brand: brand,
          controller: controller,
          readingPreferences: readingPreferences,
          bookReadingPreferences: bookReadingPreferences,
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await showAppTextPrompt(
      context,
      title: '新建合集',
      hint: '合集名称',
      confirmLabel: '创建',
    );
    if (name == null || name.isEmpty) return;
    await controller.createCollection(name);
    if (!context.mounted) return;
    showAppSnackBar(context, '已创建合集「$name」');
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
                    '合集',
                    style: TextStyle(
                      fontSize: context.appPageTitleSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: context.appPrimaryText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '新建合集',
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
            child: StreamBuilder<List<CollectionSummary>>(
              stream: controller.watchCollections(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AppEmptyState(
                    icon: KaijuanIcons.error,
                    title: '合集加载失败',
                    message: '返回书库后再试一次。',
                    actionLabel: '返回书库',
                    onAction: () => Navigator.of(context).maybePop(),
                  );
                }
                final list = snapshot.data ?? const <CollectionSummary>[];
                if (list.isEmpty) {
                  return AppEmptyState(
                    icon: KaijuanIcons.collections,
                    title: '还没有合集',
                    message: '新建合集后，可以从书库把书加入进来。',
                    actionLabel: '新建合集',
                    onAction: () => _create(context),
                  );
                }
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    hPad,
                    8,
                    hPad,
                    context.appContentBottomPadding,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return _CollectionGridCard(
                      summary: s,
                      onTap: () => CollectionDetailScreen.open(
                        context,
                        brand: brand,
                        controller: controller,
                        collection: s.collection,
                        readingPreferences: readingPreferences,
                        bookReadingPreferences: bookReadingPreferences,
                      ),
                      onLongPress: () => _menu(context, s),
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

  Future<void> _menu(BuildContext context, CollectionSummary s) async {
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
                  final name = await showAppTextPrompt(
                    context,
                    title: '重命名合集',
                    initial: s.collection.name,
                  );
                  if (name == null || name.isEmpty) return;
                  await controller.renameCollection(s.collection.id, name);
                },
              ),
              AppSheetTile(
                icon: s.collection.onShelf
                    ? KaijuanIcons.bookmarkRemove
                    : KaijuanIcons.bookmarkAdd,
                title: s.collection.onShelf ? '从书架移出' : '放到书架',
                onTap: () async {
                  Navigator.pop(ctx);
                  await controller.setCollectionOnShelf(
                    s.collection.id,
                    onShelf: !s.collection.onShelf,
                  );
                },
              ),
              AppSheetTile(
                icon: KaijuanIcons.delete,
                title: '删除合集',
                destructive: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showAppConfirmDialog(
                    context,
                    title: '删除合集？',
                    message: '删除「${s.collection.name}」不会删除书库里的条目。',
                    confirmLabel: '删除',
                    destructive: true,
                  );
                  if (ok == true) {
                    await controller.deleteCollection(s.collection.id);
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
}

class _CollectionGridCard extends StatelessWidget {
  const _CollectionGridCard({
    required this.summary,
    required this.onTap,
    required this.onLongPress,
  });

  final CollectionSummary summary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return CoverCardInk(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: CollectionCover(coverPaths: summary.coverPaths)),
          const SizedBox(height: 8),
          SizedBox(
            // 20px title + 2px gap + 14.4px metadata line.
            height: 38,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.appGridTitleStyle.copyWith(
                    color: context.appPrimaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${summary.memberCount} 本',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.appCaptionSmallSize,
                    height: 1.2,
                    color: context.appSecondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.brand,
    required this.controller,
    required this.collection,
    this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final LibraryController controller;
  final Collection collection;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  static Future<void> open(
    BuildContext context, {
    required BrandConfig brand,
    required LibraryController controller,
    required Collection collection,
    ComicReadingPreferences? readingPreferences,
    BookReadingPreferences? bookReadingPreferences,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      appPageRoute<void>(
        (_) => CollectionDetailScreen(
          brand: brand,
          controller: controller,
          collection: collection,
          readingPreferences: readingPreferences,
          bookReadingPreferences: bookReadingPreferences,
        ),
      ),
    );
  }

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  bool _selecting = false;
  final Set<String> _selected = {};

  void _enterSelecting([String? firstId]) {
    setState(() {
      _selecting = true;
      _selected.clear();
      if (firstId != null) _selected.add(firstId);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<ReadingItem> items) {
    setState(() {
      _selected
        ..clear()
        ..addAll(items.map((e) => e.id));
    });
  }

  void _openItem(ReadingItem item) {
    openReadingItem(
      context,
      database: widget.controller.database,
      item: item,
      comicReadingPreferences: widget.readingPreferences,
      bookReadingPreferences: widget.bookReadingPreferences,
    );
  }

  void _onTap(ReadingItem item) {
    if (_selecting) {
      _toggle(item.id);
      return;
    }
    _openItem(item);
  }

  void _onLongPress(ReadingItem item) {
    if (_selecting) {
      _toggle(item.id);
      return;
    }
    _enterSelecting(item.id);
  }

  Future<void> _batchRemoveFromCollection() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showAppConfirmDialog(
      context,
      title: '移出合集？',
      message: '将把已选的 $n 本从「${widget.collection.name}」移出（不删除文件）。',
      confirmLabel: '移出',
    );
    if (ok != true || !mounted) return;
    await widget.controller.removeItemsFromCollection(
      collectionId: widget.collection.id,
      itemIds: _selected,
    );
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已移出 $n 本');
  }

  Future<void> _batchShelf({required bool onShelf}) async {
    if (_selected.isEmpty) return;
    await widget.controller.setOnShelfMany(_selected, onShelf: onShelf);
    if (!mounted) return;
    final n = _selected.length;
    _exitSelecting();
    showAppSnackBar(context, onShelf ? '已加入书架 $n 本' : '已移出书架 $n 本');
  }

  Future<void> _batchDelete() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showAppConfirmDialog(
      context,
      title: '批量删除？',
      message: '将删除已选的 $n 本及其阅读进度。此操作不可撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final count = await widget.controller.deleteItems(_selected);
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已删除 $count 本');
  }

  Future<void> _batchAddToList() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final lists = await widget.controller.readingListsSnapshot();
    if (!mounted) return;

    String? listId;
    if (lists.isEmpty) {
      final name = await showAppTextPrompt(
        context,
        title: '新建书单',
        hint: '书单名称',
        confirmLabel: '创建',
      );
      if (name == null || name.isEmpty || !mounted) return;
      listId = await widget.controller.createReadingList(name);
    } else {
      listId = await showAppChoiceDialog<String>(
        context,
        title: '加入书单',
        choices: [
          for (final list in lists)
            AppDialogChoice(
              value: list.list.id,
              label: list.list.name,
              subtitle: '${list.memberCount} 本',
            ),
          const AppDialogChoice(
            value: '__new__',
            label: '新建书单…',
            icon: KaijuanIcons.add,
          ),
        ],
      );
      if (!mounted) return;
      if (listId == '__new__') {
        final name = await showAppTextPrompt(
          context,
          title: '新建书单',
          hint: '书单名称',
          confirmLabel: '创建',
        );
        if (name == null || name.isEmpty || !mounted) return;
        listId = await widget.controller.createReadingList(name);
      }
    }
    if (listId == null || !mounted) return;
    await widget.controller.addItemsToList(listId: listId, itemIds: ids);
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已将 ${ids.length} 本加入书单');
  }

  Future<void> _batchMoveToCollection() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final cols = await widget.controller.collectionsSnapshot();
    final others = cols.where((c) => c.id != widget.collection.id).toList();
    if (!mounted) return;

    String? colId;
    if (others.isEmpty) {
      final name = await showAppTextPrompt(
        context,
        title: '新建合集',
        hint: '合集名称',
        confirmLabel: '创建',
      );
      if (name == null || name.isEmpty || !mounted) return;
      colId = await widget.controller.createCollection(name);
    } else {
      colId = await showAppChoiceDialog<String>(
        context,
        title: '移到其他合集',
        choices: [
          for (final collection in others)
            AppDialogChoice(value: collection.id, label: collection.name),
          const AppDialogChoice(
            value: '__new__',
            label: '新建合集…',
            icon: KaijuanIcons.add,
          ),
        ],
      );
      if (!mounted) return;
      if (colId == '__new__') {
        final name = await showAppTextPrompt(
          context,
          title: '新建合集',
          hint: '合集名称',
          confirmLabel: '创建',
        );
        if (name == null || name.isEmpty || !mounted) return;
        colId = await widget.controller.createCollection(name);
      }
    }
    if (colId == null || !mounted) return;
    await widget.controller.addItemsToCollection(
      collectionId: colId,
      itemIds: ids,
    );
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已移动 ${ids.length} 本');
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
                    tooltip: _selecting ? '取消选择' : '返回',
                    onPressed: _selecting
                        ? _exitSelecting
                        : () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      _selecting ? KaijuanIcons.close : KaijuanIcons.back,
                      weight: 300,
                      color: context.appPrimaryText,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _selecting
                          ? '已选 ${_selected.length}'
                          : widget.collection.name,
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
                  if (!_selecting)
                    IconButton(
                      tooltip: '多选',
                      onPressed: () => _enterSelecting(),
                      icon: Icon(
                        KaijuanIcons.multiselect,
                        weight: 300,
                        color: context.appSecondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ReadingItem>>(
              stream: widget.controller.watchCollectionMembers(
                widget.collection.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AppEmptyState(
                    icon: KaijuanIcons.error,
                    title: '合集内容加载失败',
                    message: '返回书库后再试一次。',
                    actionLabel: '返回书库',
                    onAction: () => Navigator.of(context).maybePop(),
                  );
                }
                final items = snapshot.data ?? const <ReadingItem>[];
                if (items.isEmpty) {
                  return AppEmptyState(
                    icon: KaijuanIcons.collections,
                    title: '合集里还没有书',
                    message: '回到书库，多选书籍后加入这个合集。',
                    actionLabel: '返回书库',
                    onAction: () => Navigator.of(context).maybePop(),
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          hPad,
                          8,
                          hPad,
                          context.appContentBottomPadding,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 160,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.58,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final isSelected = _selected.contains(item.id);
                          return CoverCardInk(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _onTap(item),
                            onLongPress: () => _onLongPress(item),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SoftCoverFrame(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        item.coverPath != null
                                            ? Image.file(
                                                File(item.coverPath!),
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                errorBuilder: (_, _, _) =>
                                                    ColoredBox(
                                                      color: Theme.of(
                                                        context,
                                                      ).scaffoldBackgroundColor,
                                                    ),
                                              )
                                            : ColoredBox(
                                                color: Theme.of(
                                                  context,
                                                ).scaffoldBackgroundColor,
                                              ),
                                        if (_selecting)
                                          Positioned(
                                            right: 6,
                                            bottom: 6,
                                            child: CoverSelectBadge(
                                              selected: isSelected,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 24,
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.appGridTitleStyle.copyWith(
                                      color: context.appPrimaryText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (_selecting)
                      SelectionActionSheet(
                        selectedCount: _selected.length,
                        totalVisible: items.length,
                        onSelectAll: () => _selectAll(items),
                        onDone: _exitSelecting,
                        actions: [
                          SelectionActionItem(
                            icon: KaijuanIcons.removeFromCollection,
                            label: '移出合集',
                            onTap: _selected.isEmpty
                                ? null
                                : _batchRemoveFromCollection,
                          ),
                          SelectionActionItem(
                            icon: KaijuanIcons.moveToCollection,
                            label: '移到合集',
                            onTap: _selected.isEmpty
                                ? null
                                : _batchMoveToCollection,
                          ),
                          SelectionActionItem(
                            icon: KaijuanIcons.bookmarkAdd,
                            label: '加入书架',
                            onTap: _selected.isEmpty
                                ? null
                                : () => _batchShelf(onShelf: true),
                          ),
                          SelectionActionItem(
                            icon: KaijuanIcons.bookmarkRemove,
                            label: '移出书架',
                            destructive: true,
                            onTap: _selected.isEmpty
                                ? null
                                : () => _batchShelf(onShelf: false),
                          ),
                          SelectionActionItem(
                            icon: KaijuanIcons.playlistAdd,
                            label: '加入书单',
                            onTap: _selected.isEmpty ? null : _batchAddToList,
                          ),
                          SelectionActionItem(
                            icon: KaijuanIcons.delete,
                            label: '删除',
                            destructive: true,
                            onTap: _selected.isEmpty ? null : _batchDelete,
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

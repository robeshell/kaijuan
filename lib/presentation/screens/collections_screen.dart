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
import '../widgets/collection_cover.dart';
import 'book_reader_screen.dart';
import 'comic_reader_screen.dart';

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
      MaterialPageRoute<void>(
        builder: (_) => CollectionsScreen(
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
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: semantics.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_outlined,
                      weight: 300,
                      color: semantics.textPrimary,
                    ),
                  ),
                  const Text(
                    '合集',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _create(context),
                    icon: Icon(Icons.add, size: 18, weight: 300, color: accent),
                    label: Text(
                      '新建',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
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
                  return Center(
                    child: Text(
                      '加载失败：${snapshot.error}',
                      style: TextStyle(color: semantics.textSecondary),
                    ),
                  );
                }
                final list = snapshot.data ?? const <CollectionSummary>[];
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '还没有合集',
                          style: TextStyle(color: semantics.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '把系列收成一盒，会出现在书库最前',
                          style: TextStyle(
                            fontSize: 13,
                            color: semantics.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _create(context),
                          icon: const Icon(Icons.add, weight: 300),
                          label: const Text('新建合集'),
                        ),
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
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
                      onMenu: () => _menu(context, s),
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
                icon: Icons.edit_outlined,
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
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
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
                icon: Icons.delete_outline,
                title: '删除合集',
                destructive: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showAppConfirmDialog(
                    context,
                    title: '删除合集？',
                    message:
                        '删除「${s.collection.name}」不会删除书库里的条目。',
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
    required this.onMenu,
  });

  final CollectionSummary summary;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CollectionCover(coverPaths: summary.coverPaths),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      tooltip: '更多',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Icons.more_horiz_outlined,
                        size: 18,
                        weight: 300,
                        color: semantics.textSecondary,
                      ),
                      onPressed: onMenu,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${summary.memberCount} 本',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: semantics.textSecondary,
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
      MaterialPageRoute<void>(
        builder: (_) => CollectionDetailScreen(
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
    if (item.kind == ReaderKind.book.storageValue) {
      BookReaderScreen.open(
        context,
        database: widget.controller.database,
        item: item,
        readingPreferences: widget.bookReadingPreferences,
      );
      return;
    }
    ComicReaderScreen.open(
      context,
      database: widget.controller.database,
      item: item,
      readingPreferences: widget.readingPreferences,
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
    for (final id in _selected) {
      await widget.controller.removeItemFromCollection(
        collectionId: widget.collection.id,
        itemId: id,
      );
    }
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
    showAppSnackBar(context, onShelf ? '已上架 $n 本' : '已移出书架 $n 本');
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
      listId = await showDialog<String>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (ctx) {
          final semantics = Theme.of(ctx).extension<AppSemantics>()!;
          return Dialog(
            backgroundColor: semantics.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.panel),
              side: BorderSide(color: semantics.hairline),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '加入书单',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: semantics.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    for (final s in lists)
                      ListTile(
                        title: Text(s.list.name),
                        subtitle: Text('${s.memberCount} 本'),
                        onTap: () => Navigator.pop(ctx, s.list.id),
                      ),
                    ListTile(
                      leading: const Icon(Icons.add, weight: 300),
                      title: const Text('新建书单…'),
                      onTap: () => Navigator.pop(ctx, '__new__'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
    final others =
        cols.where((c) => c.id != widget.collection.id).toList();
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
      colId = await showDialog<String>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (ctx) {
          final semantics = Theme.of(ctx).extension<AppSemantics>()!;
          return Dialog(
            backgroundColor: semantics.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.panel),
              side: BorderSide(color: semantics.hairline),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '移到其他合集',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: semantics.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    for (final c in others)
                      ListTile(
                        title: Text(c.name),
                        onTap: () => Navigator.pop(ctx, c.id),
                      ),
                    ListTile(
                      leading: const Icon(Icons.add, weight: 300),
                      title: const Text('新建合集…'),
                      onTap: () => Navigator.pop(ctx, '__new__'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
    await widget.controller
        .addItemsToCollection(collectionId: colId, itemIds: ids);
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已移动 ${ids.length} 本');
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: semantics.canvas,
      appBar: AppBar(
        title: Text(
          _selecting ? '已选 ${_selected.length}' : widget.collection.name,
        ),
        backgroundColor: semantics.canvas,
        surfaceTintColor: Colors.transparent,
        primary: true,
        leading: _selecting
            ? IconButton(
                tooltip: '取消选择',
                onPressed: _exitSelecting,
                icon: const Icon(Icons.close, weight: 300),
              )
            : null,
        actions: [
          if (!_selecting)
            IconButton(
              tooltip: '多选',
              onPressed: () => _enterSelecting(),
              icon: Icon(Icons.checklist_outlined, color: accent, weight: 300),
            ),
        ],
      ),
      body: StreamBuilder<List<ReadingItem>>(
        stream: widget.controller.watchCollectionMembers(widget.collection.id),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ReadingItem>[];
          if (items.isEmpty) {
            return Center(
              child: Text(
                '合集为空\n在书库详情或多选里加入',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: semantics.textSecondary,
                  height: 1.5,
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
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
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _onTap(item),
                      onLongPress: () => _onLongPress(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: item.coverPath != null
                                      ? Image.file(
                                          File(item.coverPath!),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          errorBuilder: (_, _, _) => ColoredBox(
                                            color: semantics.canvas,
                                          ),
                                        )
                                      : ColoredBox(color: semantics.canvas),
                                ),
                                if (_selecting)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Icon(
                                      isSelected
                                          ? Icons.check_circle_outline
                                          : Icons.circle_outlined,
                                      color: isSelected
                                          ? accent
                                          : Colors.white,
                                      weight: 300,
                                      shadows: const [
                                        Shadow(
                                          blurRadius: 6,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isSelected)
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: accent,
                                          width: 2.5,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 16,
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
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
                Material(
                  color: semantics.surface,
                  elevation: 8,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => _selectAll(items),
                            child: Text(
                              _selected.length == items.length
                                  ? '取消全选'
                                  : '全选',
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '移出合集',
                            onPressed: _selected.isEmpty
                                ? null
                                : _batchRemoveFromCollection,
                            icon: Icon(
                              Icons.folder_off_outlined,
                              color: accent,
                              weight: 300,
                            ),
                          ),
                          IconButton(
                            tooltip: '移到其他合集',
                            onPressed: _selected.isEmpty
                                ? null
                                : _batchMoveToCollection,
                            icon: Icon(
                              Icons.drive_file_move_outline,
                              color: accent,
                              weight: 300,
                            ),
                          ),
                          IconButton(
                            tooltip: '加入书架',
                            onPressed: _selected.isEmpty
                                ? null
                                : () => _batchShelf(onShelf: true),
                            icon: Icon(
                              Icons.bookmark_add_outlined,
                              color: accent,
                              weight: 300,
                            ),
                          ),
                          IconButton(
                            tooltip: '移出书架',
                            onPressed: _selected.isEmpty
                                ? null
                                : () => _batchShelf(onShelf: false),
                            icon: Icon(
                              Icons.bookmark_remove_outlined,
                              color: accent,
                              weight: 300,
                            ),
                          ),
                          IconButton(
                            tooltip: '加入书单',
                            onPressed:
                                _selected.isEmpty ? null : _batchAddToList,
                            icon: Icon(
                              Icons.playlist_add_outlined,
                              color: accent,
                              weight: 300,
                            ),
                          ),
                          IconButton(
                            tooltip: '删除',
                            onPressed:
                                _selected.isEmpty ? null : _batchDelete,
                            icon: Icon(
                              Icons.delete_outline,
                              weight: 300,
                              color: _selected.isEmpty
                                  ? semantics.textSecondary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _exitSelecting,
                            child: const Text('完成'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

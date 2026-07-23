import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/theme.dart';
import '../../library/import/import_models.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../navigation/open_reading_item.dart';
import '../widgets/app_overlays.dart';
import '../widgets/collection_cover.dart';
import '../widgets/cover_card_ink.dart';
import '../widgets/selection_action_sheet.dart';
import 'collections_screen.dart';
import 'lists_screen.dart';

enum _LibraryLayout { grid, list }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
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

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _LibraryLayout _layout = _LibraryLayout.grid;
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<LibraryEntry> visible) {
    setState(() {
      _selected
        ..clear()
        ..addAll(visible.map((e) => e.item.id));
    });
  }

  Future<void> _import() async {
    final result = await widget.controller.pickAndImport();
    if (!mounted || result == null) return;
    await _showImportSummary(result);
  }

  Future<void> _showImportSummary(ImportResult result) async {
    final summary = StringBuffer('已导入 ${result.added} 本');
    if (result.updated > 0) summary.write('，更新 ${result.updated} 本');
    if (result.failures.isNotEmpty) {
      summary.write('，失败 ${result.failures.length} 本');
    }

    if (!result.hasFailures) {
      showAppSnackBar(context, summary.toString());
      return;
    }

    final openDetails = await showAppConfirmDialog(
      context,
      title: '导入结果',
      message: summary.toString(),
      cancelLabel: '关闭',
      confirmLabel: '查看失败详情',
    );
    if (openDetails == true && mounted) {
      await _showFailureDetails(result.failures);
    }
  }

  Future<void> _showFailureDetails(List<ImportFailure> failures) async {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) {
        return AppAlertDialog(
          title: '失败 ${failures.length} 本',
          content: SizedBox(
            width: 360,
            height: 220,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: failures.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: semantics.hairline),
              itemBuilder: (_, i) {
                final f = failures[i];
                final name = f.path.isEmpty ? '（未知）' : f.fileName;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.reason,
                        style: TextStyle(
                          fontSize: 12,
                          color: semantics.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            AppDialogAction(
              label: '关闭',
              primary: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
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

  void _onItemTap(LibraryEntry entry) {
    if (_selecting) {
      _toggleSelected(entry.item.id);
      return;
    }
    _openItem(entry.item);
  }

  void _onItemLongPress(LibraryEntry entry) {
    if (_selecting) {
      _toggleSelected(entry.item.id);
      return;
    }
    _enterSelecting(entry.item.id);
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

  Future<void> _batchShelf({required bool onShelf}) async {
    if (_selected.isEmpty) return;
    await widget.controller.setOnShelfMany(_selected, onShelf: onShelf);
    if (!mounted) return;
    final n = _selected.length;
    _exitSelecting();
    showAppSnackBar(context, onShelf ? '已上架 $n 本' : '已移出书架 $n 本');
  }

  Future<void> _batchAddToList() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final lists = await widget.controller.readingListsSnapshot();
    if (!mounted) return;

    String? listId;
    if (lists.isEmpty) {
      final name = await _promptNamed('新建书单', '书单名称');
      if (name == null || name.isEmpty || !mounted) return;
      listId = await widget.controller.createReadingList(name);
    } else {
      listId = await _pickNamedTarget(
        title: '加入书单',
        entries: [
          for (final s in lists) (s.list.id, s.list.name, '${s.memberCount} 本'),
        ],
        newLabel: '新建书单…',
      );
      if (listId == '__new__') {
        final name = await _promptNamed('新建书单', '书单名称');
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

  Future<void> _batchAddToCollection() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final cols = await widget.controller.collectionsSnapshot();
    if (!mounted) return;

    String? colId;
    if (cols.isEmpty) {
      final name = await _promptNamed('新建合集', '合集名称');
      if (name == null || name.isEmpty || !mounted) return;
      colId = await widget.controller.createCollection(name);
    } else {
      colId = await _pickNamedTarget(
        title: '加入合集',
        entries: [for (final c in cols) (c.id, c.name, '')],
        newLabel: '新建合集…',
      );
      if (colId == '__new__') {
        final name = await _promptNamed('新建合集', '合集名称');
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
    showAppSnackBar(context, '已将 ${ids.length} 本加入合集');
  }

  Future<String?> _promptNamed(String title, String hint) {
    return showAppTextPrompt(
      context,
      title: title,
      hint: hint,
      confirmLabel: '创建',
    );
  }

  Future<String?> _pickNamedTarget({
    required String title,
    required List<(String id, String name, String subtitle)> entries,
    required String newLabel,
  }) {
    return showDialog<String>(
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: semantics.textPrimary,
                      ),
                    ),
                  ),
                  for (final e in entries)
                    ListTile(
                      title: Text(e.$2),
                      subtitle: e.$3.isEmpty ? null : Text(e.$3),
                      onTap: () => Navigator.pop(ctx, e.$1),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add, weight: 300),
                    title: Text(newLabel),
                    onTap: () => Navigator.pop(ctx, '__new__'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.addedDesc => '最近导入',
    LibrarySort.titleAsc => '标题',
    LibrarySort.lastOpenedDesc => '最近阅读',
  };

  String _readFilterLabel(LibraryReadFilter f) => switch (f) {
    LibraryReadFilter.all => '状态',
    LibraryReadFilter.unread => '未读',
    LibraryReadFilter.reading => '在读',
    LibraryReadFilter.finished => '已读完',
  };

  String _shelfFilterLabel(LibraryShelfFilter f) => switch (f) {
    LibraryShelfFilter.all => '全部',
    LibraryShelfFilter.onShelfOnly => '已上架',
    LibraryShelfFilter.notOnShelf => '未上架',
  };

  String _kindFilterLabel(LibraryKindFilter f) => switch (f) {
    LibraryKindFilter.all => '类型',
    LibraryKindFilter.comic => '漫画',
    LibraryKindFilter.book => '图书',
  };

  void _toggleLayout() {
    setState(() {
      _layout = _layout == _LibraryLayout.grid
          ? _LibraryLayout.list
          : _LibraryLayout.grid;
    });
  }

  Widget _searchField({required Color accent, required AppSemantics semantics}) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索标题…',
          hintStyle: TextStyle(
            color: semantics.textSecondary,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: semantics.textSecondary,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.lightWash,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accent, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryHeader(
    BuildContext context,
    LibraryController controller, {
    required bool wide,
    required bool importing,
    required Color accent,
    required AppSemantics semantics,
  }) {
    final hPad = wide ? 32.0 : 16.0;
    final muted = semantics.textSecondary;

    Widget navLists() {
      if (wide) {
        return TextButton.icon(
          onPressed: () => ListsScreen.open(
            context,
            brand: widget.brand,
            controller: controller,
            readingPreferences: widget.readingPreferences,
            bookReadingPreferences: widget.bookReadingPreferences,
          ),
          icon: Icon(
            Icons.playlist_play_outlined,
            size: 18,
            weight: 300,
            color: muted,
          ),
          label: Text(
            '书单',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
      return IconButton(
        tooltip: '书单',
        onPressed: () => ListsScreen.open(
          context,
          brand: widget.brand,
          controller: controller,
          readingPreferences: widget.readingPreferences,
          bookReadingPreferences: widget.bookReadingPreferences,
        ),
        icon: Icon(Icons.playlist_play_outlined, weight: 300, color: muted),
      );
    }

    Widget navCollections() {
      if (wide) {
        return TextButton.icon(
          onPressed: () => CollectionsScreen.open(
            context,
            brand: widget.brand,
            controller: controller,
            readingPreferences: widget.readingPreferences,
            bookReadingPreferences: widget.bookReadingPreferences,
          ),
          icon: Icon(
            Icons.collections_bookmark_outlined,
            size: 18,
            weight: 300,
            color: muted,
          ),
          label: Text(
            '合集',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
      return IconButton(
        tooltip: '合集',
        onPressed: () => CollectionsScreen.open(
          context,
          brand: widget.brand,
          controller: controller,
          readingPreferences: widget.readingPreferences,
          bookReadingPreferences: widget.bookReadingPreferences,
        ),
        icon: Icon(
          Icons.collections_bookmark_outlined,
          weight: 300,
          color: muted,
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(hPad, wide ? 20 : 12, wide ? 24 : 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_selecting) ...[
                  IconButton(
                    tooltip: '取消选择',
                    onPressed: _exitSelecting,
                    icon: const Icon(Icons.close),
                  ),
                  Text(
                    '已选 ${_selected.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  const Text(
                    '书库',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (wide) const SizedBox(width: 8),
                  if (wide) ...[
                    navLists(),
                    navCollections(),
                  ],
                  const Spacer(),
                  if (!wide) ...[
                    navLists(),
                    navCollections(),
                  ],
                  IconButton(
                    tooltip: _layout == _LibraryLayout.grid
                        ? '列表视图'
                        : '网格视图',
                    onPressed: _toggleLayout,
                    icon: Icon(
                      _layout == _LibraryLayout.grid
                          ? Icons.view_list_outlined
                          : Icons.grid_view_outlined,
                      weight: 300,
                      color: muted,
                    ),
                  ),
                  IconButton(
                    tooltip: '多选',
                    onPressed: _enterSelecting,
                    icon: Icon(
                      Icons.checklist_outlined,
                      weight: 300,
                      color: muted,
                    ),
                  ),
                  IconButton(
                    tooltip: '导入（CBZ / ZIP / EPUB）',
                    onPressed: importing ? null : _import,
                    icon: importing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.add, weight: 300, color: accent),
                  ),
                ],
              ],
            ),
            if (!_selecting) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: wide ? 420 : double.infinity,
                  ),
                  child: _searchField(accent: accent, semantics: semantics),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow(
    LibraryController c, {
    required bool wide,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 0, wide ? 24 : 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FilterMenu<LibrarySort>(
            label: _sortLabel(c.sort),
            icon: Icons.sort_outlined,
            active: c.sort != LibrarySort.addedDesc,
            items: LibrarySort.values,
            itemLabel: _sortLabel,
            onSelected: c.setSort,
          ),
          _FilterMenu<LibraryKindFilter>(
            label: _kindFilterLabel(c.kindFilter),
            icon: Icons.category_outlined,
            active: c.kindFilter != LibraryKindFilter.all,
            items: LibraryKindFilter.values,
            itemLabel: _kindFilterLabel,
            onSelected: c.setKindFilter,
          ),
          _FilterMenu<LibraryReadFilter>(
            label: _readFilterLabel(c.readFilter),
            icon: Icons.auto_stories_outlined,
            active: c.readFilter != LibraryReadFilter.all,
            items: LibraryReadFilter.values,
            itemLabel: _readFilterLabel,
            onSelected: c.setReadFilter,
          ),
          _FilterMenu<LibraryShelfFilter>(
            label: _shelfFilterLabel(c.shelfFilter),
            icon: Icons.bookmark_border,
            active: c.shelfFilter != LibraryShelfFilter.all,
            items: LibraryShelfFilter.values,
            itemLabel: _shelfFilterLabel,
            onSelected: c.setShelfFilter,
          ),
          _FilterMenu<String>(
            label: c.formatFilter?.toUpperCase() ?? '格式',
            icon: Icons.insert_drive_file_outlined,
            active: c.formatFilter != null,
            items: const ['all', 'cbz', 'zip', 'epub'],
            itemLabel: (v) => v == 'all' ? '格式' : v.toUpperCase(),
            onSelected: (v) => c.setFormatFilter(v == 'all' ? null : v),
          ),
          if (c.hasActiveFilters)
            TextButton(
              onPressed: c.clearFilters,
              child: const Text('清除筛选'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    // Scaffold (not ColoredBox): ListTile ink needs a Material ancestor.
    return Scaffold(
      backgroundColor: semantics.canvas,
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final importing = c.isImporting;
          // Wide = text nav labels; both widths share title / search / filter rows.
          final wide = MediaQuery.sizeOf(context).width >= 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLibraryHeader(
                context,
                c,
                wide: wide,
                importing: importing,
                accent: accent,
                semantics: semantics,
              ),
              if (!_selecting) _buildFilterRow(c, wide: wide),
              Expanded(
                child: StreamBuilder<List<CollectionSummary>>(
                  stream: c.watchCollections(),
                  builder: (context, colSnap) {
                    return StreamBuilder<List<LibraryEntry>>(
                      stream: c.watchLibraryEntries(),
                      builder: (context, snapshot) {
                        final entries = snapshot.data ?? const <LibraryEntry>[];
                        final allCollections =
                            colSnap.data ?? const <CollectionSummary>[];
                        // 已在合集中的单本不在书库主列表重复出现。
                        final inCollectionIds = {
                          for (final s in allCollections) ...s.memberIds,
                        };
                        final singles = [
                          for (final e in entries)
                            if (!inCollectionIds.contains(e.item.id)) e,
                        ];
                        final filtered = c.filterAndSort(
                          singles,
                          query: _query,
                        );
                        // 合集在书库最前；搜索匹配合集名或成员标题；多选时不显示合集。
                        final q = _query.trim().toLowerCase();
                        final collections = _selecting
                            ? const <CollectionSummary>[]
                            : allCollections.where((s) {
                                if (q.isEmpty) return true;
                                if (s.collection.name.toLowerCase().contains(
                                  q,
                                )) {
                                  return true;
                                }
                                // 成员标题匹配也露出合集卡（不展开单本）。
                                return entries.any(
                                  (e) =>
                                      s.memberIds.contains(e.item.id) &&
                                      e.item.title.toLowerCase().contains(q),
                                );
                              }).toList();

                        if (entries.isEmpty && allCollections.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '导入 CBZ、ZIP 或 EPUB',
                                  style: TextStyle(
                                    color: semantics.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: importing ? null : _import,
                                  icon: const Icon(Icons.add),
                                  label: const Text('导入'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (filtered.isEmpty && collections.isEmpty) {
                          return Center(
                            child: Text(
                              '没有匹配的书',
                              style: TextStyle(color: semantics.textSecondary),
                            ),
                          );
                        }

                        final body = _layout == _LibraryLayout.grid
                            ? _GridBody(
                                collections: collections,
                                entries: filtered,
                                selecting: _selecting,
                                selected: _selected,
                                brand: widget.brand,
                                controller: c,
                                readingPreferences: widget.readingPreferences,
                                bookReadingPreferences:
                                    widget.bookReadingPreferences,
                                onTap: _onItemTap,
                                onLongPress: _onItemLongPress,
                              )
                            : _ListBody(
                                collections: collections,
                                entries: filtered,
                                selecting: _selecting,
                                selected: _selected,
                                brand: widget.brand,
                                controller: c,
                                readingPreferences: widget.readingPreferences,
                                bookReadingPreferences:
                                    widget.bookReadingPreferences,
                                onTap: _onItemTap,
                                onLongPress: _onItemLongPress,
                              );

                        return Column(
                          children: [
                            Expanded(child: body),
                            if (_selecting)
                              SelectionActionSheet(
                                selectedCount: _selected.length,
                                totalVisible: filtered.length,
                                onSelectAll: () => _selectAll(filtered),
                                onDone: _exitSelecting,
                                actions: [
                                  SelectionActionItem(
                                    icon: Icons.bookmark_add_outlined,
                                    label: '加入书架',
                                    onTap: _selected.isEmpty
                                        ? null
                                        : () => _batchShelf(onShelf: true),
                                  ),
                                  SelectionActionItem(
                                    icon: Icons.bookmark_remove_outlined,
                                    label: '移出书架',
                                    destructive: true,
                                    onTap: _selected.isEmpty
                                        ? null
                                        : () => _batchShelf(onShelf: false),
                                  ),
                                  SelectionActionItem(
                                    icon: Icons.playlist_add_outlined,
                                    label: '加入书单',
                                    onTap: _selected.isEmpty
                                        ? null
                                        : _batchAddToList,
                                  ),
                                  SelectionActionItem(
                                    icon: Icons.collections_bookmark_outlined,
                                    label: '加入合集',
                                    onTap: _selected.isEmpty
                                        ? null
                                        : _batchAddToCollection,
                                  ),
                                  SelectionActionItem(
                                    icon: Icons.delete_outline,
                                    label: '删除',
                                    destructive: true,
                                    onTap: _selected.isEmpty
                                        ? null
                                        : _batchDelete,
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.collections,
    required this.entries,
    required this.selecting,
    required this.selected,
    required this.brand,
    required this.controller,
    required this.readingPreferences,
    required this.bookReadingPreferences,
    required this.onTap,
    required this.onLongPress,
  });

  final List<CollectionSummary> collections;
  final List<LibraryEntry> entries;
  final bool selecting;
  final Set<String> selected;
  final BrandConfig brand;
  final LibraryController controller;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;
  final ValueChanged<LibraryEntry> onTap;
  final ValueChanged<LibraryEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final total = collections.length + entries.length;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.58,
      ),
      itemCount: total,
      itemBuilder: (context, i) {
        if (i < collections.length) {
          final s = collections[i];
          return _LibraryCollectionCard(
            summary: s,
            onTap: () => CollectionDetailScreen.open(
              context,
              brand: brand,
              controller: controller,
              collection: s.collection,
              readingPreferences: readingPreferences,
              bookReadingPreferences: bookReadingPreferences,
            ),
          );
        }
        final entry = entries[i - collections.length];
        return _GridCard(
          entry: entry,
          selecting: selecting,
          isSelected: selected.contains(entry.item.id),
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
        );
      },
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({
    required this.collections,
    required this.entries,
    required this.selecting,
    required this.selected,
    required this.brand,
    required this.controller,
    required this.readingPreferences,
    required this.bookReadingPreferences,
    required this.onTap,
    required this.onLongPress,
  });

  final List<CollectionSummary> collections;
  final List<LibraryEntry> entries;
  final bool selecting;
  final Set<String> selected;
  final BrandConfig brand;
  final LibraryController controller;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;
  final ValueChanged<LibraryEntry> onTap;
  final ValueChanged<LibraryEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final total = collections.length + entries.length;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      itemCount: total,
      separatorBuilder: (_, _) => Divider(height: 1, color: semantics.hairline),
      itemBuilder: (context, i) {
        if (i < collections.length) {
          final s = collections[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            leading: SizedBox(
              width: 48,
              height: 64,
              child: CollectionCover(coverPaths: s.coverPaths, borderRadius: 6),
            ),
            title: Text(
              s.collection.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '合集 · ${s.memberCount} 本',
              style: TextStyle(fontSize: 12, color: semantics.textSecondary),
            ),
            onTap: () => CollectionDetailScreen.open(
              context,
              brand: brand,
              controller: controller,
              collection: s.collection,
              readingPreferences: readingPreferences,
              bookReadingPreferences: bookReadingPreferences,
            ),
          );
        }
        final entry = entries[i - collections.length];
        final item = entry.item;
        final isSelected = selected.contains(item.id);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          leading: SizedBox(
            width: 48,
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: item.coverPath != null
                      ? Image.file(
                          File(item.coverPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: semantics.canvas),
                        )
                      : ColoredBox(color: semantics.canvas),
                ),
                if (selecting)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: CoverSelectBadge(selected: isSelected, size: 18),
                  ),
              ],
            ),
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              item.format.toUpperCase(),
              if (item.pageCount > 0) '${item.pageCount} 页',
              if (entry.progressFraction != null)
                '${(entry.progressFraction! * 100).round()}%',
              if (item.onShelf) '已上架',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: semantics.textSecondary),
          ),
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
        );
      },
    );
  }
}

class _LibraryCollectionCard extends StatelessWidget {
  const _LibraryCollectionCard({required this.summary, required this.onTap});

  final CollectionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return CoverCardInk(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: CollectionCover(coverPaths: summary.coverPaths)),
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
                  '合集 · ${summary.memberCount} 本',
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

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.icon,
    required this.active,
    required this.items,
    required this.itemLabel,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool active;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromRect(
      Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<T>(
      context: context,
      position: rect,
      items: [
        for (final item in items)
          PopupMenuItem<T>(
            value: item,
            height: 40,
            child: Text(itemLabel(item)),
          ),
      ],
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;
    // GestureDetector only — no InkWell / tooltip hover chrome on the chip.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMenu(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.28) : semantics.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              weight: 300,
              color: active ? accent : semantics.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? accent : semantics.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              weight: 300,
              color: active ? accent : semantics.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.entry,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryEntry entry;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final item = entry.item;
    return CoverCardInk(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
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
                              ColoredBox(color: semantics.canvas),
                        )
                      : ColoredBox(color: semantics.canvas),
                  if (item.onShelf && !selecting)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(
                            Icons.bookmark,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (selecting)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: CoverSelectBadge(selected: isSelected),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Fixed caption band so grid cells stay aligned (1-line title + meta).
          SizedBox(
            height: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.format == 'epub') 'EPUB',
                    if (entry.progressFraction != null)
                      '${(entry.progressFraction! * 100).round()}%',
                  ].join(' · '),
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

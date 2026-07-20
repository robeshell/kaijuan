import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../widgets/app_overlays.dart';

/// Detail / manage sheet for one library item (rename, shelf, lists, delete).
Future<void> showItemDetailSheet({
  required BuildContext context,
  required LibraryController controller,
  required ReadingItem item,
  double? progressFraction,
  required VoidCallback onOpen,
  required Future<void> Function() onDeleted,
}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return _ItemDetailBody(
        controller: controller,
        item: item,
        progressFraction: progressFraction,
        onOpen: () {
          Navigator.pop(ctx);
          onOpen();
        },
        onDeleted: () async {
          Navigator.pop(ctx);
          await onDeleted();
        },
      );
    },
  );
}

class _ItemDetailBody extends StatefulWidget {
  const _ItemDetailBody({
    required this.controller,
    required this.item,
    required this.progressFraction,
    required this.onOpen,
    required this.onDeleted,
  });

  final LibraryController controller;
  final ReadingItem item;
  final double? progressFraction;
  final VoidCallback onOpen;
  final Future<void> Function() onDeleted;

  @override
  State<_ItemDetailBody> createState() => _ItemDetailBodyState();
}

class _ItemDetailBodyState extends State<_ItemDetailBody> {
  late ReadingItem _item;
  late final TextEditingController _titleController;
  var _savingTitle = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _titleController = TextEditingController(text: _item.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveTitle() async {
    final next = _titleController.text.trim();
    if (next.isEmpty || next == _item.title) return;
    setState(() => _savingTitle = true);
    await widget.controller.renameItem(_item.id, next);
    final refreshed = await widget.controller.itemById(_item.id);
    if (!mounted) return;
    setState(() {
      _savingTitle = false;
      if (refreshed != null) _item = refreshed;
    });
    showAppSnackBar(context, '已重命名');
  }

  Future<void> _toggleShelf() async {
    final next = !_item.onShelf;
    await widget.controller.setOnShelf(_item.id, onShelf: next);
    final refreshed = await widget.controller.itemById(_item.id);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _item = refreshed;
    });
  }

  Future<void> _confirmDelete() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '从书库删除？',
      message: '将删除「${_item.title}」及其阅读进度。此操作不可撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    await widget.controller.deleteItem(_item.id);
    await widget.onDeleted();
  }

  Future<void> _manageLists() async {
    final lists = await widget.controller.readingListsSnapshot();
    if (!mounted) return;
    if (lists.isEmpty) {
      final name = await _promptListName();
      if (name == null || name.isEmpty || !mounted) return;
      final id = await widget.controller.createReadingList(name);
      await widget.controller.addItemToList(listId: id, itemId: _item.id);
      if (!mounted) return;
      showAppSnackBar(context, '已加入书单「$name」');
      return;
    }

    await showAppSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: FutureBuilder(
            future: Future.wait([
              widget.controller.readingListsSnapshot(),
              widget.controller.database.listIdsContainingItem(_item.id),
            ]),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final all = snap.data![0] as List<ReadingListSummary>;
              final memberOf = (snap.data![1] as List<String>).toSet();
              return ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text(
                      '加入书单',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final s in all)
                    CheckboxListTile(
                      value: memberOf.contains(s.list.id),
                      title: Text(s.list.name),
                      subtitle: Text('${s.memberCount} 本'),
                      onChanged: (v) async {
                        if (v == true) {
                          await widget.controller.addItemToList(
                            listId: s.list.id,
                            itemId: _item.id,
                          );
                        } else {
                          await widget.controller.removeItemFromList(
                            listId: s.list.id,
                            itemId: _item.id,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) await _manageLists();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建书单…'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final name = await _promptListName();
                      if (name == null || name.isEmpty || !mounted) return;
                      final id =
                          await widget.controller.createReadingList(name);
                      await widget.controller
                          .addItemToList(listId: id, itemId: _item.id);
                      if (!mounted) return;
                      showAppSnackBar(this.context, '已加入书单「$name」');
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<String?> _promptListName() {
    return showAppTextPrompt(
      context,
      title: '新建书单',
      hint: '书单名称',
      confirmLabel: '创建',
    );
  }

  Future<void> _manageCollections() async {
    final cols = await widget.controller.collectionsSnapshot();
    if (!mounted) return;
    if (cols.isEmpty) {
      final name = await showAppTextPrompt(
        context,
        title: '新建合集',
        hint: '合集名称',
        confirmLabel: '创建',
      );
      if (name == null || name.isEmpty || !mounted) return;
      final id = await widget.controller.createCollection(name);
      await widget.controller.addItemToCollection(
        collectionId: id,
        itemId: _item.id,
      );
      if (!mounted) return;
      showAppSnackBar(context, '已加入合集「$name」');
      return;
    }

    final currentId = await widget.controller.collectionIdForItem(_item.id);
    if (!mounted) return;

    await showAppSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  '加入合集',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('一本条目同一时间只在一个合集里'),
              ),
              for (final c in cols)
                ListTile(
                  leading: Icon(
                    currentId == c.id
                        ? Icons.check_circle_outline
                        : Icons.circle_outlined,
                    weight: 300,
                  ),
                  title: Text(c.name),
                  onTap: () async {
                    await widget.controller.addItemToCollection(
                      collectionId: c.id,
                      itemId: _item.id,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      showAppSnackBar(context, '已加入合集「${c.name}」');
                    }
                  },
                ),
              if (currentId != null)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, weight: 300),
                  title: const Text('移出当前合集'),
                  onTap: () async {
                    await widget.controller.removeItemFromCollection(
                      collectionId: currentId,
                      itemId: _item.id,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      showAppSnackBar(context, '已移出合集');
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add, weight: 300),
                title: const Text('新建合集…'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final name = await showAppTextPrompt(
                    context,
                    title: '新建合集',
                    hint: '合集名称',
                    confirmLabel: '创建',
                  );
                  if (name == null || name.isEmpty || !mounted) return;
                  final id = await widget.controller.createCollection(name);
                  await widget.controller.addItemToCollection(
                    collectionId: id,
                    itemId: _item.id,
                  );
                  if (!mounted) return;
                  showAppSnackBar(context, '已加入合集「$name」');
                },
              ),
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
    final progress = widget.progressFraction;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 88,
                      height: 118,
                      child: _item.coverPath != null
                          ? Image.file(
                              File(_item.coverPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  ColoredBox(color: semantics.canvas),
                            )
                          : ColoredBox(color: semantics.canvas),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '标题',
                          ),
                          onSubmitted: (_) => _saveTitle(),
                        ),
                        Text(
                          _item.format.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: semantics.textSecondary,
                          ),
                        ),
                        if (_item.pageCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_item.pageCount} 页',
                            style: TextStyle(
                              fontSize: 12,
                              color: semantics.textSecondary,
                            ),
                          ),
                        ],
                        if (progress != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: semantics.hairline,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '进度 ${(progress * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: semantics.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _savingTitle ? null : _saveTitle,
                  icon: _savingTitle
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_outlined, size: 18),
                  label: const Text('保存标题'),
                ),
              ),
              const Divider(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.menu_book_outlined,
                  color: accent,
                  weight: 300,
                ),
                title: const Text('打开'),
                onTap: widget.onOpen,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _item.onShelf
                      ? Icons.bookmark_outlined
                      : Icons.bookmark_border_outlined,
                  color: accent,
                  weight: 300,
                ),
                title: Text(_item.onShelf ? '移出我的书架' : '加入我的书架'),
                onTap: _toggleShelf,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.playlist_add_outlined,
                  color: accent,
                  weight: 300,
                ),
                title: const Text('加入书单…'),
                onTap: _manageLists,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.collections_bookmark_outlined,
                  color: accent,
                  weight: 300,
                ),
                title: const Text('加入合集…'),
                onTap: _manageCollections,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                  weight: 300,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: _confirmDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/theme.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../widgets/app_overlays.dart';
import 'comic_reader_screen.dart';

/// Reading lists hub (书库二级).
class ListsScreen extends StatelessWidget {
  const ListsScreen({
    super.key,
    required this.brand,
    required this.controller,
    this.readingPreferences,
  });

  final BrandConfig brand;
  final LibraryController controller;
  final ComicReadingPreferences? readingPreferences;

  static Future<void> open(
    BuildContext context, {
    required BrandConfig brand,
    required LibraryController controller,
    ComicReadingPreferences? readingPreferences,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListsScreen(
          brand: brand,
          controller: controller,
          readingPreferences: readingPreferences,
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: semantics.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top inset via app-level [DesktopTitleBarMediaQuery] + SafeArea.
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
                    '书单',
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
            child: StreamBuilder<List<ReadingListSummary>>(
              stream: controller.watchReadingLists(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '加载失败：${snapshot.error}',
                      style: TextStyle(color: semantics.textSecondary),
                    ),
                  );
                }
                final lists = snapshot.data ?? const <ReadingListSummary>[];
                if (lists.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '还没有书单',
                          style: TextStyle(color: semantics.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '创建后可在条目详情或书库多选里加入漫画',
                          style: TextStyle(
                            fontSize: 13,
                            color: semantics.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _create(context),
                          icon: const Icon(Icons.add, weight: 300),
                          label: const Text('新建书单'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  itemCount: lists.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: semantics.hairline),
                  itemBuilder: (context, i) {
                    final s = lists[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.playlist_play_outlined,
                        color: accent,
                        weight: 300,
                      ),
                      title: Text(
                        s.list.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${s.memberCount} 本'),
                      trailing: PopupMenuButton<String>(
                        tooltip: '',
                        onSelected: (value) async {
                          switch (value) {
                            case 'rename':
                              final name = await _promptName(
                                context,
                                title: '重命名书单',
                                initial: s.list.name,
                              );
                              if (name == null || name.isEmpty) return;
                              await controller.renameReadingList(
                                s.list.id,
                                name,
                              );
                            case 'delete':
                              final ok = await showAppConfirmDialog(
                                context,
                                title: '删除书单？',
                                message:
                                    '删除「${s.list.name}」不会删除书库里的漫画。',
                                confirmLabel: '删除',
                                destructive: true,
                              );
                              if (ok == true) {
                                await controller.deleteReadingList(s.list.id);
                              }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ListDetailScreen(
                              brand: brand,
                              controller: controller,
                              list: s.list,
                              readingPreferences: readingPreferences,
                            ),
                          ),
                        );
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

class _ListDetailScreen extends StatelessWidget {
  const _ListDetailScreen({
    required this.brand,
    required this.controller,
    required this.list,
    this.readingPreferences,
  });

  final BrandConfig brand;
  final LibraryController controller;
  final ReadingList list;
  final ComicReadingPreferences? readingPreferences;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;

    return Scaffold(
      backgroundColor: semantics.canvas,
      appBar: AppBar(
        title: Text(list.name),
        backgroundColor: semantics.canvas,
        surfaceTintColor: Colors.transparent,
        // Respects app-level desktop title-bar MediaQuery padding.
        primary: true,
      ),
      body: StreamBuilder<List<ReadingItem>>(
        stream: controller.watchListMembers(list.id),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ReadingItem>[];
          if (items.isEmpty) {
            return Center(
              child: Text(
                '书单为空\n在书库条目详情里加入',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: semantics.textSecondary,
                  height: 1.5,
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.58,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (brand.isBook) {
                    showAppSnackBar(context, '图书阅读引擎即将接入');
                    return;
                  }
                  ComicReaderScreen.open(
                    context,
                    database: controller.database,
                    item: item,
                    readingPreferences: readingPreferences,
                  );
                },
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: item.coverPath != null
                            ? Image.file(
                                File(item.coverPath!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, _, _) =>
                                    ColoredBox(color: semantics.canvas),
                              )
                            : ColoredBox(color: semantics.canvas),
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
          );
        },
      ),
    );
  }
}

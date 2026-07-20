import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../library/import/comic_import_service.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import 'comic_reader_screen.dart';

/// Library grid for imported comics. Book segment arrives with Phase 3.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<void> _import() async {
    final result = await widget.controller.pickAndImportComics();
    if (!mounted || result == null) return;
    _showImportSummary(result);
  }

  void _showImportSummary(ImportResult result) {
    final summary = StringBuffer('已导入 ${result.added} 本');
    if (result.updated > 0) summary.write('，更新 ${result.updated} 本');
    if (result.failures.isNotEmpty) {
      summary.write('，失败 ${result.failures.length} 本');
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(summary.toString())));
  }

  void _openComic(ReadingItem item) {
    ComicReaderScreen.open(
      context,
      database: widget.controller.database,
      item: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final importing = widget.controller.isImporting;
        return Scaffold(
          appBar: AppBar(
            title: const Text('书库'),
            actions: [
              IconButton(
                tooltip: '导入漫画',
                onPressed: importing ? null : _import,
                icon: importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ],
          ),
          body: StreamBuilder<List<ReadingItem>>(
            stream: widget.controller.watchComics(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? const <ReadingItem>[];
              if (items.isEmpty) {
                return _EmptyState(onImport: importing ? null : _import);
              }
              return GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.x4),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: AppSpacing.x4,
                  crossAxisSpacing: AppSpacing.x4,
                  childAspectRatio: 0.62,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _ComicCard(
                  item: items[i],
                  onTap: () => _openComic(items[i]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 48,
            color: semantics.textSecondary,
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            '书库还是空的',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '支持 CBZ / ZIP 漫画',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: semantics.textSecondary),
          ),
          const SizedBox(height: AppSpacing.x4),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('导入漫画'),
          ),
        ],
      ),
    );
  }
}

class _ComicCard extends StatelessWidget {
  const _ComicCard({required this.item, required this.onTap});

  final ReadingItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.medium),
              child: Container(
                width: double.infinity,
                color: semantics.surface,
                child: item.coverPath != null
                    ? Image.file(
                        File(item.coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _CoverFallback(),
                      )
                    : const _CoverFallback(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: semantics.textSecondary,
      ),
    );
  }
}

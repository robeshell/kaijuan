import 'package:flutter/material.dart';

import '../../../domain/reader_models.dart';
import '../app_components.dart';

void showReaderBookmarksSheet(
  BuildContext context, {
  required Listenable listenable,
  required List<ReaderBookmark> Function() bookmarks,
  required String Function(ReaderBookmark bookmark) labelFor,
  required void Function(ReaderBookmark bookmark) onOpen,
  required Future<void> Function(ReaderBookmark bookmark) onRemove,
}) {
  showAppBottomSheet<void>(
    context,
    builder: (sheetContext) => ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final rows = bookmarks();
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  '书签',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              if (rows.isEmpty)
                const AppEmptyState(
                  icon: Icons.bookmark_border,
                  title: '还没有书签',
                  message: '阅读时添加的书签会显示在这里。',
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 40),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bookmark = rows[index];
                      return ListTile(
                        leading: const Icon(Icons.bookmark_outlined),
                        title: Text(labelFor(bookmark)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onOpen(bookmark);
                        },
                        trailing: IconButton(
                          tooltip: '删除书签',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => onRemove(bookmark),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

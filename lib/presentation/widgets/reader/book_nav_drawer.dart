import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../domain/reader_models.dart';
import '../../../readers/book/book_models.dart';
import '../../controllers/book_reader_controller.dart';

/// Side drawer: 目录 | 书签 | 笔记 (刀④ + 笔记列表完善).
class BookNavDrawer extends StatefulWidget {
  const BookNavDrawer({
    super.key,
    required this.controller,
    required this.onOpenTocEntry,
    required this.onOpenNote,
  });

  final BookReaderController controller;
  final void Function(BookTocEntry entry) onOpenTocEntry;

  /// Close drawer first, then jump + present the note editor.
  final void Function(BookAnnotation note) onOpenNote;

  @override
  State<BookNavDrawer> createState() => _BookNavDrawerState();
}

class _BookNavDrawerState extends State<BookNavDrawer>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  BookReaderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: _controller.navDrawerTabIndex.clamp(0, 2),
    );
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    _controller.setNavDrawerTabIndex(_tabs.index);
    setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final noteCount = _controller.notes.length;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: TabBar(
                    controller: _tabs,
                    labelColor: accent,
                    unselectedLabelColor: semantics.textPrimary.withValues(
                      alpha: 0.55,
                    ),
                    indicatorColor: accent,
                    dividerColor: semantics.hairline,
                    labelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: [
                      const Tab(text: '目录'),
                      const Tab(text: '书签'),
                      Tab(
                        text: noteCount > 0 ? '笔记 ($noteCount)' : '笔记',
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return TabBarView(
                    controller: _tabs,
                    children: [
                      _TocList(
                        entries: _controller.tocEntries,
                        currentIndex: _controller.sectionIndex,
                        accent: accent,
                        textPrimary: semantics.textPrimary,
                        onOpen: (entry) {
                          Navigator.of(context).pop();
                          widget.onOpenTocEntry(entry);
                        },
                      ),
                      _BookmarksList(
                        bookmarks: _controller.bookmarks,
                        labelFor: _controller.bookmarkLabel,
                        onOpen: (bookmark) {
                          Navigator.of(context).pop();
                          _controller.goToBookmark(bookmark);
                        },
                        onRemove: _controller.removeBookmark,
                      ),
                      _NotesList(
                        notes: _controller.notes,
                        labelFor: _controller.noteLabel,
                        subtitleFor: _controller.noteListSubtitle,
                        onOpen: (annotation) {
                          Navigator.of(context).pop();
                          widget.onOpenNote(annotation);
                        },
                        onClearNote: _controller.clearAnnotationNote,
                      ),
                    ],
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

class _TocList extends StatelessWidget {
  const _TocList({
    required this.entries,
    required this.currentIndex,
    required this.accent,
    required this.textPrimary,
    required this.onOpen,
  });

  final List<BookTocEntry> entries;
  final int currentIndex;
  final Color accent;
  final Color textPrimary;
  final void Function(BookTocEntry entry) onOpen;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('暂无目录'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final active = entry.sectionIndex == currentIndex;
        final indent = (entry.depth * 12.0).clamp(0.0, 48.0);
        return ListTile(
          contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
          title: Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? accent : textPrimary,
            ),
          ),
          selected: active,
          enabled: entry.sectionIndex != null,
          dense: true,
          onTap: entry.sectionIndex == null ? null : () => onOpen(entry),
        );
      },
    );
  }
}

class _BookmarksList extends StatelessWidget {
  const _BookmarksList({
    required this.bookmarks,
    required this.labelFor,
    required this.onOpen,
    required this.onRemove,
  });

  final List<ReaderBookmark> bookmarks;
  final String Function(ReaderBookmark bookmark) labelFor;
  final void Function(ReaderBookmark bookmark) onOpen;
  final Future<void> Function(ReaderBookmark bookmark) onRemove;

  @override
  Widget build(BuildContext context) {
    if (bookmarks.isEmpty) {
      return const Center(child: Text('还没有书签'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: bookmarks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        return ListTile(
          leading: const Icon(Icons.bookmark_outlined),
          title: Text(labelFor(bookmark)),
          onTap: () => onOpen(bookmark),
          trailing: IconButton(
            tooltip: '删除书签',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onRemove(bookmark),
          ),
        );
      },
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.notes,
    required this.labelFor,
    required this.subtitleFor,
    required this.onOpen,
    required this.onClearNote,
  });

  final List<BookAnnotation> notes;
  final String Function(BookAnnotation annotation) labelFor;
  final String Function(BookAnnotation annotation) subtitleFor;
  final void Function(BookAnnotation annotation) onOpen;
  final Future<void> Function(BookAnnotation annotation) onClearNote;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const Center(child: Text('还没有笔记'));
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final annotation = notes[index];
        final subtitle = subtitleFor(annotation);
        final missingQuote = annotation.selectedText?.trim().isEmpty ?? true;
        return ListTile(
          isThreeLine: subtitle.length > 28,
          leading: const Icon(Icons.edit_note_outlined),
          title: Text(
            labelFor(annotation),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            missingQuote ? subtitle : '「$subtitle」',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: muted, height: 1.3),
          ),
          onTap: () => onOpen(annotation),
          trailing: IconButton(
            tooltip: '清除笔记',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onClearNote(annotation),
          ),
        );
      },
    );
  }
}

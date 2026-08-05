import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';
import '../../../domain/reader_models.dart';
import '../../../readers/book/book_models.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_components.dart';

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
  late List<BookTocEntry> _tocEntries;
  late List<ReaderBookmark> _bookmarks;
  late List<BookAnnotation> _annotations;
  late List<BookAnnotation> _notes;
  late int _sectionIndex;

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
    _takeControllerSnapshot();
    _controller.addListener(_onControllerChanged);
  }

  void _onTabChanged() {
    // TabController updates its index at the start of the indicator motion.
    // Waiting for indexIsChanging=false makes the panel content appear to lag.
    if (_controller.navDrawerTabIndex == _tabs.index) return;
    _controller.setNavDrawerTabIndex(_tabs.index);
    setState(() {});
  }

  void _takeControllerSnapshot() {
    _tocEntries = _controller.tocEntries;
    _bookmarks = _controller.bookmarks;
    _annotations = _controller.annotations;
    _notes = _controller.notes;
    _sectionIndex = _controller.sectionIndex;
  }

  void _onControllerChanged() {
    final tocEntries = _controller.tocEntries;
    final bookmarks = _controller.bookmarks;
    final annotations = _controller.annotations;
    final sectionIndex = _controller.sectionIndex;
    final tocChanged = !identical(tocEntries, _tocEntries);
    final bookmarksChanged = !identical(bookmarks, _bookmarks);
    final annotationsChanged = !identical(annotations, _annotations);
    final sectionChanged = sectionIndex != _sectionIndex;
    if (!tocChanged &&
        !bookmarksChanged &&
        !annotationsChanged &&
        !sectionChanged) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (tocChanged) _tocEntries = tocEntries;
      if (bookmarksChanged) _bookmarks = bookmarks;
      if (annotationsChanged) {
        _annotations = annotations;
        // The controller derives notes from annotations. Do that work only
        // when the annotation stream itself changes, not on every progress tick.
        _notes = _controller.notes;
      }
      if (sectionChanged) _sectionIndex = sectionIndex;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: TabBar(
                controller: _tabs,
                labelColor: accent,
                unselectedLabelColor: context.appPrimaryText.withValues(
                  alpha: 0.55,
                ),
                indicatorColor: accent,
                dividerColor: context.appDivider,
                labelStyle: TextStyle(
                  fontSize: KaiProductTokens.typographyReaderOverlayTitle,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: KaiProductTokens.typographyReaderOverlayTitle,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  const Tab(text: '目录'),
                  const Tab(text: '书签'),
                  Tab(text: _notes.isNotEmpty ? '笔记 (${_notes.length})' : '笔记'),
                ],
              ),
            ),
            Expanded(
              // Keep the drawer's raster cache stable while Scaffold moves it
              // over the platform WebView. Build only the selected list; a
              // TabBarView eagerly lays out neighboring pages on first open.
              child: RepaintBoundary(child: _buildActiveTab(accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab(Color accent) {
    return switch (_tabs.index) {
      0 => _TocList(
        entries: _tocEntries,
        currentIndex: _sectionIndex,
        accent: accent,
        textPrimary: context.appPrimaryText,
        onOpen: (entry) {
          Navigator.of(context).pop();
          widget.onOpenTocEntry(entry);
        },
      ),
      1 => _BookmarksList(
        bookmarks: _bookmarks,
        labelFor: _controller.bookmarkLabel,
        onOpen: (bookmark) {
          Navigator.of(context).pop();
          _controller.goToBookmark(bookmark);
        },
        onRemove: _controller.removeBookmark,
      ),
      _ => _NotesList(
        notes: _notes,
        labelFor: _controller.noteLabel,
        subtitleFor: _controller.noteListSubtitle,
        onOpen: (annotation) {
          Navigator.of(context).pop();
          widget.onOpenNote(annotation);
        },
        onClearNote: _controller.clearAnnotationNote,
      ),
    };
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
      return const AppEmptyState(
        icon: KaijuanIcons.toc,
        title: '这本书没有目录',
        message: '可以继续阅读，或使用搜索定位内容。',
        padding: EdgeInsets.all(20),
      );
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
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
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
      return const AppEmptyState(
        icon: KaijuanIcons.bookmark,
        title: '还没有书签',
        message: '阅读时添加的书签会显示在这里。',
        padding: EdgeInsets.all(20),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: bookmarks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        return ListTile(
          leading: const Icon(KaijuanIcons.bookmark),
          title: Text(labelFor(bookmark)),
          onTap: () => onOpen(bookmark),
          trailing: IconButton(
            tooltip: '删除书签',
            icon: const Icon(KaijuanIcons.delete),
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
      return const AppEmptyState(
        icon: KaijuanIcons.edit,
        title: '还没有笔记',
        message: '选中文字并添加笔记后，会显示在这里。',
        padding: EdgeInsets.all(20),
      );
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
          leading: const Icon(KaijuanIcons.edit),
          title: Text(
            labelFor(annotation),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            missingQuote ? subtitle : '「$subtitle」',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: context.appCaptionSize,
              color: muted,
              height: 1.3,
            ),
          ),
          onTap: () => onOpen(annotation),
          trailing: IconButton(
            tooltip: '清除笔记',
            icon: const Icon(KaijuanIcons.delete),
            onPressed: () => onClearNote(annotation),
          ),
        );
      },
    );
  }
}

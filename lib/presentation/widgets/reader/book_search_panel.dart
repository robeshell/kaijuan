import 'package:flutter/material.dart';

import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';
import '../../../readers/book/foliate_js_bridge.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_components.dart';

/// Full-screen in-book search overlay (顶栏入口 / 选区「搜索」).
class BookSearchPanel extends StatefulWidget {
  const BookSearchPanel({super.key, required this.controller});

  final BookReaderController controller;

  @override
  State<BookSearchPanel> createState() => _BookSearchPanelState();
}

class _BookSearchPanelState extends State<BookSearchPanel> {
  late final TextEditingController _text;
  late final FocusNode _focus;

  BookReaderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _controller.searchQuery);
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.searchQuery.isEmpty) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    _controller.submitSearch(_text.text);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _controller.readingTheme;
    final bg = Color(theme.backgroundArgb);
    final fg = Color(theme.foregroundArgb);
    final muted = fg.withValues(alpha: 0.55);
    final accent = Theme.of(context).colorScheme.primary;
    final hairline = context.appDivider;

    return Material(
      color: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _controller.closeSearch,
                    icon: Icon(KaijuanIcons.close, color: fg, weight: 300),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(
                        color: fg,
                        fontSize: KaiProductTokens.typographyReaderBookTitle,
                      ),
                      cursorColor: accent,
                      decoration: InputDecoration(
                        hintText: '搜索书中内容',
                        hintStyle: TextStyle(color: muted),
                        isDense: true,
                        border: InputBorder.none,
                        suffixIcon: _text.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除',
                                onPressed: () {
                                  _text.clear();
                                  _controller.submitSearch('');
                                  setState(() {});
                                  _focus.requestFocus();
                                },
                                icon: Icon(
                                  KaijuanIcons.close,
                                  color: muted,
                                  size: 18,
                                  weight: 300,
                                ),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  TextButton(
                    onPressed: _submit,
                    child: Text('搜索', style: TextStyle(color: accent)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: hairline),
            if (_controller.searchRunning)
              LinearProgressIndicator(
                value: _controller.searchProgress <= 0
                    ? null
                    : _controller.searchProgress,
                minHeight: 2,
                backgroundColor: hairline,
                color: accent,
              ),
            Expanded(
              child: _Results(controller: _controller, muted: muted, fg: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.controller,
    required this.muted,
    required this.fg,
  });

  final BookReaderController controller;
  final Color muted;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final query = controller.searchQuery.trim();
    final hits = controller.searchHits;
    final running = controller.searchRunning;

    if (query.isEmpty) {
      return const AppEmptyState(
        icon: KaijuanIcons.search,
        title: '搜索书内内容',
        message: '输入关键词开始搜索。',
        padding: EdgeInsets.all(20),
      );
    }
    if (!running && hits.isEmpty) {
      return AppEmptyState(
        icon: KaijuanIcons.searchEmpty,
        title: '没有找到结果',
        message: '没有找到“$query”，换个关键词试试。',
        padding: const EdgeInsets.all(20),
      );
    }
    if (running && hits.isEmpty) {
      return const AppEmptyState(
        icon: KaijuanIcons.search,
        title: '正在搜索',
        message: '正在查找书内内容。',
        loading: true,
        padding: EdgeInsets.all(20),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return _HitTile(
          hit: hit,
          fg: fg,
          muted: muted,
          onTap: () => controller.goToSearchHit(hit),
        );
      },
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.fg,
    required this.muted,
    required this.onTap,
  });

  final FoliateSearchHit hit;
  final Color fg;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final chapter = hit.chapterLabel.trim();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chapter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  chapter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: context.appCaptionSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  color: fg,
                  fontSize: KaiProductTokens.typographyReaderSearchResult,
                  height: 1.35,
                ),
                children: [
                  TextSpan(text: hit.excerptPre),
                  TextSpan(
                    text: hit.excerptMatch,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: hit.excerptPost),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

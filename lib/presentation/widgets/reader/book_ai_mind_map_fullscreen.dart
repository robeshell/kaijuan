import 'package:flutter/material.dart';

import '../../../ai/ai_mind_map.dart';
import 'book_ai_mind_map_view.dart';

/// Full-window explorer for a mind map embedded in a book-AI conversation.
///
/// The chat card intentionally has a bounded height so it can coexist with
/// the conversation. This route owns no cache: it keeps the same map and
/// sends layout changes back to the conversation attachment.
class BookAiMindMapFullscreen extends StatefulWidget {
  const BookAiMindMapFullscreen({
    super.key,
    required this.map,
    required this.onLayoutChanged,
    required this.onOpenEvidence,
    this.title = '思维导图',
  });

  final AiBookMindMap map;
  final ValueChanged<AiMindMapLayout> onLayoutChanged;
  final ValueChanged<AiMindMapEvidence> onOpenEvidence;
  final String title;

  @override
  State<BookAiMindMapFullscreen> createState() =>
      _BookAiMindMapFullscreenState();
}

class _BookAiMindMapFullscreenState extends State<BookAiMindMapFullscreen> {
  late AiBookMindMap _map;
  int _viewEpoch = 0;

  @override
  void initState() {
    super.initState();
    _map = widget.map;
  }

  @override
  void didUpdateWidget(BookAiMindMapFullscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.map != widget.map) _map = widget.map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '重置视图',
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed: () => setState(() => _viewEpoch++),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: BookAiMindMapView(
            key: ValueKey(_viewEpoch),
            map: _map,
            onLayoutChanged: (layout) {
              if (_map.layout == layout) return;
              setState(() => _map = _map.copyWith(layout: layout));
              widget.onLayoutChanged(layout);
            },
            onOpenEvidence: (evidence) {
              // The node-detail sheet has already closed itself. Remove the
              // fullscreen route before the chat workspace callback performs
              // its delayed pop, so the reader text is the final visible route.
              Navigator.of(context).pop();
              widget.onOpenEvidence(evidence);
            },
          ),
        ),
      ),
    );
  }
}

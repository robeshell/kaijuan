import 'package:flutter/material.dart';

import '../../../domain/reader_models.dart';
import '../../controllers/book_reader_controller.dart';
import '../app_overlays.dart';

/// Edit / clear the note attached to a selection or existing annotation.
Future<void> showBookAnnotationNoteSheet(
  BuildContext context, {
  required BookReaderController controller,
  required String cfi,
  String selectedText = '',
  String initialNote = '',
  BookAnnotationType? type,
  String? colorCss,
  bool autofocus = true,
}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _BookAnnotationNoteSheet(
      controller: controller,
      cfi: cfi,
      selectedText: selectedText,
      initialNote: initialNote,
      type: type,
      colorCss: colorCss,
      autofocus: autofocus,
    ),
  );
}

class _BookAnnotationNoteSheet extends StatefulWidget {
  const _BookAnnotationNoteSheet({
    required this.controller,
    required this.cfi,
    required this.selectedText,
    required this.initialNote,
    this.type,
    this.colorCss,
    this.autofocus = true,
  });

  final BookReaderController controller;
  final String cfi;
  final String selectedText;
  final String initialNote;
  final BookAnnotationType? type;
  final String? colorCss;
  final bool autofocus;

  @override
  State<_BookAnnotationNoteSheet> createState() =>
      _BookAnnotationNoteSheetState();
}

class _BookAnnotationNoteSheetState extends State<_BookAnnotationNoteSheet> {
  late final TextEditingController _text;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save({required bool clear}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final noteText = clear ? '' : _text.text;
    await widget.controller.saveAnnotationNote(
      cfi: widget.cfi,
      noteText: noteText,
      selectedText: widget.selectedText,
      type: widget.type,
      colorCss: widget.colorCss,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!mounted) return;
    showAppSnackBar(context, clear ? '已清除笔记' : '笔记已保存');
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final excerpt = widget.selectedText.trim();
    final hasExisting = widget.initialNote.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '笔记',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (excerpt.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                autofocus: widget.autofocus,
                maxLines: 6,
                minLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '写下想法…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (hasExisting)
                    TextButton(
                      onPressed: _saving ? null : () => _save(clear: true),
                      child: const Text('清除笔记'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(clear: false),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ai/ai_cancel.dart';
import '../../../ai/ai_language_service.dart';
import '../../../ai/ai_translation.dart';
import '../../../ai/ai_user_error.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../../../readers/book/book_language_actions.dart';
import '../../controllers/book_reader_controller.dart';
import '../ai_typography.dart';
import '../app_components.dart';
import '../app_overlays.dart';
import 'ai_result_body.dart';

/// In-app AI dictionary / translation result for a book selection.
Future<void> showBookAiLanguageSheet(
  BuildContext context, {
  required BookReaderController controller,
  required BookLanguageOperation operation,
  required String text,
  String? cfi,
  String? contextBefore,
  String? contextAfter,
}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    anchorPoint: appTrailingBottomOverlayAnchor(context),
    builder: (sheetContext) => _BookAiLanguageSheet(
      controller: controller,
      operation: operation,
      text: text,
      cfi: cfi,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
    ),
  );
}

class _BookAiLanguageSheet extends StatefulWidget {
  const _BookAiLanguageSheet({
    required this.controller,
    required this.operation,
    required this.text,
    this.cfi,
    this.contextBefore,
    this.contextAfter,
  });

  final BookReaderController controller;
  final BookLanguageOperation operation;
  final String text;
  final String? cfi;

  /// Surrounding text captured while the WebView selection was still live
  /// (翻译 附带选区前后文). May be empty / null when unavailable.
  final String? contextBefore;
  final String? contextAfter;

  @override
  State<_BookAiLanguageSheet> createState() => _BookAiLanguageSheetState();
}

class _BookAiLanguageSheetState extends State<_BookAiLanguageSheet> {
  CancelToken _cancel = CancelToken();
  StreamSubscription<String>? _sub;
  String _body = '';
  String? _error;
  bool _done = false;
  bool _savingNote = false;
  bool _sourceExpanded = false;
  bool _sameLanguage = false;

  /// Only set when the user picks a language on this sheet. Null means "apply
  /// global prefs + direction mode" (smart bi-di can flip).
  AiTranslationLanguage? _userTargetOverride;

  /// Chip / same-language copy: last resolved effective target.
  AiTranslationLanguage _displayTarget = AiTranslationLanguage.zhHans;

  AiTranslationPreferences _prefs = const AiTranslationPreferences();

  bool get _isTranslate =>
      widget.operation == BookLanguageOperation.selectionTranslation;

  String get _title => switch (widget.operation) {
    BookLanguageOperation.dictionary => '词典',
    BookLanguageOperation.selectionTranslation => '翻译',
    BookLanguageOperation.fullBookTranslation => '翻译',
  };

  @override
  void initState() {
    super.initState();
    _refreshPrefs();
    _displayTarget = _prefs.targetLanguage;
    _sourceExpanded = _prefs.displayMode == AiTranslationDisplayMode.bilingual;
    _start();
  }

  void _refreshPrefs() {
    // Always read live settings so changes made in 设置 apply on the next run
    // (and on 再译) without reopening the book.
    _prefs = widget.controller.translationPreferences;
  }

  void _start() {
    unawaited(_sub?.cancel());
    _cancel = CancelToken();
    _refreshPrefs();
    setState(() {
      _body = '';
      _error = null;
      _done = false;
      _sameLanguage = false;
    });

    AiTranslationRequestOptions? translationOptions;
    if (_isTranslate) {
      // Resolve once here. Pass the concrete effective target so the service
      // does not re-apply smartBidi differently from the chip label.
      final resolved = AiLanguageService.resolveTranslationTarget(
        sourceText: widget.text,
        prefs: _prefs,
        sessionTarget: _userTargetOverride,
      );
      _displayTarget = resolved.effectiveTarget;
      if (resolved.skipBecauseSameLanguage) {
        setState(() {
          _sameLanguage = true;
          _displayTarget = resolved.effectiveTarget;
          _done = true;
        });
        return;
      }
      final before = widget.contextBefore?.trim();
      final after = widget.contextAfter?.trim();
      translationOptions = AiTranslationRequestOptions(
        targetLanguage: resolved.effectiveTarget,
        // Target is already final — do not let the service flip again.
        directionMode: AiTranslationDirectionMode.fixedTarget,
        style: _prefs.style,
        // Pass whatever we captured; the service gates on includeContext +
        // non-empty, so this is a no-op when the engine returned nothing.
        contextBefore: (before == null || before.isEmpty) ? null : before,
        contextAfter: (after == null || after.isEmpty) ? null : after,
      );
    }

    final stream = widget.controller.streamLanguageAssist(
      operation: widget.operation,
      text: widget.text,
      cancelToken: _cancel,
      translationOptions: translationOptions,
    );
    if (stream == null) {
      setState(() {
        _error = 'AI 未启用或未配置';
        _done = true;
      });
      return;
    }
    _sub = stream.listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _body = value;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        if (error is AiSameLanguageException) {
          setState(() {
            _sameLanguage = true;
            _displayTarget = error.target;
            _done = true;
            _error = null;
          });
          return;
        }
        setState(() {
          _error = aiUserErrorMessage(
            error,
            operation: AiUserOperation.language,
          );
          _done = true;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _done = true);
      },
      cancelOnError: true,
    );
  }

  void _onTargetChanged(AiTranslationLanguage lang) {
    if (lang == _displayTarget &&
        _userTargetOverride == lang &&
        !_sameLanguage) {
      return;
    }
    _cancel.cancel();
    setState(() {
      _userTargetOverride = lang;
      _displayTarget = lang;
    });
    _start();
  }

  Future<void> _stop() async {
    _cancel.cancel();
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (!mounted) return;
    setState(() {
      _done = true;
      _error = _body.trim().isEmpty ? '已停止生成' : '已停止生成，以上内容可能不完整';
    });
  }

  @override
  void dispose() {
    _cancel.cancel();
    unawaited(_sub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _copy() async {
    final text = _body.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnackBar(context, '已复制');
  }

  Future<void> _writeNote() async {
    final cfi = (widget.cfi ?? '').trim();
    final translation = _body.trim();
    if (cfi.isEmpty || translation.isEmpty || _savingNote) return;
    setState(() => _savingNote = true);
    try {
      // Re-read prefs so note format matches the latest settings.
      _refreshPrefs();
      final note = switch (_prefs.noteFormat) {
        AiTranslationNoteFormat.translationOnly => translation,
        AiTranslationNoteFormat.sourceAndTranslation =>
          '${widget.text.trim()}\n→\n$translation',
      };
      await widget.controller.saveAnnotationNote(
        cfi: cfi,
        noteText: note,
        selectedText: widget.text,
      );
      if (mounted) showAppSnackBar(context, '已写入笔记');
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _useSystemFallback() async {
    Navigator.of(context).maybePop();
    final result = await widget.controller.performPlatformLanguageAction(
      operation: widget.operation,
      textOverride: widget.text,
    );
    if (!mounted) return;
    if (!result.handled) {
      showAppSnackBar(context, result.message ?? '系统能力不可用');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final canWriteNote =
        (widget.cfi ?? '').trim().isNotEmpty &&
        _body.trim().isNotEmpty &&
        _done &&
        !_sameLanguage &&
        _error == null;
    final source = widget.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final sourceCollapsed = source.length > 96
        ? '${source.substring(0, 96)}…'
        : source;
    final bilingual =
        _isTranslate &&
        _prefs.displayMode == AiTranslationDisplayMode.bilingual;
    final flip = _displayTarget.flipSuggestion;
    final showSource = source.isNotEmpty && (bilingual || _isTranslate);
    final sourceExpanded = _sourceExpanded || bilingual;
    final canToggleSource = !bilingual && source.length > 96;
    final canUseResult =
        _body.trim().isNotEmpty && _done && !_sameLanguage && _error == null;
    final liveStatus = _sameLanguage
        ? '原文与目标语言相同'
        : _error != null
        ? _error!
        : !_done
        ? '$_title生成中'
        : _body.trim().isEmpty
        ? '$_title没有生成内容'
        : '$_title已完成';
    final systemFallbackLabel =
        widget.operation == BookLanguageOperation.dictionary ? '系统词典' : '系统翻译';
    final actionTextStyle = TextStyle(fontSize: context.aiLabelSize);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                liveRegion: true,
                label: liveStatus,
                child: const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
                child: Row(
                  children: [
                    Text(
                      _title,
                      style: TextStyle(
                        fontSize: context.aiBodySize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_isTranslate) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _TargetLanguageChip(
                            language: _displayTarget,
                            enabled: !_savingNote,
                            onSelected: _onTargetChanged,
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    if (!_done && !_sameLanguage)
                      IconButton(
                        tooltip: '停止生成',
                        onPressed: () => unawaited(_stop()),
                        icon: Icon(
                          KaijuanIcons.stopFilled,
                          size: 22,
                          color: context.appColors.error,
                        ),
                      ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(KaijuanIcons.close, size: 20),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSource) ...[
                        if (bilingual)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '原文',
                              style: TextStyle(
                                fontSize: context.appCaptionSize,
                                fontWeight: FontWeight.w600,
                                color: context.appSecondaryText,
                              ),
                            ),
                          ),
                        if (canToggleSource)
                          Semantics(
                            button: true,
                            expanded: _sourceExpanded,
                            hint: _sourceExpanded ? '收起原文' : '展开完整原文',
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(
                                  () => _sourceExpanded = !_sourceExpanded,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          sourceExpanded
                                              ? widget.text.trim()
                                              : sourceCollapsed,
                                          style: TextStyle(
                                            fontSize: context.appCaptionSize,
                                            height: 1.4,
                                            color: context.appSecondaryText,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Icon(
                                          sourceExpanded
                                              ? KaijuanIcons.chevronDown
                                              : KaijuanIcons.chevronRight,
                                          size: 18,
                                          color: context.appSecondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Text(
                            sourceExpanded
                                ? widget.text.trim()
                                : sourceCollapsed,
                            style: TextStyle(
                              fontSize: context.appCaptionSize,
                              height: 1.4,
                              color: context.appSecondaryText,
                            ),
                          ),
                        const SizedBox(height: 14),
                        if (bilingual &&
                            !_sameLanguage &&
                            (_body.isNotEmpty || !_done))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '译文',
                              style: TextStyle(
                                fontSize: context.appCaptionSize,
                                fontWeight: FontWeight.w600,
                                color: context.appSecondaryText,
                              ),
                            ),
                          ),
                      ],
                      if (_sameLanguage) ...[
                        Text(
                          '原文已是${_displayTarget.displayName}。无需同语改写。',
                          style: TextStyle(
                            fontSize: context.aiBodySize,
                            height: 1.5,
                            color: context.appPrimaryText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              textStyle: actionTextStyle,
                            ),
                            onPressed: () => _onTargetChanged(flip),
                            child: Text('改译为 ${flip.displayName}'),
                          ),
                        ),
                      ] else if (_error != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_body.trim().isNotEmpty) ...[
                              SelectionArea(
                                child: Text(
                                  _body,
                                  style: TextStyle(
                                    fontSize: context.aiBodySize,
                                    height: 1.55,
                                    color: context.appPrimaryText,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Text(
                              _error!,
                              style: TextStyle(
                                color: context.appColors.error,
                                fontSize: context.aiBodySize,
                                height: 1.45,
                              ),
                            ),
                          ],
                        )
                      else if (_body.isEmpty && !_done)
                        Text(
                          '生成中…',
                          style: TextStyle(
                            color: context.appSecondaryText,
                            fontSize: context.aiBodySize,
                          ),
                        )
                      else if (_isTranslate)
                        // Only enable selection after the stream finishes.
                        // Rebuilding SelectionArea on every token resets the
                        // desktop selection caret and looks like a flashing cursor.
                        _done
                            ? SelectionArea(
                                child: Text(
                                  _body,
                                  style: TextStyle(
                                    fontSize: context.aiBodySize,
                                    height: 1.55,
                                    color: context.appPrimaryText,
                                  ),
                                ),
                              )
                            : Text(
                                _body,
                                style: TextStyle(
                                  fontSize: context.aiBodySize,
                                  height: 1.55,
                                  color: context.appPrimaryText,
                                ),
                              )
                      else
                        AiResultBody(text: _body),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(textStyle: actionTextStyle),
                      onPressed: canUseResult ? () => unawaited(_copy()) : null,
                      icon: const Icon(KaijuanIcons.copy, size: 18),
                      label: const Text('复制'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(textStyle: actionTextStyle),
                      onPressed: canWriteNote && !_savingNote
                          ? () => unawaited(_writeNote())
                          : null,
                      icon: const Icon(KaijuanIcons.edit, size: 18),
                      label: Text(_savingNote ? '写入中…' : '写入笔记'),
                    ),
                    if (_isTranslate && !_sameLanguage)
                      TextButton(
                        style: TextButton.styleFrom(textStyle: actionTextStyle),
                        // Re-run with live prefs + current chip override (if any).
                        onPressed: _done || _error != null ? _start : null,
                        child: const Text('再译'),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(textStyle: actionTextStyle),
                      onPressed: () => unawaited(_useSystemFallback()),
                      child: Text(systemFallbackLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetLanguageChip extends StatelessWidget {
  const _TargetLanguageChip({
    required this.language,
    required this.enabled,
    required this.onSelected,
  });

  final AiTranslationLanguage language;
  final bool enabled;
  final ValueChanged<AiTranslationLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppMenuButton<AiTranslationLanguage>(
      enabled: enabled,
      tooltip: '目标语言',
      actions: [
        for (final lang in AiTranslationLanguage.values)
          AppMenuAction(
            value: lang,
            label: lang.displayName,
            selected: lang == language,
          ),
      ],
      onSelected: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.appColors.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                language.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  fontWeight: FontWeight.w500,
                  color: context.appPrimaryText,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              KaijuanIcons.chevronDown,
              size: 14,
              color: context.appSecondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

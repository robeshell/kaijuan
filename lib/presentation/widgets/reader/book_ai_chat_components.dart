import 'package:flutter/material.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../ai/ai_chat.dart';
import '../../../ai/ai_mind_map.dart';
import '../../../ai/ai_models.dart';
import '../../../ai/ai_provider_kind.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/theme.dart';
import '../ai_typography.dart';
import 'ai_result_body.dart';
import 'book_ai_mind_map_view.dart';

class BookAiThinkingIndicator extends StatelessWidget {
  const BookAiThinkingIndicator({
    super.key,
    required this.label,
    required this.state,
  });

  final String label;
  final OrbState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: ThinkingOrb(
              state: state,
              size: OrbSize.size20,
              theme: Theme.of(context).brightness == Brightness.dark
                  ? OrbTheme.dark
                  : OrbTheme.light,
              semanticLabel: label,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: context.appSecondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookAiWebSearchToggle extends StatelessWidget {
  const BookAiWebSearchToggle({
    super.key,
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.primary : context.appSecondaryText;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '联网搜索',
      value: selected ? '已开启' : '已关闭',
      toggled: selected,
      child: Tooltip(
        message: selected ? '联网搜索已开启' : '开启联网搜索',
        child: ExcludeSemantics(
          child: IconButton(
            onPressed: enabled ? onPressed : null,
            icon: Icon(KaijuanIcons.globe, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              backgroundColor: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.42),
              disabledForegroundColor: context.appSecondaryText.withValues(
                alpha: 0.5,
              ),
              minimumSize: Size.square(context.appIsCompact ? 44 : 40),
              padding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookAiDeepThinkingToggle extends StatelessWidget {
  const BookAiDeepThinkingToggle({
    super.key,
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.primary : context.appSecondaryText;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '深度思考',
      value: selected ? '已开启' : '已关闭',
      toggled: selected,
      child: Tooltip(
        message: selected ? '深度思考已开启' : '开启深度思考',
        child: ExcludeSemantics(
          child: IconButton(
            key: const ValueKey<String>('ai-chat-deep-thinking-toggle'),
            onPressed: enabled ? onPressed : null,
            icon: const Icon(KaijuanIcons.aiChat, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              backgroundColor: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.42),
              disabledForegroundColor: context.appSecondaryText.withValues(
                alpha: 0.5,
              ),
              minimumSize: Size.square(context.appIsCompact ? 44 : 40),
              padding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookAiSuggestedQuestionList extends StatelessWidget {
  const BookAiSuggestedQuestionList({
    super.key,
    required this.shortcuts,
    required this.onSelected,
  });

  final List<AiChatShortcut> shortcuts;
  final ValueChanged<AiChatShortcut> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final compact = context.appIsCompact;
    final maxWidth = MediaQuery.sizeOf(context).width * (compact ? 0.88 : 0.74);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < shortcuts.length; index++) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSelected(shortcuts[index]),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 14,
                      compact ? 8 : 9,
                      compact ? 10 : 12,
                      compact ? 8 : 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            shortcuts[index].label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact
                                  ? context.aiLabelSize
                                  : context.aiDetailSize,
                              height: 1.4,
                              color: context.appPrimaryText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          KaijuanIcons.chevronRight,
                          size: compact ? 15 : 17,
                          color: context.appSecondaryText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (index < shortcuts.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class BookAiBubble extends StatelessWidget {
  const BookAiBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.streaming = false,
    this.onMindMapLayoutChanged,
    this.onOpenMindMapEvidence,
    this.onOpenMindMapFullscreen,
    this.onContinueEditingMindMap,
    this.revealMindMapOnMount = false,
    this.onMindMapRevealed,
    this.onMindMapPointerHoverChanged,
  });

  final AiChatMessage message;
  final VoidCallback? onCopy;
  final bool streaming;
  final ValueChanged<AiMindMapLayout>? onMindMapLayoutChanged;
  final ValueChanged<AiMindMapEvidence>? onOpenMindMapEvidence;
  final VoidCallback? onOpenMindMapFullscreen;
  final VoidCallback? onContinueEditingMindMap;
  final bool revealMindMapOnMount;
  final VoidCallback? onMindMapRevealed;
  final ValueChanged<bool>? onMindMapPointerHoverChanged;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiMessageRole.user;
    final bg = isUser
        ? context.appColors.primary.withValues(alpha: 0.12)
        : Colors.transparent;
    final webHits = message.webHitCount;
    final compact = context.appIsCompact;
    final maxWidth = MediaQuery.sizeOf(context).width * (isUser ? 0.76 : 0.92);

    final bubble = Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 14),
      padding: isUser
          ? EdgeInsets.symmetric(
              horizontal: compact ? 13 : 15,
              vertical: compact ? 9 : 10,
            )
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(isUser ? 16 : 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUser)
            SelectionArea(
              child: Text(
                message.content,
                style: TextStyle(
                  fontSize: context.aiBodySize,
                  height: compact ? 1.5 : 1.55,
                  color: context.appPrimaryText,
                ),
              ),
            )
          else ...[
            if (message.reasoningContent.trim().isNotEmpty)
              _ReasoningDisclosure(
                text: message.reasoningContent,
                streaming: streaming,
                kind: message.reasoningKind,
              ),
            if (message.reasoningContent.trim().isNotEmpty &&
                message.content.trim().isNotEmpty)
              const SizedBox(height: 8),
            if (message.content.trim().isNotEmpty)
              AiResultBody(
                text: message.content,
                compact: compact,
                streaming: streaming,
              ),
            if (message.mindMap case final map?) ...[
              if (message.content.trim().isNotEmpty) const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: context.appDivider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox(
                  height: compact ? 420 : 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BookAiMindMapView(
                      map: map,
                      onLayoutChanged: onMindMapLayoutChanged ?? (_) {},
                      onOpenEvidence: onOpenMindMapEvidence ?? (_) {},
                      onOpenFullscreen: onOpenMindMapFullscreen,
                      revealOnMount: revealMindMapOnMount,
                      onRevealed: onMindMapRevealed,
                      onPointerHoverChanged: onMindMapPointerHoverChanged,
                    ),
                  ),
                ),
              ),
              if (onContinueEditingMindMap != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    key: ValueKey<String>(
                      'ai-mind-map-edit-${map.artifactId ?? message.turnId ?? map.scopeFingerprint}',
                    ),
                    onPressed: onContinueEditingMindMap,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('继续修改'),
                  ),
                ),
              ],
            ],
          ],
          if (isUser && webHits != null) ...[
            const SizedBox(height: 6),
            Text(
              webHits == 0 ? '联网 · 无结果' : '联网 · $webHits 条',
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: context.appSecondaryText,
                height: 1.2,
              ),
            ),
          ],
          if (message.status != AiChatTurnStatus.completed &&
              message.status != AiChatTurnStatus.pending) ...[
            const SizedBox(height: 6),
            Text(
              switch (message.status) {
                AiChatTurnStatus.failed => isUser ? '发送失败' : '回答未完成',
                AiChatTurnStatus.cancelled => isUser ? '已停止' : '回答已停止',
                _ => '',
              },
              style: TextStyle(
                fontSize: context.appCaptionSize,
                color: message.status == AiChatTurnStatus.failed
                    ? context.appColors.error
                    : context.appSecondaryText,
                height: 1.2,
              ),
            ),
          ],
          if (!isUser && !streaming && onCopy != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '复制本条回答',
                onPressed: onCopy,
                icon: const Icon(KaijuanIcons.copy, size: 15),
                style: IconButton.styleFrom(
                  foregroundColor: context.appSecondaryText,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.square(compact ? 30 : 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: isUser
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: IntrinsicWidth(child: bubble),
            )
          : SizedBox(width: maxWidth, child: bubble),
    );
  }
}

class _ReasoningDisclosure extends StatefulWidget {
  const _ReasoningDisclosure({
    required this.text,
    required this.streaming,
    required this.kind,
  });

  final String text;
  final bool streaming;
  final AiReasoningContentKind kind;

  @override
  State<_ReasoningDisclosure> createState() => _ReasoningDisclosureState();
}

class _ReasoningDisclosureState extends State<_ReasoningDisclosure> {
  late bool _expanded = widget.streaming;

  @override
  void didUpdateWidget(covariant _ReasoningDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming != oldWidget.streaming) {
      _expanded = widget.streaming;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = widget.streaming
        ? '正在思考'
        : widget.kind == AiReasoningContentKind.summary
        ? '思考摘要'
        : '思考过程';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: label,
            value: _expanded ? '已展开' : '已折叠',
            onTap: () => setState(() => _expanded = !_expanded),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      KaijuanIcons.aiChat,
                      size: 15,
                      color: context.appSecondaryText,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          fontWeight: FontWeight.w600,
                          color: context.appSecondaryText,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        KaijuanIcons.chevronRight,
                        size: 15,
                        color: context.appSecondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectionArea(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    height: 1.55,
                    color: context.appSecondaryText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

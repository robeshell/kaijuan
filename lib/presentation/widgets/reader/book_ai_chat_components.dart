import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../ai/ai_chat.dart';
import '../../../ai/ai_mind_map.dart';
import '../../../ai/ai_models.dart';
import '../../../ai/ai_provider_kind.dart';
import '../../../core/kaijuan_icons.dart';
import '../../../core/text_editing_focus.dart';
import '../../../core/theme.dart';
import '../../controllers/book_ai_mind_map_coordinator.dart';
import '../ai_typography.dart';
import 'ai_result_body.dart';
import 'book_ai_mind_map_scope_card.dart';
import 'book_ai_action_confirmation_card.dart';
import 'book_ai_mind_map_view.dart';

/// Completed-turn tool summary. Live progress stays on the thinking line.
class BookAiToolStepSummary extends StatelessWidget {
  const BookAiToolStepSummary({required this.steps, super.key});

  final List<AiChatToolStep> steps;

  @override
  Widget build(BuildContext context) {
    final summary = AiChatToolStep.summarize(steps);
    if (summary.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
      child: Text(
        summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: context.appCaptionSize,
          height: 1.3,
          color: context.appSecondaryText,
        ),
      ),
    );
  }
}

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

/// AI chat composer. Stateful so the [TextField] element stays stable across
/// parent rebuilds (streaming tool steps, structure resolve, etc.) and does
/// not re-attach the text input connection mid-IME / dictation.
class BookAiComposer extends StatefulWidget {
  const BookAiComposer({
    required this.controller,
    required this.focusNode,
    required this.locked,
    required this.sending,
    required this.webSearchSelected,
    required this.deepThinkingSupported,
    required this.deepThinkingSelected,
    required this.selection,
    required this.controlSize,
    required this.onSend,
    required this.onStop,
    required this.onWebSearchChanged,
    required this.onDeepThinkingChanged,
    required this.onSelectionRemoved,
    this.actionChips = const [],
    this.onActionChip,
    this.activeMindMapTitle,
    this.activeMindMapRevision,
    this.onMindMapDetached,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool locked;
  final bool sending;
  final bool webSearchSelected;
  final bool deepThinkingSupported;
  final bool deepThinkingSelected;
  final String selection;
  final double controlSize;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<bool> onWebSearchChanged;
  final ValueChanged<bool> onDeepThinkingChanged;
  final VoidCallback onSelectionRemoved;
  final List<AiChatShortcut> actionChips;
  final ValueChanged<AiChatShortcut>? onActionChip;
  final String? activeMindMapTitle;
  final int? activeMindMapRevision;
  final VoidCallback? onMindMapDetached;

  @override
  State<BookAiComposer> createState() => _BookAiComposerState();
}

class _BookAiComposerState extends State<BookAiComposer> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final locked = widget.locked;
    final sending = widget.sending;
    final webSearchSelected = widget.webSearchSelected;
    final deepThinkingSupported = widget.deepThinkingSupported;
    final deepThinkingSelected = widget.deepThinkingSelected;
    final selection = widget.selection;
    final controlSize = widget.controlSize;
    final onSend = widget.onSend;
    final onStop = widget.onStop;
    final onWebSearchChanged = widget.onWebSearchChanged;
    final onDeepThinkingChanged = widget.onDeepThinkingChanged;
    final onSelectionRemoved = widget.onSelectionRemoved;
    final actionChips = widget.actionChips;
    final onActionChip = widget.onActionChip;
    final activeMindMapTitle = widget.activeMindMapTitle;
    final activeMindMapRevision = widget.activeMindMapRevision;
    final onMindMapDetached = widget.onMindMapDetached;
    final colors = context.appColors;
    final hasSelection = selection.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activeMindMapTitle case final title?) ...[
            InputChip(
              avatar: const Icon(Icons.account_tree_outlined, size: 16),
              label: Text(
                '$title · 修订 ${activeMindMapRevision ?? 1}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onDeleted: locked ? null : onMindMapDetached,
              deleteIcon: const Icon(KaijuanIcons.close, size: 16),
            ),
            const SizedBox(height: 6),
          ],
          if (actionChips.isNotEmpty && onActionChip != null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < actionChips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ActionChip(
                      label: Text(
                        actionChips[i].label,
                        style: TextStyle(fontSize: context.aiDetailSize),
                      ),
                      onPressed: locked
                          ? null
                          : () => onActionChip(actionChips[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              BookAiWebSearchToggle(
                enabled: !locked,
                selected: webSearchSelected,
                onPressed: () => onWebSearchChanged(!webSearchSelected),
              ),
              if (deepThinkingSupported) ...[
                const SizedBox(width: 8),
                BookAiDeepThinkingToggle(
                  enabled: !locked,
                  selected: deepThinkingSelected,
                  onPressed: () => onDeepThinkingChanged(!deepThinkingSelected),
                ),
              ],
              if (hasSelection) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: InputChip(
                    avatar: const Icon(KaijuanIcons.quote, size: 16),
                    label: Text(
                      selection.length > 28
                          ? '${selection.substring(0, 28)}…'
                          : selection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: context.aiDetailSize),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    onDeleted: locked ? null : onSelectionRemoved,
                    deleteIcon: const Icon(KaijuanIcons.close, size: 16),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            key: const ValueKey<String>('ai-chat-composer'),
            constraints: BoxConstraints(minHeight: controlSize),
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: withDesktopTextEditingShortcuts(
                    controller: controller,
                    withDesktopChatSubmit(
                      controller: controller,
                      enabled: !locked && !sending,
                      onSubmit: onSend,
                      TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !locked,
                        autofocus: false,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        // newline keeps IME/dictation from treating confirm
                        // as send. Desktop Enter is handled above when idle.
                        textInputAction: TextInputAction.newline,
                        // none: sentences capitalization rewrites the first
                        // grapheme under some IMEs / voice-to-text sessions.
                        textCapitalization: TextCapitalization.none,
                        enableInteractiveSelection: true,
                        // Fewer automatic rewrites while dictating or composing.
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        spellCheckConfiguration:
                            const SpellCheckConfiguration.disabled(),
                        // No onTap focus/clearPlatformFocus — the field focuses
                        // itself; WebView clear is deferred and IME-safe.
                        style: context.appInputTextStyle.copyWith(
                          color: context.appPrimaryText,
                        ),
                        decoration: InputDecoration(
                          hintText: '问这本书…',
                          hintStyle: context.appInputTextStyle.copyWith(
                            color: context.appSecondaryText,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (sending)
                  IconButton.filledTonal(
                    tooltip: '停止',
                    onPressed: onStop,
                    style: IconButton.styleFrom(
                      fixedSize: Size.square(controlSize),
                      padding: const EdgeInsets.all(10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      KaijuanIcons.stopFilled,
                      size: 18,
                      color: colors.error,
                    ),
                  )
                else
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: locked ? null : onSend,
                    style: IconButton.styleFrom(
                      fixedSize: Size.square(controlSize),
                      padding: const EdgeInsets.all(10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(KaijuanIcons.sendFilled, size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BookAiChatTimeline extends StatelessWidget {
  const BookAiChatTimeline({
    required this.scrollController,
    required this.compact,
    required this.pointerActive,
    required this.liveStatus,
    required this.messages,
    required this.openingShortcuts,
    required this.followUpShortcuts,
    required this.showFollowUpShortcuts,
    required this.showStatusIndicator,
    required this.statusIndicatorLabel,
    required this.statusOrbState,
    required this.activeTurnVisible,
    required this.streamingText,
    required this.streamingReasoning,
    required this.streamingReasoningKind,
    required this.searchingWeb,
    required this.actionChips,
    required this.error,
    required this.canRetry,
    required this.mindMapRevealTurnId,
    required this.onUserDrag,
    required this.onShortcutSelected,
    required this.onActionChip,
    required this.onCopy,
    required this.onMindMapLayoutChanged,
    required this.onOpenMindMapEvidence,
    required this.onOpenMindMapFullscreen,
    required this.onMindMapRevealed,
    required this.onMindMapPointerChanged,
    required this.onRetry,
    this.scopePrompt,
    this.onScopeSelected,
    this.onScopeCancelled,
    this.actionPrompt,
    this.onActionApproved,
    this.onActionRejected,
    super.key,
  });

  final ScrollController scrollController;
  final bool compact;
  final bool pointerActive;
  final String liveStatus;
  final List<AiChatMessage> messages;
  final List<AiChatShortcut> openingShortcuts;
  final List<AiChatShortcut> followUpShortcuts;
  final bool showFollowUpShortcuts;
  final bool showStatusIndicator;
  final String statusIndicatorLabel;
  final OrbState statusOrbState;
  final bool activeTurnVisible;
  final String streamingText;
  final String streamingReasoning;
  final AiReasoningContentKind streamingReasoningKind;
  final bool searchingWeb;
  final List<AiChatShortcut> actionChips;
  final String? error;
  final bool canRetry;
  final String? mindMapRevealTurnId;
  final VoidCallback onUserDrag;
  final ValueChanged<AiChatShortcut> onShortcutSelected;
  final ValueChanged<AiChatShortcut> onActionChip;
  final ValueChanged<AiChatMessage> onCopy;
  final void Function(AiChatMessage, AiMindMapLayout) onMindMapLayoutChanged;
  final ValueChanged<AiMindMapEvidence> onOpenMindMapEvidence;
  final ValueChanged<AiChatMessage> onOpenMindMapFullscreen;
  final ValueChanged<AiChatMessage> onMindMapRevealed;
  final ValueChanged<bool> onMindMapPointerChanged;
  final VoidCallback onRetry;
  final BookAiMindMapScopePrompt? scopePrompt;
  final ValueChanged<int>? onScopeSelected;
  final VoidCallback? onScopeCancelled;
  final BookAiProductActionPrompt? actionPrompt;
  final VoidCallback? onActionApproved;
  final VoidCallback? onActionRejected;

  @override
  Widget build(BuildContext context) {
    // One SelectionArea for the whole transcript. Nested SelectionArea +
    // MarkdownBody(selectable: true) fight the ListView drag gesture and make
    // desktop/macOS text selection feel broken.
    return SelectionArea(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Wheel / trackpad / drag all count. Programmatic jumpTo does not
          // emit UserScrollNotification, so auto-follow is not cancelled.
          if (notification is UserScrollNotification &&
              notification.direction != ScrollDirection.idle) {
            onUserDrag();
          }
          return false;
        },
        child: CustomScrollView(
          key: const ValueKey<String>('ai-chat-message-list'),
          controller: scrollController,
          // NeverScrollable only while the pointer is on a mind-map canvas so
          // InteractiveViewer can pan/zoom. Coordinator debounces leave events;
          // rapid physics swaps otherwise rebuild ScrollPosition and jitter the
          // whole panel.
          physics: pointerActive
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, compact ? 0 : 4, 16, 0),
              sliver: SliverToBoxAdapter(child: _buildHeader(context)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final message = messages[index];
                    return BookAiBubble(
                      key: ValueKey<String>(_messageKey(message)),
                      message: message,
                      onCopy: () => onCopy(message),
                      onMindMapLayoutChanged: message.mindMap == null
                          ? null
                          : (layout) => onMindMapLayoutChanged(message, layout),
                      onOpenMindMapEvidence: message.mindMap == null
                          ? null
                          : onOpenMindMapEvidence,
                      onOpenMindMapFullscreen: message.mindMap == null
                          ? null
                          : () => onOpenMindMapFullscreen(message),
                      revealMindMapOnMount:
                          message.mindMap != null &&
                          message.turnId == mindMapRevealTurnId,
                      onMindMapRevealed: message.turnId == null
                          ? null
                          : () => onMindMapRevealed(message),
                      onMindMapPointerHoverChanged: onMindMapPointerChanged,
                    );
                  },
                  childCount: messages.length,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final index = messages.indexWhere(
                      (message) => _messageKey(message) == key.value,
                    );
                    return index >= 0 ? index : null;
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 8 : 12),
              sliver: SliverToBoxAdapter(child: _buildFooter(context)),
            ),
          ],
        ),
      ),
    );
  }

  static String _messageKey(AiChatMessage message) =>
      '${message.turnId ?? message.createdAt?.microsecondsSinceEpoch ?? message.hashCode}:'
      '${message.mindMap?.scopeFingerprint ?? ''}';

  Widget _buildHeader(BuildContext context) {
    final showEmpty =
        messages.isEmpty &&
        streamingText.isEmpty &&
        streamingReasoning.isEmpty &&
        !searchingWeb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (liveStatus.isNotEmpty)
          Semantics(
            container: true,
            liveRegion: true,
            label: liveStatus,
            child: const SizedBox.shrink(),
          ),
        if (showEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              4,
              compact ? 12 : 20,
              4,
              compact ? 16 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '围绕这本书聊聊：总结、人物，或你想到的问题。',
                  style: TextStyle(
                    fontSize: context.aiBodySize,
                    height: 1.6,
                    color: context.appSecondaryText,
                  ),
                ),
                if (scopePrompt == null && openingShortcuts.isNotEmpty) ...[
                  SizedBox(height: compact ? 12 : 16),
                  SelectionContainer.disabled(
                    child: BookAiSuggestedQuestionList(
                      shortcuts: openingShortcuts,
                      onSelected: onShortcutSelected,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scopePrompt case final prompt?)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 14),
            child: BookAiMindMapScopeChoiceCard(
              prompt: prompt,
              onSelected: onScopeSelected!,
              onCancel: onScopeCancelled!,
            ),
          ),
        if (actionPrompt case final prompt?)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 14),
            child: BookAiActionConfirmationCard(
              prompt: prompt,
              onApprove: onActionApproved!,
              onReject: onActionRejected!,
            ),
          ),
        if (showFollowUpShortcuts) ...[
          if (actionChips.isNotEmpty)
            SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      for (var i = 0; i < actionChips.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        ActionChip(
                          label: Text(
                            actionChips[i].label,
                            style: TextStyle(fontSize: context.aiDetailSize),
                          ),
                          onPressed: () => onActionChip(actionChips[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          SelectionContainer.disabled(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 12),
              child: BookAiSuggestedQuestionList(
                shortcuts: followUpShortcuts,
                onSelected: onShortcutSelected,
              ),
            ),
          ),
        ],
        if (showStatusIndicator)
          ExcludeSemantics(
            child: BookAiThinkingIndicator(
              label: statusIndicatorLabel,
              state: statusOrbState,
            ),
          ),
        if (activeTurnVisible &&
            (streamingText.isNotEmpty || streamingReasoning.isNotEmpty))
          BookAiBubble(
            key: const ValueKey<String>('live-assistant'),
            message: AiChatMessage(
              role: AiMessageRole.assistant,
              content: streamingText,
              reasoningContent: streamingReasoning,
              reasoningKind: streamingReasoningKind,
            ),
            streaming: true,
          ),
        if (error case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: colors.error,
                      fontSize: context.aiBodySize,
                      height: 1.4,
                    ),
                  ),
                ),
                if (canRetry) ...[
                  const SizedBox(width: 8),
                  SelectionContainer.disabled(
                    child: OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    final stepSummary = !isUser && !streaming && message.toolSteps.isNotEmpty
        ? BookAiToolStepSummary(steps: message.toolSteps)
        : null;

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
            Text(
              message.visibleContent,
              style: TextStyle(
                fontSize: context.aiBodySize,
                height: compact ? 1.5 : 1.55,
                color: context.appPrimaryText,
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
              // selectable:false — parent ListView is wrapped in SelectionArea;
              // MarkdownBody's own SelectableText fights ListView drag and
              // nested selection registries on desktop.
              AiResultBody(
                text: message.content,
                compact: compact,
                streaming: streaming,
                selectable: false,
              ),
            if (message.mindMap case final map?) ...[
              if (message.content.trim().isNotEmpty) const SizedBox(height: 8),
              // Mind-map canvas must not participate in text selection.
              SelectionContainer.disabled(
                child: DecoratedBox(
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
              ),
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
              child: SelectionContainer.disabled(
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
            ),
          ],
        ],
      ),
    );

    final body = isUser
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: IntrinsicWidth(child: bubble),
          )
        : SizedBox(
            width: maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stepSummary != null)
                  SelectionContainer.disabled(child: stepSummary),
                bubble,
              ],
            ),
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: body,
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
          SelectionContainer.disabled(
            child: Semantics(
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
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              // Parent transcript SelectionArea already covers this Text.
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  height: 1.55,
                  color: context.appSecondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

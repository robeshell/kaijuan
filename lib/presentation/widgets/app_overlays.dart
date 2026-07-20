import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Shared overlay language: dialogs, sheets, snackbars.
/// Quiet surfaces, Chinese copy, light outlined icons — both brands.

/// Preferred outlined icons for chrome (not heavy rounded fills).
abstract final class AppIcons {
  static const double size = 20;
  static const double sizeSm = 18;
  static const double weight = 300;
}

/// Soft Chinese tooltips (no system English defaults).
class AppTooltip extends StatelessWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 450),
  });

  final String message;
  final Widget child;
  final Duration waitDuration;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;
    return Tooltip(
      message: message,
      waitDuration: waitDuration,
      preferBelow: true,
      child: child,
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = AppIcons.size,
    this.visualDensity = VisualDensity.compact,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final VisualDensity visualDensity;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final button = IconButton(
      onPressed: onPressed,
      visualDensity: visualDensity,
      style: IconButton.styleFrom(
        foregroundColor: color ?? semantics.textSecondary,
        disabledForegroundColor: semantics.textSecondary.withValues(alpha: 0.35),
      ),
      icon: Icon(icon, size: size, weight: AppIcons.weight),
    );
    if (tooltip == null || tooltip!.isEmpty) return button;
    return AppTooltip(message: tooltip!, child: button);
  }
}

/// Confirm / alert dialog with quiet surface (not default M3 sheet gray).
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => AppAlertDialog(
      title: title,
      content: Text(message),
      actions: [
        AppDialogAction(
          label: cancelLabel,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        AppDialogAction(
          label: confirmLabel,
          primary: true,
          destructive: destructive,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
}

Future<String?> showAppTextPrompt(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  String cancelLabel = '取消',
  String confirmLabel = '确定',
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => _AppTextPromptDialog(
      title: title,
      hint: hint,
      initial: initial,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

/// Owns [TextEditingController] for the dialog lifetime (do not dispose on
/// route future completion — reverse animation still rebuilds the field).
class _AppTextPromptDialog extends StatefulWidget {
  const _AppTextPromptDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String initial;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_AppTextPromptDialog> createState() => _AppTextPromptDialogState();
}

class _AppTextPromptDialogState extends State<_AppTextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: widget.title,
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          filled: true,
          fillColor: AppColors.lightWash,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        AppDialogAction(
          label: widget.cancelLabel,
          onPressed: () => Navigator.pop(context),
        ),
        AppDialogAction(
          label: widget.confirmLabel,
          primary: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

void showAppSnackBar(BuildContext context, String message) {
  final semantics = Theme.of(context).extension<AppSemantics>()!;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: semantics.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: semantics.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          side: BorderSide(color: semantics.hairline),
        ),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      ),
    );
}

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final semantics = Theme.of(context).extension<AppSemantics>()!;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    backgroundColor: semantics.surface,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadii.panel),
      ),
    ),
    builder: builder,
  );
}

/// Styled action row for sheets (light icon + title).
class AppSheetTile extends StatelessWidget {
  const AppSheetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : semantics.textPrimary;
    final iconColor = destructive
        ? Theme.of(context).colorScheme.error
        : accent.withValues(alpha: 0.9);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: AppIcons.size, weight: AppIcons.weight, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: semantics.textSecondary,
              ),
            ),
      onTap: onTap,
    );
  }
}

class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    return Dialog(
      backgroundColor: semantics.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        side: BorderSide(color: semantics.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: semantics.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: semantics.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
                child: content,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDialogAction extends StatelessWidget {
  const AppDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final semantics = Theme.of(context).extension<AppSemantics>()!;
    final accent = Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;

    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: destructive ? error : accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: semantics.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Popup menu themed for Chinese chrome; always pass [tooltip] in Chinese.
PopupMenuItem<T> appPopupItem<T>({
  required T value,
  required String label,
  IconData? icon,
  bool checked = false,
}) {
  return PopupMenuItem<T>(
    value: value,
    height: 40,
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppIcons.sizeSm, weight: AppIcons.weight),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        if (checked)
          const Icon(Icons.check, size: 16, weight: AppIcons.weight),
      ],
    ),
  );
}

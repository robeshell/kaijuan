import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/theme/brand_tokens.g.dart';
import 'app_components.dart';

/// Shared overlay language: dialogs, sheets, snackbars.
/// Quiet surfaces, Chinese copy, light outlined icons — both brands.
///
/// Public APIs in this file are stable; internals are built on the shared
/// component kit (app_components.dart) and the semantic tokens.

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
    final secondary = context.appSecondaryText;
    final button = IconButton(
      onPressed: onPressed,
      visualDensity: visualDensity,
      style: IconButton.styleFrom(
        foregroundColor: color ?? secondary,
        disabledForegroundColor: secondary.withValues(alpha: 0.35),
      ),
      icon: Icon(icon, size: size, weight: AppIcons.weight),
    );
    if (tooltip == null || tooltip!.isEmpty) return button;
    return AppTooltip(message: tooltip!, child: button);
  }
}

Color appDialogBarrierColor(BuildContext context) {
  return DialogTheme.of(context).barrierColor ??
      Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.62 : 0.38,
      );
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
    barrierColor: appDialogBarrierColor(context),
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
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) => _AppTextPromptDialog(
      title: title,
      hint: hint,
      initial: initial,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

class AppDialogChoice<T> {
  const AppDialogChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

Future<T?> showAppChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<AppDialogChoice<T>> choices,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (dialogContext) => AppDialog(
      maxWidth: 360,
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            ListTile(
              leading: choice.icon == null
                  ? null
                  : Icon(choice.icon, weight: 300),
              title: Text(choice.label),
              subtitle: choice.subtitle == null || choice.subtitle!.isEmpty
                  ? null
                  : Text(choice.subtitle!),
              onTap: () => Navigator.pop(dialogContext, choice.value),
            ),
        ],
      ),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

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
      content: AppTextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontWeight: FontWeight.w500),
        decoration: InputDecoration(hintText: widget.hint),
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
  final width = MediaQuery.sizeOf(context).width;
  // Tight centered chip. Do not clamp side insets — that stretched the bar
  // across the desktop window and looked like a system banner.
  final toastWidth = width >= 420 ? 220.0 : (width - 56).clamp(140.0, 220.0);
  final side = (width - toastWidth) / 2;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      _buildAppSnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(milliseconds: 2200),
        margin: EdgeInsets.fromLTRB(side, 0, side, 36),
        dismissDirection: DismissDirection.down,
      ),
    );
}

/// Persistent lightweight status chip for work that must remain visible until
/// the caller explicitly closes it (for example, automatic library scanning).
/// It deliberately shares the same floating geometry as [showAppSnackBar].
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
showAppProgressSnackBar(BuildContext context, String message) {
  final width = MediaQuery.sizeOf(context).width;
  final toastWidth = width >= 420 ? 220.0 : (width - 56).clamp(140.0, 220.0);
  final side = (width - toastWidth) / 2;
  final accent = context.appColors.primary;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();

  return messenger.showSnackBar(
    _buildAppSnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      duration: const Duration(days: 1),
      margin: EdgeInsets.fromLTRB(side, 0, side, 36),
      dismissDirection: DismissDirection.none,
    ),
  );
}

SnackBar _buildAppSnackBar({
  required Widget content,
  required Duration duration,
  required EdgeInsets margin,
  required DismissDirection dismissDirection,
}) {
  return SnackBar(
    content: AppGlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shadowOffset: const Offset(0, 3),
      shadowBlur: 12,
      child: SizedBox(width: double.infinity, child: content),
    ),
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    margin: margin,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    duration: duration,
    dismissDirection: dismissDirection,
  );
}

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
}) {
  return showAppBottomSheet<T>(
    context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
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
    final accent = context.appColors.primary;
    final error = context.appColors.error;
    final color = destructive ? error : context.appPrimaryText;
    final iconColor = destructive ? error : accent.withValues(alpha: 0.9);

    return AppListRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Icon(
        icon,
        size: AppIcons.size,
        weight: AppIcons.weight,
        color: iconColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: KaiProductTokens.typographyReaderOverlayTitle,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
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
    return AppDialog(
      maxWidth: 400,
      title: Text(title),
      content: content,
      actions: actions,
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
    if (destructive) {
      return FilledButton(
        onPressed: onPressed,
        style: context.appDestructiveButtonStyle,
        child: Text(label),
      );
    }
    if (primary) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return TextButton(onPressed: onPressed, child: Text(label));
  }
}

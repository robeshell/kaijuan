import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/import/import_models.dart';
import '../controllers/library_controller.dart';
import '../navigation/app_page_route.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';

class LocalImportReviewScreen extends StatefulWidget {
  const LocalImportReviewScreen({
    super.key,
    required this.paths,
    required this.controller,
  });

  final List<String> paths;
  final LibraryController controller;

  static Future<ImportResult?> open(
    BuildContext context, {
    required List<String> paths,
    required LibraryController controller,
  }) {
    return Navigator.of(context).push<ImportResult>(
      appPageRoute<ImportResult>(
        (_) => LocalImportReviewScreen(paths: paths, controller: controller),
      ),
    );
  }

  @override
  State<LocalImportReviewScreen> createState() =>
      _LocalImportReviewScreenState();
}

class _LocalImportReviewScreenState extends State<LocalImportReviewScreen> {
  final Set<String> _selected = {};
  bool _importing = false;

  bool get _allSelected =>
      widget.paths.isNotEmpty && _selected.length == widget.paths.length;

  void _toggle(String path) {
    if (_importing) return;
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  void _toggleAll() {
    if (_importing) return;
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.paths);
      }
    });
  }

  Future<void> _startImport() async {
    if (_importing || _selected.isEmpty) return;
    setState(() => _importing = true);
    try {
      final result = await widget.controller.importScannedPaths(_selected);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      showAppSnackBar(context, '导入失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: AppSettingsSafeArea(
        child: AppSettingsScrollView(
          maxWidth: AppSettingsMetrics.maxContentWidth,
          padding: EdgeInsets.fromLTRB(
            context.appPageGutter,
            AppSettingsMetrics.pageTop(context),
            context.appPageGutter,
            AppSpacing.x6,
          ),
          children: [
            AppSettingsPageHeader(
              title: '选择要导入的文件',
              onBack: _importing
                  ? null
                  : () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: AppSettingsMetrics.headerGap),
            AppSettingsGroup(
              children: [
                for (final path in widget.paths)
                  _LocalImportRow(
                    path: path,
                    selected: _selected.contains(path),
                    onTap: () => _toggle(path),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppSettingsBottomBar(
        maxWidth: AppSettingsMetrics.maxContentWidth,
        child: Row(
          children: [
            TextButton(
              onPressed: _importing ? null : _toggleAll,
              child: Text(_allSelected ? '取消全选' : '全选'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _importing || _selected.isEmpty ? null : _startImport,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(KaijuanIcons.download),
              label: Text(_importing ? '导入中' : '开始导入（${_selected.length}）'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalImportRow extends StatelessWidget {
  const _LocalImportRow({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(path);
    return Semantics(
      button: true,
      selected: selected,
      label: '${selected ? '取消选择' : '选择'} $fileName',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: Center(
                  child: Icon(
                    selected
                        ? KaijuanIcons.checkboxChecked
                        : KaijuanIcons.checkbox,
                    size: 20,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : context.settingsMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: context.appDivider),
                  borderRadius: BorderRadius.circular(AppRadii.menu),
                ),
                child: const SizedBox(
                  width: 44,
                  height: 52,
                  child: Icon(KaijuanIcons.document, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: context.appListTitleSize),
                    ),
                    const SizedBox(height: 3),
                    Tooltip(
                      message: path,
                      child: Text(
                        p.dirname(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.settingsSecondary,
                          fontSize: context.appBodySecondarySize,
                        ),
                      ),
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

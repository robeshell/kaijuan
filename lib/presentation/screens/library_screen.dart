import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../brand/brand_config.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/import/import_models.dart';
import '../../library/import/wifi_transfer_service.dart';
import '../../library/remote/remote_models.dart';
import '../../library/remote/remote_source_controller.dart';
import '../../library/persistence/app_database.dart';
import '../controllers/library_controller.dart';
import '../navigation/open_reading_item.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/collection_cover.dart';
import '../widgets/cover_card_ink.dart';
import '../widgets/selection_action_sheet.dart';
import '../widgets/wifi_transfer_sheet.dart';
import 'collections_screen.dart';
import 'lists_screen.dart';
import 'local_import_review_screen.dart';
import 'remote_source_screen.dart';

enum _LibraryLayout { grid, list }

enum _LibraryMoreAction { toggleLayout, sort, lists, collections }

enum _LibraryFilterAction {
  all,
  kind,
  author,
  collections,
  series,
  starred,
  read,
}

enum _LibraryImportAction { autoScan, localFile, cloud, wifi, onlineLibrary }

class _ImportMenuOption {
  const _ImportMenuOption({
    required this.action,
    required this.icon,
    required this.label,
    this.enabled = false,
  });

  final _LibraryImportAction action;
  final IconData icon;
  final String label;
  final bool enabled;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.brand,
    required this.controller,
    this.wifiTransferService,
    required this.remoteSourceController,
    this.readingPreferences,
    this.bookReadingPreferences,
  });

  final BrandConfig brand;
  final LibraryController controller;
  final WifiTransferService? wifiTransferService;
  final RemoteSourceController remoteSourceController;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final AnimationController _importMenuController;
  String _query = '';
  _LibraryLayout _layout = _LibraryLayout.grid;
  bool _selecting = false;
  final Set<String> _selected = {};

  static const _importMenuOptions = <_ImportMenuOption>[
    _ImportMenuOption(
      action: _LibraryImportAction.localFile,
      icon: KaijuanIcons.documentAdd,
      label: '本地文件',
      enabled: true,
    ),
    _ImportMenuOption(
      action: _LibraryImportAction.autoScan,
      icon: KaijuanIcons.scan,
      label: '自动扫描',
      enabled: true,
    ),
    _ImportMenuOption(
      action: _LibraryImportAction.cloud,
      icon: KaijuanIcons.cloud,
      label: '云端存储',
      enabled: true,
    ),
    _ImportMenuOption(
      action: _LibraryImportAction.wifi,
      icon: KaijuanIcons.wifi,
      label: 'WiFi 传书',
      enabled: true,
    ),
    _ImportMenuOption(
      action: _LibraryImportAction.onlineLibrary,
      icon: KaijuanIcons.globe,
      label: '在线书库',
      enabled: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _importMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor system reduce-motion: skip staged import-menu timing.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _importMenuController.duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 420);
    _importMenuController.reverseDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);
  }

  @override
  void dispose() {
    _importMenuController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _enterSelecting([String? firstId]) {
    setState(() {
      _selecting = true;
      _selected.clear();
      if (firstId != null) _selected.add(firstId);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<LibraryEntry> visible) {
    setState(() {
      _selected
        ..clear()
        ..addAll(visible.map((e) => e.item.id));
    });
  }

  Future<void> _import() async {
    final result = await widget.controller.pickAndImport();
    if (!mounted || result == null) return;
    await _showImportSummary(result);
  }

  Future<void> _scanDirectory() async {
    if (!mounted) return;
    final progress = showAppProgressSnackBar(context, '扫描中');
    final stopwatch = Stopwatch()..start();
    ImportDiscoveryResult discovery;
    try {
      // Give the status chip a frame to paint before a fast empty-directory
      // scan completes and replaces it with the result message.
      await WidgetsBinding.instance.endOfFrame;
      discovery = await widget.controller.discoverDefaultImport();
    } catch (_) {
      discovery = const ImportDiscoveryResult();
    } finally {
      const minimumVisible = Duration(milliseconds: 240);
      final remaining = minimumVisible - stopwatch.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      progress.close();
    }
    if (!mounted) return;
    var paths = discovery.paths;
    if (discovery.needsDownloadsAuthorization) {
      final useFilePicker = Platform.isAndroid || Platform.isIOS;
      final authorize = await showAppConfirmDialog(
        context,
        title: '访问下载目录',
        message: useFilePicker
            ? '系统不允许应用直接扫描公共下载目录，请在接下来的系统窗口中选择要导入的书籍。'
            : '系统不允许应用直接读取公共下载目录，请在接下来的系统窗口中选择“下载”文件夹。',
        cancelLabel: '暂不',
        confirmLabel: useFilePicker ? '选择文件' : '选择目录',
      );
      if (authorize == true && mounted) {
        final grantedPaths = useFilePicker
            ? await widget.controller.pickFilesForReview()
            : await widget.controller.pickDirectoryForReview(
                initialDirectory: discovery.downloadsPath,
              );
        if (grantedPaths != null && grantedPaths.isNotEmpty) {
          paths = {...paths, ...grantedPaths}.toList()..sort();
        }
      }
    }
    if (!mounted) return;
    if (paths.isEmpty) {
      await _showScanSummary(const ImportResult());
      return;
    }
    final result = await LocalImportReviewScreen.open(
      context,
      paths: paths,
      controller: widget.controller,
    );
    if (!mounted || result == null) return;
    await _showImportSummary(result);
  }

  Future<void> _openWifiTransfer() async {
    final service = widget.wifiTransferService;
    if (service == null) return;
    try {
      await service.start();
    } catch (error) {
      if (mounted) showAppSnackBar(context, 'WiFi 传书启动失败：$error');
      return;
    }
    if (!mounted) {
      await service.stop();
      return;
    }
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (_) => WifiTransferSheet(service: service),
      );
    } finally {
      await service.stop();
    }
  }

  Future<void> _showImportSummary(ImportResult result) async {
    final summary = StringBuffer('已导入 ${result.added} 本');
    if (result.updated > 0) summary.write('，更新 ${result.updated} 本');
    if (result.failures.isNotEmpty) {
      summary.write('，失败 ${result.failures.length} 本');
    }

    if (!result.hasFailures) {
      showAppSnackBar(context, summary.toString());
      return;
    }

    final openDetails = await showAppConfirmDialog(
      context,
      title: '导入结果',
      message: summary.toString(),
      cancelLabel: '关闭',
      confirmLabel: '查看失败详情',
    );
    if (openDetails == true && mounted) {
      await _showFailureDetails(result.failures);
    }
  }

  Future<void> _showScanSummary(ImportResult result) async {
    final total = result.added + result.updated;
    final summary = StringBuffer('扫描完成，$total 本');
    if (result.failures.isNotEmpty) {
      summary.write('，失败 ${result.failures.length} 本');
    }

    if (!result.hasFailures) {
      showAppSnackBar(context, summary.toString());
      return;
    }

    final openDetails = await showAppConfirmDialog(
      context,
      title: '扫描结果',
      message: summary.toString(),
      cancelLabel: '关闭',
      confirmLabel: '查看失败详情',
    );
    if (openDetails == true && mounted) {
      await _showFailureDetails(result.failures);
    }
  }

  Future<void> _showFailureDetails(List<ImportFailure> failures) async {
    await showDialog<void>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        return AppAlertDialog(
          title: '失败 ${failures.length} 本',
          content: SizedBox(
            width: 360,
            height: 220,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: failures.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: ctx.appDivider),
              itemBuilder: (_, i) {
                final f = failures[i];
                final name = f.path.isEmpty ? '（未知）' : f.fileName;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: context.appLabelSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.reason,
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: ctx.appSecondaryText,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            AppDialogAction(
              label: '关闭',
              primary: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }

  void _openItem(ReadingItem item) {
    openReadingItem(
      context,
      database: widget.controller.database,
      item: item,
      comicReadingPreferences: widget.readingPreferences,
      bookReadingPreferences: widget.bookReadingPreferences,
    );
  }

  void _onItemTap(LibraryEntry entry) {
    if (_selecting) {
      _toggleSelected(entry.item.id);
      return;
    }
    _openItem(entry.item);
  }

  void _onItemLongPress(LibraryEntry entry) {
    if (_selecting) {
      _toggleSelected(entry.item.id);
      return;
    }
    _enterSelecting(entry.item.id);
  }

  Future<void> _batchDelete() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showAppConfirmDialog(
      context,
      title: '批量删除？',
      message: '将删除已选的 $n 本及其阅读进度。此操作不可撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final count = await widget.controller.deleteItems(_selected);
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已删除 $count 本');
  }

  Future<void> _batchShelf({required bool onShelf}) async {
    if (_selected.isEmpty) return;
    await widget.controller.setOnShelfMany(_selected, onShelf: onShelf);
    if (!mounted) return;
    final n = _selected.length;
    _exitSelecting();
    showAppSnackBar(context, onShelf ? '已加入书架 $n 本' : '已移出书架 $n 本');
  }

  Future<void> _batchAddToList() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final lists = await widget.controller.readingListsSnapshot();
    if (!mounted) return;

    String? listId;
    if (lists.isEmpty) {
      final name = await _promptNamed('新建书单', '书单名称');
      if (name == null || name.isEmpty || !mounted) return;
      listId = await widget.controller.createReadingList(name);
    } else {
      listId = await _pickNamedTarget(
        title: '加入书单',
        entries: [
          for (final s in lists) (s.list.id, s.list.name, '${s.memberCount} 本'),
        ],
        newLabel: '新建书单…',
      );
      if (listId == '__new__') {
        final name = await _promptNamed('新建书单', '书单名称');
        if (name == null || name.isEmpty || !mounted) return;
        listId = await widget.controller.createReadingList(name);
      }
    }
    if (listId == null || !mounted) return;
    await widget.controller.addItemsToList(listId: listId, itemIds: ids);
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已将 ${ids.length} 本加入书单');
  }

  Future<void> _batchAddToCollection() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final cols = await widget.controller.collectionsSnapshot();
    if (!mounted) return;

    String? colId;
    if (cols.isEmpty) {
      final name = await _promptNamed('新建合集', '合集名称');
      if (name == null || name.isEmpty || !mounted) return;
      colId = await widget.controller.createCollection(name);
    } else {
      colId = await _pickNamedTarget(
        title: '加入合集',
        entries: [for (final c in cols) (c.id, c.name, '')],
        newLabel: '新建合集…',
      );
      if (colId == '__new__') {
        final name = await _promptNamed('新建合集', '合集名称');
        if (name == null || name.isEmpty || !mounted) return;
        colId = await widget.controller.createCollection(name);
      }
    }
    if (colId == null || !mounted) return;
    await widget.controller.addItemsToCollection(
      collectionId: colId,
      itemIds: ids,
    );
    if (!mounted) return;
    _exitSelecting();
    showAppSnackBar(context, '已将 ${ids.length} 本加入合集');
  }

  Future<String?> _promptNamed(String title, String hint) {
    return showAppTextPrompt(
      context,
      title: title,
      hint: hint,
      confirmLabel: '创建',
    );
  }

  Future<String?> _pickNamedTarget({
    required String title,
    required List<(String id, String name, String subtitle)> entries,
    required String newLabel,
  }) {
    return showAppChoiceDialog<String>(
      context,
      title: title,
      choices: [
        for (final entry in entries)
          AppDialogChoice(value: entry.$1, label: entry.$2, subtitle: entry.$3),
        AppDialogChoice(
          value: '__new__',
          label: newLabel,
          icon: KaijuanIcons.add,
        ),
      ],
    );
  }

  String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.addedDesc => '最近导入',
    LibrarySort.titleAsc => '标题',
    LibrarySort.lastOpenedDesc => '最近阅读',
  };

  String _readFilterLabel(LibraryReadFilter f) => switch (f) {
    LibraryReadFilter.all => '状态',
    LibraryReadFilter.unread => '未读',
    LibraryReadFilter.reading => '在读',
    LibraryReadFilter.finished => '已读完',
  };

  String _kindFilterLabel(LibraryKindFilter f) => switch (f) {
    LibraryKindFilter.all => '类型',
    LibraryKindFilter.comic => '漫画',
    LibraryKindFilter.book => '图书',
  };

  String _libraryFilterLabel(LibraryController controller) {
    if (!controller.hasActiveFilters) return '全部书籍';
    final active = controller.activeFilterCount;
    if (active > 1) return '已筛选';
    if (controller.kindFilter != LibraryKindFilter.all) {
      return _kindFilterLabel(controller.kindFilter);
    }
    return _readFilterLabel(controller.readFilter);
  }

  List<AppMenuAction<_LibraryFilterAction>> _libraryFilterActions(
    LibraryController controller,
  ) {
    return [
      AppMenuAction(
        value: _LibraryFilterAction.all,
        label: '全部书籍',
        icon: KaijuanIcons.library,
        selected: !controller.hasActiveFilters,
      ),
      AppMenuAction(
        value: _LibraryFilterAction.kind,
        label: '类型',
        icon: KaijuanIcons.category,
        selected: controller.kindFilter != LibraryKindFilter.all,
      ),
      const AppMenuAction(
        value: _LibraryFilterAction.author,
        label: '作者',
        icon: KaijuanIcons.bookOpen,
        enabled: false,
        subtitle: '即将支持',
      ),
      const AppMenuAction(
        value: _LibraryFilterAction.collections,
        label: '合集',
        icon: KaijuanIcons.collections,
        enabled: false,
        subtitle: '即将支持',
      ),
      const AppMenuAction(
        value: _LibraryFilterAction.series,
        label: '丛书系列',
        icon: KaijuanIcons.playlists,
        enabled: false,
        subtitle: '即将支持',
      ),
      const AppMenuAction(
        value: _LibraryFilterAction.starred,
        label: '星标',
        icon: KaijuanIcons.bookmark,
        enabled: false,
        subtitle: '即将支持',
      ),
      AppMenuAction(
        value: _LibraryFilterAction.read,
        label: '阅读进度',
        icon: KaijuanIcons.bookOpen,
        selected: controller.readFilter != LibraryReadFilter.all,
      ),
    ];
  }

  Future<void> _handleLibraryFilterAction(
    LibraryController controller,
    _LibraryFilterAction action,
  ) async {
    if (!mounted) return;

    switch (action) {
      case _LibraryFilterAction.all:
        controller.clearFilters();
      case _LibraryFilterAction.kind:
        await _openKindFilterMenu(controller);
      case _LibraryFilterAction.read:
        await _openReadFilterMenu(controller);
      case _LibraryFilterAction.author ||
          _LibraryFilterAction.collections ||
          _LibraryFilterAction.series ||
          _LibraryFilterAction.starred:
        break;
    }
  }

  Future<void> _openKindFilterMenu(LibraryController controller) async {
    final selected = await showAppMenu<LibraryKindFilter>(
      context,
      title: '类型',
      actions: [
        for (final value in LibraryKindFilter.values)
          AppMenuAction(
            value: value,
            label: _kindFilterLabel(value),
            icon: KaijuanIcons.category,
            selected: controller.kindFilter == value,
          ),
      ],
    );
    if (selected != null) controller.setKindFilter(selected);
  }

  Future<void> _openReadFilterMenu(LibraryController controller) async {
    final selected = await showAppMenu<LibraryReadFilter>(
      context,
      title: '阅读进度',
      actions: [
        for (final value in LibraryReadFilter.values)
          AppMenuAction(
            value: value,
            label: _readFilterLabel(value),
            icon: KaijuanIcons.bookOpen,
            selected: controller.readFilter == value,
          ),
      ],
    );
    if (selected != null) controller.setReadFilter(selected);
  }

  Future<void> _openSortMenu(LibraryController controller) async {
    final selected = await showAppMenu<LibrarySort>(
      context,
      title: '排序方式',
      actions: [
        for (final value in LibrarySort.values)
          AppMenuAction(
            value: value,
            label: _sortLabel(value),
            icon: KaijuanIcons.sort,
            selected: controller.sort == value,
          ),
      ],
    );
    if (selected != null) controller.setSort(selected);
  }

  void _toggleImportMenu({required bool importing}) {
    if (importing) return;
    if (_importMenuController.value > 0) {
      unawaited(_importMenuController.reverse());
    } else {
      unawaited(_importMenuController.forward());
    }
  }

  Future<void> _closeImportMenu() async {
    if (_importMenuController.value == 0) return;
    await _importMenuController.reverse();
  }

  Future<void> _handleImportAction(_ImportMenuOption option) async {
    if (!option.enabled) return;
    await _closeImportMenu();
    if (!mounted) return;
    switch (option.action) {
      case _LibraryImportAction.localFile:
        await _import();
      case _LibraryImportAction.autoScan:
        await _scanDirectory();
      case _LibraryImportAction.cloud:
        await RemoteSourceManagementScreen.open(
          context,
          type: RemoteSourceType.webDav,
          remote: widget.remoteSourceController,
          libraryController: widget.controller,
        );
      case _LibraryImportAction.onlineLibrary:
        await RemoteSourceManagementScreen.open(
          context,
          type: RemoteSourceType.opds,
          remote: widget.remoteSourceController,
          libraryController: widget.controller,
        );
      case _LibraryImportAction.wifi:
        await _openWifiTransfer();
    }
  }

  Widget _buildImportMenu({
    required double fabBottom,
    required double fabRight,
    required bool wide,
  }) {
    final fabSize = wide ? 56.0 : 40.0;
    final menuWidth = wide ? 176.0 : 160.0;
    const itemHeight = 46.0;
    const itemGap = 6.0;
    final accent = Theme.of(context).colorScheme.primary;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _importMenuController,
        builder: (context, _) {
          final progress = _importMenuController.value;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: progress == 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_closeImportMenu()),
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: progress * (wide ? 0.025 : 0.04),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              for (var index = 0; index < _importMenuOptions.length; index++)
                Builder(
                  builder: (context) {
                    final option = _importMenuOptions[index];
                    final reduceMotion =
                        MediaQuery.disableAnimationsOf(context);
                    final start = index * 0.1;
                    final end = 0.62 + index * 0.075;
                    final itemProgress = reduceMotion
                        ? (progress > 0 ? 1.0 : 0.0)
                        : Interval(
                            start,
                            end,
                            curve: Curves.easeOutCubic,
                          ).transform(progress).clamp(0.0, 1.0).toDouble();
                    final foreground = option.enabled
                        ? context.appPrimaryText
                        : context.appMutedText;

                    return Positioned(
                      right: fabRight + fabSize + 12,
                      bottom:
                          fabBottom +
                          fabSize +
                          12 +
                          index * (itemHeight + itemGap),
                      child: IgnorePointer(
                        ignoring: !option.enabled || itemProgress < 0.5,
                        child: Opacity(
                          opacity: itemProgress,
                          child: Transform.translate(
                            offset: Offset(
                              24 * (1 - itemProgress),
                              10 * (1 - itemProgress),
                            ),
                            child: Transform.scale(
                              scale: 0.84 + itemProgress * 0.16,
                              alignment: Alignment.bottomRight,
                              child: Semantics(
                                button: true,
                                enabled: option.enabled,
                                label: option.label,
                                child: SizedBox(
                                  width: menuWidth,
                                  height: itemHeight,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => unawaited(
                                        _handleImportAction(option),
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      splashColor: Colors.transparent,
                                      child: AppGlassSurface(
                                        strong: true,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        shadowOffset: const Offset(0, 2),
                                        shadowBlur: 8,
                                        child: Row(
                                          children: [
                                            Icon(
                                              option.icon,
                                              size: 20,
                                              color: option.enabled
                                                  ? accent
                                                  : context.appMutedText,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                option.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: foreground,
                                                  fontSize:
                                                      context.appLabelSize,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            if (option.enabled)
                                              Icon(
                                                KaijuanIcons.chevronRight,
                                                size: 16,
                                                color: context.appSecondaryText,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  void _toggleLayout() {
    setState(() {
      _layout = _layout == _LibraryLayout.grid
          ? _LibraryLayout.list
          : _LibraryLayout.grid;
    });
  }

  Widget _searchField({required Color accent}) {
    return SizedBox(
      height: 40,
      child: AppTextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索标题…',
          hintStyle: TextStyle(color: context.appSecondaryText),
          prefixIcon: Icon(
            KaijuanIcons.search,
            size: 18,
            color: context.appSecondaryText,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除',
                  icon: const Icon(KaijuanIcons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          // Follow theme input fill (elevated light / subtle dark), not a
          // hard-coded light wash that breaks dark skins.
          fillColor:
              Theme.of(context).inputDecorationTheme.fillColor ??
              context.appColors.surfaceContainer,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.menu),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.menu),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.menu),
            borderSide: BorderSide(color: accent, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryHeader(
    BuildContext context,
    LibraryController controller, {
    required bool contentWide,
    required bool showBrowseTools,
    required Color accent,
  }) {
    final hPad = context.appPageGutter;
    final muted = context.appSecondaryText;
    // Anchored menus only when side-rail/desktop chrome; bottom-bar shells keep
    // sheet menus for touch.
    final anchoredMenus = !context.appUsesMobileShell;

    void openLists() {
      ListsScreen.open(
        context,
        brand: widget.brand,
        controller: controller,
        readingPreferences: widget.readingPreferences,
        bookReadingPreferences: widget.bookReadingPreferences,
      );
    }

    void openCollections() {
      CollectionsScreen.open(
        context,
        brand: widget.brand,
        controller: controller,
        readingPreferences: widget.readingPreferences,
        bookReadingPreferences: widget.bookReadingPreferences,
      );
    }

    Widget moreButton() {
      return AppMenuButton<_LibraryMoreAction>(
        tooltip: '更多',
        actions: [
          AppMenuAction(
            value: _LibraryMoreAction.toggleLayout,
            label: _layout == _LibraryLayout.grid ? '列表视图' : '网格视图',
            icon: _layout == _LibraryLayout.grid
                ? KaijuanIcons.list
                : KaijuanIcons.grid,
          ),
          AppMenuAction(
            value: _LibraryMoreAction.sort,
            label: '排序方式',
            subtitle: _sortLabel(controller.sort),
            icon: KaijuanIcons.sort,
          ),
          AppMenuAction(
            value: _LibraryMoreAction.lists,
            label: '书单',
            icon: KaijuanIcons.playlists,
            dividerBefore: true,
          ),
          const AppMenuAction(
            value: _LibraryMoreAction.collections,
            label: '合集',
            icon: KaijuanIcons.collections,
          ),
        ],
        onSelected: (action) {
          switch (action) {
            case _LibraryMoreAction.toggleLayout:
              _toggleLayout();
            case _LibraryMoreAction.sort:
              unawaited(_openSortMenu(controller));
            case _LibraryMoreAction.lists:
              openLists();
            case _LibraryMoreAction.collections:
              openCollections();
          }
        },
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Icon(KaijuanIcons.more, size: 25, weight: 300, color: muted),
          ),
        ),
      );
    }

    Widget filterTitle() {
      return AppMenuButton<_LibraryFilterAction>(
        tooltip: '筛选书籍',
        forceAnchored: anchoredMenus,
        actions: _libraryFilterActions(controller),
        onSelected: (action) =>
            unawaited(_handleLibraryFilterAction(controller, action)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _libraryFilterLabel(controller),
                style: TextStyle(
                  fontSize: context.appSectionTitleSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: context.appPrimaryText,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                KaijuanIcons.caretDown,
                size: 18,
                color: context.appSecondaryText,
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(hPad, contentWide ? 20 : 12, hPad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_selecting) ...[
                  IconButton(
                    tooltip: '取消选择',
                    onPressed: _exitSelecting,
                    icon: const Icon(KaijuanIcons.close),
                  ),
                  Text(
                    '已选 ${_selected.length}',
                    style: TextStyle(
                      fontSize: context.appPageTitleSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: context.appPrimaryText,
                    ),
                  ),
                ] else ...[
                  if (showBrowseTools)
                    filterTitle()
                  else
                    Text(
                      '书库',
                      style: TextStyle(
                        fontSize: context.appSectionTitleSize,
                        fontWeight: FontWeight.w600,
                        color: context.appPrimaryText,
                      ),
                    ),
                  const Spacer(),
                  if (showBrowseTools) moreButton(),
                ],
              ],
            ),
            if (showBrowseTools && !_selecting) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: contentWide ? 420 : double.infinity,
                  ),
                  child: _searchField(accent: accent),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    // Scaffold (not ColoredBox): ListTile ink needs a Material ancestor.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final importing = c.isImporting;
          // Content density (gutters/search) ≠ nav chrome (bottom bar vs rail).
          final contentWide = context.appContentWide;
          return StreamBuilder<List<CollectionSummary>>(
            stream: c.watchCollections(),
            builder: (context, colSnap) {
              return StreamBuilder<List<LibraryEntry>>(
                stream: c.watchLibraryEntries(),
                builder: (context, snapshot) {
                  // Honest loading: don't flash the empty state before first emit.
                  if (!snapshot.hasData || !colSnap.hasData) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLibraryHeader(
                          context,
                          c,
                          contentWide: contentWide,
                          showBrowseTools: false,
                          accent: accent,
                        ),
                        const Expanded(
                          child: AppEmptyState(
                            icon: KaijuanIcons.library,
                            title: '加载中',
                            message: '正在读取书库…',
                            loading: true,
                          ),
                        ),
                      ],
                    );
                  }

                  final entries = snapshot.data!;
                  final allCollections = colSnap.data!;
                  final hasContent =
                      entries.isNotEmpty || allCollections.isNotEmpty;
                  // 已在合集中的单本不在书库主列表重复出现。
                  final inCollectionIds = {
                    for (final s in allCollections) ...s.memberIds,
                  };
                  final singles = [
                    for (final e in entries)
                      if (!inCollectionIds.contains(e.item.id)) e,
                  ];
                  final filtered = c.filterAndSort(singles, query: _query);
                  // 合集在书库最前；搜索匹配合集名或成员标题；多选时不显示合集。
                  final q = _query.trim().toLowerCase();
                  final collections = _selecting
                      ? const <CollectionSummary>[]
                      : allCollections.where((s) {
                          if (q.isEmpty) return true;
                          if (s.collection.name.toLowerCase().contains(q)) {
                            return true;
                          }
                          // 成员标题匹配也露出合集卡（不展开单本）。
                          return entries.any(
                            (e) =>
                                s.memberIds.contains(e.item.id) &&
                                e.item.title.toLowerCase().contains(q),
                          );
                        }).toList();

                  Widget content;
                  if (!hasContent) {
                    content = AppEmptyState(
                      icon: KaijuanIcons.library,
                      title: '书库还是空的',
                      message: '导入图书或漫画文件后会显示在这里。',
                    );
                  } else if (filtered.isEmpty && collections.isEmpty) {
                    content = AppEmptyState(
                      icon: KaijuanIcons.searchEmpty,
                      title: '没有匹配的书',
                      message: '换个关键词，或者清除当前筛选。',
                      actionLabel: '清除筛选',
                      onAction: () {
                        _searchController.clear();
                        c.clearFilters();
                        setState(() => _query = '');
                      },
                    );
                  } else {
                    final body = _layout == _LibraryLayout.grid
                        ? _GridBody(
                            collections: collections,
                            entries: filtered,
                            selecting: _selecting,
                            selected: _selected,
                            brand: widget.brand,
                            controller: c,
                            readingPreferences: widget.readingPreferences,
                            bookReadingPreferences:
                                widget.bookReadingPreferences,
                            onTap: _onItemTap,
                            onLongPress: _onItemLongPress,
                          )
                        : _ListBody(
                            collections: collections,
                            entries: filtered,
                            selecting: _selecting,
                            selected: _selected,
                            brand: widget.brand,
                            controller: c,
                            readingPreferences: widget.readingPreferences,
                            bookReadingPreferences:
                                widget.bookReadingPreferences,
                            onTap: _onItemTap,
                            onLongPress: _onItemLongPress,
                          );
                    content = Column(
                      children: [
                        Expanded(child: body),
                        if (_selecting)
                          SelectionActionSheet(
                            selectedCount: _selected.length,
                            totalVisible: filtered.length,
                            onSelectAll: () => _selectAll(filtered),
                            onDone: _exitSelecting,
                            actions: [
                              SelectionActionItem(
                                icon: KaijuanIcons.bookmarkAdd,
                                label: '加入书架',
                                onTap: _selected.isEmpty
                                    ? null
                                    : () => _batchShelf(onShelf: true),
                              ),
                              SelectionActionItem(
                                icon: KaijuanIcons.bookmarkRemove,
                                label: '移出书架',
                                destructive: true,
                                onTap: _selected.isEmpty
                                    ? null
                                    : () => _batchShelf(onShelf: false),
                              ),
                              SelectionActionItem(
                                icon: KaijuanIcons.playlistAdd,
                                label: '加入书单',
                                onTap: _selected.isEmpty
                                    ? null
                                    : _batchAddToList,
                              ),
                              SelectionActionItem(
                                icon: KaijuanIcons.collections,
                                label: '加入合集',
                                onTap: _selected.isEmpty
                                    ? null
                                    : _batchAddToCollection,
                              ),
                              SelectionActionItem(
                                icon: KaijuanIcons.delete,
                                label: '删除',
                                destructive: true,
                                onTap: _selected.isEmpty ? null : _batchDelete,
                              ),
                            ],
                          ),
                      ],
                    );
                  }

                  final fabCompact =
                      context.appIsCompact || context.appIsShortViewport;
                  final fabBottom = context.appFabBottomInset;
                  final fabEnd = context.appFabTrailingInset;
                  return Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLibraryHeader(
                            context,
                            c,
                            contentWide: contentWide,
                            showBrowseTools: hasContent,
                            accent: accent,
                          ),
                          Expanded(child: content),
                        ],
                      ),
                      if (!_selecting) ...[
                        _buildImportMenu(
                          fabBottom: fabBottom,
                          fabRight: fabEnd,
                          wide: !fabCompact,
                        ),
                        Positioned.directional(
                          textDirection: Directionality.of(context),
                          end: fabEnd,
                          bottom: fabBottom,
                          child: Semantics(
                            button: true,
                            label: '导入',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: context.appGlass.shadow,
                                    blurRadius:
                                        14 *
                                        context.appSkinEffects.shadowScale,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: FloatingActionButton(
                                heroTag: 'library-import',
                                tooltip: '导入',
                                mini: fabCompact,
                                onPressed: importing
                                    ? null
                                    : () => _toggleImportMenu(
                                        importing: importing,
                                      ),
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                // Theme keeps Material elevation at 0; depth
                                // comes from the glass shadow above.
                                elevation: 0,
                                focusElevation: 0,
                                hoverElevation: 0,
                                highlightElevation: 0,
                                child: importing
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : RotationTransition(
                                        turns: Tween<double>(
                                          begin: 0,
                                          end: 0.125,
                                        ).animate(_importMenuController),
                                        child: Icon(
                                          KaijuanIcons.add,
                                          size: fabCompact ? 22 : 25,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.collections,
    required this.entries,
    required this.selecting,
    required this.selected,
    required this.brand,
    required this.controller,
    required this.readingPreferences,
    required this.bookReadingPreferences,
    required this.onTap,
    required this.onLongPress,
  });

  final List<CollectionSummary> collections;
  final List<LibraryEntry> entries;
  final bool selecting;
  final Set<String> selected;
  final BrandConfig brand;
  final LibraryController controller;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;
  final ValueChanged<LibraryEntry> onTap;
  final ValueChanged<LibraryEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final total = collections.length + entries.length;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        context.appPageGutter,
        8,
        context.appPageGutter,
        context.appContentBottomPadding,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        // Fold-open / tablet: slightly larger tiles so covers don't stampede.
        maxCrossAxisExtent: context.appCoverGridMaxExtent,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        // Whole cell (cover + 8 + 20 title). ~0.65 keeps cover near 3:4
        // like shelf cards; 0.58 made books read overly tall.
        childAspectRatio: 0.65,
      ),
      itemCount: total,
      itemBuilder: (context, i) {
        if (i < collections.length) {
          final s = collections[i];
          return _LibraryCollectionCard(
            summary: s,
            onTap: () => CollectionDetailScreen.open(
              context,
              brand: brand,
              controller: controller,
              collection: s.collection,
              readingPreferences: readingPreferences,
              bookReadingPreferences: bookReadingPreferences,
            ),
          );
        }
        final entry = entries[i - collections.length];
        return _GridCard(
          entry: entry,
          selecting: selecting,
          isSelected: selected.contains(entry.item.id),
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
        );
      },
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({
    required this.collections,
    required this.entries,
    required this.selecting,
    required this.selected,
    required this.brand,
    required this.controller,
    required this.readingPreferences,
    required this.bookReadingPreferences,
    required this.onTap,
    required this.onLongPress,
  });

  final List<CollectionSummary> collections;
  final List<LibraryEntry> entries;
  final bool selecting;
  final Set<String> selected;
  final BrandConfig brand;
  final LibraryController controller;
  final ComicReadingPreferences? readingPreferences;
  final BookReadingPreferences? bookReadingPreferences;
  final ValueChanged<LibraryEntry> onTap;
  final ValueChanged<LibraryEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final total = collections.length + entries.length;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        context.appPageGutter,
        8,
        context.appPageGutter,
        context.appContentBottomPadding,
      ),
      itemCount: total,
      separatorBuilder: (_, _) => Divider(height: 1, color: context.appDivider),
      itemBuilder: (context, i) {
        if (i < collections.length) {
          final s = collections[i];
          return AppListRow(
            minHeight: 76,
            leadingWidth: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            leading: SizedBox(
              width: 48,
              height: 64,
              child: CollectionCover(coverPaths: s.coverPaths, borderRadius: 6),
            ),
            title: Text(s.collection.name),
            subtitle: Text('合集 · ${s.memberCount} 本'),
            onTap: () => CollectionDetailScreen.open(
              context,
              brand: brand,
              controller: controller,
              collection: s.collection,
              readingPreferences: readingPreferences,
              bookReadingPreferences: bookReadingPreferences,
            ),
          );
        }
        final entry = entries[i - collections.length];
        final item = entry.item;
        final isSelected = selected.contains(item.id);
        return AppListRow(
          minHeight: 76,
          leadingWidth: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          selected: selecting && isSelected,
          leading: SizedBox(
            width: 48,
            height: 64,
            child: SoftCoverFrame(
              radius: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.coverPath != null
                      ? Image.file(
                          File(item.coverPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
                        )
                      : ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                        ),
                  if (selecting)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: CoverSelectBadge(selected: isSelected, size: 18),
                    ),
                ],
              ),
            ),
          ),
          title: Text(item.title),
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
        );
      },
    );
  }
}

class _LibraryCollectionCard extends StatelessWidget {
  const _LibraryCollectionCard({required this.summary, required this.onTap});

  final CollectionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CoverCardInk(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppProductRadii.cover),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: CollectionCover(coverPaths: summary.coverPaths)),
          const SizedBox(height: 8),
          SizedBox(
            // 20px title + 2px gap + 14.4px metadata line.
            height: 38,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.appGridTitleStyle.copyWith(
                    color: context.appPrimaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '合集 · ${summary.memberCount} 本',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.appCaptionSmallSize,
                    height: 1.2,
                    color: context.appSecondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.entry,
    required this.selecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryEntry entry;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    return Semantics(
      button: true,
      selected: selecting && isSelected,
      label: item.title,
      child: CoverCardInk(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppProductRadii.cover),
        // Multi-select is high-frequency; keep scale for open taps only.
        enablePressScale: !selecting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SoftCoverFrame(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.coverPath != null
                        ? Image.file(
                            File(item.coverPath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                          )
                        : ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
                    if (item.onShelf && !selecting)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              KaijuanIcons.bookmarkFilled,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (selecting)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: CoverSelectBadge(selected: isSelected),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Keep the title band fixed so grid cells stay aligned.
            SizedBox(
              height: 20,
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appGridTitleStyle.copyWith(
                  color: context.appPrimaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

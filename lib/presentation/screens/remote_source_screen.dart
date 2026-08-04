import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/remote/remote_import_queue.dart';
import '../../library/remote/remote_models.dart';
import '../../library/remote/remote_source_controller.dart';
import '../../library/remote/webdav_client.dart';
import '../controllers/library_controller.dart';
import '../navigation/app_page_route.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';

class RemoteSourceManagementScreen extends StatefulWidget {
  const RemoteSourceManagementScreen({
    super.key,
    required this.type,
    required this.remote,
    required this.libraryController,
  });

  final RemoteSourceType type;
  final RemoteSourceController remote;
  final LibraryController libraryController;

  static Future<void> open(
    BuildContext context, {
    required RemoteSourceType type,
    required RemoteSourceController remote,
    required LibraryController libraryController,
  }) {
    return Navigator.of(context).push<void>(
      appPageRoute<void>(
        (_) => RemoteSourceManagementScreen(
          type: type,
          remote: remote,
          libraryController: libraryController,
        ),
      ),
    );
  }

  @override
  State<RemoteSourceManagementScreen> createState() =>
      _RemoteSourceManagementScreenState();
}

class _RemoteSourceManagementScreenState
    extends State<RemoteSourceManagementScreen> {
  List<RemoteConnection> get _connections =>
      widget.remote.connectionsFor(widget.type);

  Future<void> _add() async {
    await Navigator.of(context).push<void>(
      appPageRoute<void>(
        (_) => RemoteConnectionFormScreen(
          type: widget.type,
          remote: widget.remote,
        ),
      ),
    );
  }

  Future<void> _edit(RemoteConnection connection) async {
    await Navigator.of(context).push<void>(
      appPageRoute<void>(
        (_) => RemoteConnectionFormScreen(
          type: widget.type,
          remote: widget.remote,
          existing: connection,
        ),
      ),
    );
  }

  Future<void> _test(RemoteConnection connection) async {
    final result = await widget.remote.testConnection(connection);
    if (!mounted) return;
    showAppSnackBar(
      context,
      result.isSuccess ? '连接正常' : (result.error ?? '连接失败'),
    );
  }

  Future<void> _more(RemoteConnection connection) async {
    final action = await showAppChoiceDialog<_ConnectionAction>(
      context,
      title: connection.displayName,
      choices: const [
        AppDialogChoice(value: _ConnectionAction.open, label: '打开'),
        AppDialogChoice(value: _ConnectionAction.test, label: '测试连接'),
        AppDialogChoice(value: _ConnectionAction.edit, label: '编辑'),
        AppDialogChoice(value: _ConnectionAction.remove, label: '删除'),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ConnectionAction.open:
        await _open(connection);
      case _ConnectionAction.test:
        await _test(connection);
      case _ConnectionAction.edit:
        await _edit(connection);
      case _ConnectionAction.remove:
        final confirmed = await showAppConfirmDialog(
          context,
          title: '删除连接？',
          message: '只会删除开卷保存的连接和凭据，不会删除远程文件。',
          confirmLabel: '删除',
          destructive: true,
        );
        if (confirmed == true) {
          await widget.remote.removeConnection(connection.id);
        }
    }
  }

  Future<void> _open(RemoteConnection connection) async {
    await Navigator.of(context).push<void>(
      appPageRoute<void>(
        (_) => RemoteBrowserScreen(
          connection: connection,
          remote: widget.remote,
          libraryController: widget.libraryController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;
    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: AppSettingsSafeArea(
        bottom: true,
        child: ListenableBuilder(
          listenable: widget.remote,
          builder: (context, _) {
            final connections = _connections;
            return AppSettingsScrollView(
              maxWidth: AppSettingsMetrics.maxContentWidth,
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSettingsMetrics.pageTop(context),
                hPad,
                AppSpacing.x6,
              ),
              children: [
                AppSettingsPageHeader(
                  title: widget.type.managementTitle,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: 28),
                _RemoteSourceSectionHeader(
                  title: widget.type == RemoteSourceType.webDav
                      ? 'WebDAV 网盘'
                      : '自定义 OPDS 目录',
                  description: widget.type == RemoteSourceType.webDav
                      ? '连接 NAS 或 WebDAV 服务'
                      : '浏览并下载 OPDS 书目',
                  onAdd: _add,
                ),
                const SizedBox(height: 12),
                if (connections.isEmpty)
                  _RemoteEmptyState(type: widget.type, onAdd: _add)
                else
                  _RemoteSourceCard(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < connections.length;
                          index++
                        ) ...[
                          if (index > 0)
                            Divider(
                              height: 1,
                              indent: 76,
                              color: context.settingsRowDivider,
                            ),
                          _ConnectionRow(
                            connection: connections[index],
                            onTap: () => unawaited(_open(connections[index])),
                            onMore: () => unawaited(_more(connections[index])),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _ConnectionAction { open, test, edit, remove }

class _RemoteEmptyState extends StatelessWidget {
  const _RemoteEmptyState({required this.type, required this.onAdd});

  final RemoteSourceType type;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final label = type == RemoteSourceType.webDav ? 'WebDAV' : 'OPDS';
    return _RemoteSourceCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '还没有$label连接',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.settingsPrimary,
                fontSize: context.appTitleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              type == RemoteSourceType.webDav
                  ? '添加连接，按需导入文件。'
                  : '添加连接，浏览并下载书目。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.settingsSecondary,
                fontSize: context.appBodySecondarySize,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onAdd,
              child: Text('添加$label'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteSourceSectionHeader extends StatelessWidget {
  const _RemoteSourceSectionHeader({
    required this.title,
    required this.description,
    required this.onAdd,
  });

  final String title;
  final String description;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.settingsPrimary,
                  fontSize: context.appTitleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: context.settingsSecondary,
                  fontSize: context.appCaptionSize,
                ),
              ),
            ],
          ),
        ),
        if (context.appIsCompact)
          TextButton(
            onPressed: onAdd,
            child: const Text('添加'),
          )
        else
          OutlinedButton(
            onPressed: onAdd,
            child: const Text('添加连接'),
          ),
      ],
    );
  }
}

class _RemoteSourceCard extends StatelessWidget {
  const _RemoteSourceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.menu);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.settingsGroupSurface,
        borderRadius: radius,
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.connection,
    required this.onTap,
    required this.onMore,
  });

  final RemoteConnection connection;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (connection.status) {
      RemoteConnectionStatus.connected => '已连接，可直接浏览',
      RemoteConnectionStatus.idle => '未连接',
      RemoteConnectionStatus.checking => '连接中',
      RemoteConnectionStatus.authenticationFailed => '认证失败',
      RemoteConnectionStatus.unreachable => '无法连接',
      RemoteConnectionStatus.error => '连接异常',
    };
    final statusColor = switch (connection.status) {
      RemoteConnectionStatus.authenticationFailed ||
      RemoteConnectionStatus.unreachable ||
      RemoteConnectionStatus.error => context.appColors.error,
      RemoteConnectionStatus.checking => context.appColors.primary,
      _ => context.settingsSecondary,
    };
    final checkedLabel = connection.lastCheckedAt == null
        ? '尚未测试'
        : '最近测试 ${_formatConnectionDate(connection.lastCheckedAt!)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.settingsPrimary,
                      fontSize: context.appTitleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Tooltip(
                    message: connection.url,
                    child: Text(
                      connection.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.settingsSecondary,
                        fontSize: context.appBodySecondarySize,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$statusLabel · $checkedLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: context.appBodySecondarySize,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onMore,
              child: Text(
                '更多',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.settingsSecondary,
                ),
              ),
            ),
            Icon(
              KaijuanIcons.chevronRight,
              size: 18,
              color: context.settingsMuted,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatConnectionDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class RemoteConnectionFormScreen extends StatefulWidget {
  const RemoteConnectionFormScreen({
    super.key,
    required this.type,
    required this.remote,
    this.existing,
  });

  final RemoteSourceType type;
  final RemoteSourceController remote;
  final RemoteConnection? existing;

  @override
  State<RemoteConnectionFormScreen> createState() =>
      _RemoteConnectionFormScreenState();
}

class _RemoteConnectionFormScreenState
    extends State<RemoteConnectionFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _allowBadCertificate = false;
  bool _testing = false;
  bool _saving = false;
  bool _tested = false;
  bool _obscurePassword = true;
  String? _testError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.displayName ?? '');
    _url = TextEditingController(text: existing?.url ?? '');
    _username = TextEditingController();
    _password = TextEditingController();
    _allowBadCertificate = existing?.allowBadCertificate ?? false;
    if (existing != null) unawaited(_loadExistingCredentials(existing));
  }

  Future<void> _loadExistingCredentials(RemoteConnection connection) async {
    final credentials = await widget.remote.credentialStore.read(connection.id);
    if (!mounted || credentials == null) return;
    _username.text = credentials.username;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  RemoteCredentials get _credentials => RemoteCredentials(
    username: _username.text.trim(),
    password: _password.text,
  );

  InputDecoration _formDecoration(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _testError = null;
      _tested = false;
    });
    try {
      final result = await widget.remote.probeDraft(
        type: widget.type,
        url: _url.text,
        credentials: _credentials,
        allowBadCertificate: _allowBadCertificate,
      );
      if (!mounted) return;
      setState(() {
        _tested = result.isSuccess;
        _testError = result.error;
      });
      showAppSnackBar(
        context,
        result.isSuccess ? '连接测试成功' : (result.error ?? '连接失败'),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _testError = error.toString());
      showAppSnackBar(context, error.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_tested) {
      showAppSnackBar(context, '请先测试连接');
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await widget.remote.saveConnection(
        existing: widget.existing,
        type: widget.type,
        displayName: _name.text,
        url: _url.text,
        credentials: _credentials,
        allowBadCertificate: _allowBadCertificate,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _tested = false;
          _testError = result.error;
        });
        showAppSnackBar(context, result.error ?? '保存前连接测试失败');
      }
    } catch (error) {
      if (mounted) showAppSnackBar(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;
    final label = widget.type.label;
    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: AppSettingsSafeArea(
        child: AppSettingsScrollView(
          maxWidth: AppSettingsMetrics.formMaxWidth,
          padding: EdgeInsets.fromLTRB(
            hPad,
            AppSettingsMetrics.pageTop(context),
            hPad,
            AppSpacing.x6,
          ),
          children: [
            AppSettingsPageHeader(
              title: widget.existing == null ? '添加$label' : '编辑$label',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 34),
            AppSettingsFormField(
              label: widget.type == RemoteSourceType.webDav
                  ? '服务器地址'
                  : 'OPDS URL',
              child: AppTextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                decoration: _formDecoration('例如：https://example.com/dav'),
                onChanged: (_) => setState(() => _tested = false),
              ),
            ),
            const SizedBox(height: 24),
            AppSettingsFormField(
              label: widget.type == RemoteSourceType.webDav ? '用户名' : '目录名称',
              child: AppTextField(
                controller: widget.type == RemoteSourceType.webDav
                    ? _username
                    : _name,
                textInputAction: TextInputAction.next,
                decoration: _formDecoration(
                  widget.type == RemoteSourceType.webDav
                      ? '请输入用户名'
                      : '例如：我的 OPDS 书库',
                ),
                onChanged: (_) => setState(() => _tested = false),
              ),
            ),
            const SizedBox(height: 24),
            AppSettingsFormField(
              label: widget.type == RemoteSourceType.webDav ? '密码' : '用户名',
              child: AppTextField(
                controller: widget.type == RemoteSourceType.webDav
                    ? _password
                    : _username,
                textInputAction: TextInputAction.next,
                decoration: _formDecoration(
                  widget.type == RemoteSourceType.webDav
                      ? '请输入密码'
                      : '请输入用户名（可选）',
                  suffixIcon: widget.type == RemoteSourceType.webDav
                      ? IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          icon: Icon(
                            _obscurePassword
                                ? KaijuanIcons.visibility
                                : KaijuanIcons.visibilityOff,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        )
                      : null,
                ),
                obscureText: widget.type == RemoteSourceType.webDav
                    ? _obscurePassword
                    : false,
                onChanged: (_) => setState(() => _tested = false),
              ),
            ),
            const SizedBox(height: 24),
            AppSettingsFormField(
              label: widget.type == RemoteSourceType.webDav ? '连接名称' : '密码',
              child: AppTextField(
                controller: widget.type == RemoteSourceType.webDav
                    ? _name
                    : _password,
                textInputAction: TextInputAction.done,
                decoration: _formDecoration(
                  widget.type == RemoteSourceType.webDav
                      ? '例如：坚果云 / 家用 NAS'
                      : '请输入密码（可选）',
                  suffixIcon: widget.type == RemoteSourceType.opds
                      ? IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          icon: Icon(
                            _obscurePassword
                                ? KaijuanIcons.visibility
                                : KaijuanIcons.visibilityOff,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        )
                      : null,
                ),
                obscureText: widget.type == RemoteSourceType.opds
                    ? _obscurePassword
                    : false,
                onChanged: (_) => setState(() => _tested = false),
              ),
            ),
            if (widget.type == RemoteSourceType.webDav) ...[
              const SizedBox(height: 20),
              CheckboxListTile(
                value: _allowBadCertificate,
                onChanged: _testing
                    ? null
                    : (value) => setState(() {
                        _allowBadCertificate = value ?? false;
                        _tested = false;
                      }),
                contentPadding: EdgeInsets.zero,
                title: const Text('允许自签名证书'),
                subtitle: const Text('仅建议用于可信的家庭 NAS 或局域网服务'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            if (_testError case final error?) ...[
              const SizedBox(height: 14),
              Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: context.appBodySecondarySize,
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: AppSettingsBottomBar(
        maxWidth: AppSettingsMetrics.formMaxWidth,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _testing || _saving ? null : _test,
                child: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_testing ? '测试中' : '测试连接'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _saving || _testing || !_tested ? null : _save,
                child: Text(_saving ? '保存中' : '保存连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Remote browsing intent. Backup folder selection must not enter the import
/// queue even though it shares WebDAV authentication and directory loading.
enum RemoteBrowserMode { importFiles, chooseBackupFolder }

class RemoteBrowserScreen extends StatefulWidget {
  const RemoteBrowserScreen({
    super.key,
    required this.connection,
    required this.remote,
    required this.libraryController,
    this.mode = RemoteBrowserMode.importFiles,
  });

  final RemoteConnection connection;
  final RemoteSourceController remote;
  final LibraryController libraryController;
  final RemoteBrowserMode mode;

  @override
  State<RemoteBrowserScreen> createState() => _RemoteBrowserScreenState();
}

class _RemoteBrowserScreenState extends State<RemoteBrowserScreen> {
  final Map<String, RemoteEntry> _selected = {};
  final List<_RemoteNavigationLocation> _navigationHistory = [];
  String? _currentUrl;
  String? _currentTitle;
  String? _nextUrl;
  String? _searchUrl;
  List<RemoteEntry> _entries = const [];
  Object? _error;
  bool _loading = true;
  bool _preparingQueue = false;

  bool get _isFolderPicker =>
      widget.mode == RemoteBrowserMode.chooseBackupFolder;

  @override
  void initState() {
    super.initState();
    _load(widget.connection.url, title: widget.connection.displayName);
  }

  Future<void> _load(String url, {String? title}) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentUrl = url;
      if (title != null) _currentTitle = _decodeRemoteLabel(title);
    });
    try {
      final page = await widget.remote.browsePage(widget.connection, url: url);
      if (!page.isSuccess) {
        throw StateError(page.error ?? '读取远程目录失败');
      }
      if (!mounted) return;
      setState(() {
        _entries = page.entries;
        _nextUrl = page.nextUri;
        _searchUrl = page.searchUri;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final template = _searchUrl;
    if (template == null) return;
    final query = await showAppTextPrompt(
      context,
      title: '搜索书库',
      hint: '输入书名或作者',
    );
    if (query == null || query.trim().isEmpty) return;
    final encoded = Uri.encodeQueryComponent(query.trim());
    final url = template
        .replaceAll('{searchTerms}', encoded)
        .replaceAll('{searchTerms?}', encoded);
    _rememberCurrentLocation();
    await _load(url, title: '搜索结果');
  }

  void _toggle(RemoteEntry entry) {
    setState(() {
      final key = entry.effectiveDownloadUri;
      if (_selected.containsKey(key)) {
        _selected.remove(key);
      } else {
        _selected[key] = entry;
      }
    });
  }

  Future<void> _openDirectory(RemoteEntry entry) async {
    _rememberCurrentLocation();
    await _load(
      entry.effectiveNavigationUri,
      title: _decodeRemoteLabel(entry.displayTitle),
    );
  }

  void _rememberCurrentLocation() {
    final url = _currentUrl;
    if (url == null) return;
    _navigationHistory.add(
      _RemoteNavigationLocation(
        url: url,
        title: _currentTitle ?? widget.connection.displayName,
      ),
    );
  }

  Future<void> _navigateToBreadcrumb(int index) async {
    if (_loading || index < 0 || index >= _navigationHistory.length) {
      return;
    }
    final target = _navigationHistory[index];
    setState(() {
      _navigationHistory.removeRange(index, _navigationHistory.length);
    });
    await _load(target.url, title: target.title);
  }

  List<RemoteEntry> get _selectableEntries => [
    for (final entry in _entries)
      if (entry.isDirectory ||
          entry.isSupportedFile ||
          entry.downloadUri != null)
        entry,
  ];

  List<RemoteEntry> get _folderEntries => [
    for (final entry in _entries)
      if (entry.isDirectory) entry,
  ];

  bool get _allVisibleSelected =>
      _selectableEntries.isNotEmpty &&
      _selectableEntries.every(
        (entry) => _selected.containsKey(entry.effectiveDownloadUri),
      );

  void _toggleAll() {
    final entries = _selectableEntries;
    setState(() {
      if (_allVisibleSelected) {
        for (final entry in entries) {
          _selected.remove(entry.effectiveDownloadUri);
        }
      } else {
        for (final entry in entries) {
          _selected[entry.effectiveDownloadUri] = entry;
        }
      }
    });
  }

  Future<void> _openQueue() async {
    if (_preparingQueue) return;
    setState(() => _preparingQueue = true);
    var opened = false;
    try {
      final entries = <RemoteEntry>[];
      final seen = <String>{};
      for (final selected in _selected.values) {
        final expanded = selected.isDirectory
            ? await widget.remote.collectFilesRecursively(
                widget.connection,
                selected,
              )
            : [selected];
        for (final entry in expanded) {
          if ((entry.isSupportedFile || entry.downloadUri != null) &&
              seen.add(entry.effectiveDownloadUri)) {
            entries.add(entry);
          }
        }
      }
      if (entries.isEmpty) {
        if (mounted) showAppSnackBar(context, '所选文件夹中没有可导入的文件');
        return;
      }
      if (!mounted) return;
      opened = true;
      await Navigator.of(context).push<void>(
        appPageRoute<void>(
          (_) => RemoteImportQueueScreen(
            connection: widget.connection,
            entries: entries,
            remote: widget.remote,
            libraryController: widget.libraryController,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showAppSnackBar(context, '整理所选文件失败：$error');
    } finally {
      if (mounted) setState(() => _preparingQueue = false);
    }
    if (opened && mounted) setState(() => _selected.clear());
  }

  void _selectCurrentFolder() {
    if (_loading || _currentUrl == null) return;
    final relative = WebDavClient.relativePathFromRoot(
      widget.connection.url,
      _currentUrl!,
    );
    if (relative == null) {
      showAppSnackBar(context, '无法确定备份目录');
      return;
    }
    Navigator.of(context).pop(relative);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _isFolderPicker ? _folderEntries : _selectableEntries;
    // A folder picker is an action page, not a page named after whichever
    // remote folder happens to be open. Keep the task visible while the
    // breadcrumb carries the current location.
    final title = _isFolderPicker
        ? '选择备份目录'
        : (_currentTitle ?? widget.connection.displayName);
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
              title: title,
              onBack: () => Navigator.of(context).maybePop(),
              actions: [
                if (widget.connection.type == RemoteSourceType.opds &&
                    _searchUrl != null)
                  AppIconButton(
                    icon: KaijuanIcons.search,
                    tooltip: '搜索',
                    onPressed: _loading ? null : _search,
                  ),
                AppIconButton(
                  icon: KaijuanIcons.refresh,
                  tooltip: '刷新',
                  onPressed: _loading || _currentUrl == null
                      ? null
                      : () => _load(_currentUrl!),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_navigationHistory.isNotEmpty) ...[
              _RemoteBreadcrumb(
                items: [
                  for (
                    var index = 0;
                    index < _navigationHistory.length;
                    index++
                  )
                    _RemoteBreadcrumbItem(
                      label: index == 0
                          ? widget.connection.displayName
                          : _navigationHistory[index].title,
                      onTap: _loading
                          ? null
                          : () => _navigateToBreadcrumb(index),
                    ),
                  _RemoteBreadcrumbItem(
                    label: _currentTitle ?? widget.connection.displayName,
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (_loading)
              const AppEmptyState(
                alignment: Alignment.topCenter,
                padding: EdgeInsets.symmetric(vertical: AppSpacing.x8 * 2),
                icon: KaijuanIcons.folder,
                title: '正在读取目录',
                message: '正在连接远程来源，请稍候。',
                loading: true,
              )
            else if (_error != null)
              AppSettingsGroup(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '读取失败',
                    style: TextStyle(
                      color: context.settingsPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_error',
                    style: TextStyle(color: context.settingsSecondary),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () => _load(_currentUrl!),
                    child: const Text('重试'),
                  ),
                ],
              )
            else if (visible.isEmpty)
              AppSettingsGroup(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    _isFolderPicker ? '没有子文件夹' : '这里还没有可导入的内容',
                    style: TextStyle(
                      color: context.settingsPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isFolderPicker
                        ? '可直接选择当前目录'
                        : widget.connection.type == RemoteSourceType.opds
                        ? '请进入其他分类，或检查 OPDS 目录是否提供下载链接。'
                        : '请进入其他文件夹，或检查远程目录中的文件格式。',
                    style: TextStyle(color: context.settingsSecondary),
                  ),
                ],
              )
            else
              _RemoteEntryList(
                entries: visible,
                selected: _selected,
                connection: widget.connection,
                remote: widget.remote,
                folderPicker: _isFolderPicker,
                onTap: (entry) =>
                    entry.isDirectory ? _openDirectory(entry) : _toggle(entry),
                onToggle: _isFolderPicker ? null : _toggle,
              ),
            if (!_loading && _nextUrl != null) ...[
              const SizedBox(height: 14),
              Center(
                child: OutlinedButton(
                  onPressed: () => _load(_nextUrl!),
                  child: const Text('加载下一页'),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: AppSettingsBottomBar(
        maxWidth: AppSettingsMetrics.maxContentWidth,
        child: _isFolderPicker
            ? SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _selectCurrentFolder,
                  icon: const Icon(KaijuanIcons.folder),
                  label: const Text('选择此目录'),
                ),
              )
            : Row(
                children: [
                  TextButton(
                    onPressed: _preparingQueue || visible.isEmpty
                        ? null
                        : _toggleAll,
                    child: Text(_allVisibleSelected ? '取消全选' : '全选'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _preparingQueue || _selected.isEmpty
                        ? null
                        : _openQueue,
                    icon: Icon(
                      _preparingQueue
                          ? KaijuanIcons.stop
                          : KaijuanIcons.download,
                    ),
                    label: Text(
                      _preparingQueue
                          ? '正在整理'
                          : widget.connection.type == RemoteSourceType.webDav
                          ? '导入'
                          : '下载',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RemoteBreadcrumb extends StatelessWidget {
  const _RemoteBreadcrumb({required this.items});

  final List<_RemoteBreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          KaijuanIcons.navigateUp,
          size: 18,
          color: context.settingsSecondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '/',
                        style: TextStyle(
                          color: context.settingsMuted,
                          fontSize: context.appBodySecondarySize,
                        ),
                      ),
                    ),
                  _RemoteBreadcrumbLabel(item: items[index]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RemoteBreadcrumbItem {
  const _RemoteBreadcrumbItem({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;
}

class _RemoteBreadcrumbLabel extends StatelessWidget {
  const _RemoteBreadcrumbLabel({required this.item});

  final _RemoteBreadcrumbItem item;

  @override
  Widget build(BuildContext context) {
    final isLink = item.onTap != null;
    return Semantics(
      button: isLink,
      label: isLink ? '返回${item.label}' : item.label,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            item.label,
            style: TextStyle(
              color: isLink
                  ? Theme.of(context).colorScheme.primary
                  : context.settingsSecondary,
              fontSize: context.appBodySecondarySize,
              fontWeight: isLink ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteEntryList extends StatelessWidget {
  const _RemoteEntryList({
    required this.entries,
    required this.selected,
    required this.connection,
    required this.remote,
    required this.folderPicker,
    required this.onTap,
    required this.onToggle,
  });

  final List<RemoteEntry> entries;
  final Map<String, RemoteEntry> selected;
  final RemoteConnection connection;
  final RemoteSourceController remote;
  final bool folderPicker;
  final ValueChanged<RemoteEntry> onTap;
  final ValueChanged<RemoteEntry>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          _RemoteEntryRow(
            entry: entries[index],
            selected: selected.containsKey(entries[index].effectiveDownloadUri),
            connection: connection,
            remote: remote,
            folderPicker: folderPicker,
            onTap: () => onTap(entries[index]),
            onToggle: onToggle == null ? null : () => onToggle!(entries[index]),
          ),
          if (index < entries.length - 1)
            Divider(height: 1, indent: 56, color: context.settingsRowDivider),
        ],
      ],
    );
  }
}

class _RemoteEntryRow extends StatelessWidget {
  const _RemoteEntryRow({
    required this.entry,
    required this.selected,
    required this.connection,
    required this.remote,
    required this.folderPicker,
    required this.onTap,
    required this.onToggle,
  });

  final RemoteEntry entry;
  final bool selected;
  final RemoteConnection connection;
  final RemoteSourceController remote;
  final bool folderPicker;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final title = _decodeRemoteLabel(entry.displayTitle);
    final subtitle = entry.isDirectory
        ? ''
        : [
            _remoteFormatLabel(entry.displayName),
            if (entry.size >= 0) _remoteSizeLabel(entry.size),
            if (entry.author case final author? when author.isNotEmpty) author,
          ].where((value) => value.isNotEmpty).join(' | ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (!folderPicker) ...[
              AppIconButton(
                icon: selected
                    ? KaijuanIcons.checkboxChecked
                    : KaijuanIcons.checkbox,
                tooltip: entry.isDirectory
                    ? (selected ? '取消选择文件夹' : '选择整个文件夹')
                    : (selected ? '取消选择' : '选择'),
                onPressed: onToggle,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : context.settingsMuted,
              ),
              const SizedBox(width: 12),
            ],
            if (entry.isDirectory) ...[
              Icon(
                KaijuanIcons.folder,
                color: context.settingsSecondary,
                size: 28,
              ),
              const SizedBox(width: 12),
            ],
            if (!entry.isDirectory) ...[
              _RemoteFilePreview(
                coverUri: entry.coverUri,
                connection: connection,
                remote: remote,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: context.appListTitleSize),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.settingsSecondary,
                        fontSize: context.appCaptionSmallSize,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.isDirectory) ...[const Icon(KaijuanIcons.chevronRight)],
          ],
        ),
      ),
    );
  }
}

class _RemoteFilePreview extends StatefulWidget {
  const _RemoteFilePreview({
    required this.coverUri,
    required this.connection,
    required this.remote,
  });

  final String? coverUri;
  final RemoteConnection connection;
  final RemoteSourceController remote;

  @override
  State<_RemoteFilePreview> createState() => _RemoteFilePreviewState();
}

class _RemoteFilePreviewState extends State<_RemoteFilePreview> {
  Future<Uint8List>? _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = _loadCover();
  }

  @override
  void didUpdateWidget(covariant _RemoteFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUri != widget.coverUri ||
        oldWidget.connection.id != widget.connection.id) {
      _coverFuture = _loadCover();
    }
  }

  Future<Uint8List> _loadCover() {
    final url = widget.coverUri;
    if (url == null || url.isEmpty) {
      return Future<Uint8List>.error(const FormatException('没有封面'));
    }
    return widget.remote.loadCover(widget.connection, url);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.appDivider),
        borderRadius: BorderRadius.circular(AppRadii.menu),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.menu),
        child: SizedBox(
          width: 44,
          height: 52,
          child: FutureBuilder<Uint8List>(
            future: _coverFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const _RemoteDocumentFallback(),
                );
              }
              if (snapshot.hasError) {
                return const _RemoteDocumentFallback();
              }
              return const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RemoteDocumentFallback extends StatelessWidget {
  const _RemoteDocumentFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Icon(KaijuanIcons.document, size: 28));
  }
}

class _RemoteNavigationLocation {
  const _RemoteNavigationLocation({required this.url, required this.title});

  final String url;
  final String title;
}

String _decodeRemoteLabel(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

String _remoteFormatLabel(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '文件';
  return fileName.substring(dot + 1).toUpperCase();
}

String _remoteSizeLabel(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}

class RemoteImportQueueScreen extends StatefulWidget {
  const RemoteImportQueueScreen({
    super.key,
    required this.connection,
    required this.entries,
    required this.remote,
    required this.libraryController,
  });

  final RemoteConnection connection;
  final List<RemoteEntry> entries;
  final RemoteSourceController remote;
  final LibraryController libraryController;

  @override
  State<RemoteImportQueueScreen> createState() =>
      _RemoteImportQueueScreenState();
}

class _RemoteImportQueueScreenState extends State<RemoteImportQueueScreen> {
  late final RemoteImportQueueController _queue;

  @override
  void initState() {
    super.initState();
    _queue = RemoteImportQueueController(
      remote: widget.remote,
      importOne: (candidate) =>
          widget.libraryController.importCandidates([candidate]),
      items: [
        for (final entry in widget.entries)
          RemoteImportQueueItem(connection: widget.connection, entry: entry),
      ],
    )..addListener(_queueChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void dispose() {
    _queue.removeListener(_queueChanged);
    _queue.dispose();
    super.dispose();
  }

  void _queueChanged() => setState(() {});

  Future<void> _start() async {
    await _queue.start();
    if (!mounted) return;
    final completed = _queue.items
        .where((item) => item.status == RemoteQueueStatus.completed)
        .length;
    final failed = _queue.items
        .where((item) => item.status == RemoteQueueStatus.failed)
        .length;
    showAppSnackBar(
      context,
      failed == 0 ? '已完成 $completed 项' : '已完成 $completed 项，失败 $failed 项',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.settingsCanvas,
      body: AppSettingsSafeArea(
        bottom: true,
        child: AppSettingsScrollView(
          maxWidth: AppSettingsMetrics.formMaxWidth,
          padding: EdgeInsets.fromLTRB(
            context.appPageGutter,
            AppSettingsMetrics.pageTop(context),
            context.appPageGutter,
            AppSpacing.x6,
          ),
          children: [
            AppSettingsPageHeader(
              title:
                  '待${widget.connection.type == RemoteSourceType.webDav ? '导入' : '下载'}队列',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: AppSettingsMetrics.headerGap),
            AppSettingsGroup(
              children: [
                for (var index = 0; index < _queue.items.length; index++)
                  _QueueRow(
                    item: _queue.items[index],
                    onRetry: _queue.isRunning
                        ? null
                        : () => _queue.start(onlyIndex: index),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_queue.isRunning)
              Text(
                '正在处理，请保持页面打开…',
                style: TextStyle(color: context.settingsSecondary),
              )
            else if (_queue.allCompleted)
              const Text('全部处理完成，可以返回继续浏览。'),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item, required this.onRetry});

  final RemoteImportQueueItem item;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.status == RemoteQueueStatus.failed
        ? Theme.of(context).colorScheme.error
        : item.status == RemoteQueueStatus.downloading ||
              item.status == RemoteQueueStatus.importing
        ? Theme.of(context).colorScheme.primary
        : context.settingsSecondary;
    final statusIcon = item.status == RemoteQueueStatus.completed
        ? KaijuanIcons.checkCircle
        : item.status == RemoteQueueStatus.failed
        ? KaijuanIcons.error
        : item.status == RemoteQueueStatus.waiting
        ? KaijuanIcons.circle
        : KaijuanIcons.download;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.entry.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: context.appListTitleSize),
                ),
                const SizedBox(height: 3),
                Text(
                  item.error ?? item.status.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: context.appCaptionSmallSize,
                  ),
                ),
              ],
            ),
          ),
          if (item.status == RemoteQueueStatus.failed)
            AppIconButton(
              icon: KaijuanIcons.restore,
              tooltip: '重试',
              onPressed: onRetry,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 5),
                Text(
                  item.status.label,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: context.appBodySecondarySize,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_provider_kind.dart';
import '../../ai/ai_search.dart';
import '../../ai/ai_translation.dart';
import '../../ai/ai_user_error.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../controllers/ai_settings_controller.dart';
import '../navigation/app_page_route.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';
import 'ai_content_rules_screen.dart';

/// Settings subpage: BYOK, provider preset, model, test connection.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.controller});

  final AiSettingsController controller;

  static Future<void> open(
    BuildContext context, {
    required AiSettingsController controller,
  }) {
    return Navigator.of(context).push<void>(
      appPageRoute<void>((_) => AiSettingsScreen(controller: controller)),
    );
  }

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _searchApiKey;
  bool _obscureKey = true;
  bool _obscureSearchKey = true;
  bool _seeded = false;

  AiSettingsController get controller => widget.controller;

  /// Cloud presets listed under the 云端 group; local backends are separate.
  static const _cloudProviderKinds = [
    AiProviderKind.openai,
    AiProviderKind.anthropic,
    AiProviderKind.deepseek,
    AiProviderKind.xai,
    AiProviderKind.custom,
  ];

  @override
  void initState() {
    super.initState();
    _apiKey = TextEditingController();
    _baseUrl = TextEditingController();
    _model = TextEditingController();
    _searchApiKey = TextEditingController();
    // Rebuild only this State when text changes — never push keystrokes into
    // ChangeNotifier (that rebuilds the form mid-paste on macOS).
    _apiKey.addListener(_onDraftChanged);
    _baseUrl.addListener(_onDraftChanged);
    _model.addListener(_onDraftChanged);
    _searchApiKey.addListener(_onDraftChanged);
    unawaited(_ensureLoaded());
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureLoaded() async {
    if (!controller.isLoaded) {
      await controller.load();
    }
    if (!mounted) return;
    _syncFieldsFromController();
  }

  void _syncFieldsFromController() {
    final settings = controller.settings;
    _apiKey.value = TextEditingValue(
      text: controller.apiKey,
      selection: TextSelection.collapsed(offset: controller.apiKey.length),
    );
    final base = settings.baseUrl.isEmpty
        ? settings.providerKind.defaultBaseUrl
        : settings.baseUrl;
    final model = settings.model.isEmpty
        ? settings.providerKind.defaultModel
        : settings.model;
    _baseUrl.value = TextEditingValue(
      text: base,
      selection: TextSelection.collapsed(offset: base.length),
    );
    _model.value = TextEditingValue(
      text: model,
      selection: TextSelection.collapsed(offset: model.length),
    );
    _searchApiKey.value = TextEditingValue(
      text: controller.searchApiKey,
      selection: TextSelection.collapsed(
        offset: controller.searchApiKey.length,
      ),
    );
    _seeded = true;
    setState(() {});
  }

  Future<void> _flushDraft({bool notifyController = true}) async {
    if (notifyController) {
      await controller.applyDraft(
        apiKey: _apiKey.text,
        baseUrl: _baseUrl.text,
        model: _model.text,
      );
      await controller.setSearchApiKey(_searchApiKey.text, notify: true);
    }
  }

  @override
  void dispose() {
    // Connection fields persist best-effort on leave. Advanced AI rules
    // live on their own explicitly-saved route.
    unawaited(
      controller.applyDraft(
        apiKey: _apiKey.text,
        baseUrl: _baseUrl.text,
        model: _model.text,
      ),
    );
    unawaited(controller.setSearchApiKey(_searchApiKey.text, notify: false));
    _apiKey
      ..removeListener(_onDraftChanged)
      ..dispose();
    _baseUrl
      ..removeListener(_onDraftChanged)
      ..dispose();
    _model
      ..removeListener(_onDraftChanged)
      ..dispose();
    _searchApiKey
      ..removeListener(_onDraftChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _onSearchProviderSelected(AiSearchProviderKind kind) async {
    await controller.setSearchApiKey(_searchApiKey.text, notify: false);
    await controller.setSearchProviderKind(kind);
    if (!mounted) return;
    final key = controller.searchApiKey;
    _searchApiKey.value = TextEditingValue(
      text: key,
      selection: TextSelection.collapsed(offset: key.length),
    );
  }

  InputDecoration _decoration(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffixIcon,
    );
  }

  Future<void> _onProviderSelected(AiProviderKind kind) async {
    // Save current provider's key/url/model, then switch; controller loads the
    // destination provider's own key (does not carry the previous one).
    await _flushDraft();
    await controller.setProviderKind(kind);
    if (!mounted) return;
    final settings = controller.settings;
    final key = controller.apiKey;
    final base = settings.baseUrl.isEmpty
        ? kind.defaultBaseUrl
        : settings.baseUrl;
    final model = settings.model.isEmpty ? kind.defaultModel : settings.model;
    _apiKey.value = TextEditingValue(
      text: key,
      selection: TextSelection.collapsed(offset: key.length),
    );
    _baseUrl.value = TextEditingValue(
      text: base,
      selection: TextSelection.collapsed(offset: base.length),
    );
    _model.value = TextEditingValue(
      text: model,
      selection: TextSelection.collapsed(offset: model.length),
    );
  }

  Future<void> _pasteInto(TextEditingController field) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (mounted) showAppSnackBar(context, '剪贴板没有文本');
      return;
    }
    final value = field.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    field.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// Copy the field's full value to the clipboard.
  ///
  /// Unlike [copyFromController] this does not depend on a visible selection,
  /// so it works while the field is obscured (macOS secure input blocks
  /// Cmd+C / the Edit-menu copy path for obscured fields).
  void _copyFrom(TextEditingController field) {
    final text = field.text;
    if (text.isEmpty) {
      if (mounted) showAppSnackBar(context, '没有可复制的内容');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnackBar(context, '已复制到剪贴板');
  }

  Future<void> _test() async {
    final result = await controller.testConnection(
      apiKey: _apiKey.text,
      baseUrl: _baseUrl.text,
      model: _model.text,
    );
    if (!mounted) return;
    showAppSnackBar(context, result.message);
  }

  Future<void> _fetchModels() async {
    try {
      final models = await controller.fetchModels(
        apiKey: _apiKey.text,
        baseUrl: _baseUrl.text,
        model: _model.text,
      );
      if (!mounted) return;
      if (models.isEmpty) {
        showAppSnackBar(context, '未获取到可用模型');
        return;
      }
      final selected = await _pickModel(models);
      if (!mounted || selected == null) return;
      _model.value = TextEditingValue(
        text: selected,
        selection: TextSelection.collapsed(offset: selected.length),
      );
      await controller.setModel(selected);
    } on AiProviderException catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          aiUserErrorMessage(error, operation: AiUserOperation.loadModels),
        );
      }
    } catch (_) {
      if (mounted) showAppSnackBar(context, '获取模型失败');
    }
  }

  Future<String?> _pickModel(List<AiModelInfo> models) async {
    final current = _model.text.trim();
    return showAppMenu<String>(
      context,
      title: '选择模型',
      forceAnchored: appUsesDesktopPlatform,
      actions: [
        for (final model in models)
          AppMenuAction<String>(
            value: model.id,
            label: model.id,
            subtitle:
                model.displayName != null &&
                    model.displayName!.isNotEmpty &&
                    model.displayName != model.id
                ? model.displayName
                : null,
            selected: model.id == current,
          ),
      ],
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
          listenable: controller,
          builder: (context, _) {
            if (!_seeded && controller.isLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_seeded) _syncFieldsFromController();
              });
            }
            final settings = controller.settings;
            final enabled = settings.enabled;
            final fieldsEnabled = enabled && !controller.isBusy;
            final hasKey = _apiKey.text.trim().isNotEmpty;
            final liveStatus = controller.isListingModels
                ? '正在获取模型'
                : controller.isTesting
                ? '正在测试模型连接'
                : controller.isTestingSearch
                ? '正在测试搜索服务'
                : controller.modelsError ??
                      controller.searchTestMessage ??
                      controller.testMessage ??
                      '';

            return AppSettingsScrollView(
              maxWidth: AppSettingsMetrics.formMaxWidth,
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSettingsMetrics.pageTop(context),
                hPad,
                AppSpacing.x6,
              ),
              children: [
                AppSettingsPageHeader(
                  title: 'AI 助手',
                  onBack: () {
                    // Await flush so search/model keys are in memory before
                    // the chat sheet re-checks isSearchReady.
                    unawaited(() async {
                      await _flushDraft();
                      if (context.mounted) {
                        await Navigator.of(context).maybePop();
                      }
                    }());
                  },
                ),
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: liveStatus,
                  child: const SizedBox.shrink(),
                ),
                const SizedBox(height: AppSettingsMetrics.headerGap),
                Text(
                  settings.providerKind.isLocalBackend
                      ? '使用本地 Ollama 服务，无需 API Key，数据不出本机。'
                      : '使用你自己的 API Key。密钥只保存在本机，不会进入 WebDAV 备份。',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    height: 1.45,
                    color: context.settingsSecondary,
                  ),
                ),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                AppSettingsGroup(
                  children: [
                    AppSettingsSwitchRow(
                      title: '启用 AI',
                      subtitle: '关闭后不会发起任何 AI 网络请求',
                      value: enabled,
                      onChanged: controller.isBusy
                          ? null
                          : (value) {
                              unawaited(_flushDraft());
                              unawaited(controller.setEnabled(value));
                            },
                    ),
                  ],
                ),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _SectionLabel('服务商'),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  // Single child so [AppSettingsGroup] does not insert hairline
                  // dividers between the provider strip and protocol row.
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppChoiceStrip<AiProviderKind>(
                          wrap: true,
                          selected: settings.providerKind,
                          onSelected: fieldsEnabled
                              ? (kind) => unawaited(_onProviderSelected(kind))
                              : (_) {},
                          options: [
                            for (final kind in _cloudProviderKinds)
                              AppChoiceOption(
                                value: kind,
                                label: kind.displayName,
                                enabled: fieldsEnabled,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '本地',
                          style: TextStyle(
                            fontSize: context.appCaptionSize,
                            fontWeight: FontWeight.w600,
                            color: context.settingsSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppChoiceStrip<AiProviderKind>(
                          wrap: true,
                          selected: settings.providerKind,
                          onSelected: fieldsEnabled
                              ? (kind) => unawaited(_onProviderSelected(kind))
                              : (_) {},
                          options: [
                            for (final kind in AiProviderKind.values)
                              if (kind.isLocalBackend)
                                AppChoiceOption(
                                  value: kind,
                                  label: kind.displayName,
                                  enabled: fieldsEnabled,
                                ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _SectionLabel('连接'),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                  children: [
                    if (settings.providerKind.isLocalBackend) ...[
                      //
                      AppSettingsFormField(
                        label: '本地模型服务',
                        child: Text(
                          'Ollama 运行在本机，无需 API Key。请确认已安装并启动 '
                          'Ollama（默认端口 11434），然后填写接口地址与模型。',
                          style: TextStyle(
                            fontSize: context.appCaptionSize,
                            height: 1.45,
                            color: context.settingsSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      //
                      AppSettingsFormField(
                        label: 'API Key',
                        child: AppTextField(
                          controller: _apiKey,
                          obscureText: _obscureKey,
                          enabled: fieldsEnabled,
                          enableInteractiveSelection: true,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            '粘贴服务商提供的密钥',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '粘贴',
                                  icon: const Icon(
                                    KaijuanIcons.paste,
                                    size: 18,
                                  ),
                                  onPressed: fieldsEnabled
                                      ? () => unawaited(_pasteInto(_apiKey))
                                      : null,
                                ),
                                IconButton(
                                  tooltip: '复制',
                                  icon: const Icon(KaijuanIcons.copy, size: 18),
                                  onPressed: fieldsEnabled
                                      ? () => _copyFrom(_apiKey)
                                      : null,
                                ),
                                IconButton(
                                  tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                                  icon: Icon(
                                    _obscureKey
                                        ? KaijuanIcons.visibility
                                        : KaijuanIcons.visibilityOff,
                                    size: 20,
                                  ),
                                  onPressed: fieldsEnabled
                                      ? () => setState(
                                          () => _obscureKey = !_obscureKey,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    AppSettingsFormField(
                      label: '接口地址',
                      child: AppTextField(
                        controller: _baseUrl,
                        enabled: fieldsEnabled,
                        enableInteractiveSelection: true,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          settings.providerKind.defaultBaseUrl.isEmpty
                              ? '例如：https://api.example.com/v1'
                              : settings.providerKind.defaultBaseUrl,
                          suffixIcon: IconButton(
                            tooltip: '粘贴',
                            icon: const Icon(KaijuanIcons.paste, size: 18),
                            onPressed: fieldsEnabled
                                ? () => unawaited(_pasteInto(_baseUrl))
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppSettingsFormField(
                      label: '模型',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _model,
                              enabled: fieldsEnabled,
                              enableInteractiveSelection: true,
                              textInputAction: TextInputAction.done,
                              decoration: _decoration(
                                settings.providerKind.isLocalBackend
                                    ? '例如：llama3.2（先「获取模型」）'
                                    : settings.providerKind.defaultModel.isEmpty
                                    ? '例如：gpt-5.4-mini'
                                    : settings.providerKind.defaultModel,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: OutlinedButton(
                              onPressed:
                                  fieldsEnabled &&
                                      (hasKey ||
                                          settings.providerKind.isLocalBackend)
                                  ? () => unawaited(_fetchModels())
                                  : null,
                              child: Text(
                                controller.isListingModels ? '获取中…' : '获取模型',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.modelsError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        controller.modelsError!,
                        style: TextStyle(
                          fontSize: context.appCaptionSize,
                          color: context.appColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        fieldsEnabled &&
                            (hasKey || settings.providerKind.isLocalBackend)
                        ? () => unawaited(_test())
                        : null,
                    child: Text(controller.isTesting ? '测试中…' : '测试连接'),
                  ),
                ),
                if (controller.testMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    controller.testMessage!,
                    style: TextStyle(
                      fontSize: context.appCaptionSize,
                      height: 1.4,
                      color: controller.testOk == true
                          ? context.appColors.primary
                          : context.appColors.error,
                    ),
                  ),
                ],
                if (settings.providerKind
                    .reasoningCapabilities(settings.resolvedModel)
                    .supported) ...[
                  const SizedBox(height: AppSettingsMetrics.sectionGap),
                  const _SectionLabel('生成'),
                  const SizedBox(height: 10),
                  AppSettingsGroup(
                    children: [
                      AppSettingsSwitchRow(
                        title: '默认开启深度思考',
                        subtitle: settings.reasoningEnabled
                            ? '${settings.providerKind.reasoningCapabilities(settings.resolvedModel).enabledLabel}；可在对话中临时调整'
                            : '${settings.providerKind.reasoningCapabilities(settings.resolvedModel).disabledLabel}；可在对话中临时调整',
                        value: settings.reasoningEnabled,
                        onChanged: fieldsEnabled
                            ? (value) => unawaited(
                                controller.setReasoningEnabled(value),
                              )
                            : null,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _SectionLabel('联网搜索'),
                const SizedBox(height: 10),
                Text(
                  '可选。填写搜索服务 Key 后，本书 AI 对话上方可打开「联网」，用于补充书外背景；与上方模型 Key 分开保存。',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    height: 1.45,
                    color: context.settingsSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppChoiceStrip<AiSearchProviderKind>(
                          wrap: true,
                          selected: settings.searchProviderKind,
                          onSelected: (kind) =>
                              unawaited(_onSearchProviderSelected(kind)),
                          options: [
                            for (final kind in AiSearchProviderKind.values)
                              AppChoiceOption(
                                value: kind,
                                label: kind.displayName,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        AppSettingsFormField(
                          label: '搜索 API Key',
                          child: AppTextField(
                            controller: _searchApiKey,
                            obscureText: _obscureSearchKey,
                            enableInteractiveSelection: true,
                            textInputAction: TextInputAction.done,
                            decoration: _decoration(
                              '粘贴 ${settings.searchProviderKind.displayName} 密钥',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: '粘贴',
                                    icon: const Icon(
                                      KaijuanIcons.paste,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        unawaited(_pasteInto(_searchApiKey)),
                                  ),
                                  IconButton(
                                    tooltip: '复制',
                                    icon: const Icon(
                                      KaijuanIcons.copy,
                                      size: 18,
                                    ),
                                    onPressed: () => _copyFrom(_searchApiKey),
                                  ),
                                  IconButton(
                                    tooltip: _obscureSearchKey
                                        ? '显示密钥'
                                        : '隐藏密钥',
                                    icon: Icon(
                                      _obscureSearchKey
                                          ? KaijuanIcons.visibility
                                          : KaijuanIcons.visibilityOff,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscureSearchKey =
                                          !_obscureSearchKey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '申请地址：${settings.searchProviderKind.hintUrl}',
                          style: TextStyle(
                            fontSize: context.appCaptionSize,
                            height: 1.4,
                            color: context.settingsMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: enabled && controller.hasSearchApiKey
                                ? () => unawaited(controller.testSearch())
                                : null,
                            child: Text(
                              controller.isTestingSearch ? '测试中…' : '测试搜索服务',
                            ),
                          ),
                        ),
                        if (controller.searchTestMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            controller.searchTestMessage!,
                            style: TextStyle(
                              fontSize: context.appCaptionSize,
                              height: 1.4,
                              color: context.settingsSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _SectionLabel('翻译'),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  children: [
                    _TranslationPickerRow<AiTranslationLanguage>(
                      title: '目标语言',
                      valueLabel:
                          settings.translation.targetLanguage.displayName,
                      enabled: true,
                      actions: [
                        for (final lang in AiTranslationLanguage.values)
                          AppMenuAction(
                            value: lang,
                            label: lang.displayName,
                            selected:
                                lang == settings.translation.targetLanguage,
                          ),
                      ],
                      onSelected: (lang) => unawaited(
                        controller.updateTranslation(
                          (t) => t.copyWith(targetLanguage: lang),
                        ),
                      ),
                    ),
                    _TranslationPickerRow<AiTranslationDirectionMode>(
                      title: '方向策略',
                      valueLabel:
                          settings.translation.directionMode.displayName,
                      enabled: true,
                      actions: [
                        for (final mode in AiTranslationDirectionMode.values)
                          AppMenuAction(
                            value: mode,
                            label: mode.displayName,
                            selected:
                                mode == settings.translation.directionMode,
                          ),
                      ],
                      onSelected: (mode) => unawaited(
                        controller.updateTranslation(
                          (t) => t.copyWith(directionMode: mode),
                        ),
                      ),
                    ),
                    _TranslationPickerRow<AiTranslationStyle>(
                      title: '译文风格',
                      valueLabel: settings.translation.style.displayName,
                      enabled: true,
                      actions: [
                        for (final style in AiTranslationStyle.values)
                          AppMenuAction(
                            value: style,
                            label: style.displayName,
                            selected: style == settings.translation.style,
                          ),
                      ],
                      onSelected: (style) => unawaited(
                        controller.updateTranslation(
                          (t) => t.copyWith(style: style),
                        ),
                      ),
                    ),
                    _TranslationPickerRow<AiTranslationDisplayMode>(
                      title: '显示方式',
                      valueLabel: settings.translation.displayMode.displayName,
                      enabled: true,
                      actions: [
                        for (final mode in AiTranslationDisplayMode.values)
                          AppMenuAction(
                            value: mode,
                            label: mode.displayName,
                            selected: mode == settings.translation.displayMode,
                          ),
                      ],
                      onSelected: (mode) => unawaited(
                        controller.updateTranslation(
                          (t) => t.copyWith(displayMode: mode),
                        ),
                      ),
                    ),
                    _TranslationPickerRow<AiTranslationNoteFormat>(
                      title: '写入笔记',
                      valueLabel: settings.translation.noteFormat.displayName,
                      enabled: true,
                      actions: [
                        for (final format in AiTranslationNoteFormat.values)
                          AppMenuAction(
                            value: format,
                            label: format.displayName,
                            selected: format == settings.translation.noteFormat,
                          ),
                      ],
                      onSelected: (format) => unawaited(
                        controller.updateTranslation(
                          (t) => t.copyWith(noteFormat: format),
                        ),
                      ),
                    ),
                    AppSettingsSwitchRow(
                      title: '携带选区上下文',
                      subtitle: '开启后，翻译时附带选区前后文（需引擎提供）',
                      value: settings.translation.includeContext,
                      onChanged: (value) => unawaited(
                        controller.updateTranslation(
                          (t) => t.copyWith(includeContext: value),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _SectionLabel('知识图谱'),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  children: [
                    AppSettingsSwitchRow(
                      title: '分析未读内容',
                      subtitle: '开启后图谱可分析全书；关闭时只覆盖已读内容。对话和大纲不受影响',
                      value: settings.allowUnreadContext,
                      onChanged: (value) =>
                          unawaited(controller.setAllowUnreadContext(value)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSettingsMetrics.sectionGap),
                const _SectionLabel('高级设置'),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  children: [
                    AppListRow(
                      title: const Text('高级 AI 规则'),
                      subtitle: const Text('思维导图内容范围、图谱关系与别名'),
                      trailing: Icon(
                        KaijuanIcons.chevronRight,
                        size: 18,
                        color: context.settingsMuted,
                      ),
                      enabled: !controller.isBusy,
                      onTap: controller.isBusy
                          ? null
                          : () => unawaited(
                              AiContentRulesScreen.open(
                                context,
                                controller: controller,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '正文片段只会发送到你配置的模型接口。联网开启时，问题还会发到你选择的搜索服务。选区词典与翻译在 AI 启用后走应用内结果；未启用时使用系统能力。搜索 Key 与模型 Key 一样只保存在本机，不进 WebDAV。',
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    height: 1.45,
                    color: context.settingsMuted,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: context.appCaptionSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: context.settingsSecondary,
        ),
      ),
    );
  }
}

/// Settings row: title left, current value + chevron right, opens [AppMenuButton].
class _TranslationPickerRow<T> extends StatelessWidget {
  const _TranslationPickerRow({
    required this.title,
    required this.valueLabel,
    required this.actions,
    required this.onSelected,
    this.enabled = true,
  });

  final String title;
  final String valueLabel;
  final List<AppMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppMenuButton<T>(
      tooltip: title,
      menuTitle: title,
      forceAnchored: appUsesDesktopPlatform,
      enabled: enabled,
      actions: actions,
      onSelected: onSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: context.appListTitleSize,
                  fontWeight: FontWeight.w600,
                  color: context.settingsPrimary,
                ),
              ),
            ),
            Flexible(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  color: context.settingsSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              KaijuanIcons.chevronRight,
              size: 16,
              color: context.settingsMuted,
            ),
          ],
        ),
      ),
    );
  }
}

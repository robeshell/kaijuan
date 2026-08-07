import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_provider_kind.dart';
import '../../ai/ai_search.dart';
import '../../ai/ai_settings.dart';
import '../../ai/ai_translation.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../controllers/ai_settings_controller.dart';
import '../navigation/app_page_route.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';

/// Settings subpage: BYOK, provider preset, model, test connection.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.controller});

  final AiSettingsController controller;

  static Future<void> open(
    BuildContext context, {
    required AiSettingsController controller,
  }) {
    return Navigator.of(context).push<void>(
      appPageRoute<void>(
        (_) => AiSettingsScreen(controller: controller),
      ),
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
  late final TextEditingController _appendixWords;
  late final TextEditingController _metadataWords;
  late final TextEditingController _citationTemplates;
  late final TextEditingController _relationTypes;
  late final TextEditingController _relationAliases;
  late final TextEditingController _titleSuffixes;
  late final TextEditingController _genericTerms;
  late final TextEditingController _bookPriors;
  bool _obscureKey = true;
  bool _obscureSearchKey = true;
  bool _seeded = false;
  bool _ruleWordsDirty = false;
  bool _showAdvancedRules = false;

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
    _appendixWords = TextEditingController();
    _metadataWords = TextEditingController();
    _citationTemplates = TextEditingController();
    _relationTypes = TextEditingController();
    _relationAliases = TextEditingController();
    _titleSuffixes = TextEditingController();
    _genericTerms = TextEditingController();
    _bookPriors = TextEditingController();
    // Rebuild only this State when text changes — never push keystrokes into
    // ChangeNotifier (that rebuilds the form mid-paste on macOS).
    _apiKey.addListener(_onDraftChanged);
    _baseUrl.addListener(_onDraftChanged);
    _model.addListener(_onDraftChanged);
    _searchApiKey.addListener(_onDraftChanged);
    // Graph-rule fields are saved EXPLICITLY (保存规则 button); edits only
    // mark them dirty so leaving without saving can warn.
    for (final c in _ruleWordControllers) {
      c.addListener(_onRuleWordsChanged);
    }
    unawaited(_ensureLoaded());
  }

  List<TextEditingController> get _ruleWordControllers => [
        _appendixWords,
        _metadataWords,
        _citationTemplates,
        _relationTypes,
        _relationAliases,
        _titleSuffixes,
        _genericTerms,
        _bookPriors,
      ];

  void _onRuleWordsChanged() {
    _ruleWordsDirty = true;
    if (mounted) setState(() {});
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
    _appendixWords.text = settings.graphRuleWords.appendixUnits.join('\n');
    _metadataWords.text = settings.graphRuleWords.metadataUnits.join('\n');
    _citationTemplates.text = settings
        .graphRuleWords
        .citationQuoteTemplates
        .join('\n');
    _relationTypes.text = settings.graphRuleWords.relationTypes.join('\n');
    _relationAliases.text = settings
        .graphRuleWords
        .relationTypeAliases
        .entries
        .map((e) => '${e.key}=${e.value}')
        .join('\n');
    _titleSuffixes.text = settings
        .graphRuleWords
        .personTitleSuffixes
        .join('\n');
    _genericTerms.text = settings.graphRuleWords.genericPersonTerms.join('\n');
    _bookPriors.text = settings
        .graphRuleWords
        .bookNamePriors
        .entries
        .expand((entry) => [
              for (final alias in entry.value.entries)
                '${entry.key}::${alias.key}=${alias.value}',
            ])
        .join('\n');
    _seeded = true;
    setState(() {});
  }

  Future<void> _saveRuleWords() async {
    final words = AiGraphRuleWords(
      appendixUnits: _parseWords(_appendixWords.text),
      metadataUnits: _parseWords(_metadataWords.text),
      citationQuoteTemplates: _parseWords(_citationTemplates.text),
      relationTypes: _parseWords(_relationTypes.text),
      relationTypeAliases: _parseAliases(_relationAliases.text),
      personTitleSuffixes: _parseWords(_titleSuffixes.text),
      genericPersonTerms: _parseWords(_genericTerms.text),
      bookNamePriors: _parseBookPriors(_bookPriors.text),
    );
    final skipped = _skippedLineCount();
    await controller.applyDraft(
      apiKey: _apiKey.text,
      baseUrl: _baseUrl.text,
      model: _model.text,
      graphRuleWords: words,
    );
    _ruleWordsDirty = false;
    if (mounted) {
      setState(() {});
      showAppSnackBar(
        context,
        skipped == 0
            ? '图谱规则已保存'
            : '图谱规则已保存（$skipped 行格式不对，已忽略）',
      );
    }
  }

  /// Counts malformed lines across the three keyed textareas (alias + priors)
  /// so the user knows what was dropped, not silently lost.
  int _skippedLineCount() {
    var skipped = 0;
    for (final line in _relationAliases.text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final eq = t.indexOf('=');
      if (eq <= 0 || eq == t.length - 1) skipped++;
    }
    for (final line in _bookPriors.text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final sep = t.indexOf('::');
      if (sep <= 0) {
        skipped++;
        continue;
      }
      final eq = t.indexOf('=', sep);
      if (eq <= sep + 2 || eq == t.length - 1) skipped++;
    }
    return skipped;
  }

  /// Parses `书名::别名=规范名` lines into the book priors map; malformed
  /// lines are skipped.
  static Map<String, Map<String, String>> _parseBookPriors(String text) {
    final priors = <String, Map<String, String>>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final sep = trimmed.indexOf('::');
      if (sep <= 0) continue;
      final book = trimmed.substring(0, sep).trim();
      final eq = trimmed.indexOf('=', sep);
      if (eq <= sep + 2 || eq == trimmed.length - 1) continue;
      priors
          .putIfAbsent(book, () => {})
          .putIfAbsent(
            trimmed.substring(sep + 2, eq).trim(),
            () => trimmed.substring(eq + 1).trim(),
          );
    }
    return priors;
  }

  Future<void> _flushDraft({bool notifyController = true}) async {
    if (notifyController) {
      await controller.applyDraft(
        apiKey: _apiKey.text,
        baseUrl: _baseUrl.text,
        model: _model.text,
        graphRuleWords: AiGraphRuleWords(
          appendixUnits: _parseWords(_appendixWords.text),
          metadataUnits: _parseWords(_metadataWords.text),
          citationQuoteTemplates: _parseWords(_citationTemplates.text),
          relationTypes: _parseWords(_relationTypes.text),
          relationTypeAliases: _parseAliases(_relationAliases.text),
          personTitleSuffixes: _parseWords(_titleSuffixes.text),
          genericPersonTerms: _parseWords(_genericTerms.text),
          bookNamePriors: _parseBookPriors(_bookPriors.text),
        ),
      );
      await controller.setSearchApiKey(_searchApiKey.text, notify: true);
    }
  }

  /// Splits a word-list textarea into trimmed, non-empty lines.
  static List<String> _parseWords(String text) => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  /// Parses `english=中文` lines into an alias map; malformed lines are
  /// skipped (keeps hand edits from silently corrupting the map).
  static Map<String, String> _parseAliases(String text) {
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0 || eq == trimmed.length - 1) continue;
      map[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
    return map;
  }

  @override
  void dispose() {
    // Connection fields persist best-effort on leave; graph-rule words are
    // saved EXPLICITLY via the 保存规则 button and are NOT flushed here
    // (a half-finished edit must not silently overwrite the config).
    unawaited(
      controller.applyDraft(
        apiKey: _apiKey.text,
        baseUrl: _baseUrl.text,
        model: _model.text,
      ),
    );
    unawaited(
      controller.setSearchApiKey(_searchApiKey.text, notify: false),
    );
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
    _appendixWords
      ..removeListener(_onDraftChanged)
      ..dispose();
    _metadataWords
      ..removeListener(_onDraftChanged)
      ..dispose();
    _citationTemplates
      ..removeListener(_onDraftChanged)
      ..dispose();
    _relationTypes
      ..removeListener(_onDraftChanged)
      ..dispose();
    _relationAliases
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
      if (mounted) showAppSnackBar(context, error.message);
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
            subtitle: model.displayName != null &&
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
    return PopScope(
      canPop: !_ruleWordsDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) _confirmDiscardRules();
      },
      child: Scaffold(
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
                        if (settings.providerKind == AiProviderKind.custom) ...[
                          const SizedBox(height: 14),
                          Text(
                            '接口格式',
                            style: TextStyle(
                              fontSize: context.appCaptionSize,
                              fontWeight: FontWeight.w600,
                              color: context.settingsSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AppChoiceStrip<AiApiProtocol>(
                            wrap: true,
                            selected: settings.customProtocol,
                            onSelected: fieldsEnabled
                                ? (protocol) => unawaited(
                                    controller.setCustomProtocol(protocol),
                                  )
                                : (_) {},
                            options: [
                              for (final protocol in AiApiProtocol.values)
                                AppChoiceOption(
                                  value: protocol,
                                  label: protocol.displayName,
                                  enabled: fieldsEnabled,
                                ),
                            ],
                          ),
                        ],
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
                    if (settings.providerKind.isLocalBackend) ...[ //
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
                    ] else ...[ //
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
                                  icon: const Icon(
                                    KaijuanIcons.copy,
                                    size: 18,
                                  ),
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
                    child: Text(
                      controller.isTesting ? '测试中…' : '测试连接',
                    ),
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
                            onPressed: controller.hasSearchApiKey
                                ? () => unawaited(controller.testSearch())
                                : null,
                            child: Text(controller.isTestingSearch
                                ? '测试中…'
                                : '测试搜索服务'),
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
                      valueLabel: settings.translation.targetLanguage.displayName,
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
                      valueLabel: settings.translation.directionMode.displayName,
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
                            selected:
                                format == settings.translation.noteFormat,
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
                const _SectionLabel('知识图谱规则'),
                const SizedBox(height: 10),
                AppSettingsGroup(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                  children: [
                    AppSettingsSwitchRow(
                      title: '图谱范围：已读章节',
                      subtitle: '关闭时，知识图谱仅覆盖已读章节（防剧透）；开启则分析全书。对话与大纲不受影响',
                      value: settings.allowUnreadContext,
                      onChanged: (value) => unawaited(
                        controller.setAllowUnreadContext(value),
                      ),
                    ),
                    const Divider(
                      height: 24,
                      indent: 14,
                      endIndent: 14,
                    ),
                    _GraphRuleWordsField(
                      label: '正文前的辅文',
                      helper: '每行一个词，按开头匹配；以 ! 开头的行表示排除，如 !序曲（附录、后记等）',
                      controller: _appendixWords,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _appendixWords.text = AiGraphRuleWords
                            .defaultAppendixUnits
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 20),
                    _GraphRuleWordsField(
                      label: '目录/版权页标题',
                      helper: '每行一个词，完全匹配，如 目录',
                      controller: _metadataWords,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _metadataWords.text = AiGraphRuleWords
                            .defaultMetadataUnits
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 20),
                    _GraphRuleWordsField(
                      label: '引用识别句式',
                      helper: '每行一个句式，{name} 替换为实体名，如 据{name}；命中的实体视为外部引用',
                      controller: _citationTemplates,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _citationTemplates.text = AiGraphRuleWords
                            .defaultCitationQuoteTemplates
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 20),
                    _GraphRuleWordsField(
                      label: '关系词表',
                      helper: '每行一个关系词，如 信任、敌对、师徒',
                      controller: _relationTypes,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _relationTypes.text = AiGraphRuleWords
                            .defaultRelationTypes
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(
                            () => _showAdvancedRules = !_showAdvancedRules),
                        icon: Icon(
                          _showAdvancedRules
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(_showAdvancedRules
                            ? '收起高级规则'
                            : '高级规则（别名/称谓/先验）'),
                      ),
                    ),
                    if (_showAdvancedRules) ...[
                    _GraphRuleWordsField(
                      label: '英文关系别名',
                      helper: '每行 英文=中文，如 trusts=信任、teacher_student=师生',
                      controller: _relationAliases,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _relationAliases.text = AiGraphRuleWords
                            .defaultRelationTypeAliases
                            .entries
                            .map((e) => '${e.key}=${e.value}')
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 20),
                    _GraphRuleWordsField(
                      label: '称谓后缀',
                      helper: '每行一个，同一人称号的后缀变体，如 皇太后、皇帝',
                      controller: _titleSuffixes,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _titleSuffixes.text = AiGraphRuleWords
                            .defaultPersonTitleSuffixes
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 20),
                    _GraphRuleWordsField(
                      label: '泛称拦截词',
                      helper: '每行一个；这些称呼（皇帝、哥哥、先生…）不会与具体'
                          '人名合并，防止张冠李戴',
                      controller: _genericTerms,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _genericTerms.text = AiGraphRuleWords
                            .defaultGenericPersonTerms
                            .join('\n');
                      }),
                    ),
                    const SizedBox(height: 20),
                    _GraphRuleWordsField(
                      label: '书名别名先验',
                      helper: '每行 书名::别名=规范名，如 西游记::行者=孙悟空；'
                          '该书生成图谱时别名直接归并为规范名',
                      controller: _bookPriors,
                      enabled: !controller.isBusy,
                      onReset: () => setState(() {
                        _bookPriors.text = AiGraphRuleWords
                            .defaultBookNamePriors
                            .entries
                            .expand((entry) => [
                                  for (final alias in entry.value.entries)
                                    '${entry.key}::${alias.key}=${alias.value}',
                                ])
                            .join('\n');
                      }),
                    ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: controller.isBusy ? null : _saveRuleWords,
                      child: const Text('保存图谱规则'),
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
      ),
    );
  }

  /// Unsaved graph-rule edits block leaving until the user chooses.
  Future<void> _confirmDiscardRules() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('图谱规则未保存'),
        content: const Text('你对图谱规则的修改还没有保存。放弃修改并离开？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('留下继续编辑'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _ruleWordsDirty = false;
      Navigator.of(context).pop();
    }
  }
}

/// Multi-line editor for one graph rule word list, with a per-list
/// restore-defaults action. Edits are drafts flushed on page exit.
class _GraphRuleWordsField extends StatelessWidget {
  const _GraphRuleWordsField({
    required this.label,
    required this.helper,
    required this.controller,
    required this.enabled,
    required this.onReset,
  });

  final String label;
  final String helper;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppSettingsFormField(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: controller,
            enabled: enabled,
            maxLines: 7,
            minLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: helper,
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  helper,
                  style: TextStyle(
                    fontSize: context.appCaptionSize,
                    height: 1.35,
                    color: context.settingsSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: enabled ? onReset : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ],
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

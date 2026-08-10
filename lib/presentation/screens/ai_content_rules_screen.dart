import 'dart:async';

import 'package:flutter/material.dart';

import '../../ai/ai_settings.dart';
import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../controllers/ai_settings_controller.dart';
import '../navigation/app_page_route.dart';
import '../widgets/app_components.dart';
import '../widgets/app_overlays.dart';
import '../widgets/settings_components.dart';

/// Advanced, explicitly saved deterministic AI content rules.
///
/// These fields intentionally live outside the ordinary AI setup page: they
/// tune content selection and extraction heuristics rather than enabling a
/// reader-facing feature.
class AiContentRulesScreen extends StatefulWidget {
  const AiContentRulesScreen({super.key, required this.controller});

  final AiSettingsController controller;

  static Future<void> open(
    BuildContext context, {
    required AiSettingsController controller,
  }) {
    return Navigator.of(context).push<void>(
      appPageRoute<void>((_) => AiContentRulesScreen(controller: controller)),
    );
  }

  @override
  State<AiContentRulesScreen> createState() => _AiContentRulesScreenState();
}

class _AiContentRulesScreenState extends State<AiContentRulesScreen> {
  late final TextEditingController _mindMapExcludedTitles;
  late final TextEditingController _appendixWords;
  late final TextEditingController _metadataWords;
  late final TextEditingController _citationTemplates;
  late final TextEditingController _relationTypes;
  late final TextEditingController _relationAliases;
  late final TextEditingController _titleSuffixes;
  late final TextEditingController _genericTerms;
  late final TextEditingController _bookPriors;

  var _dirty = false;
  var _saving = false;
  var _showAdvanced = false;

  AiSettingsController get controller => widget.controller;

  List<TextEditingController> get _controllers => [
    _mindMapExcludedTitles,
    _appendixWords,
    _metadataWords,
    _citationTemplates,
    _relationTypes,
    _relationAliases,
    _titleSuffixes,
    _genericTerms,
    _bookPriors,
  ];

  @override
  void initState() {
    super.initState();
    final rules = controller.settings.contentRuleWords;
    _mindMapExcludedTitles = TextEditingController(
      text: rules.mindMapExcludedTitlePatterns.join('\n'),
    );
    _appendixWords = TextEditingController(
      text: rules.appendixUnits.join('\n'),
    );
    _metadataWords = TextEditingController(
      text: rules.metadataUnits.join('\n'),
    );
    _citationTemplates = TextEditingController(
      text: rules.citationQuoteTemplates.join('\n'),
    );
    _relationTypes = TextEditingController(
      text: rules.relationTypes.join('\n'),
    );
    _relationAliases = TextEditingController(
      text: rules.relationTypeAliases.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('\n'),
    );
    _titleSuffixes = TextEditingController(
      text: rules.personTitleSuffixes.join('\n'),
    );
    _genericTerms = TextEditingController(
      text: rules.genericPersonTerms.join('\n'),
    );
    _bookPriors = TextEditingController(
      text: rules.bookNamePriors.entries
          .expand(
            (entry) => [
              for (final alias in entry.value.entries)
                '${entry.key}::${alias.key}=${alias.value}',
            ],
          )
          .join('\n'),
    );
    for (final field in _controllers) {
      field.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  AiContentRuleWords _draftRules() => AiContentRuleWords(
    mindMapExcludedTitlePatterns: _parseWords(_mindMapExcludedTitles.text),
    appendixUnits: _parseWords(_appendixWords.text),
    metadataUnits: _parseWords(_metadataWords.text),
    citationQuoteTemplates: _parseWords(_citationTemplates.text),
    relationTypes: _parseWords(_relationTypes.text),
    relationTypeAliases: _parseAliases(_relationAliases.text),
    personTitleSuffixes: _parseWords(_titleSuffixes.text),
    genericPersonTerms: _parseWords(_genericTerms.text),
    bookNamePriors: _parseBookPriors(_bookPriors.text),
  );

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    final skipped = _skippedLineCount();
    try {
      await controller.applyDraft(
        apiKey: controller.apiKey,
        baseUrl: controller.settings.baseUrl,
        model: controller.settings.model,
        contentRuleWords: _draftRules(),
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      showAppSnackBar(
        context,
        skipped == 0 ? 'AI 规则已保存' : 'AI 规则已保存，已忽略 $skipped 行格式不正确的内容',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnackBar(context, 'AI 规则保存失败，请稍后重试');
    }
  }

  Future<void> _requestBack() async {
    if (!_dirty) {
      await Navigator.of(context).maybePop();
      return;
    }
    final discard = await showAppConfirmDialog(
      context,
      title: '放弃 AI 规则修改？',
      message: '尚未保存的修改不会生效。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃修改',
      destructive: true,
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  int _skippedLineCount() {
    var skipped = 0;
    for (final line in _relationAliases.text.split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final equals = value.indexOf('=');
      if (equals <= 0 || equals == value.length - 1) skipped++;
    }
    for (final line in _bookPriors.text.split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final separator = value.indexOf('::');
      final equals = value.indexOf('=', separator);
      if (separator <= 0 ||
          equals <= separator + 2 ||
          equals == value.length - 1) {
        skipped++;
      }
    }
    return skipped;
  }

  static List<String> _parseWords(String text) => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  static Map<String, String> _parseAliases(String text) {
    final result = <String, String>{};
    for (final line in text.split('\n')) {
      final value = line.trim();
      final equals = value.indexOf('=');
      if (value.isEmpty || equals <= 0 || equals == value.length - 1) continue;
      result[value.substring(0, equals).trim()] = value
          .substring(equals + 1)
          .trim();
    }
    return result;
  }

  static Map<String, Map<String, String>> _parseBookPriors(String text) {
    final result = <String, Map<String, String>>{};
    for (final line in text.split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final separator = value.indexOf('::');
      final equals = value.indexOf('=', separator);
      if (separator <= 0 ||
          equals <= separator + 2 ||
          equals == value.length - 1) {
        continue;
      }
      final book = value.substring(0, separator).trim();
      final alias = value.substring(separator + 2, equals).trim();
      final canonical = value.substring(equals + 1).trim();
      if (book.isEmpty || alias.isEmpty || canonical.isEmpty) continue;
      result.putIfAbsent(book, () => {})[alias] = canonical;
    }
    return result;
  }

  @override
  void dispose() {
    for (final field in _controllers) {
      field
        ..removeListener(_markDirty)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.appPageGutter;
    const rules = AiContentRuleWords();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) unawaited(_requestBack());
      },
      child: Scaffold(
        backgroundColor: context.settingsCanvas,
        body: AppSettingsSafeArea(
          bottom: true,
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
                title: '高级 AI 规则',
                onBack: () => unawaited(_requestBack()),
                actions: [
                  TextButton(
                    key: const ValueKey('ai-rules-save-top'),
                    onPressed: _dirty && !_saving
                        ? () => unawaited(_save())
                        : null,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
              const SizedBox(height: AppSettingsMetrics.headerGap),
              Text(
                '这些规则用于控制思维导图内容范围，以及知识图谱的辅文、关系和别名。一般不需要修改；格式错误的行会在保存时忽略。',
                style: TextStyle(
                  fontSize: context.appCaptionSize,
                  height: 1.45,
                  color: context.settingsSecondary,
                ),
              ),
              const SizedBox(height: AppSettingsMetrics.sectionGap),
              AppSettingsGroup(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '思维导图内容范围',
                        style: TextStyle(
                          fontSize: context.appBodySize,
                          fontWeight: FontWeight.w600,
                          color: context.settingsPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RuleWordsField(
                        fieldKey: const ValueKey(
                          'content-rule-mind-map-excluded-titles',
                        ),
                        label: '整书排除标题',
                        helper: '每行一个完整标题模式；* 可匹配任意文字，例如 附录*、*出版始末*',
                        controller: _mindMapExcludedTitles,
                        enabled: !_saving,
                        onReset: () => _mindMapExcludedTitles.text = rules
                            .mindMapExcludedTitlePatterns
                            .join('\n'),
                      ),
                      const SizedBox(height: 24),
                      Divider(color: context.appColors.outlineVariant),
                      const SizedBox(height: 20),
                      Text(
                        '知识图谱',
                        style: TextStyle(
                          fontSize: context.appBodySize,
                          fontWeight: FontWeight.w600,
                          color: context.settingsPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RuleWordsField(
                        fieldKey: const ValueKey('graph-rule-appendix'),
                        label: '建议排除的辅文',
                        helper: '每行一个词，按开头匹配；以 ! 开头表示排除，例如 !序曲',
                        controller: _appendixWords,
                        enabled: !_saving,
                        onReset: () => _appendixWords.text = rules.appendixUnits
                            .join('\n'),
                      ),
                      const SizedBox(height: 20),
                      _RuleWordsField(
                        fieldKey: const ValueKey('graph-rule-metadata'),
                        label: '目录和版权页标题',
                        helper: '每行一个词，完全匹配，例如 目录',
                        controller: _metadataWords,
                        enabled: !_saving,
                        onReset: () => _metadataWords.text = rules.metadataUnits
                            .join('\n'),
                      ),
                      const SizedBox(height: 20),
                      _RuleWordsField(
                        fieldKey: const ValueKey('graph-rule-citations'),
                        label: '引用识别句式',
                        helper: '每行一个句式；用 {name} 代表实体名，例如 据{name}',
                        controller: _citationTemplates,
                        enabled: !_saving,
                        onReset: () => _citationTemplates.text = rules
                            .citationQuoteTemplates
                            .join('\n'),
                      ),
                      const SizedBox(height: 20),
                      _RuleWordsField(
                        fieldKey: const ValueKey('graph-rule-relations'),
                        label: '关系词表',
                        helper: '每行一个关系词，例如 信任、敌对、师徒',
                        controller: _relationTypes,
                        enabled: !_saving,
                        onReset: () => _relationTypes.text = rules.relationTypes
                            .join('\n'),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        button: true,
                        expanded: _showAdvanced,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showAdvanced = !_showAdvanced),
                          icon: Icon(
                            _showAdvanced
                                ? KaijuanIcons.chevronDown
                                : KaijuanIcons.chevronRight,
                            size: 18,
                          ),
                          label: Text(_showAdvanced ? '收起更多规则' : '显示更多规则'),
                        ),
                      ),
                      if (_showAdvanced) ...[
                        const SizedBox(height: 12),
                        _RuleWordsField(
                          fieldKey: const ValueKey('graph-rule-aliases'),
                          label: '英文关系别名',
                          helper: '每行 英文=中文，例如 trusts=信任',
                          controller: _relationAliases,
                          enabled: !_saving,
                          onReset: () => _relationAliases.text = rules
                              .relationTypeAliases
                              .entries
                              .map((entry) => '${entry.key}=${entry.value}')
                              .join('\n'),
                        ),
                        const SizedBox(height: 20),
                        _RuleWordsField(
                          fieldKey: const ValueKey('graph-rule-titles'),
                          label: '称谓后缀',
                          helper: '每行一个称谓，例如 皇太后、皇帝',
                          controller: _titleSuffixes,
                          enabled: !_saving,
                          onReset: () => _titleSuffixes.text = rules
                              .personTitleSuffixes
                              .join('\n'),
                        ),
                        const SizedBox(height: 20),
                        _RuleWordsField(
                          fieldKey: const ValueKey('graph-rule-generics'),
                          label: '泛称拦截词',
                          helper: '每行一个；这些泛称不会与具体人名合并',
                          controller: _genericTerms,
                          enabled: !_saving,
                          onReset: () => _genericTerms.text = rules
                              .genericPersonTerms
                              .join('\n'),
                        ),
                        const SizedBox(height: 20),
                        _RuleWordsField(
                          fieldKey: const ValueKey('graph-rule-book-priors'),
                          label: '书名别名先验',
                          helper: '每行 书名::别名=规范名，例如 西游记::行者=孙悟空',
                          controller: _bookPriors,
                          enabled: !_saving,
                          onReset: () => _bookPriors.text = rules
                              .bookNamePriors
                              .entries
                              .expand(
                                (entry) => [
                                  for (final alias in entry.value.entries)
                                    '${entry.key}::${alias.key}=${alias.value}',
                                ],
                              )
                              .join('\n'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('ai-rules-save-bottom'),
                onPressed: _dirty && !_saving ? () => unawaited(_save()) : null,
                icon: const Icon(KaijuanIcons.check, size: 18),
                label: Text(_saving ? '保存中…' : '保存 AI 规则'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleWordsField extends StatelessWidget {
  const _RuleWordsField({
    required this.fieldKey,
    required this.label,
    required this.helper,
    required this.controller,
    required this.enabled,
    required this.onReset,
  });

  final Key fieldKey;
  final String label;
  final String helper;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return AppSettingsFormField(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            minLines: 4,
            maxLines: 7,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: helper,
              isDense: true,
              filled: true,
              fillColor: context.appColors.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

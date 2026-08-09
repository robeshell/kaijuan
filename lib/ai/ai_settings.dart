import 'ai_provider_kind.dart';
import 'ai_search.dart';
import 'ai_translation.dart';

/// Tunable word lists that drive the graph-pipeline hard rules. Kept in
/// settings so the user can extend them without a code change; the const
/// constructor carries today's built-in defaults.
class AiGraphRuleWords {
  const AiGraphRuleWords({
    this.appendixUnits = defaultAppendixUnits,
    this.metadataUnits = defaultMetadataUnits,
    this.citationQuoteTemplates = defaultCitationQuoteTemplates,
    this.relationTypes = defaultRelationTypes,
    this.relationTypeAliases = defaultRelationTypeAliases,
    this.personTitleSuffixes = defaultPersonTitleSuffixes,
    this.genericPersonTerms = defaultGenericPersonTerms,
    this.bookNamePriors = defaultBookNamePriors,
  });

  /// Front/back-matter unit words matched as a PREFIX of a section label
  /// (附录, 后记, 文前辅文, 序 ...). Lines starting with `!` are exclusions
  /// applied as a leading negative lookahead (e.g. `!序曲` keeps 序曲 as a
  /// body opening instead of a front-matter 序).
  final List<String> appendixUnits;

  /// Metadata titles matched EXACTLY (目录, 版权, 封面 ...).
  final List<String> metadataUnits;

  /// Citation-quote templates; `{name}` is replaced with the entity name
  /// (e.g. `据{name}`, `{name}写道`).
  final List<String> citationQuoteTemplates;

  /// Curated Chinese relation-type vocabulary the extraction prompt offers;
  /// anything else collapses via [relationTypeAliases] or to '相关'.
  final List<String> relationTypes;

  /// Raw (usually English NER) relation tags → Chinese vocabulary, one entry
  /// per line as `english=中文` in the settings UI.
  final Map<String, String> relationTypeAliases;

  /// Person-title suffixes marking the same individual's honorific /
  /// posthumous variants (皇后升格太后、皇帝/帝号简称) — the 0.7 stem rule
  /// (慈圣太后↔慈圣皇太后) matches on these.
  final List<String> personTitleSuffixes;

  /// Generic honorific / contextual kinship terms that must never absorb a
  /// named person via the substring rule (皇帝/太后/哥哥/先生…). Configurable
  /// so book-specific 称谓 systems can be tuned without touching the pipeline.
  final List<String> genericPersonTerms;

  /// Book-specific alias→canonical priors, keyed by book title (matched
  /// against the graph's bookTitle). Populated for the four classics out of
  /// the box; any other book can add its own entry via settings — this is a
  /// config library, never pipeline code. Aliases here are resolved before
  /// every generic merge rule (they are certain, not probabilistic).
  final Map<String, Map<String, String>> bookNamePriors;

  static const defaultAppendixUnits = <String>[
    '附录',
    '参考书目',
    '参考文献',
    '参考资料',
    '人名索引',
    '地名索引',
    '主题索引',
    '关键词索引',
    '索引',
    '致谢',
    '谢辞',
    '鸣谢',
    '后记',
    '跋',
    '注释',
    '年表',
    '词汇表',
    '术语表',
    '缩略语表',
    '勘误',
    '勘误表',
    '卷末',
    '书末',
    '前言',
    '序言',
    '序',
    '自序',
    '代序',
    '弁言',
    '小引',
    '凡例',
    '出版说明',
    '出版前言',
    '出版后记',
    '出版者的话',
    '编者按',
    '导读',
    '题记',
    '题词',
    '题辞',
    '题献',
    '献词',
    '献页',
    '致献',
    '重印前记',
    '重印后记',
    '再版前记',
    '再版后记',
    '再版说明',
    '重印说明',
    '修订说明',
    '修订版说明',
    '校订说明',
    '点校说明',
    '整理说明',
    '编译说明',
    '编写说明',
    '译者序',
    '译者前言',
    '译者后记',
    '译后记',
    '译序',
    '校后记',
    '编后',
    '编后记',
    '文前辅文',
    '文前',
    '辅文',
    '前置部分',
    '卷首',
    '卷首语',
    '扉页',
    '书名页',
    '版权页',
    '衬页',
    '环衬',
    '飞页',
    '插页',
    '内容简介',
    '内容提要',
    '图书简介',
    '作者简介',
    '关于作者',
    '关于本书',
    '作者小传',
    '作者生平',
    '制作说明',
    '画廊',
    '系列封面',
    '封面画廊',
    '封面语',
    '封底语',
    '!序曲',
    '!序章',
    '!序幕',
    '!序篇',
  ];

  static const defaultMetadataUnits = <String>[
    '目录',
    '总目录',
    '全书目录',
    '章节目录',
    '目次',
    '版权',
    '版权信息',
    '版权页',
    '版权记录',
    '出版',
    '出版信息',
    '出版说明',
    '出版记录',
    '出版前言',
    '出版后记',
    '图书在版编目',
    '版本记录',
    '封面',
    '封底',
    '扉页',
    '书名页',
    '护封',
    '腰封',
  ];

  static const defaultCitationQuoteTemplates = <String>[
    '据{name}',
    '按{name}',
    '如{name}所言',
    '正如{name}所说',
    '{name}曾说',
    '{name}写道',
    '{name}所言',
    '据说{name}',
  ];

  static const defaultRelationTypes = <String>[
    '信任',
    '效力',
    '敌对',
    '弹劾',
    '师生',
    '师徒',
    '同僚',
    '亲属',
    '更替',
    '调停',
    '协助',
    '隶属',
    '婚配',
    '爱慕',
    '仇视',
    '追随',
    '举荐',
    '主从',
    '同盟',
    '竞争',
    '仰慕',
    '忌惮',
    '庇护',
    '提携',
    '投靠',
    '反目',
    '和解',
    '嫌隙',
    '知遇',
    '共事',
    '打压',
    '倚重',
  ];

  static const defaultRelationTypeAliases = <String, String>{
    'trust': '信任',
    'trusts': '信任',
    'trusted': '信任',
    'serve': '效力',
    'serves': '效力',
    'served': '效力',
    'servant': '效力',
    'works_for': '效力',
    'work_for': '效力',
    'worked_for': '效力',
    'employer': '效力',
    'employee': '效力',
    'teacher_student': '师生',
    'teacher': '师生',
    'student': '师生',
    'mentor': '师生',
    'mentee': '师生',
    'apprentice': '师徒',
    'master': '师徒',
    'master_apprentice': '师徒',
    'disciple': '师徒',
    'married': '婚配',
    'marriage': '婚配',
    'married_to': '婚配',
    'spouse': '婚配',
    'wife': '婚配',
    'husband': '婚配',
    'lover': '爱慕',
    'love': '爱慕',
    'loves': '爱慕',
    'romance': '爱慕',
    'affair': '爱慕',
    'parent': '亲属',
    'father': '亲属',
    'mother': '亲属',
    'son': '亲属',
    'daughter': '亲属',
    'child': '亲属',
    'family': '亲属',
    'relative': '亲属',
    'brother': '亲属',
    'sister': '亲属',
    'friend': '同盟',
    'friends': '同盟',
    'friend_of': '同盟',
    'allied': '同盟',
    'allies': '同盟',
    'alliance': '同盟',
    'enemy': '敌对',
    'enemies': '敌对',
    'enemy_of': '敌对',
    'rival': '敌对',
    'rivals': '敌对',
    'rivalry': '敌对',
    'conflict': '敌对',
    'conflicts': '敌对',
    'attacked': '敌对',
    'impeached': '弹劾',
    'accused': '弹劾',
    'impeachment': '弹劾',
    'replaced': '更替',
    'replaces': '更替',
    'replace': '更替',
    'succeeded': '更替',
    'successor': '更替',
    'succession': '更替',
    'mediated': '调停',
    'mediator': '调停',
    'mediate': '调停',
    'helped': '协助',
    'helps': '协助',
    'helped_by': '协助',
    'assisted': '协助',
    'supports': '协助',
    'supported': '协助',
    'recommended': '举荐',
    'recommend': '举荐',
    'recommendation': '举荐',
    'colleague': '同僚',
    'colleagues': '同僚',
    'worked_with': '同僚',
    'coworker': '同僚',
    'subordinate': '隶属',
    'subordinates': '隶属',
    'under': '隶属',
    'followed': '追随',
    'follower': '追随',
    'followers': '追随',
    'fear': '忌惮',
    'fears': '忌惮',
    'feared': '忌惮',
    'protects': '庇护',
    'protected': '庇护',
    'patron': '庇护',
    'patronage': '庇护',
    'promoted': '提携',
    'promote': '提携',
    'collaborates': '共事',
    'collaborated': '共事',
    'worked_together': '共事',
    'collaborator': '共事',
  };

  /// Person-title suffixes for the 0.7 stem rule (慈圣太后↔慈圣皇太后).
  static const defaultPersonTitleSuffixes = <String>['皇太后', '太后', '皇帝', '皇后'];

  /// Generic honorific / contextual kinship terms excluded from substring
  /// merges (皇帝/太后/哥哥/先生… — roles, not names).
  static const defaultGenericPersonTerms = <String>[
    // 身份/爵位
    '皇帝', '皇上', '陛下', '万岁', '太后', '皇后', '贵妃', '娘娘',
    '殿下', '王爷', '亲王', '大人', '将军', '尚书', '侍郎', '都督',
    '公主', '太子', '皇子', '世子', '圣母', '先帝', '朕',
    // 亲属称谓（上下文相关，跨章指人不同）
    '哥哥', '弟弟', '姐姐', '妹妹', '兄长', '贤弟', '母亲', '父亲',
    '娘亲', '爹爹', '爷爷', '奶奶', '祖父', '祖母', '外公', '外婆',
    '叔叔', '婶婶', '舅舅', '舅母', '姑姑', '姑母', '伯父', '伯母',
    '叔父', '叔母', '侄儿', '侄子', '侄女', '外甥', '外甥女', '孙子',
    '孙女', '儿子', '女儿', '兄弟', '姐妹',
    // 身份/称谓
    '师父', '师傅', '师尊', '弟子', '徒弟', '徒儿', '道友', '道兄',
    '那怪', '妖怪', '妇人', '老汉', '老翁', '老妪', '书生', '和尚',
    '道士', '先生', '小姐', '公子', '夫人', '姑娘', '娘子', '官人',
    '郎君', '大姐', '大婶', '大妈', '堂兄', '堂弟', '表兄', '表弟',
  ];

  /// Alias→canonical priors for the four classics (公版、测试常客、别名共指
  /// 出错率高的作品). Only aliases that unambiguously name one person are
  /// listed; generic terms (丞相/师父) are deliberately excluded. Matched by
  /// bookTitle; empty map when the book is not listed.
  static const defaultBookNamePriors = <String, Map<String, String>>{
    '红楼梦': {
      '宝二爷': '贾宝玉',
      '怡红公子': '贾宝玉',
      '绛珠仙子': '林黛玉',
      '潇湘妃子': '林黛玉',
      '颦儿': '林黛玉',
      '蘅芜君': '薛宝钗',
      '凤辣子': '王熙凤',
      '琏二爷': '贾琏',
      '老祖宗': '贾母',
      '史太君': '贾母',
      '稻香老农': '李纨',
      '蕉下客': '贾探春',
    },
    '西游记': {
      '行者': '孙悟空',
      '孙行者': '孙悟空',
      '美猴王': '孙悟空',
      '齐天大圣': '孙悟空',
      '斗战胜佛': '孙悟空',
      '泼猴': '孙悟空',
      '弼马温': '孙悟空',
      '金蝉子': '唐僧',
      '玄奘': '唐僧',
      '唐长老': '唐僧',
      '圣僧': '唐僧',
      '天蓬元帅': '猪八戒',
      '猪悟能': '猪八戒',
      '净坛使者': '猪八戒',
      '卷帘大将': '沙僧',
      '沙悟净': '沙僧',
    },
    '三国演义': {
      '孟德': '曹操',
      '曹孟德': '曹操',
      '云长': '关羽',
      '关云长': '关羽',
      '美髯公': '关羽',
      '孔明': '诸葛亮',
      '诸葛孔明': '诸葛亮',
      '卧龙': '诸葛亮',
      '玄德': '刘备',
      '刘玄德': '刘备',
      '翼德': '张飞',
      '张翼德': '张飞',
      '奉先': '吕布',
      '吕奉先': '吕布',
      '子龙': '赵云',
      '赵子龙': '赵云',
      '仲谋': '孙权',
      '孙仲谋': '孙权',
    },
    '水浒传': {
      '公明': '宋江',
      '宋公明': '宋江',
      '及时雨': '宋江',
      '豹子头': '林冲',
      '林教头': '林冲',
      '智多星': '吴用',
      '吴学究': '吴用',
      '黑旋风': '李逵',
      '铁牛': '李逵',
      '花和尚': '鲁智深',
      '鲁提辖': '鲁智深',
      '武二郎': '武松',
      '青面兽': '杨志',
      '玉麒麟': '卢俊义',
    },
  };

  AiGraphRuleWords copyWith({
    List<String>? appendixUnits,
    List<String>? metadataUnits,
    List<String>? citationQuoteTemplates,
    List<String>? relationTypes,
    Map<String, String>? relationTypeAliases,
    List<String>? personTitleSuffixes,
    List<String>? genericPersonTerms,
    Map<String, Map<String, String>>? bookNamePriors,
  }) {
    return AiGraphRuleWords(
      appendixUnits: appendixUnits ?? this.appendixUnits,
      metadataUnits: metadataUnits ?? this.metadataUnits,
      citationQuoteTemplates:
          citationQuoteTemplates ?? this.citationQuoteTemplates,
      relationTypes: relationTypes ?? this.relationTypes,
      relationTypeAliases: relationTypeAliases ?? this.relationTypeAliases,
      personTitleSuffixes: personTitleSuffixes ?? this.personTitleSuffixes,
      genericPersonTerms: genericPersonTerms ?? this.genericPersonTerms,
      bookNamePriors: bookNamePriors ?? this.bookNamePriors,
    );
  }

  Map<String, Object?> toJson() => {
    'appendixUnits': appendixUnits,
    'metadataUnits': metadataUnits,
    'citationQuoteTemplates': citationQuoteTemplates,
    'relationTypes': relationTypes,
    'relationTypeAliases': relationTypeAliases,
    'personTitleSuffixes': personTitleSuffixes,
    'genericPersonTerms': genericPersonTerms,
    'bookNamePriors': bookNamePriors,
  };

  static AiGraphRuleWords fromJson(Object? json) {
    if (json is! Map) return const AiGraphRuleWords();
    final map = Map<String, dynamic>.from(json);
    final defaults = const AiGraphRuleWords();
    return AiGraphRuleWords(
      appendixUnits:
          (map['appendixUnits'] as List?)?.cast<String>() ??
          defaults.appendixUnits,
      metadataUnits:
          (map['metadataUnits'] as List?)?.cast<String>() ??
          defaults.metadataUnits,
      citationQuoteTemplates:
          (map['citationQuoteTemplates'] as List?)?.cast<String>() ??
          defaults.citationQuoteTemplates,
      relationTypes:
          (map['relationTypes'] as List?)?.cast<String>() ??
          defaults.relationTypes,
      relationTypeAliases: map['relationTypeAliases'] is Map
          ? Map<String, String>.from(
              (map['relationTypeAliases'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
          : defaults.relationTypeAliases,
      personTitleSuffixes:
          (map['personTitleSuffixes'] as List?)?.cast<String>() ??
          defaults.personTitleSuffixes,
      genericPersonTerms:
          (map['genericPersonTerms'] as List?)?.cast<String>() ??
          defaults.genericPersonTerms,
      bookNamePriors: map['bookNamePriors'] is Map
          ? {
              for (final entry in (map['bookNamePriors'] as Map).entries)
                entry.key.toString(): {
                  for (final alias in (entry.value as Map? ?? const {}).entries)
                    alias.key.toString(): alias.value.toString(),
                },
            }
          : defaults.bookNamePriors,
    );
  }
}

/// Non-secret AI preferences. The API key lives only in secure storage.
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.providerKind = AiProviderKind.openai,
    this.customProtocol = AiApiProtocol.openai,
    this.baseUrl = '',
    this.model = '',
    this.allowUnreadContext = false,
    this.translation = const AiTranslationPreferences(),
    this.searchProviderKind = AiSearchProviderKind.tavily,
    this.graphRuleWords = const AiGraphRuleWords(),
  });

  final bool enabled;
  final AiProviderKind providerKind;

  /// API wire format when [providerKind] is [AiProviderKind.custom].
  /// Presets ignore this and use [AiProviderKind.fixedProtocol].
  final AiApiProtocol customProtocol;

  /// Effective base URL. Empty means "use the preset default".
  final String baseUrl;

  /// Model id. Empty means "use the preset default".
  final String model;

  /// When true, knowledge-graph generation/display may include unread sections.
  /// Chat and outline always use their explicit whole-work scopes.
  final bool allowUnreadContext;

  /// Selection / whole-book translation preferences (not per-provider).
  final AiTranslationPreferences translation;

  /// Web search backend for book-chat「联网」(key in secure storage).
  final AiSearchProviderKind searchProviderKind;

  /// Word lists driving the graph pipeline hard rules.
  final AiGraphRuleWords graphRuleWords;

  /// Resolved protocol for the current provider selection.
  AiApiProtocol get resolvedProtocol =>
      providerKind.fixedProtocol ?? customProtocol;

  bool get usesAnthropicProtocol => resolvedProtocol == AiApiProtocol.anthropic;

  bool get usesOpenAiProtocol => resolvedProtocol == AiApiProtocol.openai;

  String get resolvedBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.isNotEmpty) return _stripTrailingSlash(trimmed);
    return _stripTrailingSlash(providerKind.defaultBaseUrl);
  }

  /// Null when the endpoint is safe and syntactically usable.
  ///
  /// Plain HTTP is deliberately limited to the built-in, no-key local backend
  /// on loopback. A BYOK secret must never cross the network in clear text.
  String? get endpointValidationError {
    final raw = resolvedBaseUrl.trim();
    if (raw.isEmpty) return '请填写接口地址';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '接口地址格式无效';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return '接口地址只支持 HTTPS；本机 Ollama 可使用 HTTP';
    }
    if (scheme == 'https') return null;
    final host = uri.host.toLowerCase();
    final loopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (providerKind.isLocalBackend && !requiresApiKey && loopback) return null;
    return '携带 API Key 的接口必须使用 HTTPS';
  }

  bool get hasValidEndpoint => endpointValidationError == null;

  String get resolvedModel {
    final trimmed = model.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return providerKind.defaultModel;
  }

  /// Cloud presets always need an API key; local backends (Ollama) skip it.
  bool get requiresApiKey => !providerKind.isLocalBackend;

  AiSettings copyWith({
    bool? enabled,
    AiProviderKind? providerKind,
    AiApiProtocol? customProtocol,
    String? baseUrl,
    String? model,
    bool? allowUnreadContext,
    AiTranslationPreferences? translation,
    AiSearchProviderKind? searchProviderKind,
    AiGraphRuleWords? graphRuleWords,
  }) {
    return AiSettings(
      enabled: enabled ?? this.enabled,
      providerKind: providerKind ?? this.providerKind,
      customProtocol: customProtocol ?? this.customProtocol,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      allowUnreadContext: allowUnreadContext ?? this.allowUnreadContext,
      translation: translation ?? this.translation,
      searchProviderKind: searchProviderKind ?? this.searchProviderKind,
      graphRuleWords: graphRuleWords ?? this.graphRuleWords,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'providerKind': providerKind.storageValue,
    'customProtocol': customProtocol.storageValue,
    'baseUrl': baseUrl,
    'model': model,
    'allowUnreadContext': allowUnreadContext,
    'translation': translation.toJson(),
    'searchProviderKind': searchProviderKind.storageValue,
    'graphRuleWords': graphRuleWords.toJson(),
  };

  static AiSettings fromJson(Map<String, dynamic> json) {
    final translationRaw = json['translation'];
    return AiSettings(
      enabled: json['enabled'] as bool? ?? false,
      providerKind: AiProviderKind.fromStorage(json['providerKind'] as String?),
      customProtocol: AiApiProtocol.fromStorage(
        json['customProtocol'] as String?,
      ),
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      allowUnreadContext: json['allowUnreadContext'] as bool? ?? false,
      translation: AiTranslationPreferences.fromJson(
        translationRaw is Map
            ? Map<String, dynamic>.from(translationRaw)
            : null,
      ),
      searchProviderKind: AiSearchProviderKind.fromStorage(
        json['searchProviderKind'] as String?,
      ),
      graphRuleWords: AiGraphRuleWords.fromJson(json['graphRuleWords']),
    );
  }

  static String _stripTrailingSlash(String value) {
    if (value.length > 1 && value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}

// Translation preferences for selection / (future) whole-book AI translate.
// See docs/specs/ai-translation.md.

enum AiTranslationLanguage {
  zhHans,
  en,
  zhHant,
  ja,
  ko;

  String get storageValue => switch (this) {
    AiTranslationLanguage.zhHans => 'zh-Hans',
    AiTranslationLanguage.en => 'en',
    AiTranslationLanguage.zhHant => 'zh-Hant',
    AiTranslationLanguage.ja => 'ja',
    AiTranslationLanguage.ko => 'ko',
  };

  /// UI label (sentence case / product Chinese).
  String get displayName => switch (this) {
    AiTranslationLanguage.zhHans => '简体中文',
    AiTranslationLanguage.en => 'English',
    AiTranslationLanguage.zhHant => '繁體中文',
    AiTranslationLanguage.ja => '日本語',
    AiTranslationLanguage.ko => '한국어',
  };

  /// Name used inside model prompts.
  String get promptName => switch (this) {
    AiTranslationLanguage.zhHans => 'Simplified Chinese (简体中文)',
    AiTranslationLanguage.en => 'English',
    AiTranslationLanguage.zhHant => 'Traditional Chinese (繁體中文)',
    AiTranslationLanguage.ja => 'Japanese (日本語)',
    AiTranslationLanguage.ko => 'Korean (한국어)',
  };

  static AiTranslationLanguage fromStorage(String? value) {
    for (final lang in AiTranslationLanguage.values) {
      if (lang.storageValue == value) return lang;
    }
    return AiTranslationLanguage.zhHans;
  }

  /// Alternate language for "改译为…" when source already matches target.
  AiTranslationLanguage get flipSuggestion => switch (this) {
    AiTranslationLanguage.zhHans || AiTranslationLanguage.zhHant =>
      AiTranslationLanguage.en,
    AiTranslationLanguage.en => AiTranslationLanguage.zhHans,
    AiTranslationLanguage.ja || AiTranslationLanguage.ko =>
      AiTranslationLanguage.zhHans,
  };
}

enum AiTranslationDirectionMode {
  /// Always translate into [AiTranslationPreferences.targetLanguage].
  fixedTarget,

  /// If source ≈ target, flip to the opposite of a zh↔en pair.
  smartBidi;

  String get storageValue => name;

  String get displayName => switch (this) {
    AiTranslationDirectionMode.fixedTarget => '固定译到目标语言',
    AiTranslationDirectionMode.smartBidi => '智能双向',
  };

  static AiTranslationDirectionMode fromStorage(String? value) {
    for (final mode in AiTranslationDirectionMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return AiTranslationDirectionMode.fixedTarget;
  }
}

enum AiTranslationStyle {
  natural,
  literal,
  academic;

  String get storageValue => name;

  String get displayName => switch (this) {
    AiTranslationStyle.natural => '通顺意译',
    AiTranslationStyle.literal => '偏直译',
    AiTranslationStyle.academic => '学术意译',
  };

  String get promptHint => switch (this) {
    AiTranslationStyle.natural =>
      'Prefer natural, fluent phrasing suitable for continuous reading.',
    AiTranslationStyle.literal =>
      'Prefer a closer, more literal rendering; keep structure when possible.',
    AiTranslationStyle.academic =>
      'Prefer clear modern prose for scholarly or classical source text; do not fake archaic style.',
  };

  static AiTranslationStyle fromStorage(String? value) {
    for (final style in AiTranslationStyle.values) {
      if (style.storageValue == value) return style;
    }
    return AiTranslationStyle.natural;
  }
}

enum AiTranslationDisplayMode {
  targetOnly,
  bilingual;

  String get storageValue => name;

  String get displayName => switch (this) {
    AiTranslationDisplayMode.targetOnly => '仅译文',
    AiTranslationDisplayMode.bilingual => '对照',
  };

  static AiTranslationDisplayMode fromStorage(String? value) {
    for (final mode in AiTranslationDisplayMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return AiTranslationDisplayMode.targetOnly;
  }
}

enum AiTranslationNoteFormat {
  translationOnly,
  sourceAndTranslation;

  String get storageValue => name;

  String get displayName => switch (this) {
    AiTranslationNoteFormat.translationOnly => '仅译文',
    AiTranslationNoteFormat.sourceAndTranslation => '原文 + 译文',
  };

  static AiTranslationNoteFormat fromStorage(String? value) {
    for (final format in AiTranslationNoteFormat.values) {
      if (format.storageValue == value) return format;
    }
    return AiTranslationNoteFormat.translationOnly;
  }
}

/// Defaults from docs/specs/ai-translation.md §1.
class AiTranslationPreferences {
  const AiTranslationPreferences({
    this.targetLanguage = AiTranslationLanguage.zhHans,
    this.directionMode = AiTranslationDirectionMode.fixedTarget,
    this.style = AiTranslationStyle.natural,
    this.displayMode = AiTranslationDisplayMode.targetOnly,
    this.includeContext = false,
    this.contextChars = 100,
    this.noteFormat = AiTranslationNoteFormat.translationOnly,
  });

  final AiTranslationLanguage targetLanguage;
  final AiTranslationDirectionMode directionMode;
  final AiTranslationStyle style;
  final AiTranslationDisplayMode displayMode;
  final bool includeContext;
  final int contextChars;
  final AiTranslationNoteFormat noteFormat;

  AiTranslationPreferences copyWith({
    AiTranslationLanguage? targetLanguage,
    AiTranslationDirectionMode? directionMode,
    AiTranslationStyle? style,
    AiTranslationDisplayMode? displayMode,
    bool? includeContext,
    int? contextChars,
    AiTranslationNoteFormat? noteFormat,
  }) {
    return AiTranslationPreferences(
      targetLanguage: targetLanguage ?? this.targetLanguage,
      directionMode: directionMode ?? this.directionMode,
      style: style ?? this.style,
      displayMode: displayMode ?? this.displayMode,
      includeContext: includeContext ?? this.includeContext,
      contextChars: contextChars ?? this.contextChars,
      noteFormat: noteFormat ?? this.noteFormat,
    );
  }

  Map<String, Object?> toJson() => {
    'targetLanguage': targetLanguage.storageValue,
    'directionMode': directionMode.storageValue,
    'style': style.storageValue,
    'displayMode': displayMode.storageValue,
    'includeContext': includeContext,
    'contextChars': contextChars,
    'noteFormat': noteFormat.storageValue,
  };

  static AiTranslationPreferences fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiTranslationPreferences();
    final chars = json['contextChars'];
    return AiTranslationPreferences(
      targetLanguage: AiTranslationLanguage.fromStorage(
        json['targetLanguage'] as String?,
      ),
      directionMode: AiTranslationDirectionMode.fromStorage(
        json['directionMode'] as String?,
      ),
      style: AiTranslationStyle.fromStorage(json['style'] as String?),
      displayMode: AiTranslationDisplayMode.fromStorage(
        json['displayMode'] as String?,
      ),
      includeContext: json['includeContext'] as bool? ?? false,
      contextChars: chars is int
          ? chars.clamp(40, 400)
          : 100,
      noteFormat: AiTranslationNoteFormat.fromStorage(
        json['noteFormat'] as String?,
      ),
    );
  }
}

/// Per-request overrides for one result sheet (not persisted).
///
/// [targetLanguage] is only set when the user explicitly picks a language in
/// the result card. Leaving it null lets [AiLanguageService] apply global
/// prefs + [AiTranslationDirectionMode] (including smart bi-directional flip).
class AiTranslationRequestOptions {
  const AiTranslationRequestOptions({
    this.targetLanguage,
    this.directionMode,
    this.style,
    this.contextBefore,
    this.contextAfter,
    this.bookTitle,
    this.bookAuthor,
    this.chapterTitle,
  });

  /// User override from the result-card chip; null = use settings prefs.
  final AiTranslationLanguage? targetLanguage;
  final AiTranslationDirectionMode? directionMode;
  final AiTranslationStyle? style;
  final String? contextBefore;
  final String? contextAfter;

  /// Library / EPUB work identity — helps proper nouns and established names.
  final String? bookTitle;
  final String? bookAuthor;
  final String? chapterTitle;
}

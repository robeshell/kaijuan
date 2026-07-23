import 'book_theme.dart';

/// Where the reading face comes from.
enum BookFontKind { book, system, user }

/// Persisted body-font choice (book / system id / installed user id).
class BookFontSelection {
  const BookFontSelection.book()
      : kind = BookFontKind.book,
        systemId = null,
        userFontId = null;

  const BookFontSelection.system(this.systemId)
      : kind = BookFontKind.system,
        userFontId = null;

  const BookFontSelection.user(this.userFontId)
      : kind = BookFontKind.user,
        systemId = null;

  factory BookFontSelection.fromJson(Map<String, dynamic>? json) {
    if (json == null) return BookFontSelection.system(BookSystemFont.defaultId);
    final kind = BookFontKind.values.asNameMap()[json['kind'] as String?];
    switch (kind) {
      case BookFontKind.book:
        return const BookFontSelection.book();
      case BookFontKind.user:
        final id = json['userFontId'] as String?;
        if (id == null || id.isEmpty) {
          return BookFontSelection.system(BookSystemFont.defaultId);
        }
        return BookFontSelection.user(id);
      case BookFontKind.system:
      case null:
        final id = json['systemId'] as String?;
        if (id != null && BookSystemFont.byId(id) != null) {
          return BookFontSelection.system(id);
        }
        return BookFontSelection.system(BookSystemFont.defaultId);
    }
  }

  /// Maps legacy [BookBodyFont] / `bodyFont` string storage.
  factory BookFontSelection.fromLegacyBodyFont(String? value) {
    return switch (value) {
      null || 'defaultFont' => BookFontSelection.system(BookSystemFont.defaultId),
      'system' => BookFontSelection.system(BookSystemFont.systemUiId),
      'georgia' ||
      'crimsonPro' ||
      'libreBaskerville' ||
      'lora' ||
      'notoSerif' ||
      'ptSerif' =>
        BookFontSelection.system(BookSystemFont.songtiId),
      'lexend' || 'nunito' || 'ptSans' || 'publicSans' =>
        BookFontSelection.system(BookSystemFont.defaultId),
      _ => BookFontSelection.system(BookSystemFont.defaultId),
    };
  }

  final BookFontKind kind;
  final String? systemId;
  final String? userFontId;

  static final BookFontSelection defaultSelection =
      BookFontSelection.system(BookSystemFont.defaultId);

  String get label {
    switch (kind) {
      case BookFontKind.book:
        return '图书自带';
      case BookFontKind.system:
        return BookSystemFont.byId(systemId!)?.label ?? '默认字体';
      case BookFontKind.user:
        return '用户字体';
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (systemId != null) 'systemId': systemId,
        if (userFontId != null) 'userFontId': userFontId,
      };

  @override
  bool operator ==(Object other) =>
      other is BookFontSelection &&
      other.kind == kind &&
      other.systemId == systemId &&
      other.userFontId == userFontId;

  @override
  int get hashCode => Object.hash(kind, systemId, userFontId);
}

/// Curated system CSS stacks (no font files).
class BookSystemFont {
  const BookSystemFont({
    required this.id,
    required this.label,
    required this.cssFontName,
    this.previewFamily,
  });

  static const defaultId = 'default';
  static const systemUiId = 'systemUi';
  static const songtiId = 'songti';
  static const kaitiId = 'kaiti';
  static const heitiId = 'heiti';
  static const fangsongId = 'fangsong';
  static const yaheiId = 'yahei';

  final String id;
  final String label;
  final String cssFontName;
  final String? previewFamily;

  static final List<BookSystemFont> all = [
    BookSystemFont(
      id: defaultId,
      label: '默认字体',
      cssFontName: BookReadingTheme.cssReadingFontFamily,
    ),
    const BookSystemFont(
      id: systemUiId,
      label: '系统界面',
      cssFontName: 'system',
    ),
    const BookSystemFont(
      id: heitiId,
      label: '黑体',
      cssFontName:
          '"PingFang SC", "Heiti SC", "Noto Sans SC", "Microsoft YaHei", sans-serif',
      previewFamily: 'PingFang SC',
    ),
    const BookSystemFont(
      id: songtiId,
      label: '宋体',
      cssFontName:
          '"Songti SC", "STSong", "Noto Serif SC", "SimSun", serif',
      previewFamily: 'Songti SC',
    ),
    const BookSystemFont(
      id: kaitiId,
      label: '楷体',
      cssFontName: '"Kaiti SC", "STKaiti", "KaiTi", "Noto Serif SC", serif',
      previewFamily: 'Kaiti SC',
    ),
    const BookSystemFont(
      id: fangsongId,
      label: '仿宋',
      cssFontName: '"STFangsong", "FangSong", "Songti SC", serif',
      previewFamily: 'STFangsong',
    ),
    const BookSystemFont(
      id: yaheiId,
      label: '雅黑',
      cssFontName:
          '"Microsoft YaHei", "PingFang SC", "Noto Sans SC", sans-serif',
      previewFamily: 'Microsoft YaHei',
    ),
  ];

  static BookSystemFont? byId(String id) {
    for (final font in all) {
      if (font.id == id) return font;
    }
    return null;
  }
}

/// How a user font entered the local pool.
enum BookUserFontSource { download, import }

/// Installed user face on disk under support/fonts.
class BookUserFont {
  const BookUserFont({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.source,
    this.catalogId,
  });

  factory BookUserFont.fromJson(Map<String, dynamic> json) {
    return BookUserFont(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? json['id'] as String,
      fileName: json['fileName'] as String,
      source: BookUserFontSource.values.asNameMap()[json['source'] as String?] ??
          BookUserFontSource.import,
      catalogId: json['catalogId'] as String?,
    );
  }

  final String id;
  final String displayName;
  final String fileName;
  final BookUserFontSource source;
  final String? catalogId;

  /// Foliate `fontName` / `@font-face` family (quoted CSS ident).
  String get cssFamilyName => '"KaikaUserFont_$id"';

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'fileName': fileName,
        'source': source.name,
        if (catalogId != null) 'catalogId': catalogId,
      };
}

/// Built-in downloadable OFL catalog entry (China-reachable mirrors).
class BookCatalogFont {
  const BookCatalogFont({
    required this.id,
    required this.displayName,
    required this.license,
    required this.approxBytes,
    required this.fileExtension,
    required this.urls,
  });

  final String id;
  final String displayName;
  final String license;
  final int approxBytes;
  final String fileExtension;

  /// Try in order: npmmirror first when available, then jsDelivr.
  final List<String> urls;

  String get sizeLabel {
    final mb = approxBytes / (1024 * 1024);
    if (mb >= 10) return '${mb.round()} MB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// SIL OFL Chinese faces; URLs verified for npmmirror / jsDelivr.
  /// Smaller files first in the panel; 霞鹜文楷用 woff2（约 7MB，比 woff 少约 3MB）。
  static const List<BookCatalogFont> all = [
    BookCatalogFont(
      id: 'smiley-sans',
      displayName: '得意黑',
      license: 'SIL OFL 1.1',
      approxBytes: 1150924,
      fileExtension: 'woff2',
      urls: [
        'https://cdn.jsdelivr.net/npm/@fontpkg/smiley-sans@2.0.4/SmileySans-Oblique.ttf.woff2',
        'https://registry.npmmirror.com/@fontpkg/smiley-sans/2.0.4/files/SmileySans-Oblique.ttf.woff2',
      ],
    ),
    BookCatalogFont(
      id: 'glow-sans',
      displayName: '未来荧黑',
      license: 'SIL OFL 1.1',
      approxBytes: 9119372,
      fileExtension: 'otf',
      urls: [
        'https://cdn.jsdelivr.net/npm/@fontpkg/glow-sans-sc@0.93.2/GlowSansSC-Normal-Regular.otf',
        'https://registry.npmmirror.com/@fontpkg/glow-sans-sc/0.93.2/files/GlowSansSC-Normal-Regular.otf',
      ],
    ),
    BookCatalogFont(
      id: 'lxgw-wenkai',
      displayName: '霞鹜文楷',
      license: 'SIL OFL 1.1',
      approxBytes: 7231496,
      fileExtension: 'woff2',
      urls: [
        // jsDelivr 优先：同体积下通常比 registry 拉大文件更稳；woff2 比原 woff 少约 3MB。
        'https://cdn.jsdelivr.net/npm/@fontsource/lxgw-wenkai@5.3.0/files/lxgw-wenkai-latin-500-normal.woff2',
        'https://registry.npmmirror.com/@fontsource/lxgw-wenkai/5.3.0/files/files/lxgw-wenkai-latin-500-normal.woff2',
      ],
    ),
  ];

  static BookCatalogFont? byId(String id) {
    for (final font in all) {
      if (font.id == id) return font;
    }
    return null;
  }
}

import 'package:flutter/foundation.dart';

import '../../app/book_reading_preferences.dart';
import '../../readers/book/book_theme.dart';

/// Owns reflow presentation preferences and their persistence.
///
/// Reading position remains in [BookReaderController]. A mode change asks the
/// reader to freeze its locator through [onReadingModeWillChange] before the
/// persisted preference is updated.
class BookReaderPreferencesController extends ChangeNotifier {
  BookReaderPreferencesController({
    BookReadingPreferences? preferences,
    required this.scrollModeEnabled,
    required this.onReadingModeWillChange,
  }) : _preferences = preferences,
       _fontSize =
           preferences?.fontSize ?? BookReadingPreferences.defaultFontSize,
       _lineHeight =
           preferences?.lineHeight ?? BookReadingPreferences.defaultLineHeight,
       _readingTheme = preferences?.readingTheme ?? BookReadingTheme.paper,
       _margin = preferences?.margin ?? BookReadingPreferences.defaultMargin,
       _verticalMargin =
           preferences?.verticalMargin ??
           BookReadingPreferences.defaultVerticalMargin,
       _bold = preferences?.bold ?? BookReadingPreferences.defaultBold,
       _brightness =
           preferences?.brightness ?? BookReadingPreferences.defaultBrightness,
       _fontSelection =
           preferences?.fontSelection ??
           BookReadingPreferences.defaultFontSelection,
       _letterSpacing =
           preferences?.letterSpacing ??
           BookReadingPreferences.defaultLetterSpacing,
       _paragraphSpacing =
           preferences?.paragraphSpacing ??
           BookReadingPreferences.defaultParagraphSpacing,
       _textAlign =
           preferences?.textAlign ?? BookReadingPreferences.defaultTextAlign,
       _firstLineIndent =
           preferences?.firstLineIndent ??
           BookReadingPreferences.defaultFirstLineIndent,
       _hyphenate =
           preferences?.hyphenate ?? BookReadingPreferences.defaultHyphenate,
       _readingMode = scrollModeEnabled
           ? preferences?.readingMode ??
                 BookReadingPreferences.defaultReadingMode
           : BookReadingMode.page,
       _pageTurnEffect =
           preferences?.pageTurnEffect ??
           BookReadingPreferences.defaultPageTurnEffect {
    preferences?.fontStore.addListener(_onFontStoreChanged);
  }

  final BookReadingPreferences? _preferences;
  final bool scrollModeEnabled;
  final VoidCallback onReadingModeWillChange;

  double _fontSize;
  double _lineHeight;
  BookReadingTheme _readingTheme;
  double _margin;
  double _verticalMargin;
  bool _bold;
  double _brightness;
  BookFontSelection _fontSelection;
  double _letterSpacing;
  double _paragraphSpacing;
  BookTextAlign _textAlign;
  bool _firstLineIndent;
  bool _hyphenate;
  BookReadingMode _readingMode;
  BookPageTurnEffect _pageTurnEffect;
  bool _disposed = false;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  BookReadingTheme get readingTheme => _readingTheme;
  double get margin => _margin;
  double get verticalMargin => _verticalMargin;
  bool get bold => _bold;
  double get brightness => _brightness;
  BookFontSelection get fontSelection => _fontSelection;
  BookFontStore? get fontStore => _preferences?.fontStore;
  double get letterSpacing => _letterSpacing;
  double get paragraphSpacing => _paragraphSpacing;
  BookTextAlign get textAlign => _textAlign;
  bool get firstLineIndent => _firstLineIndent;
  bool get hyphenate => _hyphenate;
  BookReadingMode get readingMode => _readingMode;
  BookPageTurnEffect get pageTurnEffect => _pageTurnEffect;

  String get fontLabel => switch (_fontSelection.kind) {
    BookFontKind.book => '图书自带',
    BookFontKind.system =>
      BookSystemFont.byId(_fontSelection.systemId!)?.label ?? '默认字体',
    BookFontKind.user =>
      fontStore?.byId(_fontSelection.userFontId!)?.displayName ?? '用户字体',
  };

  void _onFontStoreChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    final next = size.clamp(
      BookReadingPreferences.minFontSize,
      BookReadingPreferences.maxFontSize,
    );
    if (next == _fontSize) return;
    _fontSize = next;
    notifyListeners();
    await _preferences?.setFontSize(next);
  }

  Future<void> changeFontSize(double delta) => setFontSize(_fontSize + delta);

  Future<void> setLineHeight(double height) async {
    final next = height.clamp(
      BookReadingPreferences.minLineHeight,
      BookReadingPreferences.maxLineHeight,
    );
    if (next == _lineHeight) return;
    _lineHeight = next;
    notifyListeners();
    await _preferences?.setLineHeight(next);
  }

  Future<void> setReadingTheme(BookReadingTheme theme) async {
    if (theme == _readingTheme) return;
    _readingTheme = theme;
    notifyListeners();
    await _preferences?.setReadingTheme(theme);
  }

  Future<void> setMargin(double margin) async {
    final next = margin.clamp(
      BookReadingPreferences.minMargin,
      BookReadingPreferences.maxMargin,
    );
    if (next == _margin) return;
    _margin = next;
    notifyListeners();
    await _preferences?.setMargin(next);
  }

  Future<void> setVerticalMargin(double margin) async {
    final next = margin.clamp(
      BookReadingPreferences.minVerticalMargin,
      BookReadingPreferences.maxVerticalMargin,
    );
    if (next == _verticalMargin) return;
    _verticalMargin = next;
    notifyListeners();
    await _preferences?.setVerticalMargin(next);
  }

  Future<void> setBold(bool bold) async {
    if (bold == _bold) return;
    _bold = bold;
    notifyListeners();
    await _preferences?.setBold(bold);
  }

  Future<void> setBrightness(double value) async {
    final next = value.clamp(
      BookReadingPreferences.minBrightness,
      BookReadingPreferences.maxBrightness,
    );
    if (next != _brightness) {
      _brightness = next;
      notifyListeners();
    }
    await _preferences?.setBrightness(next);
  }

  /// Live dimming while dragging; persist with [setBrightness] on drag end.
  void previewBrightness(double value) {
    final next = value.clamp(
      BookReadingPreferences.minBrightness,
      BookReadingPreferences.maxBrightness,
    );
    if (next == _brightness) return;
    _brightness = next;
    notifyListeners();
  }

  Future<void> setFontSelection(BookFontSelection selection) async {
    if (selection == _fontSelection) return;
    if (selection.kind == BookFontKind.user) {
      final id = selection.userFontId;
      if (id == null || fontStore?.byId(id) == null) return;
    }
    _fontSelection = selection;
    notifyListeners();
    await _preferences?.setFontSelection(selection);
  }

  Future<String?> downloadCatalogFont(BookCatalogFont catalog) async {
    final store = fontStore;
    if (store == null) return '字体存储未就绪';
    try {
      final font = await store.downloadCatalogFont(catalog);
      await setFontSelection(BookFontSelection.user(font.id));
      return null;
    } catch (error) {
      debugPrint('[Font] download failed: $error');
      return '字体下载失败';
    }
  }

  Future<String?> importFontFile(String path) async {
    final store = fontStore;
    if (store == null) return '字体存储未就绪';
    try {
      final font = await store.importFontFile(path);
      await setFontSelection(BookFontSelection.user(font.id));
      return null;
    } catch (error) {
      debugPrint('[Font] import failed: $error');
      return '字体导入失败';
    }
  }

  Future<void> deleteUserFont(String id) async {
    final store = fontStore;
    if (store == null) return;
    final wasSelected =
        _fontSelection.kind == BookFontKind.user &&
        _fontSelection.userFontId == id;
    await store.deleteUserFont(id);
    if (wasSelected) {
      await setFontSelection(BookReadingPreferences.defaultFontSelection);
    } else {
      notifyListeners();
    }
  }

  Future<void> setLetterSpacing(double spacing) async {
    final next = spacing.clamp(
      BookReadingPreferences.minLetterSpacing,
      BookReadingPreferences.maxLetterSpacing,
    );
    if (next == _letterSpacing) return;
    _letterSpacing = next;
    notifyListeners();
    await _preferences?.setLetterSpacing(next);
  }

  Future<void> setParagraphSpacing(double spacing) async {
    final next = spacing.clamp(
      BookReadingPreferences.minParagraphSpacing,
      BookReadingPreferences.maxParagraphSpacing,
    );
    if (next == _paragraphSpacing) return;
    _paragraphSpacing = next;
    notifyListeners();
    await _preferences?.setParagraphSpacing(next);
  }

  Future<void> setTextAlign(BookTextAlign align) async {
    if (align == _textAlign) return;
    _textAlign = align;
    notifyListeners();
    await _preferences?.setTextAlign(align);
  }

  Future<void> setFirstLineIndent(bool enabled) async {
    if (enabled == _firstLineIndent) return;
    _firstLineIndent = enabled;
    notifyListeners();
    await _preferences?.setFirstLineIndent(enabled);
  }

  Future<void> setHyphenate(bool enabled) async {
    if (enabled == _hyphenate) return;
    _hyphenate = enabled;
    notifyListeners();
    await _preferences?.setHyphenate(enabled);
  }

  Future<void> setReadingMode(BookReadingMode mode) async {
    if (mode == BookReadingMode.scroll && !scrollModeEnabled) return;
    if (mode == _readingMode) return;
    onReadingModeWillChange();
    _readingMode = mode;
    notifyListeners();
    await _preferences?.setReadingMode(mode);
  }

  Future<void> setPageTurnEffect(BookPageTurnEffect effect) async {
    if (effect == _pageTurnEffect) return;
    _pageTurnEffect = effect;
    notifyListeners();
    await _preferences?.setPageTurnEffect(effect);
  }

  @override
  void dispose() {
    _disposed = true;
    _preferences?.fontStore.removeListener(_onFontStoreChanged);
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/comic_reading_preferences.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/comic/comic_models.dart';
import '../../readers/comic/comic_page_cache.dart';
import '../../readers/comic/comic_session.dart';

/// Owns comic reading session state: open archive, page index, mode, chrome.
class ComicReaderController extends ChangeNotifier {
  ComicReaderController({
    required AppDatabase database,
    required ReadingItem item,
    ComicReadingPreferences? readingPreferences,
  }) : this._(database, item, readingPreferences);

  ComicReaderController._(
    this._database,
    this.item,
    ComicReadingPreferences? readingPreferences,
  )   : _readingPreferences = readingPreferences,
        _mode = readingPreferences?.mode ?? ComicReaderMode.slide,
        _direction = readingPreferences?.direction ?? ComicReadDirection.ltr,
        _readingTheme =
            readingPreferences?.readingTheme ?? ComicReadingTheme.comicDefault;

  final AppDatabase _database;
  final ReadingItem item;
  final ComicReadingPreferences? _readingPreferences;

  ComicSession? _session;
  ComicPageCache? _cache;
  Object? _openError;

  int _pageIndex = 0;
  bool _chromeVisible = false;
  ComicReaderMode _mode;
  ComicReadDirection _direction;
  ComicReadingTheme _readingTheme;
  bool _ready = false;
  bool _disposed = false;

  /// Slider draft while the user is dragging; committed on changeEnd.
  int? _sliderPreview;

  ComicSession? get session => _session;
  ComicPageCache? get cache => _cache;
  Object? get openError => _openError;
  bool get isReady => _ready;
  int get pageIndex => _pageIndex;
  int get pageCount => _session?.pageCount ?? item.pageCount;
  bool get chromeVisible => _chromeVisible;
  ComicReaderMode get mode => _mode;
  ComicReadDirection get direction => _direction;
  ComicReadingTheme get readingTheme => _readingTheme;
  int get displayPage => _sliderPreview ?? _pageIndex;

  String get pageLabel {
    final total = pageCount;
    if (total <= 0) return '—';
    return '${displayPage + 1} / $total';
  }

  double get progressFraction {
    final total = pageCount;
    if (total <= 1) return total == 1 ? 1.0 : 0.0;
    return displayPage / (total - 1);
  }

  Future<void> open() async {
    try {
      final session = await ComicSession.open(item.filePath);
      if (_disposed) {
        await session.close();
        return;
      }
      _session = session;
      _cache = ComicPageCache(session: session);
      await _restoreProgress();
      await _database.touchLastOpened(item.id, DateTime.now());
      _ready = true;
      _openError = null;
      _cache!.preloadAround(_pageIndex);
      notifyListeners();
    } catch (e) {
      _openError = e;
      _ready = false;
      notifyListeners();
    }
  }

  Future<void> _restoreProgress() async {
    final row = await _database.progressFor(item.id);
    if (row == null) return;
    final locator = ComicLocator.tryDecode(row.locatorJson);
    final valid = locator?.validated(
      pageCount: pageCount,
      itemPageOrderVersion: item.pageOrderVersion,
    );
    if (valid != null) {
      _pageIndex = valid.pageIndex;
    }
  }

  void toggleChrome() {
    _chromeVisible = !_chromeVisible;
    notifyListeners();
  }

  void hideChrome() {
    if (!_chromeVisible) return;
    _chromeVisible = false;
    notifyListeners();
  }

  void showChrome() {
    if (_chromeVisible) return;
    _chromeVisible = true;
    notifyListeners();
  }

  void setMode(ComicReaderMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    unawaited(_readingPreferences?.setMode(mode));
  }

  void setDirection(ComicReadDirection direction) {
    if (_direction == direction) return;
    _direction = direction;
    notifyListeners();
    unawaited(_readingPreferences?.setDirection(direction));
  }

  void setReadingTheme(ComicReadingTheme theme) {
    if (_readingTheme == theme) return;
    _readingTheme = theme;
    notifyListeners();
    unawaited(_readingPreferences?.setReadingTheme(theme));
  }

  /// Semantic "next" — toward the end of the book.
  /// In spread mode, advances by one spread (two pages).
  void goForward() {
    if (_mode == ComicReaderMode.spread) {
      jumpTo(comicSpreadStep(_pageIndex, delta: 1, pageCount: pageCount));
    } else {
      jumpTo(_pageIndex + 1);
    }
  }

  /// Semantic "previous" — toward the start of the book.
  /// In spread mode, retreats by one spread (two pages).
  void goBackward() {
    if (_mode == ComicReaderMode.spread) {
      jumpTo(comicSpreadStep(_pageIndex, delta: -1, pageCount: pageCount));
    } else {
      jumpTo(_pageIndex - 1);
    }
  }

  void jumpTo(int index) {
    final total = pageCount;
    if (total <= 0) return;
    final clamped = index.clamp(0, total - 1);
    if (clamped == _pageIndex) return;
    _pageIndex = clamped;
    _sliderPreview = null;
    _cache?.preloadAround(_pageIndex);
    notifyListeners();
    unawaited(_persistProgress());
  }

  /// Vertical list reports the page at the viewport; same path as [jumpTo].
  /// Scroll bodies must gate re-entrant animate/jump with local flags.
  void reportVisiblePage(int index) => jumpTo(index);

  void onSliderChanged(double value) {
    final total = pageCount;
    if (total <= 0) return;
    _sliderPreview = value.round().clamp(0, total - 1);
    notifyListeners();
  }

  void onSliderChangeEnd(double value) {
    final total = pageCount;
    if (total <= 0) return;
    final target = value.round().clamp(0, total - 1);
    _sliderPreview = null;
    jumpTo(target);
  }

  /// Spread layout for [anchor] (primary page index).
  PageSpread spreadFor(int anchor) {
    if (_mode != ComicReaderMode.spread || pageCount <= 0) {
      final safe = pageCount <= 0 ? 0 : anchor.clamp(0, pageCount - 1);
      return PageSpread.single(safe);
    }
    return comicSpreadFor(anchor, pageCount: pageCount);
  }

  Future<void> _persistProgress() async {
    if (_session == null || pageCount <= 0) return;
    final locator = ComicLocator(
      pageIndex: _pageIndex,
      pageOrderVersion: ComicPageOrder.version,
    );
    final fraction = pageCount <= 1 ? 1.0 : _pageIndex / (pageCount - 1);
    await _database.upsertProgress(
      itemId: item.id,
      locatorJson: locator.encode(),
      progressFraction: fraction,
      updatedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_persistProgress());
    _cache?.dispose();
    unawaited(_session?.close() ?? Future<void>.value());
    super.dispose();
  }
}

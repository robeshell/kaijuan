import 'package:flutter/foundation.dart';

import '../../readers/book/foliate_js_bridge.dart';

/// Owns book-search and body-image overlay state plus their Foliate bridge.
class BookSearchController extends ChangeNotifier {
  BookSearchController({
    required this.beforeOpenOverlay,
    required this.onSearchHitSelected,
  });

  final VoidCallback beforeOpenOverlay;
  final ValueChanged<FoliateSearchHit> onSearchHitSelected;

  bool _open = false;
  String _query = '';
  bool _running = false;
  double _progress = 0;
  List<FoliateSearchHit> _hits = const [];
  String? _imageDataUrl;
  void Function(String query)? _runSearch;
  VoidCallback? _clearSearch;
  bool _disposed = false;

  bool get open => _open;
  String get query => _query;
  bool get running => _running;
  double get progress => _progress;
  List<FoliateSearchHit> get hits => _hits;
  String? get imageDataUrl => _imageDataUrl;
  bool get imageOpen => _imageDataUrl != null;

  void attachBridge({
    required void Function(String query) runSearch,
    required VoidCallback clearSearch,
  }) {
    _runSearch = runSearch;
    _clearSearch = clearSearch;
  }

  void detachBridge() {
    _runSearch = null;
    _clearSearch = null;
  }

  void openSearch({String? initialQuery}) {
    beforeOpenOverlay();
    final nextQuery = initialQuery?.trim() ?? '';
    _open = true;
    if (nextQuery.isNotEmpty) {
      _query = nextQuery;
      notifyListeners();
      submit(nextQuery);
      return;
    }
    notifyListeners();
  }

  void closeSearch() {
    if (!_open && !_running && _hits.isEmpty) return;
    _open = false;
    _running = false;
    _progress = 0;
    _hits = const [];
    _clearSearch?.call();
    notifyListeners();
  }

  void submit(String query) {
    final trimmed = query.trim();
    _query = trimmed;
    if (trimmed.isEmpty) {
      _running = false;
      _progress = 0;
      _hits = const [];
      _clearSearch?.call();
      notifyListeners();
      return;
    }
    _running = true;
    _progress = 0;
    _hits = const [];
    notifyListeners();
    _clearSearch?.call();
    _runSearch?.call(trimmed);
  }

  void report(FoliateSearchEvent event) {
    if (_disposed || !_open) return;
    switch (event) {
      case FoliateSearchProgress(:final fraction):
        _progress = fraction;
        notifyListeners();
      case FoliateSearchDone():
        _running = false;
        _progress = 1;
        notifyListeners();
      case FoliateSearchChapterHits(:final hits):
        _hits = [..._hits, ...hits];
        notifyListeners();
    }
  }

  void selectHit(FoliateSearchHit hit) {
    if (hit.cfi.trim().isEmpty) return;
    _open = false;
    _running = false;
    notifyListeners();
    onSearchHitSelected(hit);
  }

  void openImage(String dataUrl) {
    final url = dataUrl.trim();
    if (!url.startsWith('data:')) return;
    beforeOpenOverlay();
    _imageDataUrl = url;
    notifyListeners();
  }

  void closeImage() {
    if (_imageDataUrl == null) return;
    _imageDataUrl = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    detachBridge();
    super.dispose();
  }
}

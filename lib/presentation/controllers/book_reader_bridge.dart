import 'package:flutter/foundation.dart';

import '../../domain/book_structure.dart';

typedef BookPlainTextLoader =
    Future<String> Function(
      int maxChars, {
      bool toc,
      int? startSection,
      int? endSectionExclusive,
    });

typedef BookSelectionContextLoader =
    Future<({String before, String after})?> Function(int before, int after);

/// Holds the renderer callbacks attached to one open Foliate session.
///
/// This is deliberately state-light: reader state stays in
/// `BookReaderController`, while the adapter lifecycle owns these callbacks.
class BookReaderBridge {
  BookReaderBridge({this.onContentDetached});

  VoidCallback? onContentDetached;
  VoidCallback? _nextPage;
  VoidCallback? _previousPage;
  ValueChanged<double>? _seek;
  Future<String> Function()? _chapterText;
  BookPlainTextLoader? _bookPlainText;
  Future<BookStructureIndex?> Function()? _bookStructureIndex;
  BookSelectionContextLoader? _selectionContext;

  bool get canGoNextPage => _nextPage != null;
  bool get canGoPreviousPage => _previousPage != null;

  void attachPageNavigation({
    required VoidCallback nextPage,
    required VoidCallback previousPage,
  }) {
    _nextPage = nextPage;
    _previousPage = previousPage;
  }

  void detachPageNavigation() {
    _nextPage = null;
    _previousPage = null;
  }

  void attachSeek(ValueChanged<double> seek) => _seek = seek;

  void detachSeek() => _seek = null;

  void attachContent({
    Future<String> Function()? getChapterText,
    BookPlainTextLoader? getBookPlainText,
    Future<BookStructureIndex?> Function()? getBookStructureIndex,
    BookSelectionContextLoader? getSelectionContext,
  }) {
    _chapterText = getChapterText;
    _bookPlainText = getBookPlainText;
    _bookStructureIndex = getBookStructureIndex;
    _selectionContext = getSelectionContext;
  }

  void detachContent() {
    _chapterText = null;
    _bookPlainText = null;
    _bookStructureIndex = null;
    _selectionContext = null;
    onContentDetached?.call();
  }

  void nextPage() => _nextPage?.call();

  void previousPage() => _previousPage?.call();

  void seek(double fraction) => _seek?.call(fraction);

  Future<String> loadChapterText() async => (await _chapterText?.call()) ?? '';

  Future<String> loadBookPlainText(
    int maxChars, {
    bool toc = true,
    int? startSection,
    int? endSectionExclusive,
  }) async =>
      (await _bookPlainText?.call(
        maxChars,
        toc: toc,
        startSection: startSection,
        endSectionExclusive: endSectionExclusive,
      )) ??
      '';

  Future<BookStructureIndex?> loadBookStructureIndex() async =>
      await _bookStructureIndex?.call();

  Future<({String before, String after})?> loadSelectionContext({
    int before = 100,
    int after = 100,
  }) async {
    final load = _selectionContext;
    if (load == null) return null;
    try {
      return await load(before, after);
    } catch (_) {
      return null;
    }
  }

  void detachAll() {
    detachPageNavigation();
    detachSeek();
    detachContent();
  }
}

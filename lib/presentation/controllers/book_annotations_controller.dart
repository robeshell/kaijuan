import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../../readers/book/book_language_actions.dart';
import '../../readers/book/book_models.dart';
import '../../readers/book/foliate_js_bridge.dart';

/// Owns annotations, the two-phase selection menu, notes, and Foliate markup.
class BookAnnotationsController extends ChangeNotifier {
  BookAnnotationsController({
    required this.database,
    required this.item,
    required this.languageProvider,
    required this.beforeOpenMenu,
    required this.tocTitles,
    required this.tocEntries,
    required this.sectionCount,
    required this.onGoToCfi,
  });

  final AppDatabase database;
  final ReadingItem item;
  final BookLanguageProvider languageProvider;
  final VoidCallback beforeOpenMenu;
  final List<String> Function() tocTitles;
  final List<BookTocEntry> Function() tocEntries;
  final int Function() sectionCount;
  final ValueChanged<String> onGoToCfi;

  List<BookAnnotation> _annotations = const [];
  StreamSubscription<List<BookAnnotation>>? _annotationsSubscription;
  BookSelectionMenu? _selectionMenu;
  bool _selectionClearLocked = false;
  Timer? _selectionClearLockTimer;
  DateTime? _selectionMenuBarrierArmAt;
  DateTime? _suppressPageTurnUntil;
  bool _annotationsHydrated = false;
  bool _annotationsRenderRequested = false;
  DateTime? _ignoreAnnotationClickUntil;
  int _navDrawerTabIndex = 0;
  Map<String, double>? _lastMenuCursorZone;
  void Function(List<Map<String, Object?>> annotations)? _renderAnnotations;
  void Function(Map<String, Object?> annotation)? _addAnnotationToEngine;
  void Function(String cfi)? _removeAnnotationFromEngine;
  VoidCallback? _clearWebSelection;
  Future<String> Function()? _getSelectedText;
  void Function(Map<String, double>? zone)? _setMenuCursorZone;
  void Function(bool open)? _setMenuOpen;
  bool _disposed = false;

  List<BookAnnotation> get annotations => _annotations;
  BookSelectionMenu? get selectionMenu => _selectionMenu;
  int get navDrawerTabIndex => _navDrawerTabIndex;

  bool get selectionMenuBarrierAcceptsDismiss {
    if (_selectionMenu == null) return false;
    final armAt = _selectionMenuBarrierArmAt;
    if (armAt == null) return true;
    return !DateTime.now().isBefore(armAt);
  }

  bool get shouldSuppressPageTurnFromClick {
    final until = _suppressPageTurnUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _armSelectionMenuDismissBarrier() {
    _selectionMenuBarrierArmAt = DateTime.now().add(
      const Duration(milliseconds: 450),
    );
  }

  void _armPageTurnSuppressAfterSelection() {
    _suppressPageTurnUntil = DateTime.now().add(
      const Duration(milliseconds: 900),
    );
  }

  void Function(BookAnnotation note)? onOpenNoteEditor;

  void attachBridge({
    required void Function(List<Map<String, Object?>> annotations) renderAll,
    required void Function(Map<String, Object?> annotation) add,
    required void Function(String cfi) remove,
    required VoidCallback clearSelection,
    required Future<String> Function() getSelectedText,
    required void Function(Map<String, double>? zone) setMenuCursorZone,
    required void Function(bool open) setMenuOpen,
  }) {
    _renderAnnotations = renderAll;
    _addAnnotationToEngine = add;
    _removeAnnotationFromEngine = remove;
    _clearWebSelection = clearSelection;
    _getSelectedText = getSelectedText;
    _setMenuCursorZone = setMenuCursorZone;
    _setMenuOpen = setMenuOpen;
  }

  void detachBridge() {
    _renderAnnotations = null;
    _addAnnotationToEngine = null;
    _removeAnnotationFromEngine = null;
    _clearWebSelection = null;
    _getSelectedText = null;
    _setMenuCursorZone = null;
    _setMenuOpen = null;
  }

  Future<String> peekSelectedText() async {
    final fromMenu = _selectionMenu?.text.trim() ?? '';
    if (fromMenu.isNotEmpty) return fromMenu;
    return ((await _getSelectedText?.call()) ?? '').trim();
  }

  /// Dismiss the selection **bubble** but keep page highlight when possible.
  /// Call after [peekSelectedText] when opening 本书 AI.
  void dismissSelectionMenuKeepHighlight() {
    // Survive focus moving into the AI panel (WebView may fire selectionchange).
    retainSelectionMenuForInteraction(
      duration: const Duration(milliseconds: 2000),
    );
    clearSelectionMenu(clearWebSelection: false);
  }

  void requestAnnotationsRender() {
    _annotationsRenderRequested = true;
    if (_annotationsHydrated) {
      pushAnnotationsToEngine();
    }
  }

  /// Push current DB annotations into Foliate (open / section overlay / heal).
  void pushAnnotationsToEngine() {
    final render = _renderAnnotations;
    if (render == null) return;
    render([for (final annotation in _annotations) annotation.toFoliateJson()]);
    _annotationsRenderRequested = false;
  }

  // Selection / annotations
  // ------------------------------------------------------------------

  void watchAnnotations() {
    _annotationsSubscription?.cancel();
    _annotationsHydrated = false;
    _annotationsSubscription = database.watchAnnotationsFor(item.id).listen((
      rows,
    ) {
      if (_disposed) return;
      _annotations = List.unmodifiable(rows);
      _annotationsHydrated = true;
      notifyListeners();
      // Heal open race: Foliate may have called renderAnnotations before the
      // first watch emission. addAnnotation replaces by CFI so re-push is safe.
      if (_annotationsRenderRequested) {
        pushAnnotationsToEngine();
      }
    });
  }

  void reportSelectionEnd(FoliateSelectionEnd selection) {
    if (_disposed) return;
    if (selection.footnote) {
      clearSelectionMenu();
      return;
    }
    beforeOpenMenu();
    final matched = _annotationForCfi(selection.cfi);
    _selectionMenu = BookSelectionMenu(
      cfi: selection.cfi,
      text: selection.text,
      left: selection.pos.left,
      top: selection.pos.top,
      right: selection.pos.right,
      bottom: selection.pos.bottom,
      phase: BookSelectionMenuPhase.actions,
      annotationId: matched?.id,
      annotationType: matched?.type,
      annotationColorCss: matched?.colorCss,
      note: matched?.note,
      fromAnnotation: matched != null,
    );
    _armSelectionMenuDismissBarrier();
    _armPageTurnSuppressAfterSelection();
    _setMenuOpen?.call(true);
    notifyListeners();
  }

  void reportSelectionCleared() {
    // Deselect → close immediately (Anx default). Only ignore while a bubble
    // press / style write briefly locks to survive focus-loss clears.
    if (_selectionClearLocked) return;
    if (_selectionMenu == null) return;
    clearSelectionMenu(clearWebSelection: false);
  }

  void reportAnnotationClick(FoliateAnnotationClick click) {
    if (_disposed) return;
    final ignoreUntil = _ignoreAnnotationClickUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }
    beforeOpenMenu();
    BookAnnotation? matched;
    for (final row in _annotations) {
      if (row.cfi == click.cfi) {
        matched = row;
        break;
      }
    }
    final type = BookAnnotationType.fromStorage(click.type);
    final contextText = click.contextText?.trim() ?? '';
    final storedQuote = matched?.selectedText?.trim() ?? '';
    // Heal older rows that lost selectedText (upsert used to wipe it).
    if (matched != null && storedQuote.isEmpty && contextText.isNotEmpty) {
      unawaited(
        database.upsertAnnotation(
          itemId: item.id,
          cfi: matched.cfi,
          type: matched.type.storageValue,
          color: matched.colorCss,
          selectedText: contextText,
        ),
      );
    }
    _selectionMenu = BookSelectionMenu(
      cfi: click.cfi,
      text: storedQuote.isNotEmpty ? storedQuote : contextText,
      left: click.pos.left,
      top: click.pos.top,
      right: click.pos.right,
      bottom: click.pos.bottom,
      phase: BookSelectionMenuPhase.markup,
      annotationId: matched?.id ?? click.id,
      annotationType: type ?? matched?.type,
      annotationColorCss: click.color,
      note: matched?.note ?? click.note,
      fromAnnotation: true,
    );
    // Clicking an existing mark often collapses any leftover Range; hold
    // briefly so the markup panel is not torn down by that clear.
    retainSelectionMenuForInteraction();
    _armSelectionMenuDismissBarrier();
    _setMenuOpen?.call(true);
    notifyListeners();
  }

  /// Enter ②. Fresh selections immediately paint a default underline (Anx
  /// autoMarkSelection equivalent) so the range stays visible after the
  /// native DOM selection collapses.
  ///
  /// Desktop Platform Views often collapse selection when the Flutter bubble
  /// takes focus; mobile keeps selection handles. Always clear the web
  /// selection after the mark is drawn so both feel the same: 划线 → paint →
  /// 取消选中, menu stays on ② for style/color.
  Future<void> openMarkupPhase() async {
    final menu = _selectionMenu;
    if (menu == null) return;
    retainSelectionMenuForInteraction();
    if (menu.phase == BookSelectionMenuPhase.markup &&
        menu.annotationId != null) {
      return;
    }
    if (menu.annotationId != null || menu.fromAnnotation) {
      if (menu.phase != BookSelectionMenuPhase.markup) {
        _selectionMenu = menu.copyWith(phase: BookSelectionMenuPhase.markup);
        notifyListeners();
      }
      return;
    }
    // 划线 = commit default mark (kept on menu dismiss; 清空 to delete).
    await applyAnnotationStyle(
      type: BookAnnotationType.underline,
      color: BookHighlightColor.yellow,
      dismissMenu: false,
    );
    if (_disposed) return;
    // Hold the lock so the deselect's onSelectionCleared does not tear down ②.
    retainSelectionMenuForInteraction();
    _clearWebSelection?.call();
  }

  void clearSelectionMenu({bool clearWebSelection = true}) {
    _selectionClearLockTimer?.cancel();
    _selectionClearLocked = false;
    _selectionMenuBarrierArmAt = null;
    // Same pointer that dismissed can hit the overlayer next — ignore briefly.
    _ignoreAnnotationClickUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
    if (_selectionMenu == null) {
      _setMenuOpen?.call(false);
      _clearMenuCursorZone();
      return;
    }
    _selectionMenu = null;
    _setMenuOpen?.call(false);
    _clearMenuCursorZone();
    // Anx only clears the native selection when the menu closes.
    if (clearWebSelection) {
      _clearWebSelection?.call();
    }
    notifyListeners();
  }

  /// Call from the bubble on pointer-down so focus-loss selection clears do
  /// not dismiss mid-tap. Auto-unlocks; a later real deselect will close.
  void retainSelectionMenuForInteraction({
    Duration duration = const Duration(milliseconds: 500),
  }) {
    _selectionClearLocked = true;
    _selectionClearLockTimer?.cancel();
    _selectionClearLockTimer = Timer(duration, () {
      _selectionClearLocked = false;
    });
  }

  /// Normalized viewport box for the Flutter menu bubble (Platform View cursor).
  ///
  /// Skips identical updates — the selection overlay rebuilds often, and
  /// re-pushing the same zone into the WebView makes the desktop cursor flicker.
  void setMenuCursorZone({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final zone = <String, double>{
      'left': left.clamp(0.0, 1.0),
      'top': top.clamp(0.0, 1.0),
      'right': right.clamp(0.0, 1.0),
      'bottom': bottom.clamp(0.0, 1.0),
    };
    final prev = _lastMenuCursorZone;
    if (prev != null &&
        prev['left'] == zone['left'] &&
        prev['top'] == zone['top'] &&
        prev['right'] == zone['right'] &&
        prev['bottom'] == zone['bottom']) {
      return;
    }
    _lastMenuCursorZone = zone;
    _setMenuCursorZone?.call(zone);
  }

  void _clearMenuCursorZone() {
    if (_lastMenuCursorZone == null) {
      // Still tell the engine — it may hold a zone after a hot restart / race.
      _setMenuCursorZone?.call(null);
      return;
    }
    _lastMenuCursorZone = null;
    _setMenuCursorZone?.call(null);
  }

  /// Returns true when text was written to the clipboard.
  Future<bool> copySelection({String? textOverride}) async {
    var text = (textOverride ?? _selectionMenu?.text ?? '').trim();
    if (text.isEmpty) {
      text = ((await _getSelectedText?.call()) ?? '').trim();
    }
    if (text.isEmpty) {
      _clearWebSelection?.call();
      clearSelectionMenu();
      return false;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _clearWebSelection?.call();
    clearSelectionMenu();
    return true;
  }

  Future<BookLanguageActionResult> performLanguageAction({
    required BookLanguageOperation operation,
    String? textOverride,
  }) {
    return performPlatformLanguageAction(
      operation: operation,
      textOverride: textOverride,
    );
  }

  /// Always uses the platform dictionary / translation path (system apps).
  Future<BookLanguageActionResult> performPlatformLanguageAction({
    required BookLanguageOperation operation,
    String? textOverride,
  }) {
    final menu = _selectionMenu;
    final text = (textOverride ?? _selectionMenu?.text ?? '').trim();
    return languageProvider.execute(
      BookLanguageRequest(
        operation: operation,
        text: text,
        itemId: item.id,
        cfi: menu?.cfi,
      ),
    );
  }

  /// AI stream for in-app dictionary / translation. Null when AI is unavailable.

  Future<bool> copyExcerpt({String? textOverride}) =>
      copySelection(textOverride: textOverride);

  Future<void> applyAnnotationStyle({
    required BookAnnotationType type,
    required BookHighlightColor color,
    String? cfiOverride,
    String? textOverride,
    bool dismissMenu = true,
  }) async {
    final menu = _selectionMenu;
    final cfi = (cfiOverride ?? menu?.cfi ?? '').trim();
    if (cfi.isEmpty) return;
    retainSelectionMenuForInteraction();
    final selectedText = (textOverride ?? menu?.text ?? '').trim();
    final id = await database.upsertAnnotation(
      itemId: item.id,
      cfi: cfi,
      type: type.storageValue,
      color: color.css,
      selectedText: selectedText.isEmpty ? null : selectedText,
    );
    if (_disposed) return;
    // Keep note in the engine payload so the「注」bubble is not dropped on
    // style-only upserts (JS replace-by-cfi).
    final existingNote = _selectionMenu?.note ?? _annotationForCfi(cfi)?.note;
    _addAnnotationToEngine?.call({
      'id': id,
      'value': cfi,
      'type': type.storageValue,
      'color': color.css,
      'replace': true,
      if (existingNote != null && existingNote.trim().isNotEmpty)
        'note': existingNote.trim(),
    });
    if (dismissMenu) {
      clearSelectionMenu();
    } else if (menu != null) {
      _selectionMenu = menu.copyWith(
        phase: BookSelectionMenuPhase.markup,
        annotationId: id,
        annotationType: type,
        annotationColorCss: color.css,
        fromAnnotation: true,
      );
      notifyListeners();
    }
  }

  Future<void> removeActiveAnnotation() async {
    final menu = _selectionMenu;
    if (menu == null) return;
    if (menu.annotationId != null) {
      await database.deleteAnnotation(menu.annotationId!);
    } else {
      await database.deleteAnnotationByCfi(itemId: item.id, cfi: menu.cfi);
    }
    if (_disposed) return;
    _removeAnnotationFromEngine?.call(menu.cfi);
    _clearWebSelection?.call();
    clearSelectionMenu();
  }

  /// Annotations that carry a non-empty note (for the notes list).
  List<BookAnnotation> get notes {
    final rows = [
      for (final row in _annotations)
        if (row.note != null && row.note!.trim().isNotEmpty) row,
    ];
    // Newest first (DB watch is ascending by createdAt).
    return List.unmodifiable(rows.reversed);
  }

  String noteLabel(BookAnnotation annotation) {
    final note = annotation.note?.trim() ?? '';
    if (note.isNotEmpty) return note;
    final text = annotation.selectedText?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return '笔记';
  }

  /// Chapter title for a note row (from CFI spine index + TOC titles).
  String? noteChapterTitle(BookAnnotation annotation) {
    final index = BookLocator.sectionIndexFromCfi(annotation.cfi);
    if (index == null) return null;
    if (index >= 0 && index < tocTitles().length) {
      final title = tocTitles()[index].trim();
      if (title.isNotEmpty) return title;
    }
    for (final entry in tocEntries()) {
      if (entry.sectionIndex == index) {
        final title = entry.title.trim();
        if (title.isNotEmpty) return title;
      }
    }
    if (sectionCount() > 0 && index < sectionCount()) {
      return '第 ${index + 1} 节';
    }
    return null;
  }

  /// Original quote for the subtitle — always the selected range when stored.
  String? noteExcerpt(BookAnnotation annotation) {
    final text = annotation.selectedText?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// List subtitle: **原文摘录** first. Chapter alone is useless when many notes
  /// share a section — only used as a fallback label when quote is missing.
  String noteListSubtitle(BookAnnotation annotation) {
    final quote = noteExcerpt(annotation);
    if (quote != null) return quote;
    final chapter = noteChapterTitle(annotation);
    if (chapter != null) return '$chapter（无原文）';
    return '（无原文摘录）';
  }

  void setNavDrawerTabIndex(int index) {
    final next = index.clamp(0, 2);
    if (next == _navDrawerTabIndex) return;
    _navDrawerTabIndex = next;
  }

  BookAnnotation? _annotationForCfi(String cfi) {
    final key = cfi.trim();
    if (key.isEmpty) return null;
    for (final row in _annotations) {
      if (row.cfi == key) return row;
    }
    return null;
  }

  Future<void> saveAnnotationNote({
    required String cfi,
    required String noteText,
    String? selectedText,
    BookAnnotationType? type,
    String? colorCss,
  }) async {
    final key = cfi.trim();
    if (key.isEmpty) return;
    final trimmed = noteText.trim();
    final existing = _annotationForCfi(key);
    if (trimmed.isEmpty && existing == null) return;

    final resolvedType = type ?? existing?.type ?? BookAnnotationType.underline;
    final resolvedColor = BookHighlightColor.fromCss(
      colorCss ?? existing?.colorCss ?? BookHighlightColor.yellow.css,
    );
    // Empty string from UI must not erase a previously stored quote.
    final incoming = selectedText?.trim() ?? '';
    final text = incoming.isNotEmpty
        ? incoming
        : (existing?.selectedText?.trim() ?? '');
    final noteValue = trimmed.isEmpty ? null : trimmed;

    final id = await database.upsertAnnotation(
      itemId: item.id,
      cfi: key,
      type: resolvedType.storageValue,
      color: resolvedColor.css,
      selectedText: text.isEmpty ? null : text,
      note: noteValue,
      writeNote: true,
    );
    if (_disposed) return;
    _addAnnotationToEngine?.call({
      'id': id,
      'value': key,
      'type': resolvedType.storageValue,
      'color': resolvedColor.css,
      'replace': true,
      'note': ?noteValue,
    });
  }

  /// Clear note from the list; keeps underline / highlight.
  Future<void> clearAnnotationNote(BookAnnotation annotation) {
    return saveAnnotationNote(
      cfi: annotation.cfi,
      noteText: '',
      selectedText: annotation.selectedText,
      type: annotation.type,
      colorCss: annotation.colorCss,
    );
  }

  /// Note bubble / list: jump optional caller, then present the editor.
  void openNoteEditor(BookAnnotation annotation) {
    clearSelectionMenu(clearWebSelection: false);
    onOpenNoteEditor?.call(annotation);
  }

  /// Foliate note-marker tap — open editor, not markup ②.
  void reportAnnotationNoteClick(FoliateAnnotationClick click) {
    if (_disposed) return;
    // Keep WebView selection untouched; clearing it reflows the paginator.
    if (_selectionMenu != null) {
      clearSelectionMenu(clearWebSelection: false);
    }
    final matched = _annotationForCfi(click.cfi);
    final noteText = (matched?.note ?? click.note)?.trim() ?? '';
    final forEditor =
        matched ??
        BookAnnotation(
          id: click.id ?? 0,
          cfi: click.cfi,
          type:
              BookAnnotationType.fromStorage(click.type) ??
              BookAnnotationType.underline,
          colorCss: click.color,
          selectedText: matched?.selectedText,
          note: noteText.isEmpty ? null : noteText,
          createdAt: DateTime.now(),
        );
    onOpenNoteEditor?.call(forEditor);
  }

  // ------------------------------------------------------------------
  void goToAnnotation(BookAnnotation annotation) {
    final cfi = annotation.cfi.trim();
    if (cfi.isNotEmpty) onGoToCfi(cfi);
  }

  @override
  void dispose() {
    _disposed = true;
    _selectionClearLockTimer?.cancel();
    unawaited(_annotationsSubscription?.cancel());
    detachBridge();
    super.dispose();
  }
}

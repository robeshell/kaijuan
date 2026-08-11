import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/persistence/app_database.dart';
import 'package:kaijuan/presentation/controllers/book_annotations_controller.dart';
import 'package:kaijuan/readers/book/book_language_actions.dart';
import 'package:kaijuan/readers/book/foliate_js_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ReadingItem item;
  late BookAnnotationsController controller;
  var menuOpened = false;
  var chromeHidden = 0;
  String? navigatedCfi;
  Map<String, Object?>? engineAnnotation;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026);
    await database.upsertReadingItem(
      ReadingItemsCompanion.insert(
        id: 'book',
        kind: ReaderKind.book.storageValue,
        format: ReaderFormat.epub.storageValue,
        title: 'Test Book',
        filePath: '/tmp/book.epub',
        contentHash: 'hash-book',
        pageCount: const Value(3),
        addedAt: now,
        updatedAt: now,
      ),
    );
    item = (await database.readingItemById('book'))!;
    controller =
        BookAnnotationsController(
          database: database,
          item: item,
          languageProvider: const PlatformBookLanguageProvider(),
          beforeOpenMenu: () => chromeHidden++,
          tocTitles: () => const ['第一章', '第二章', '第三章'],
          tocEntries: () => const [],
          sectionCount: () => 3,
          onGoToCfi: (cfi) => navigatedCfi = cfi,
        )..attachBridge(
          renderAll: (_) {},
          add: (annotation) => engineAnnotation = annotation,
          remove: (_) {},
          clearSelection: () {},
          getSelectedText: () async => '',
          setMenuCursorZone: (_) {},
          setMenuOpen: (open) => menuOpened = open,
        );
    controller.watchAnnotations();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'selection markup has one state owner and persists through the bridge',
    () async {
      controller.reportSelectionEnd(
        const FoliateSelectionEnd(
          cfi: 'epubcfi(/6/4)',
          text: '被选择的原文',
          pos: FoliateNormalizedBox(
            left: 0.1,
            top: 0.2,
            right: 0.4,
            bottom: 0.3,
          ),
        ),
      );

      expect(controller.selectionMenu?.text, '被选择的原文');
      expect(menuOpened, isTrue);
      expect(chromeHidden, 1);

      await controller.applyAnnotationStyle(
        type: BookAnnotationType.highlight,
        color: BookHighlightColor.yellow,
        dismissMenu: false,
      );
      await pumpEventQueue();

      expect(controller.annotations, hasLength(1));
      expect(controller.annotations.single.selectedText, '被选择的原文');
      expect(engineAnnotation?['replace'], isTrue);
      expect(controller.selectionMenu?.annotationId, isNotNull);
    },
  );

  test(
    'note projection and navigation remain inside annotation controller',
    () async {
      await database.upsertAnnotation(
        itemId: item.id,
        cfi: 'epubcfi(/6/4)',
        type: BookAnnotationType.underline.storageValue,
        color: BookHighlightColor.yellow.css,
        selectedText: '原文',
        note: '我的笔记',
        writeNote: true,
      );
      await pumpEventQueue();

      final note = controller.notes.single;
      expect(controller.noteLabel(note), '我的笔记');
      expect(controller.noteListSubtitle(note), '原文');

      controller.goToAnnotation(note);
      expect(navigatedCfi, note.cfi);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/foliate_js_bridge.dart';

void main() {
  test('import snapshot parses Foliate metadata and cover data URL', () {
    final snapshot = FoliateImportSnapshot.fromHandlerArguments([
      {
        'title': '测试图书',
        'author': [
          {'name': '作者甲'},
          '作者乙',
        ],
        'sectionCount': 20,
        'sampledSections': 12,
        'sampledImageOnlySections': 2,
        'totalTextLength': 3600,
        'cover': 'data:image/png;base64,iVBORw0KGgo=',
      },
    ]);

    expect(snapshot, isNotNull);
    expect(snapshot!.title, '测试图书');
    expect(snapshot.authors, ['作者甲', '作者乙']);
    expect(snapshot.sectionCount, 20);
    expect(snapshot.sampledSections, 12);
    expect(snapshot.sampledImageOnlySections, 2);
    expect(snapshot.totalTextLength, 3600);
    expect(snapshot.coverMimeType, 'image/png');
    expect(snapshot.coverBytes, isNotEmpty);
  });

  test('publication snapshot parses sections and nested toc', () {
    final snapshot = FoliatePublicationSnapshot.fromJsonString('''
      {
        "sections": ["Text/a.xhtml", "Text/b.xhtml"],
        "toc": [
          {
            "label": "第一章",
            "href": "Text/a.xhtml#start",
            "subitems": [
              {"label": "小节", "href": "Text/a.xhtml#part"}
            ]
          }
        ]
      }
    ''');

    expect(snapshot.sectionHrefs, ['Text/a.xhtml', 'Text/b.xhtml']);
    expect(snapshot.toc, hasLength(1));
    expect(snapshot.toc.first.title, '第一章');
    expect(snapshot.toc.first.children.single.href, 'Text/a.xhtml#part');
  });

  test('publication snapshot rejects malformed section payload', () {
    expect(
      () => FoliatePublicationSnapshot.fromJsonString('{"sections": {}}'),
      throwsFormatException,
    );
  });

  test('relocation validates CFI and clamps percentage', () {
    final relocation = FoliateRelocation.fromHandlerArguments([
      {
        'cfi': 'epubcfi(/6/4!/4/2)',
        'chapterHref': 'Text/b.xhtml',
        'percentage': '1.2',
      },
    ]);

    expect(relocation, isNotNull);
    expect(relocation!.chapterHref, 'Text/b.xhtml');
    expect(relocation.percentage, 1);
    expect(FoliateRelocation.fromHandlerArguments(const []), isNull);
    expect(
      FoliateRelocation.fromHandlerArguments([
        {'percentage': 0.5},
      ]),
      isNull,
    );
  });

  test('viewport click accepts strings and uses safe defaults', () {
    final click = FoliateViewportClick.fromHandlerArguments([
      {'x': '-1', 'y': 'bad'},
    ]);

    expect(click, isNotNull);
    expect(click!.x, 0);
    expect(click.y, 0.5);
    expect(FoliateViewportClick.fromHandlerArguments(const []), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_epub_fonts.dart';

void main() {
  test('parseFontFaces extracts family and src', () {
    const css = '''
@font-face {
  font-family: "Calibre Serif";
  src: url("../Fonts/CalibreSerif.ttf");
}
body { font-family: "Calibre Serif", serif; }
''';
    final faces = BookEpubFonts.parseFontFaces(css);
    expect(faces, hasLength(1));
    expect(faces.first.family, 'Calibre Serif');
    expect(faces.first.src, '../Fonts/CalibreSerif.ttf');
  });

  test('parseFontFaces skips data urls', () {
    const css = '''
@font-face {
  font-family: Embedded;
  src: url("data:font/woff;base64,AAAA");
}
''';
    expect(BookEpubFonts.parseFontFaces(css), isEmpty);
  });
}

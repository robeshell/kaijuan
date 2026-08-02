import 'dart:typed_data';
import 'dart:ui' as ui;

/// Generates a minimal gradient cover for books without embedded artwork.
///
/// The platform text renderer is used instead of a bundled bitmap font so
/// Chinese titles and other Unicode text can render through the system's font
/// fallback. Long titles are constrained to four lines and ellipsized.
abstract final class DefaultCoverGenerator {
  static const storageVersion = 'v4';

  static String storageKey(String contentHash) =>
      'default-cover-$storageVersion-$contentHash';

  static Future<Uint8List> png({
    required String seed,
    required String title,
  }) async {
    final palette = _palettes[_seed(seed) % _palettes.length];
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      const ui.Rect.fromLTWH(0, 0, _width, _height),
    );

    final gradient = ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(_width, _height),
        [_color(palette.accent), _color(palette.secondary)],
      );
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, _width, _height), gradient);

    final titlePaint = ui.Paint()
      ..shader =
          ui.Gradient.linear(const ui.Offset(0, 370), const ui.Offset(0, 620), [
            const ui.Color(0xFFFDFCF9),
            _mix(const ui.Color(0xFFFDFCF9), _color(palette.accent), 0.35),
          ]);
    final paragraph =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: ui.TextAlign.center,
                  maxLines: 4,
                  ellipsis: '…',
                  height: 1.32,
                ),
              )
              ..pushStyle(
                ui.TextStyle(
                  foreground: titlePaint,
                  fontSize: 48,
                  fontWeight: ui.FontWeight.w700,
                ),
              )
              ..addText(_displayTitle(title)))
            .build();
    paragraph.layout(const ui.ParagraphConstraints(width: 500));
    canvas.drawParagraph(paragraph, const ui.Offset(50, 370));

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width.toInt(), _height.toInt());
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('默认封面编码失败');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  static String _displayTitle(String title) {
    final normalized = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? '未命名书籍' : normalized;
  }

  static int _seed(String value) {
    var result = 0;
    for (final codeUnit in value.codeUnits) {
      result = (result * 31 + codeUnit) & 0x7fffffff;
    }
    return result;
  }

  static ui.Color _color(List<int> rgb) =>
      ui.Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);

  static ui.Color _mix(ui.Color first, ui.Color second, double amount) =>
      ui.Color.lerp(first, second, amount)!;

  static const _width = 600.0;
  static const _height = 900.0;

  static const _palettes = <({List<int> accent, List<int> secondary})>[
    (accent: [224, 104, 77], secondary: [246, 207, 190]),
    (accent: [74, 111, 151], secondary: [194, 216, 232]),
    (accent: [112, 86, 154], secondary: [215, 202, 234]),
    (accent: [55, 125, 105], secondary: [193, 224, 209]),
  ];
}

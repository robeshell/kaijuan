import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:path/path.dart' as p;

/// Renders EPUB `<img>` tags by resolving relative `src` values against the
/// spine item's base href and loading bytes from the ZIP archive.
class EpubImageExtension extends HtmlExtension {
  EpubImageExtension({
    required this.baseHref,
    required this.readBytes,
  });

  final String baseHref;
  final Future<Uint8List?> Function(String entry) readBytes;

  @override
  Set<String> get supportedTags => const {'img'};

  @override
  bool matches(ExtensionContext context) => context.elementName == 'img';

  @override
  StyledElement prepare(
    ExtensionContext context,
    List<StyledElement> children,
  ) {
    final parsedWidth = double.tryParse(context.attributes['width'] ?? '');
    final parsedHeight = double.tryParse(context.attributes['height'] ?? '');

    return ImageElement(
      name: context.elementName,
      children: children,
      style: Style(),
      node: context.node,
      elementId: context.id,
      src: context.attributes['src'] ?? '',
      alt: context.attributes['alt'],
      width: parsedWidth != null ? Width(parsedWidth) : null,
      height: parsedHeight != null ? Height(parsedHeight) : null,
    );
  }

  @override
  InlineSpan build(ExtensionContext context) {
    final element = context.styledElement as ImageElement;
    final src = element.src;
    if (src.isEmpty) return TextSpan(text: element.alt);

    // Let the built-in extension handle data URIs.
    if (src.startsWith('data:')) {
      return ImageExtension().build(context);
    }

    final resolved = _resolveImageEntry(baseHref, src);

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: FutureBuilder<Uint8List?>(
        future: readBytes(resolved),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return _Placeholder(alt: element.alt);
          }
          return Image.memory(
            bytes,
            width: element.width?.value,
            height: element.height?.value,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _Placeholder(alt: element.alt),
          );
        },
      ),
    );
  }

  static String _resolveImageEntry(String baseHref, String src) {
    final clean = src.split('#').first.split('?').first;
    final baseDir = p.posix.dirname(baseHref);
    final joined = baseDir == '.' || baseDir.isEmpty
        ? clean
        : p.posix.normalize(p.posix.join(baseDir, clean));
    return joined.replaceAll('\\', '/');
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) {
    final fg = DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: fg, size: 32),
          const SizedBox(height: 8),
          Text(
            alt?.trim().isNotEmpty == true ? alt! : '图片',
            style: TextStyle(color: fg, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

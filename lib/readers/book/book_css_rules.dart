import 'package:flutter/material.dart';

/// Subset of EPUB CSS for page-mode layout (class / tag rules — not a full engine).
class BookCssRules {
  const BookCssRules({
    this.classProperties = const {},
    this.tagProperties = const {},
  });

  final Map<String, Map<String, String>> classProperties;
  final Map<String, Map<String, String>> tagProperties;

  static final BookCssRules empty = BookCssRules();

  static BookCssRules parseAll(List<String> stylesheets) {
    final classProps = <String, Map<String, String>>{};
    final tagProps = <String, Map<String, String>>{};
    for (final sheet in stylesheets) {
      _parseSheet(sheet, classProps, tagProps);
    }
    return BookCssRules(
      classProperties: classProps,
      tagProperties: tagProps,
    );
  }

  static void _parseSheet(
    String css,
    Map<String, Map<String, String>> classProps,
    Map<String, Map<String, String>> tagProps,
  ) {
    final stripped = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final ruleRe = RegExp(r'([^{]+)\{([^}]*)\}');
    for (final match in ruleRe.allMatches(stripped)) {
      final selectorRaw = match.group(1)?.trim() ?? '';
      final body = match.group(2)?.trim() ?? '';
      if (selectorRaw.isEmpty || body.isEmpty) continue;
      if (selectorRaw.startsWith('@')) continue;

      final decls = _parseDeclarations(body);
      if (decls.isEmpty) continue;

      for (final part in selectorRaw.split(',')) {
        final selector = part.trim();
        if (selector.isEmpty) continue;
        if (selector.startsWith('.')) {
          final name = selector.substring(1).split(RegExp(r'[:\s#>+~\[]')).first;
          if (name.isEmpty) continue;
          classProps.putIfAbsent(name, () => {}).addAll(decls);
        } else {
          final tag = selector.split(RegExp(r'[.\s#>+~\[]')).first.toLowerCase();
          if (tag.isEmpty || !RegExp(r'^[a-z][a-z0-9]*$').hasMatch(tag)) {
            continue;
          }
          tagProps.putIfAbsent(tag, () => {}).addAll(decls);
        }
      }
    }
  }

  static Map<String, String> _parseDeclarations(String body) {
    final out = <String, String>{};
    for (final chunk in body.split(';')) {
      final idx = chunk.indexOf(':');
      if (idx <= 0) continue;
      final key = chunk.substring(0, idx).trim().toLowerCase();
      final value = chunk.substring(idx + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  Map<String, String> _mergedProps({String? tag, Iterable<String>? classes}) {
    final merged = <String, String>{};
    if (tag != null) merged.addAll(tagProperties[tag.toLowerCase()] ?? const {});
    if (classes != null) {
      for (final cls in classes) {
        merged.addAll(classProperties[cls] ?? const {});
      }
    }
    return merged;
  }

  TextStyle applyToStyle(
    TextStyle base, {
    String? tag,
    Iterable<String>? classes,
    required double baseFontSize,
  }) {
    final props = _mergedProps(tag: tag, classes: classes);
    if (props.isEmpty) return base;

    var style = base;
    final weight = props['font-weight'];
    if (weight != null && _isBold(weight)) {
      style = style.copyWith(fontWeight: FontWeight.bold);
    }
    final fontStyle = props['font-style'];
    if (fontStyle != null &&
        (fontStyle.contains('italic') || fontStyle.contains('oblique'))) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    final decoration = props['text-decoration'];
    if (decoration != null) {
      if (decoration.contains('underline')) {
        style = style.copyWith(decoration: TextDecoration.underline);
      } else if (decoration.contains('line-through')) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
    }
    final fontSize = props['font-size'];
    if (fontSize != null) {
      final parsed = _lengthToPixels(fontSize, baseFontSize);
      if (parsed != null) style = style.copyWith(fontSize: parsed);
    }
    final family = props['font-family'];
    if (family != null) {
      final name = family.split(',').first.trim().replaceAll('"', '').replaceAll("'", '');
      if (name.isNotEmpty) style = style.copyWith(fontFamily: name);
    }
    return style;
  }

  double? textIndent({
    String? tag,
    Iterable<String>? classes,
    required double baseFontSize,
  }) {
    final props = _mergedProps(tag: tag, classes: classes);
    final raw = props['text-indent'];
    if (raw == null) return null;
    return _lengthToPixels(raw, baseFontSize);
  }

  double? extraParagraphSpacing({
    String? tag,
    Iterable<String>? classes,
    required double baseFontSize,
  }) {
    final props = _mergedProps(tag: tag, classes: classes);
    final bottom = props['margin-bottom'] ?? props['margin'];
    if (bottom == null) return null;
    return _lengthToPixels(bottom, baseFontSize);
  }

  double headingScale(String tag, {Iterable<String>? classes}) {
    final props = _mergedProps(tag: tag, classes: classes);
    final raw = props['font-size'];
    if (raw == null) return _defaultHeadingScale(tag);
    if (raw.endsWith('em')) {
      final v = double.tryParse(raw.replaceAll('em', '').trim());
      if (v != null && v > 0) return v;
    }
    if (raw.endsWith('%')) {
      final v = double.tryParse(raw.replaceAll('%', '').trim());
      if (v != null && v > 0) return v / 100;
    }
    return _defaultHeadingScale(tag);
  }

  static double _defaultHeadingScale(String tag) => switch (tag) {
        'h1' => 1.6,
        'h2' => 1.4,
        'h3' => 1.25,
        'h4' => 1.15,
        'h5' => 1.1,
        'h6' => 1.05,
        _ => 1.0,
      };

  static bool _isBold(String weight) {
    final w = weight.toLowerCase();
    if (w == 'bold' || w == 'bolder') return true;
    final n = int.tryParse(w);
    return n != null && n >= 600;
  }

  static double? _lengthToPixels(String raw, double baseFontSize) {
    final v = raw.trim().toLowerCase();
    if (v.endsWith('em')) {
      final n = double.tryParse(v.replaceAll('em', '').trim());
      return n == null ? null : n * baseFontSize;
    }
    if (v.endsWith('rem')) {
      final n = double.tryParse(v.replaceAll('rem', '').trim());
      return n == null ? null : n * baseFontSize;
    }
    if (v.endsWith('px')) {
      return double.tryParse(v.replaceAll('px', '').trim());
    }
    if (v.endsWith('%')) {
      final n = double.tryParse(v.replaceAll('%', '').trim());
      return n == null ? null : baseFontSize * n / 100;
    }
    return double.tryParse(v);
  }
}

import 'package:flutter/material.dart';

/// Quote-card layout variants for book excerpts.
enum BookExcerptLayout {
  classic('经典'),
  leftBar('左齐'),
  largeQuote('大引号');

  const BookExcerptLayout(this.label);
  final String label;

  static const all = BookExcerptLayout.values;
}

/// Solid color / light-gradient palette for excerpt cards.
class BookExcerptPalette {
  const BookExcerptPalette({
    required this.id,
    required this.label,
    required this.background,
    required this.backgroundEnd,
    required this.foreground,
    required this.muted,
    required this.accent,
  });

  final String id;
  final String label;
  final Color background;
  final Color backgroundEnd;
  final Color foreground;
  final Color muted;
  final Color accent;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, backgroundEnd],
  );

  static const paper = BookExcerptPalette(
    id: 'paper',
    label: '纸白',
    background: Color(0xFFF7F4EF),
    backgroundEnd: Color(0xFFEFEAE2),
    foreground: Color(0xFF1C1917),
    muted: Color(0xFF78716C),
    accent: Color(0xFFA8A29E),
  );

  static const night = BookExcerptPalette(
    id: 'night',
    label: '暗夜',
    background: Color(0xFF1C1C1E),
    backgroundEnd: Color(0xFF111113),
    foreground: Color(0xFFF2F2F4),
    muted: Color(0xFFA1A1AA),
    accent: Color(0xFF71717A),
  );

  static const warm = BookExcerptPalette(
    id: 'warm',
    label: '暖米',
    background: Color(0xFFF3E7D3),
    backgroundEnd: Color(0xFFE8D5B5),
    foreground: Color(0xFF3F2E1E),
    muted: Color(0xFF8B7355),
    accent: Color(0xFFC4A574),
  );

  static const sage = BookExcerptPalette(
    id: 'sage',
    label: '青灰',
    background: Color(0xFFE8EEEA),
    backgroundEnd: Color(0xFFD5E0D9),
    foreground: Color(0xFF1F2A24),
    muted: Color(0xFF6B7F74),
    accent: Color(0xFF8FA396),
  );

  static const ink = BookExcerptPalette(
    id: 'ink',
    label: '浅墨',
    background: Color(0xFFE7E5E4),
    backgroundEnd: Color(0xFFD6D3D1),
    foreground: Color(0xFF1C1917),
    muted: Color(0xFF57534E),
    accent: Color(0xFFA8A29E),
  );

  static const all = <BookExcerptPalette>[
    paper,
    night,
    warm,
    sage,
    ink,
  ];
}

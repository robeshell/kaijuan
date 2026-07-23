import 'package:flutter/material.dart';

import '../../../brand/brand_config.dart';
import '../../../readers/book/book_excerpt_style.dart';

/// Pure excerpt preview / export surface (same tree for RepaintBoundary).
class BookExcerptCard extends StatelessWidget {
  const BookExcerptCard({
    super.key,
    required this.quote,
    required this.bookTitle,
    required this.layout,
    required this.palette,
    this.chapterTitle,
    this.subtitle,
    this.width = 320,
  });

  final String quote;
  final String bookTitle;
  final String? chapterTitle;
  final String? subtitle;
  final BookExcerptLayout layout;
  final BookExcerptPalette palette;
  final double width;

  static const maxQuoteLines = 12;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: palette.gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: switch (layout) {
            BookExcerptLayout.classic => _ClassicBody(
              quote: quote,
              bookTitle: bookTitle,
              chapterTitle: chapterTitle,
              subtitle: subtitle,
              palette: palette,
            ),
            BookExcerptLayout.leftBar => _LeftBarBody(
              quote: quote,
              bookTitle: bookTitle,
              chapterTitle: chapterTitle,
              subtitle: subtitle,
              palette: palette,
            ),
            BookExcerptLayout.largeQuote => _LargeQuoteBody(
              quote: quote,
              bookTitle: bookTitle,
              chapterTitle: chapterTitle,
              subtitle: subtitle,
              palette: palette,
            ),
          },
        ),
      ),
    );
  }
}

class _ClassicBody extends StatelessWidget {
  const _ClassicBody({
    required this.quote,
    required this.bookTitle,
    required this.chapterTitle,
    required this.subtitle,
    required this.palette,
  });

  final String quote;
  final String bookTitle;
  final String? chapterTitle;
  final String? subtitle;
  final BookExcerptPalette palette;

  @override
  Widget build(BuildContext context) {
    final chapter = chapterTitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quote,
          textAlign: TextAlign.center,
          maxLines: BookExcerptCard.maxQuoteLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.foreground,
            fontSize: 16,
            height: 1.55,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 20),
        Container(height: 1, color: palette.accent.withValues(alpha: 0.45)),
        const SizedBox(height: 16),
        if (chapter.isNotEmpty) ...[
          Text(
            '—— $chapter ——',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          bookTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!.trim(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            BrandConfig.app.displayName,
            style: TextStyle(
              color: palette.accent,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeftBarBody extends StatelessWidget {
  const _LeftBarBody({
    required this.quote,
    required this.bookTitle,
    required this.chapterTitle,
    required this.subtitle,
    required this.palette,
  });

  final String quote;
  final String bookTitle;
  final String? chapterTitle;
  final String? subtitle;
  final BookExcerptPalette palette;

  @override
  Widget build(BuildContext context) {
    final chapter = chapterTitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  quote,
                  textAlign: TextAlign.left,
                  maxLines: BookExcerptCard.maxQuoteLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (chapter.isNotEmpty) ...[
          Text(
            chapter,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          bookTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            BrandConfig.app.displayName,
            style: TextStyle(
              color: palette.accent,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _LargeQuoteBody extends StatelessWidget {
  const _LargeQuoteBody({
    required this.quote,
    required this.bookTitle,
    required this.chapterTitle,
    required this.subtitle,
    required this.palette,
  });

  final String quote;
  final String bookTitle;
  final String? chapterTitle;
  final String? subtitle;
  final BookExcerptPalette palette;

  @override
  Widget build(BuildContext context) {
    final chapter = chapterTitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '“',
          style: TextStyle(
            color: palette.accent.withValues(alpha: 0.7),
            fontSize: 48,
            height: 0.75,
            fontWeight: FontWeight.w300,
          ),
        ),
        Text(
          quote,
          textAlign: TextAlign.left,
          maxLines: BookExcerptCard.maxQuoteLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.foreground,
            fontSize: 18,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chapter.isNotEmpty)
                    Text(
                      chapter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11,
                      ),
                    ),
                  Text(
                    bookTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((subtitle ?? '').trim().isNotEmpty)
                    Text(
                      subtitle!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                ],
              ),
            ),
            Text(
              BrandConfig.app.displayName,
              style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

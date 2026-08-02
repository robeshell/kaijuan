import 'package:flutter/material.dart';

import '../../../brand/brand_config.dart';
import '../../../core/theme.dart';
import '../../../core/theme/brand_tokens.g.dart';
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
    required this.subtitle,
    required this.palette,
  });

  final String quote;
  final String bookTitle;
  final String? subtitle;
  final BookExcerptPalette palette;

  @override
  Widget build(BuildContext context) {
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
            fontSize: KaiProductTokens.typographyReaderExcerptTitle,
            height: 1.65,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          bookTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.foreground,
            fontSize: KaiProductTokens.typographyReaderExcerptBody,
            fontWeight: FontWeight.w600,
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
            style: TextStyle(
              color: palette.muted,
              fontSize: context.appCaptionSmallSize,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 1,
              color: palette.accent.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 8),
            Text(
              BrandConfig.app.displayName,
              style: TextStyle(
                color: palette.accent,
                fontSize: context.appCaptionSmallSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 18,
              height: 1,
              color: palette.accent.withValues(alpha: 0.65),
            ),
          ],
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
        if (chapter.isNotEmpty) ...[
          Text(
            chapter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.muted,
              fontSize: context.appCaptionSmallSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
        ],
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
                    fontSize: KaiProductTokens.typographyReaderExcerptTitle,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          bookTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.foreground,
            fontSize: KaiProductTokens.typographyReaderExcerptBody,
            fontWeight: FontWeight.w600,
          ),
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.muted,
              fontSize: context.appCaptionSize,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            BrandConfig.app.displayName,
            style: TextStyle(
              color: palette.accent,
              fontSize: context.appCaptionSmallSize,
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
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.62),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 28),
              child: Text(
                quote,
                textAlign: TextAlign.left,
                maxLines: BookExcerptCard.maxQuoteLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.foreground,
                  fontSize: KaiProductTokens.typographyReaderChapterTitle,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: -8,
              child: _QuoteMark(text: '“', palette: palette),
            ),
            Positioned(
              right: 12,
              bottom: -20,
              child: _QuoteMark(
                text: '”',
                palette: palette,
                maskBackground: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
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
                        fontSize: context.appCaptionSmallSize,
                      ),
                    ),
                  Text(
                    bookTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.foreground,
                      fontSize: context.appLabelSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((subtitle ?? '').trim().isNotEmpty)
                    Text(
                      subtitle!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: context.appCaptionSmallSize,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              BrandConfig.app.displayName,
              style: TextStyle(
                color: palette.accent,
                fontSize: context.appCaptionSmallSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuoteMark extends StatelessWidget {
  const _QuoteMark({
    required this.text,
    required this.palette,
    this.maskBackground = true,
  });

  final String text;
  final BookExcerptPalette palette;
  final bool maskBackground;

  @override
  Widget build(BuildContext context) {
    final mark = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        text,
        style: TextStyle(
          color: palette.accent,
          fontSize: KaiProductTokens.typographyReaderExcerptQuote,
          height: 0.75,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
    if (!maskBackground) return mark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: mark,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/core/theme.dart';
import 'package:kaijuan/domain/reader_models.dart';
import 'package:kaijuan/library/import/comic_archive.dart';

void main() {
  group('AppColors.presetById', () {
    test('returns the matching preset', () {
      expect(AppColors.presetById('forest').id, 'forest');
    });

    test('falls back to the default for unknown or null ids', () {
      expect(AppColors.presetById('nope').id, AppColors.defaultAccent.id);
      expect(AppColors.presetById(null).id, AppColors.defaultAccent.id);
    });
  });

  test('dialog barriers follow the light and dark overlay tokens', () {
    final accent = AppColors.defaultAccent;

    expect(
      AppTheme.light(accent).dialogTheme.barrierColor?.a,
      closeTo(0.38, 0.001),
    );
    expect(
      AppTheme.dark(accent).dialogTheme.barrierColor?.a,
      closeTo(0.62, 0.001),
    );
  });

  test('light shell uses a white canvas while dark shell stays dark', () {
    final accent = AppColors.defaultAccent;

    expect(AppTheme.light(accent).scaffoldBackgroundColor, Colors.white);
    expect(
      AppTheme.dark(accent).scaffoldBackgroundColor,
      AppSkins.deepNight.canvas,
    );
  });

  test('system list tiles use the shared list-row metrics', () {
    final listTile = AppTheme.light(AppColors.defaultAccent).listTileTheme;

    expect(listTile.minTileHeight, 54);
    expect(listTile.minVerticalPadding, 6);
    expect(listTile.minLeadingWidth, 32);
    expect(listTile.horizontalTitleGap, 10);
    expect(listTile.titleTextStyle?.fontSize, 14);
    expect(listTile.subtitleTextStyle?.fontSize, 15);
  });

  group('ReaderFormat.fromExtension', () {
    test('parses known extensions case-insensitively', () {
      expect(ReaderFormat.fromExtension('epub'), ReaderFormat.epub);
      expect(ReaderFormat.fromExtension('.CBZ'), ReaderFormat.cbz);
      expect(ReaderFormat.fromExtension('md'), ReaderFormat.markdown);
      expect(ReaderFormat.fromExtension('markdown'), ReaderFormat.markdown);
    });

    test('returns null for unsupported extensions', () {
      expect(ReaderFormat.fromExtension('docx'), isNull);
      expect(ReaderFormat.fromExtension(''), isNull);
    });
  });

  group('storage wire format', () {
    test('ReaderKind round-trips', () {
      expect(ReaderKind.comic.storageValue, 'comic');
      expect(ReaderKind.fromStorage('book'), ReaderKind.book);
      expect(ReaderKind.fromStorage('nope'), isNull);
    });

    test('ReaderFormat round-trips', () {
      expect(ReaderFormat.cbz.storageValue, 'cbz');
      expect(ReaderFormat.fromStorage('zip'), ReaderFormat.zip);
      expect(ReaderFormat.fromStorage('nope'), isNull);
    });

    test('ComicPageOrder version is pinned for progress safety', () {
      expect(ComicPageOrder.version, 1);
    });
  });

  group('ComicArchive.naturalCompare', () {
    test('sorts numeric chunks numerically', () {
      final names = ['page10.jpg', 'page2.jpg', 'page1.jpg'];
      names.sort(ComicArchive.naturalCompare);
      expect(names, ['page1.jpg', 'page2.jpg', 'page10.jpg']);
    });

    test('falls back to case-insensitive text for non-numeric chunks', () {
      expect(ComicArchive.naturalCompare('B1.png', 'a2.png'), greaterThan(0));
      expect(ComicArchive.naturalCompare('cover.jpg', 'cover.jpg'), 0);
    });
  });
}

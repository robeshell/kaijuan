import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/core/theme.dart';
import 'package:kaika/domain/reader_models.dart';

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
}

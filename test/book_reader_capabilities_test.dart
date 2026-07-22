import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/readers/book/book_reader_capabilities.dart';

void main() {
  test('desktop platforms expose page mode only', () {
    expect(
      BookReaderCapabilities.supportsScrollMode(TargetPlatform.macOS),
      isFalse,
    );
    expect(
      BookReaderCapabilities.supportsScrollMode(TargetPlatform.windows),
      isFalse,
    );
    expect(
      BookReaderCapabilities.supportsScrollMode(TargetPlatform.linux),
      isFalse,
    );
  });

  test('mobile platforms keep scroll mode', () {
    expect(
      BookReaderCapabilities.supportsScrollMode(TargetPlatform.iOS),
      isTrue,
    );
    expect(
      BookReaderCapabilities.supportsScrollMode(TargetPlatform.android),
      isTrue,
    );
  });

  test('page chrome uses compact stable platform insets', () {
    expect(
      BookReaderCapabilities.pageVerticalInset(TargetPlatform.android),
      16,
    );
    expect(BookReaderCapabilities.pageVerticalInset(TargetPlatform.iOS), 16);
    expect(BookReaderCapabilities.pageVerticalInset(TargetPlatform.macOS), 24);
    expect(
      BookReaderCapabilities.pageVerticalInset(TargetPlatform.windows),
      24,
    );
  });
}

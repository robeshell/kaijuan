import 'package:flutter/material.dart';

import '../../app/book_reading_preferences.dart';
import '../../app/comic_reading_preferences.dart';
import '../../domain/reader_models.dart';
import '../../library/persistence/app_database.dart';
import '../screens/book_reader_screen.dart';
import '../screens/comic_reader_screen.dart';
import '../widgets/reader/book_cover_hero.dart';

/// Single entry for opening a library item in the correct reader.
///
/// Keeps kind routing in one place (library / shelf / lists / collections).
/// Pass the tapped card's [context] so books can measure [CoverFlightHandle].
Future<void> openReadingItem(
  BuildContext context, {
  required AppDatabase database,
  required ReadingItem item,
  ComicReadingPreferences? comicReadingPreferences,
  BookReadingPreferences? bookReadingPreferences,
  Rect? sourceCoverRect,
}) {
  if (item.kind == ReaderKind.book.storageValue) {
    return BookReaderScreen.open(
      context,
      database: database,
      item: item,
      readingPreferences: bookReadingPreferences,
      sourceCoverRect:
          sourceCoverRect ?? CoverFlightHandle.resolve(context, item.id),
    );
  }
  return ComicReaderScreen.open(
    context,
    database: database,
    item: item,
    readingPreferences: comicReadingPreferences,
  );
}

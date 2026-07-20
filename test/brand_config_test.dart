import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/brand/brand_config.dart';

void main() {
  test('comic and book brands are isolated configs', () {
    expect(BrandConfig.comic.brand, AppBrand.comic);
    expect(BrandConfig.book.brand, AppBrand.book);
    expect(BrandConfig.comic.databaseName, isNot(BrandConfig.book.databaseName));
    expect(BrandConfig.comic.applicationId, 'com.kaika.comic');
    expect(BrandConfig.book.applicationId, 'com.kaika.book');
    expect(BrandConfig.comic.importExtensions, containsAll(['cbz', 'zip', 'epub']));
    expect(BrandConfig.book.importExtensions, contains('epub'));
    expect(BrandConfig.comic.storageNamespace, isEmpty);
    expect(BrandConfig.book.storageNamespace, 'book');
    expect(BrandConfig.comic.dartEntry, 'lib/main_comic.dart');
    expect(BrandConfig.book.flavorName, 'book');
  });
}

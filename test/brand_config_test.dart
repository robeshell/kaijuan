import 'package:flutter_test/flutter_test.dart';
import 'package:kaika/brand/brand_config.dart';

void main() {
  test('single app config exposes unified reader identity', () {
    const config = BrandConfig.app;
    expect(config.displayName, 'Kaika');
    expect(config.applicationId, 'com.kaika.comic');
    expect(config.databaseName, 'app_library');
    expect(config.storageNamespace, isEmpty);
    expect(config.importExtensions, containsAll(['cbz', 'zip', 'epub']));
  });
}

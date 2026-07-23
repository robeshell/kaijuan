import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/brand/brand_config.dart';

void main() {
  test('single app config exposes unified reader identity', () {
    const config = BrandConfig.app;
    expect(config.displayName, '开卷');
    expect(config.applicationId, 'com.kaijuan.reader');
    expect(config.databaseName, 'app_library');
    expect(config.storageNamespace, isEmpty);
    expect(config.importExtensions, containsAll(['cbz', 'zip', 'epub']));
  });
}

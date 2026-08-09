import 'package:flutter_test/flutter_test.dart';

import 'package:kaijuan/library/backup/backup_format.dart';

void main() {
  test('changing backup target can clear target-scoped success state', () {
    final settings = BackupTargetSettings(
      connectionId: 'old',
      lastSnapshotId: 'snapshot-old',
      lastSuccessfulAt: DateTime.utc(2026, 8, 9),
    );

    final changed = settings.copyWith(
      connectionId: 'new',
      clearLastSnapshotId: true,
      clearLastSuccessfulAt: true,
    );

    expect(changed.connectionId, 'new');
    expect(changed.lastSnapshotId, isNull);
    expect(changed.lastSuccessfulAt, isNull);
  });

  test('device names are truncated by Unicode scalar count', () {
    final value = '${List.filled(255, 'a').join()}😀尾部';

    final truncated = KaijuanBackupFormat.truncateDeviceName(value);

    expect(truncated.runes.length, 256);
    expect(truncated.endsWith('😀'), isTrue);
  });
}

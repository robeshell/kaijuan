import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaijuan/library/import/import_staging.dart';

void main() {
  late Directory supportDirectory;
  late File source;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'kaika_import_staging_',
    );
    source = File('${supportDirectory.path}/source.EPUB');
    await source.writeAsBytes(List<int>.generate(4096, (index) => index % 251));
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('content is hidden until atomic commit', () async {
    final area = ImportStagingArea(supportDirectory);
    final staged = await area.stageContent(source);
    final expectedHash = sha256.convert(await source.readAsBytes()).toString();

    expect(staged.hash, expectedHash);
    expect(await staged.file.stagedFile.exists(), isTrue);
    expect(await staged.file.targetFile.exists(), isFalse);
    expect(staged.file.targetPath, endsWith('$expectedHash.epub'));

    await staged.file.commit();
    expect(await staged.file.stagedFile.exists(), isFalse);
    expect(await staged.file.targetFile.exists(), isTrue);
    expect(
      await staged.file.targetFile.readAsBytes(),
      await source.readAsBytes(),
    );
  });

  test('rollback removes a target created by this transaction', () async {
    final staged = await ImportStagingArea(
      supportDirectory,
    ).stageContent(source);
    await staged.file.commit();
    expect(staged.file.createdTarget, isTrue);

    await staged.file.rollback();
    expect(await staged.file.targetFile.exists(), isFalse);
  });

  test('rollback never removes a pre-existing content target', () async {
    final area = ImportStagingArea(supportDirectory);
    final first = await area.stageContent(source);
    await first.file.commit();

    final second = await area.stageContent(source);
    await second.file.commit();
    expect(second.file.createdTarget, isFalse);

    await second.file.rollback();
    expect(await first.file.targetFile.exists(), isTrue);
  });

  test('cover follows the same commit and rollback contract', () async {
    final area = ImportStagingArea(supportDirectory);
    final cover = await area.stageCover(
      hash: 'abc',
      extension: 'JPG',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(cover.targetPath, endsWith('/covers/abc.jpg'));
    expect(await cover.targetFile.exists(), isFalse);

    await cover.commit();
    expect(await cover.targetFile.exists(), isTrue);
    await cover.rollback();
    expect(await cover.targetFile.exists(), isFalse);

    final unsafe = await area.stageCover(
      hash: 'def',
      extension: '../../outside',
      bytes: Uint8List.fromList([4]),
    );
    expect(unsafe.targetPath, endsWith('/covers/def.img'));
    await unsafe.rollback();
  });

  test('purgeStalePartials only deletes aged .partial files', () async {
    final area = ImportStagingArea(supportDirectory);
    final staging = Directory('${supportDirectory.path}/.import-staging');
    await staging.create(recursive: true);

    final fresh = File('${staging.path}/fresh.partial');
    final stale = File('${staging.path}/stale.partial');
    final other = File('${staging.path}/notes.txt');
    await fresh.writeAsString('fresh');
    await stale.writeAsString('stale');
    await other.writeAsString('keep');

    final now = DateTime.utc(2026, 7, 22, 12);
    await fresh.setLastModified(now.subtract(const Duration(hours: 1)));
    await stale.setLastModified(now.subtract(const Duration(hours: 25)));

    final deleted = await area.purgeStalePartials(
      maxAge: const Duration(hours: 24),
      clock: () => now,
    );

    expect(deleted, 1);
    expect(await fresh.exists(), isTrue);
    expect(await stale.exists(), isFalse);
    expect(await other.exists(), isTrue);
  });
}

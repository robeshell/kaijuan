import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Stages import artifacts on the same filesystem as the final library so the
/// successful transition is an atomic rename rather than a partially visible
/// copy.
class ImportStagingArea {
  ImportStagingArea(this.supportDirectory);

  final Directory supportDirectory;

  static int _sequence = 0;

  Future<StagedContentFile> stageContent(File source) async {
    final staged = await _newStagingFile(p.basename(source.path));
    final output = staged.openWrite();
    final digestResult = _DigestResultSink();
    final digestSink = sha256.startChunkedConversion(digestResult);
    var digestClosed = false;
    var outputClosed = false;
    try {
      await for (final chunk in source.openRead()) {
        digestSink.add(chunk);
        output.add(chunk);
      }
      digestSink.close();
      digestClosed = true;
      await output.flush();
      await output.close();
      outputClosed = true;
      final digest = digestResult.value.toString();
      final extension = p.extension(source.path).toLowerCase();
      return StagedContentFile(
        hash: digest,
        file: StagedImportFile._(
          staged,
          File(p.join(_libraryDirectory.path, '$digest$extension')),
        ),
      );
    } catch (_) {
      if (!digestClosed) {
        try {
          digestSink.close();
        } catch (_) {
          // Preserve the original file read/write failure.
        }
      }
      if (!outputClosed) {
        try {
          await output.close();
        } catch (_) {
          // Preserve the original file read/write failure.
        }
      }
      await _deleteIfExists(staged);
      rethrow;
    }
  }

  Future<StagedImportFile> stageCover({
    required String hash,
    required String extension,
    required Uint8List bytes,
  }) async {
    final normalizedExtension = extension.startsWith('.')
        ? extension.toLowerCase()
        : '.${extension.toLowerCase()}';
    final safeExtension =
        RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(normalizedExtension)
        ? normalizedExtension
        : '.img';
    final staged = await _newStagingFile('$hash$safeExtension');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      return StagedImportFile._(
        staged,
        File(p.join(_coversDirectory.path, '$hash$safeExtension')),
      );
    } catch (_) {
      await _deleteIfExists(staged);
      rethrow;
    }
  }

  Future<File> _newStagingFile(String hint) async {
    await _stagingDirectory.create(recursive: true);
    final sequence = _sequence++;
    final safeHint = hint.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(
      p.join(
        _stagingDirectory.path,
        '${DateTime.now().microsecondsSinceEpoch}-$sequence-$safeHint.partial',
      ),
    );
  }

  /// Deletes orphaned `.partial` files older than [maxAge].
  ///
  /// Active imports keep their staging files younger than the default window,
  /// so age gating avoids deleting an in-flight transaction.
  Future<int> purgeStalePartials({
    Duration maxAge = const Duration(hours: 24),
    DateTime Function()? clock,
  }) async {
    final staging = _stagingDirectory;
    if (!await staging.exists()) return 0;
    final now = clock?.call() ?? DateTime.now();
    var deleted = 0;
    await for (final entity in staging.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.partial')) continue;
      try {
        final modified = await entity.lastModified();
        if (now.difference(modified) < maxAge) continue;
        await entity.delete();
        deleted++;
      } catch (error) {
        debugPrint('[Import] stale partial purge skipped ${entity.path}: $error');
      }
    }
    return deleted;
  }

  Directory get _stagingDirectory =>
      Directory(p.join(supportDirectory.path, '.import-staging'));
  Directory get _libraryDirectory =>
      Directory(p.join(supportDirectory.path, 'library'));
  Directory get _coversDirectory =>
      Directory(p.join(supportDirectory.path, 'covers'));
}

class StagedContentFile {
  const StagedContentFile({required this.hash, required this.file});

  final String hash;
  final StagedImportFile file;
}

class StagedImportFile {
  StagedImportFile._(this.stagedFile, this.targetFile);

  final File stagedFile;
  final File targetFile;

  bool _committed = false;
  bool _createdTarget = false;

  String get stagedPath => stagedFile.path;
  String get targetPath => targetFile.path;
  bool get createdTarget => _createdTarget;

  Future<String> commit() async {
    if (_committed) return targetPath;
    await targetFile.parent.create(recursive: true);
    if (await targetFile.exists()) {
      await _deleteIfExists(stagedFile);
      _committed = true;
      return targetPath;
    }
    try {
      await stagedFile.rename(targetPath);
      _createdTarget = true;
      _committed = true;
      return targetPath;
    } on FileSystemException {
      // Another import may have committed the same content concurrently.
      if (!await targetFile.exists()) rethrow;
      await _deleteIfExists(stagedFile);
      _committed = true;
      return targetPath;
    }
  }

  /// Removes uncommitted staging data and compensates a target created by this
  /// transaction. A pre-existing content-addressed target is never deleted.
  Future<void> rollback() async {
    await _deleteIfExists(stagedFile);
    if (_createdTarget) {
      await _deleteIfExists(targetFile);
      _createdTarget = false;
    }
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}

Future<void> rollbackStagedFiles(Iterable<StagedImportFile?> files) async {
  for (final file in files) {
    if (file == null) continue;
    try {
      await file.rollback();
    } catch (error) {
      debugPrint('[Import] rollback failed for ${file.targetPath}: $error');
    }
  }
}

class _DigestResultSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final result = _value;
    if (result == null) throw StateError('SHA-256 digest is not available');
    return result;
  }

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}

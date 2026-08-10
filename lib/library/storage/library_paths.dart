import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../brand/brand_config.dart';
import '../persistence/app_database.dart';

/// Content-addressed files live under [supportDirectory] as
/// `library/<hash>.ext` and `covers/<hash>.ext`.
///
/// The Drift DB is in Application Documents (drift_flutter default). On iOS a
/// reinstall can change the container UUID while the DB still holds absolute
/// paths with the old UUID. Resolve and rebind through this helper before
/// open / delete / cover display.
class LibraryPaths {
  LibraryPaths(this.supportDirectory);

  final Directory supportDirectory;

  /// Matches [bootstrap] support-root resolution for [BrandConfig.app].
  static Future<LibraryPaths> forApp({
    BrandConfig brand = BrandConfig.app,
  }) async {
    final root = await getApplicationSupportDirectory();
    final dir = brand.storageNamespace.isEmpty
        ? root
        : Directory(p.join(root.path, brand.storageNamespace));
    if (brand.storageNamespace.isNotEmpty) {
      await dir.create(recursive: true);
    }
    return LibraryPaths(dir);
  }

  Directory get libraryDirectory =>
      Directory(p.join(supportDirectory.path, 'library'));

  Directory get coversDirectory =>
      Directory(p.join(supportDirectory.path, 'covers'));

  Directory get aiChatDirectory =>
      Directory(p.join(supportDirectory.path, 'ai_chat'));

  Directory get aiGraphDirectory =>
      Directory(p.join(supportDirectory.path, 'ai_graph'));

  Directory get aiMindMapDirectory =>
      Directory(p.join(supportDirectory.path, 'ai_mind_map'));

  /// Path to store in the DB: relative to [supportDirectory] when possible.
  String toStoragePath(String absolutePath) {
    final root = supportDirectory.path;
    final normalized = p.normalize(absolutePath);
    if (p.isWithin(root, normalized) ||
        normalized == root ||
        normalized.startsWith('$root${p.separator}')) {
      return p.relative(normalized, from: root);
    }
    final base = p.basename(normalized);
    final sep = p.separator;
    if (normalized.contains('${sep}library$sep') ||
        normalized.contains('/library/')) {
      return p.join('library', base);
    }
    if (normalized.contains('${sep}covers$sep') ||
        normalized.contains('/covers/')) {
      return p.join('covers', base);
    }
    return normalized;
  }

  /// Resolve a stored path to a [File] under the current support root when
  /// possible (does not check existence).
  File resolve(String stored) {
    if (stored.isEmpty) return File(stored);
    if (!p.isAbsolute(stored)) {
      return File(p.normalize(p.join(supportDirectory.path, stored)));
    }
    return File(p.normalize(stored));
  }

  /// Prefer an existing file: as-stored, remapped support root, or content-hash.
  Future<File?> resolveExisting(
    String stored, {
    String? contentHash,
    bool cover = false,
  }) async {
    final folder = cover ? 'covers' : 'library';
    final candidates = <String>{};

    void add(String path) {
      if (path.isEmpty) return;
      candidates.add(p.normalize(path));
    }

    add(resolve(stored).path);

    if (p.isAbsolute(stored)) {
      final base = p.basename(stored);
      add(p.join(supportDirectory.path, folder, base));
      final unix = stored.replaceAll('\\', '/');
      for (final name in ['library', 'covers']) {
        final needle = '/$name/';
        final idx = unix.lastIndexOf(needle);
        if (idx >= 0) {
          final tail = unix.substring(idx + 1); // library/hash.ext
          add(p.joinAll([supportDirectory.path, ...tail.split('/')]));
        }
      }
    }

    if (contentHash != null && contentHash.isNotEmpty) {
      final ext = p.extension(stored);
      add(p.join(supportDirectory.path, folder, '$contentHash$ext'));
      if (cover) {
        for (final e in const ['.jpg', '.jpeg', '.png', '.webp', '.img']) {
          add(p.join(supportDirectory.path, 'covers', '$contentHash$e'));
        }
      }
    }

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    return null;
  }

  /// Absolute filesystem path for open/delete, or null if missing.
  Future<String?> resolveExistingPath(
    String stored, {
    String? contentHash,
    bool cover = false,
  }) async {
    final file = await resolveExisting(
      stored,
      contentHash: contentHash,
      cover: cover,
    );
    return file?.path;
  }

  /// Rewrite DB paths so UUID-stale absolute entries become relative to the
  /// current support root. Safe to run on every cold start.
  Future<int> rebindDatabase(AppDatabase database) async {
    final items = await database.select(database.readingItems).get();
    var updated = 0;
    for (final item in items) {
      final file = await resolveExisting(
        item.filePath,
        contentHash: item.contentHash,
      );
      File? cover;
      if (item.coverPath != null && item.coverPath!.isNotEmpty) {
        cover = await resolveExisting(
          item.coverPath!,
          contentHash: item.contentHash,
          cover: true,
        );
      }

      // Write absolute paths under the *current* support root so Image.file /
      // open() keep working. Relative forms are normalized via [resolve] first.
      final newFilePath =
          file?.path ??
          (p.isAbsolute(item.filePath)
              ? resolve(toStoragePath(item.filePath)).path
              : resolve(item.filePath).path);
      final String? newCoverPath;
      if (cover != null) {
        newCoverPath = cover.path;
      } else if (item.coverPath == null || item.coverPath!.isEmpty) {
        newCoverPath = item.coverPath;
      } else {
        newCoverPath = resolve(
          p.isAbsolute(item.coverPath!)
              ? toStoragePath(item.coverPath!)
              : item.coverPath!,
        ).path;
      }

      if (newFilePath == item.filePath && newCoverPath == item.coverPath) {
        continue;
      }

      await (database.update(
        database.readingItems,
      )..where((t) => t.id.equals(item.id))).write(
        ReadingItemsCompanion(
          filePath: Value(newFilePath),
          coverPath: Value(newCoverPath),
        ),
      );
      updated++;
    }
    return updated;
  }
}
